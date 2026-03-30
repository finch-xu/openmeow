#if OPUS_AVAILABLE
import Foundation

nonisolated enum OggOpusEncoder {

    private static let opusSampleRate: Int32 = 48000
    private static let frameSize: Int32 = 960  // 20ms at 48kHz
    private static let bitrate: Int32 = 64000

    static func encode(_ buffer: AudioBuffer) throws -> Data {
        // Resample to 48kHz if needed
        let samples: [Float]
        if buffer.sampleRate == Int(opusSampleRate) {
            samples = buffer.samples
        } else {
            samples = AudioResampler.resample(buffer.samples, from: buffer.sampleRate, to: Int(opusSampleRate))
        }

        // Create Opus encoder
        var error: Int32 = 0
        guard let encoder = opus_encoder_create(opusSampleRate, 1, OPUS_APPLICATION_AUDIO, &error),
              error == OPUS_OK else {
            throw AudioEncoderError.encodingFailed("Opus encoder creation failed: \(error)")
        }
        defer { opus_encoder_destroy(encoder) }

        opus_encoder_set_bitrate(encoder, bitrate)

        // Get encoder lookahead for pre-skip
        var lookahead: Int32 = 0
        opus_encoder_get_lookahead(encoder, &lookahead)
        let preSkip = UInt16(lookahead)

        // Init OGG stream
        var os = ogg_stream_state()
        let serialno = Int32.random(in: Int32.min...Int32.max)
        guard ogg_stream_init(&os, serialno) == 0 else {
            throw AudioEncoderError.encodingFailed("OGG stream init failed")
        }
        defer { ogg_stream_clear(&os) }

        var output = Data()

        // Write OpusHead packet (RFC 7845 §5.1)
        let opusHead = buildOpusHead(preSkip: preSkip, inputSampleRate: UInt32(buffer.sampleRate))
        try writeOggPacket(&os, data: opusHead, packetNo: 0, granulePos: 0, bos: true, eos: false, output: &output, flush: true)

        // Write OpusTags packet (RFC 7845 §5.2)
        let opusTags = buildOpusTags()
        try writeOggPacket(&os, data: opusTags, packetNo: 1, granulePos: 0, bos: false, eos: false, output: &output, flush: true)

        // Encode audio frames
        let maxPacketSize: Int32 = 4000
        var packetBuffer = [UInt8](repeating: 0, count: Int(maxPacketSize))
        var packetNo: Int64 = 2
        var granulePos: Int64 = Int64(preSkip)
        let totalSamples = samples.count
        var offset = 0

        while offset < totalSamples {
            let remaining = totalSamples - offset
            let frameSamples = Int(frameSize)

            // Prepare frame (pad with silence if last frame is short)
            let frame: [Float]
            if remaining >= frameSamples {
                frame = Array(samples[offset..<(offset + frameSamples)])
            } else {
                var padded = Array(samples[offset..<totalSamples])
                padded.append(contentsOf: [Float](repeating: 0, count: frameSamples - remaining))
                frame = padded
            }

            let encodedBytes = frame.withUnsafeBufferPointer { ptr in
                opus_encode_float(encoder, ptr.baseAddress!, frameSize, &packetBuffer, maxPacketSize)
            }

            guard encodedBytes > 0 else {
                throw AudioEncoderError.encodingFailed("Opus encode failed: \(encodedBytes)")
            }

            granulePos += Int64(frameSize)
            let isLast = (offset + frameSamples) >= totalSamples

            let packetData = Data(packetBuffer[0..<Int(encodedBytes)])
            try writeOggPacket(&os, data: packetData, packetNo: packetNo, granulePos: granulePos, bos: false, eos: isLast, output: &output, flush: isLast)

            packetNo += 1
            offset += frameSamples
        }

        return output
    }

    // MARK: - OGG helpers

    private static func writeOggPacket(
        _ os: inout ogg_stream_state,
        data: Data,
        packetNo: Int64,
        granulePos: Int64,
        bos: Bool,
        eos: Bool,
        output: inout Data,
        flush: Bool
    ) throws {
        var op = ogg_packet()
        let mutableData = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        defer { mutableData.deallocate() }
        data.copyBytes(to: mutableData, count: data.count)

        op.packet = mutableData
        op.bytes = Int(data.count)
        op.b_o_s = bos ? 1 : 0
        op.e_o_s = eos ? 1 : 0
        op.granulepos = granulePos
        op.packetno = packetNo

        guard ogg_stream_packetin(&os, &op) == 0 else {
            throw AudioEncoderError.encodingFailed("OGG packetin failed")
        }

        var og = ogg_page()
        if flush {
            while ogg_stream_flush(&os, &og) != 0 {
                output.append(og.header, count: og.header_len)
                output.append(og.body, count: og.body_len)
            }
        } else {
            while ogg_stream_pageout(&os, &og) != 0 {
                output.append(og.header, count: og.header_len)
                output.append(og.body, count: og.body_len)
            }
        }
    }

    // MARK: - RFC 7845 header builders

    private static func buildOpusHead(preSkip: UInt16, inputSampleRate: UInt32) -> Data {
        var data = Data(capacity: 19)
        data.append(contentsOf: [0x4F, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64]) // "OpusHead"
        data.append(1)                                    // version
        data.append(1)                                    // channel count
        appendLE(&data, preSkip)                          // pre-skip
        appendLE(&data, inputSampleRate)                  // original sample rate
        appendLE(&data, Int16(0))                         // output gain
        data.append(0)                                    // channel mapping family
        return data
    }

    private static func buildOpusTags() -> Data {
        let vendor = "openmeow"
        let vendorBytes = Array(vendor.utf8)

        var data = Data(capacity: 8 + 4 + vendorBytes.count + 4)
        data.append(contentsOf: [0x4F, 0x70, 0x75, 0x73, 0x54, 0x61, 0x67, 0x73]) // "OpusTags"
        appendLE(&data, UInt32(vendorBytes.count))        // vendor string length
        data.append(contentsOf: vendorBytes)              // vendor string
        appendLE(&data, UInt32(0))                        // user comment count
        return data
    }

    // MARK: - Helpers

    private static func appendLE<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

}
#endif
