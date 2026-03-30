import Foundation
import Accelerate
import AVFoundation

nonisolated enum ResponseFormat: String, Codable, Sendable {
    case mp3, wav, opus, pcm, flac, aac
}

nonisolated enum AudioEncoderError: Error, CustomStringConvertible {
    case unsupportedFormat(ResponseFormat)
    case encodingFailed(String)

    var description: String {
        switch self {
        case .unsupportedFormat(let fmt):
            "Unsupported audio format: \(fmt.rawValue)"
        case .encodingFailed(let msg):
            "Audio encoding failed: \(msg)"
        }
    }
}

nonisolated enum AudioEncoder {

    static func encode(_ buffer: AudioBuffer, format: ResponseFormat) throws -> Data {
        switch format {
        case .wav:
            return encodeWAV(buffer)
        case .pcm:
            return encodePCM(buffer)
        case .mp3:
            #if LAME_AVAILABLE
            return try MP3Encoder.encode(buffer)
            #else
            throw AudioEncoderError.encodingFailed(
                "MP3 encoding requires libmp3lame. Rebuild with LAME support enabled."
            )
            #endif
        case .aac:
            return try encodeCompressed(buffer, fileType: .m4a, formatID: kAudioFormatMPEG4AAC)
        case .flac:
            return try encodeCompressed(buffer, fileType: AVFileType(rawValue: "public.flac"), formatID: kAudioFormatFLAC)
        case .opus:
            #if OPUS_AVAILABLE
            return try OggOpusEncoder.encode(buffer)
            #else
            throw AudioEncoderError.encodingFailed(
                "Opus encoding requires libopus. Rebuild with opus support enabled."
            )
            #endif
        }
    }

    // MARK: - WAV Encoding

    static func encodeWAV(_ buffer: AudioBuffer) -> Data {
        let int16Samples = floatToInt16(buffer.samples)
        let dataSize = int16Samples.count * 2
        let fileSize = UInt32(36 + dataSize)

        var data = Data(capacity: 44 + dataSize)

        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        appendLE(&data, fileSize)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt chunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        appendLE(&data, UInt32(16))
        appendLE(&data, UInt16(1))            // PCM
        appendLE(&data, UInt16(1))            // mono
        appendLE(&data, UInt32(buffer.sampleRate))
        appendLE(&data, UInt32(buffer.sampleRate * 2))
        appendLE(&data, UInt16(2))
        appendLE(&data, UInt16(16))

        // data chunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        appendLE(&data, UInt32(dataSize))

        int16Samples.withUnsafeBufferPointer { ptr in
            ptr.withMemoryRebound(to: UInt8.self) { bytes in
                data.append(bytes)
            }
        }

        return data
    }

    // MARK: - PCM Encoding

    static func encodePCM(_ buffer: AudioBuffer) -> Data {
        let int16Samples = floatToInt16(buffer.samples)
        return int16Samples.withUnsafeBufferPointer { ptr in
            ptr.withMemoryRebound(to: UInt8.self) { bytes in
                Data(bytes)
            }
        }
    }

    // MARK: - Compressed Encoding (AAC, FLAC via AVFoundation)

    private static func encodeCompressed(
        _ buffer: AudioBuffer,
        fileType: AVFileType,
        formatID: AudioFormatID
    ) throws -> Data {
        let sampleRate = Double(buffer.sampleRate)
        let frameCount = AVAudioFrameCount(buffer.samples.count)

        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioEncoderError.encodingFailed("Cannot create input format")
        }

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            throw AudioEncoderError.encodingFailed("Cannot create input buffer")
        }
        inputBuffer.frameLength = frameCount

        if let channelData = inputBuffer.floatChannelData {
            buffer.samples.withUnsafeBufferPointer { src in
                channelData[0].initialize(from: src.baseAddress!, count: Int(frameCount))
            }
        }

        let ext = fileType.rawValue.contains("flac") ? "flac" : "m4a"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        defer { try? FileManager.default.removeItem(at: tempURL) }

        var outputSettings: [String: Any] = [
            AVFormatIDKey: formatID,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]

        if formatID == kAudioFormatMPEG4AAC {
            outputSettings[AVEncoderBitRateKey] = 128000
        }

        let outputFile: AVAudioFile
        do {
            outputFile = try AVAudioFile(
                forWriting: tempURL,
                settings: outputSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw AudioEncoderError.encodingFailed(
                "Format \(formatID) not available: \(error.localizedDescription)"
            )
        }

        try outputFile.write(from: inputBuffer)

        return try Data(contentsOf: tempURL)
    }

    // MARK: - Helpers

    private static func floatToInt16(_ samples: [Float]) -> [Int16] {
        guard !samples.isEmpty else { return [] }
        let count = samples.count
        var scaled = [Float](repeating: 0, count: count)
        var scale: Float = 32767.0

        var minVal: Float = -1.0
        var maxVal: Float = 1.0
        var clamped = [Float](repeating: 0, count: count)
        vDSP_vclip(samples, 1, &minVal, &maxVal, &clamped, 1, vDSP_Length(count))
        vDSP_vsmul(clamped, 1, &scale, &scaled, 1, vDSP_Length(count))

        var result = [Int16](repeating: 0, count: count)
        vDSP_vfix16(scaled, 1, &result, 1, vDSP_Length(count))
        return result
    }

    private static func appendLE<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
