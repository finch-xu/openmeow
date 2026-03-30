#if LAME_AVAILABLE
import Foundation

nonisolated enum MP3Encoder {

    static func encode(_ buffer: AudioBuffer) throws -> Data {
        guard let lame = lame_init() else {
            throw AudioEncoderError.encodingFailed("LAME init failed")
        }
        defer { lame_close(lame) }

        lame_set_in_samplerate(lame, Int32(buffer.sampleRate))
        lame_set_num_channels(lame, 1)
        lame_set_VBR(lame, vbr_default)
        lame_set_VBR_quality(lame, 2)
        lame_set_quality(lame, 2)

        guard lame_init_params(lame) == 0 else {
            throw AudioEncoderError.encodingFailed("LAME parameter init failed")
        }

        let sampleCount = Int32(buffer.samples.count)
        // LAME docs: worst-case output size = 1.25 * nsamples + 7200
        let mp3BufSize = Int(1.25 * Double(sampleCount)) + 7200
        var mp3Buf = [UInt8](repeating: 0, count: mp3BufSize)

        let bytesWritten = buffer.samples.withUnsafeBufferPointer { pcm in
            lame_encode_buffer_ieee_float(
                lame,
                pcm.baseAddress!, // left channel (mono)
                pcm.baseAddress!, // right channel (same for mono)
                sampleCount,
                &mp3Buf,
                Int32(mp3BufSize)
            )
        }

        guard bytesWritten >= 0 else {
            throw AudioEncoderError.encodingFailed("LAME encode failed: \(bytesWritten)")
        }

        var output = Data(mp3Buf[0..<Int(bytesWritten)])

        // Flush remaining MP3 frames
        let flushBytes = lame_encode_flush(lame, &mp3Buf, Int32(mp3BufSize))
        if flushBytes > 0 {
            output.append(contentsOf: mp3Buf[0..<Int(flushBytes)])
        }

        return output
    }
}
#endif
