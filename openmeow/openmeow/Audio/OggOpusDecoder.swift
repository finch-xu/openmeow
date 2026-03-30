#if OPUS_AVAILABLE
import Foundation

nonisolated enum OggOpusDecoder {

    private static let opusSampleRate: Int32 = 48000
    private static let maxFrameSize: Int32 = 5760 // 120ms at 48kHz

    /// Decode OGG Opus data to PCM float32 mono AudioBuffer (48kHz).
    static func decode(_ data: Data) throws -> AudioBuffer {
        // Init OGG sync state
        var oy = ogg_sync_state()
        ogg_sync_init(&oy)
        defer { ogg_sync_clear(&oy) }

        // Feed all data into sync buffer
        guard let bufferPtr = ogg_sync_buffer(&oy, data.count) else {
            throw AudioDecoderError.decodingFailed("OGG sync buffer allocation failed")
        }
        data.withUnsafeBytes { raw in
            _ = memcpy(bufferPtr, raw.baseAddress!, data.count)
        }
        ogg_sync_wrote(&oy, data.count)

        // State for parsing
        var os = ogg_stream_state()
        var streamInited = false
        defer { if streamInited { ogg_stream_clear(&os) } }

        var channelCount: Int32 = 0
        var preSkip: Int = 0
        var outputGain: Int16 = 0
        var decoder: OpaquePointer?
        defer { if let d = decoder { opus_decoder_destroy(d) } }

        var packetIndex: Int64 = 0
        var allSamples = [Float]()

        // Page-level loop
        var page = ogg_page()
        while ogg_sync_pageout(&oy, &page) == 1 {
            if !streamInited {
                let serialno = ogg_page_serialno(&page)
                guard ogg_stream_init(&os, serialno) == 0 else {
                    throw AudioDecoderError.decodingFailed("OGG stream init failed")
                }
                streamInited = true
            }

            guard ogg_stream_pagein(&os, &page) == 0 else { continue }

            // Packet-level loop within this page
            var op = ogg_packet()
            while ogg_stream_packetout(&os, &op) == 1 {
                if packetIndex == 0 {
                    // Parse OpusHead (RFC 7845 §5.1)
                    let parsed = try parseOpusHead(op)
                    channelCount = parsed.channels
                    preSkip = parsed.preSkip
                    outputGain = parsed.outputGain

                    // Create Opus decoder
                    var error: Int32 = 0
                    decoder = opus_decoder_create(opusSampleRate, channelCount, &error)
                    guard error == OPUS_OK, decoder != nil else {
                        throw AudioDecoderError.decodingFailed("Opus decoder creation failed: \(error)")
                    }
                    // Apply output gain if non-zero (RFC 7845 §5.1)
                    if outputGain != 0 {
                        opus_decoder_set_gain(decoder, Int32(outputGain))
                    }
                } else if packetIndex >= 2 {
                    // Audio packet (skip packet 1 = OpusTags)
                    guard let dec = decoder else {
                        throw AudioDecoderError.decodingFailed("Opus decoder not initialized")
                    }
                    let frameSamples = Int(maxFrameSize) * Int(channelCount)
                    var pcmBuffer = [Float](repeating: 0, count: frameSamples)

                    let decoded = opus_decode_float(
                        dec, op.packet, Int32(op.bytes),
                        &pcmBuffer, maxFrameSize, 0
                    )
                    guard decoded > 0 else {
                        throw AudioDecoderError.decodingFailed("Opus decode failed: \(decoded)")
                    }

                    let decodedCount = Int(decoded)
                    if channelCount == 1 {
                        allSamples.append(contentsOf: pcmBuffer[0..<decodedCount])
                    } else {
                        // Downmix stereo to mono
                        for i in 0..<decodedCount {
                            let l = pcmBuffer[i * Int(channelCount)]
                            let r = pcmBuffer[i * Int(channelCount) + 1]
                            allSamples.append((l + r) * 0.5)
                        }
                    }
                }
                packetIndex += 1
            }
        }

        guard !allSamples.isEmpty else {
            throw AudioDecoderError.emptyAudio
        }

        // Apply pre-skip: remove first preSkip samples
        if preSkip > 0 && preSkip < allSamples.count {
            allSamples.removeFirst(preSkip)
        }

        return AudioBuffer(samples: allSamples, sampleRate: Int(opusSampleRate))
    }

    // MARK: - OpusHead Parser

    private struct OpusHead {
        let channels: Int32
        let preSkip: Int
        let originalSampleRate: UInt32
        let outputGain: Int16
    }

    /// Parse OpusHead packet (RFC 7845 §5.1)
    /// Layout: "OpusHead"(8) + version(1) + channels(1) + preSkip(2 LE) + sampleRate(4 LE) + gain(2 LE) + mapping(1)
    private static func parseOpusHead(_ packet: ogg_packet) throws -> OpusHead {
        guard packet.bytes >= 19 else {
            throw AudioDecoderError.decodingFailed("OpusHead too short (\(packet.bytes) bytes)")
        }

        let ptr = packet.packet!

        // Verify magic "OpusHead"
        let magic = Data(bytes: ptr, count: 8)
        guard magic.elementsEqual([0x4F, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64]) else {
            throw AudioDecoderError.decodingFailed("OGG file does not contain Opus audio (missing OpusHead magic)")
        }

        let channels = Int32(ptr[9])
        guard channels == 1 || channels == 2 else {
            throw AudioDecoderError.decodingFailed("Unsupported channel count: \(channels)")
        }

        let preSkip = Int(UInt16(ptr[10]) | (UInt16(ptr[11]) << 8))
        let sampleRate = UInt32(ptr[12]) | (UInt32(ptr[13]) << 8) | (UInt32(ptr[14]) << 16) | (UInt32(ptr[15]) << 24)
        let gain = Int16(bitPattern: UInt16(ptr[16]) | (UInt16(ptr[17]) << 8))

        return OpusHead(channels: channels, preSkip: preSkip, originalSampleRate: sampleRate, outputGain: gain)
    }
}
#endif
