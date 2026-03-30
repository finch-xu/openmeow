#if OPUS_AVAILABLE
import Foundation

nonisolated enum WebMOpusDecoder {

    private static let opusSampleRate: Int32 = 48000
    private static let maxFrameSize: Int32 = 5760

    // EBML Element IDs
    private static let idEBML: UInt32        = 0x1A45_DFA3
    private static let idSegment: UInt32     = 0x1853_8067
    private static let idTracks: UInt32      = 0x1654_AE6B
    private static let idTrackEntry: UInt32  = 0xAE
    private static let idTrackType: UInt32   = 0x83
    private static let idCodecID: UInt32     = 0x86
    private static let idCodecPrivate: UInt32 = 0x63A2
    private static let idCluster: UInt32     = 0x1F43_B675
    private static let idSimpleBlock: UInt32 = 0xA3
    private static let idBlock: UInt32       = 0xA1
    private static let idTrackNumber: UInt32 = 0xD7

    /// Decode WebM Opus data to PCM float32 mono AudioBuffer (48kHz).
    static func decode(_ data: Data) throws -> AudioBuffer {
        var reader = EBMLReader(data: data)

        // Parse EBML header
        let ebmlID = try reader.readElementID()
        guard ebmlID == idEBML else {
            throw AudioDecoderError.decodingFailed("Invalid WebM: missing EBML header")
        }
        let ebmlSize = try reader.readDataSize()
        reader.offset += Int(ebmlSize) // skip EBML header content

        // Enter Segment
        let segID = try reader.readElementID()
        guard segID == idSegment else {
            throw AudioDecoderError.decodingFailed("Invalid WebM: missing Segment element")
        }
        let segSize = try reader.readDataSize()
        let segEnd = segSize == UInt64.max ? data.count : min(reader.offset + Int(segSize), data.count)

        // First pass: find audio track info
        var audioTrackNumber: UInt64 = 0
        var channelCount: Int32 = 1
        var preSkip: Int = 0
        var outputGain: Int16 = 0
        var foundAudioTrack = false

        let savedOffset = reader.offset
        try scanForAudioTrack(
            &reader, end: Int(segEnd),
            audioTrackNumber: &audioTrackNumber,
            channelCount: &channelCount,
            preSkip: &preSkip,
            outputGain: &outputGain,
            found: &foundAudioTrack
        )

        guard foundAudioTrack else {
            throw AudioDecoderError.decodingFailed("WebM does not contain an Opus audio track")
        }

        // Create Opus decoder
        var error: Int32 = 0
        let decoder = opus_decoder_create(opusSampleRate, channelCount, &error)
        guard error == OPUS_OK, let decoder else {
            throw AudioDecoderError.decodingFailed("Opus decoder creation failed: \(error)")
        }
        defer { opus_decoder_destroy(decoder) }

        if outputGain != 0 {
            opus_decoder_set_gain(decoder, Int32(outputGain))
        }

        // Second pass: decode audio from clusters
        reader.offset = savedOffset
        var allSamples = [Float]()

        while reader.offset < Int(segEnd) {
            guard let elemID = try? reader.readElementID(),
                  let elemSize = try? reader.readDataSize() else { break }

            let elemEnd = elemSize == UInt64.max ? Int(segEnd) : min(reader.offset + Int(elemSize), Int(segEnd))

            if elemID == idCluster {
                try decodeCluster(
                    &reader, end: elemEnd,
                    audioTrack: audioTrackNumber,
                    decoder: decoder,
                    channelCount: channelCount,
                    samples: &allSamples
                )
            } else {
                reader.offset = elemEnd
            }
        }

        guard !allSamples.isEmpty else {
            throw AudioDecoderError.emptyAudio
        }

        // Apply pre-skip
        if preSkip > 0 && preSkip < allSamples.count {
            allSamples.removeFirst(preSkip)
        }

        return AudioBuffer(samples: allSamples, sampleRate: Int(opusSampleRate))
    }

    // MARK: - Track Scanner

    private static func scanForAudioTrack(
        _ reader: inout EBMLReader, end: Int,
        audioTrackNumber: inout UInt64,
        channelCount: inout Int32,
        preSkip: inout Int,
        outputGain: inout Int16,
        found: inout Bool
    ) throws {
        while reader.offset < end {
            guard let elemID = try? reader.readElementID(),
                  let elemSize = try? reader.readDataSize() else { return }

            let elemEnd = elemSize == UInt64.max ? end : min(reader.offset + Int(elemSize), end)

            switch elemID {
            case idTracks, idTrackEntry:
                // Recurse into container elements
                try scanForAudioTrack(
                    &reader, end: elemEnd,
                    audioTrackNumber: &audioTrackNumber,
                    channelCount: &channelCount,
                    preSkip: &preSkip,
                    outputGain: &outputGain,
                    found: &found
                )
            case idTrackNumber:
                audioTrackNumber = try reader.readUInt(count: Int(elemSize))
            case idTrackType:
                let trackType = try reader.readUInt(count: Int(elemSize))
                if trackType == 2 { found = true } // 2 = audio
            case idCodecID:
                let codecStr = reader.readString(count: Int(elemSize))
                if codecStr != "A_OPUS" {
                    throw AudioDecoderError.decodingFailed("WebM audio is not Opus (CodecID: \(codecStr))")
                }
            case idCodecPrivate:
                // CodecPrivate contains OpusHead for Opus tracks
                let cpData = reader.readBytes(count: Int(elemSize))
                if cpData.count >= 19 && cpData[0..<8].elementsEqual([0x4F, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64]) {
                    channelCount = Int32(cpData[9])
                    preSkip = Int(UInt16(cpData[10]) | (UInt16(cpData[11]) << 8))
                    outputGain = Int16(bitPattern: UInt16(cpData[16]) | (UInt16(cpData[17]) << 8))
                }
            default:
                reader.offset = elemEnd
            }

            if reader.offset < elemEnd && elemID != idTracks && elemID != idTrackEntry {
                reader.offset = elemEnd
            }
        }
    }

    // MARK: - Cluster Decoder

    private static func decodeCluster(
        _ reader: inout EBMLReader, end: Int,
        audioTrack: UInt64,
        decoder: OpaquePointer,
        channelCount: Int32,
        samples: inout [Float]
    ) throws {
        while reader.offset < end {
            guard let elemID = try? reader.readElementID(),
                  let elemSize = try? reader.readDataSize() else { return }

            let elemEnd = min(reader.offset + Int(elemSize), end)

            if elemID == idSimpleBlock || elemID == idBlock {
                // Read track number (VINT without masking for SimpleBlock)
                let trackVINT = try reader.readVINTRaw()
                let trackNum = trackVINT.value

                if trackNum == audioTrack {
                    // Skip timecode (2 bytes) + flags (1 byte)
                    reader.offset += 3
                    let frameSize = elemEnd - reader.offset
                    if frameSize > 0 {
                        let frameData = reader.readBytes(count: frameSize)
                        let maxSamples = Int(maxFrameSize) * Int(channelCount)
                        var pcmBuffer = [Float](repeating: 0, count: maxSamples)

                        let decoded = frameData.withUnsafeBytes { raw -> Int32 in
                            let ptr = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
                            return opus_decode_float(
                                decoder, ptr, Int32(frameSize),
                                &pcmBuffer, maxFrameSize, 0
                            )
                        }

                        if decoded > 0 {
                            let count = Int(decoded)
                            if channelCount == 1 {
                                samples.append(contentsOf: pcmBuffer[0..<count])
                            } else {
                                for i in 0..<count {
                                    let l = pcmBuffer[i * Int(channelCount)]
                                    let r = pcmBuffer[i * Int(channelCount) + 1]
                                    samples.append((l + r) * 0.5)
                                }
                            }
                        }
                    }
                }
                reader.offset = elemEnd
            } else {
                reader.offset = elemEnd
            }
        }
    }

    // MARK: - EBML Reader

    private struct VINTResult {
        let value: UInt64
        let length: Int
    }

    private struct EBMLReader {
        let data: Data
        var offset: Int = 0

        /// Read EBML Element ID (variable-length, leading 1-bit kept)
        mutating func readElementID() throws -> UInt32 {
            guard offset < data.count else {
                throw AudioDecoderError.decodingFailed("WebM: unexpected end of data reading element ID")
            }
            let first = data[offset]
            let length: Int
            if first & 0x80 != 0 { length = 1 }
            else if first & 0x40 != 0 { length = 2 }
            else if first & 0x20 != 0 { length = 3 }
            else if first & 0x10 != 0 { length = 4 }
            else { throw AudioDecoderError.decodingFailed("WebM: invalid element ID") }

            guard offset + length <= data.count else {
                throw AudioDecoderError.decodingFailed("WebM: truncated element ID")
            }

            var result: UInt32 = 0
            for i in 0..<length {
                result = (result << 8) | UInt32(data[offset + i])
            }
            offset += length
            return result
        }

        /// Read EBML Data Size (variable-length, leading 1-bit masked off)
        mutating func readDataSize() throws -> UInt64 {
            let vint = try readVINTRaw()
            // Mask off the length marker bit
            let mask = UInt64(1) << (7 * vint.length)
            let value = vint.value ^ mask
            // All-1s means unknown size
            let allOnes = mask | (mask - 1)
            if vint.value == allOnes { return UInt64.max }
            return value
        }

        /// Read raw VINT (variable-length integer with leading bit intact)
        mutating func readVINTRaw() throws -> VINTResult {
            guard offset < data.count else {
                throw AudioDecoderError.decodingFailed("WebM: unexpected end of data reading VINT")
            }
            let first = data[offset]
            let length: Int
            if first & 0x80 != 0 { length = 1 }
            else if first & 0x40 != 0 { length = 2 }
            else if first & 0x20 != 0 { length = 3 }
            else if first & 0x10 != 0 { length = 4 }
            else if first & 0x08 != 0 { length = 5 }
            else if first & 0x04 != 0 { length = 6 }
            else if first & 0x02 != 0 { length = 7 }
            else if first & 0x01 != 0 { length = 8 }
            else { throw AudioDecoderError.decodingFailed("WebM: invalid VINT") }

            guard offset + length <= data.count else {
                throw AudioDecoderError.decodingFailed("WebM: truncated VINT")
            }

            var result: UInt64 = 0
            for i in 0..<length {
                result = (result << 8) | UInt64(data[offset + i])
            }
            offset += length
            return VINTResult(value: result, length: length)
        }

        /// Read fixed-size unsigned integer (big-endian)
        mutating func readUInt(count: Int) throws -> UInt64 {
            guard offset + count <= data.count else {
                throw AudioDecoderError.decodingFailed("WebM: truncated uint")
            }
            var result: UInt64 = 0
            for i in 0..<count {
                result = (result << 8) | UInt64(data[offset + i])
            }
            offset += count
            return result
        }

        /// Read UTF-8 string
        mutating func readString(count: Int) -> String {
            let end = min(offset + count, data.count)
            let str = String(data: data[offset..<end], encoding: .utf8) ?? ""
            offset = end
            return str
        }

        /// Read raw bytes
        mutating func readBytes(count: Int) -> Data {
            let end = min(offset + count, data.count)
            let result = data[offset..<end]
            offset = end
            return Data(result)
        }
    }
}
#endif
