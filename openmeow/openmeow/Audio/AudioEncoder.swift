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
            return try encodeAAC(buffer)
        case .flac:
            return try encodeFLAC(buffer)
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

    // MARK: - AAC Encoding (M4A container)

    private static func encodeAAC(_ buffer: AudioBuffer) throws -> Data {
        // Try at native sample rate first; fall back to 48kHz if the encoder rejects it
        if let data = try? encodeAACAtRate(buffer, sampleRate: Double(buffer.sampleRate)) {
            return data
        }
        let resampled = AudioBuffer(
            samples: AudioResampler.resample(buffer.samples, from: buffer.sampleRate, to: 48000),
            sampleRate: 48000
        )
        return try encodeAACAtRate(resampled, sampleRate: 48000)
    }

    private static func encodeAACAtRate(_ buffer: AudioBuffer, sampleRate: Double) throws -> Data {
        let frameCount = AVAudioFrameCount(buffer.samples.count)

        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
        ) else {
            throw AudioEncoderError.encodingFailed("Cannot create input format")
        }

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            throw AudioEncoderError.encodingFailed("Cannot create input buffer")
        }
        inputBuffer.frameLength = frameCount
        buffer.samples.withUnsafeBufferPointer { src in
            inputBuffer.floatChannelData![0].initialize(from: src.baseAddress!, count: Int(frameCount))
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Let Core Audio pick a valid bitrate -- do NOT hardcode AVEncoderBitRateKey
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]

        // Inner scope ensures AVAudioFile is deallocated (and the container finalized) before reading
        do {
            let outputFile = try AVAudioFile(
                forWriting: tempURL,
                settings: outputSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try outputFile.write(from: inputBuffer)
        }
        return try Data(contentsOf: tempURL)
    }

    // MARK: - FLAC Encoding (CAF container)

    private static func encodeFLAC(_ buffer: AudioBuffer) throws -> Data {
        let sampleRate = Double(buffer.sampleRate)
        let frameCount = AVAudioFrameCount(buffer.samples.count)

        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
        ) else {
            throw AudioEncoderError.encodingFailed("Cannot create input format")
        }

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            throw AudioEncoderError.encodingFailed("Cannot create input buffer")
        }
        inputBuffer.frameLength = frameCount
        buffer.samples.withUnsafeBufferPointer { src in
            inputBuffer.floatChannelData![0].initialize(from: src.baseAddress!, count: Int(frameCount))
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatFLAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]

        // Inner scope ensures AVAudioFile is deallocated (and the container finalized) before reading
        do {
            let outputFile = try AVAudioFile(
                forWriting: tempURL,
                settings: outputSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try outputFile.write(from: inputBuffer)
        }
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
