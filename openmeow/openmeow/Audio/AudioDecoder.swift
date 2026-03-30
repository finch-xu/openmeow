import Foundation
import AVFoundation

nonisolated enum AudioDecoderError: Error, CustomStringConvertible {
    case unsupportedFormat
    case decodingFailed(String)
    case emptyAudio

    var description: String {
        switch self {
        case .unsupportedFormat: "Unsupported audio format (supported: wav, mp3, m4a, flac, aac, caf, ogg, webm, pcm)"
        case .decodingFailed(let msg): "Audio decoding failed: \(msg)"
        case .emptyAudio: "Audio file is empty"
        }
    }
}

nonisolated enum AudioDecoder {

    /// Decode audio data (wav, mp3, m4a, flac, aac, caf, ogg, webm, pcm) to PCM float32 mono.
    static func decode(_ data: Data, filenameHint: String? = nil, contentTypeHint: String? = nil) throws -> AudioBuffer {
        guard let format = detectFormat(data, filenameHint: filenameHint, contentTypeHint: contentTypeHint) else {
            throw AudioDecoderError.unsupportedFormat
        }

        switch format {
        case .ogg:
            #if OPUS_AVAILABLE
            return try OggOpusDecoder.decode(data)
            #else
            throw AudioDecoderError.decodingFailed("OGG Opus decoding requires libopus")
            #endif
        case .webm:
            #if OPUS_AVAILABLE
            return try WebMOpusDecoder.decode(data)
            #else
            throw AudioDecoderError.decodingFailed("WebM Opus decoding requires libopus")
            #endif
        case .pcm:
            return try decodePCM(data)
        default:
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(format.rawValue)
            try data.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            return try decodeWithAVAudio(tempURL)
        }
    }

    /// Decode raw PCM data (assumed 16-bit signed integer, 16kHz, mono).
    private static func decodePCM(_ data: Data) throws -> AudioBuffer {
        guard data.count >= 2 else { throw AudioDecoderError.emptyAudio }
        let sampleCount = data.count / 2
        var samples = [Float](repeating: 0, count: sampleCount)
        data.withUnsafeBytes { raw in
            let int16Ptr = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                samples[i] = Float(int16Ptr[i]) / 32768.0
            }
        }
        return AudioBuffer(samples: samples, sampleRate: 16000)
    }

    /// Decode using AVAudioFile (supports mp3, m4a, wav, flac, aac, caf)
    private static func decodeWithAVAudio(_ url: URL) throws -> AudioBuffer {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AudioDecoderError.decodingFailed(error.localizedDescription)
        }

        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else { throw AudioDecoderError.emptyAudio }

        // Read as float32
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: 1,
            interleaved: false
        )!

        guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            throw AudioDecoderError.decodingFailed("Failed to create PCM buffer")
        }

        // If source is mono float32, read directly
        if format.channelCount == 1 && format.commonFormat == .pcmFormatFloat32 {
            try file.read(into: buffer)
        } else {
            // Need conversion
            let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            try file.read(into: sourceBuffer)

            guard let converter = AVAudioConverter(from: format, to: outputFormat) else {
                throw AudioDecoderError.decodingFailed("Cannot create audio converter")
            }

            var error: NSError?
            converter.convert(to: buffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return sourceBuffer
            }
            if let error {
                throw AudioDecoderError.decodingFailed(error.localizedDescription)
            }
        }

        guard let floatData = buffer.floatChannelData else {
            throw AudioDecoderError.decodingFailed("No float channel data")
        }

        let samples = Array(UnsafeBufferPointer(
            start: floatData[0],
            count: Int(buffer.frameLength)
        ))

        return AudioBuffer(
            samples: samples,
            sampleRate: Int(outputFormat.sampleRate)
        )
    }

    // MARK: - Format Detection

    private enum AudioFormat: String {
        case wav, mp3, m4a, flac, aac, caf, ogg, webm, pcm
    }

    /// Detect audio format from magic bytes, Content-Type, or filename hint.
    private static func detectFormat(_ data: Data, filenameHint: String? = nil, contentTypeHint: String? = nil) -> AudioFormat? {
        let count = data.count

        // WAV: RIFF....WAVE
        if count >= 12,
           data[0..<4].elementsEqual([0x52, 0x49, 0x46, 0x46]),
           data[8..<12].elementsEqual([0x57, 0x41, 0x56, 0x45]) {
            return .wav
        }

        // FLAC: "fLaC"
        if count >= 4,
           data[0..<4].elementsEqual([0x66, 0x4C, 0x61, 0x43]) {
            return .flac
        }

        // OGG: "OggS"
        if count >= 4,
           data[0..<4].elementsEqual([0x4F, 0x67, 0x67, 0x53]) {
            return .ogg
        }

        // CAF: "caff"
        if count >= 4,
           data[0..<4].elementsEqual([0x63, 0x61, 0x66, 0x66]) {
            return .caf
        }

        // WebM (EBML header): 0x1A 0x45 0xDF 0xA3
        if count >= 4,
           data[0..<4].elementsEqual([0x1A, 0x45, 0xDF, 0xA3]) {
            return .webm
        }

        // MP3: ID3 tag header
        if count >= 3,
           data[0..<3].elementsEqual([0x49, 0x44, 0x33]) {
            return .mp3
        }

        // MP3: sync word
        if count >= 2,
           data[0] == 0xFF,
           data[1] & 0xE0 == 0xE0 {
            return .mp3
        }

        // M4A/MP4/AAC: "ftyp" at offset 4
        if count >= 8,
           data[4..<8].elementsEqual([0x66, 0x74, 0x79, 0x70]) {
            return .m4a
        }

        // Content-Type hint (needed for PCM which has no magic bytes)
        if let ct = contentTypeHint?.lowercased() {
            if ct.contains("audio/pcm") || ct.contains("audio/l16") || ct.contains("audio/x-raw") {
                return .pcm
            }
        }

        // Fallback: try filename extension
        if let filename = filenameHint,
           let ext = filename.split(separator: ".").last?.lowercased() {
            let mapped: String
            switch ext {
            case "mp4":          mapped = "m4a"
            case "mpeg", "mpga": mapped = "mp3"
            case "raw":          mapped = "pcm"
            default:             mapped = String(ext)
            }
            return AudioFormat(rawValue: mapped)
        }

        return nil
    }

}
