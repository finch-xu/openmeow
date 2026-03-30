import Accelerate

nonisolated enum AudioResampler {

    static func resample(
        _ samples: [Float],
        from sourceSR: Int,
        to targetSR: Int
    ) -> [Float] {
        guard sourceSR != targetSR, !samples.isEmpty else { return samples }

        let ratio = Double(targetSR) / Double(sourceSR)
        let outputCount = Int(Double(samples.count) * ratio)
        guard outputCount > 1 else { return outputCount == 1 ? [samples[0]] : [] }

        var indices = [Float](repeating: 0, count: outputCount)
        var start: Float = 0
        var step = Float(samples.count - 1) / Float(outputCount - 1)
        vDSP_vramp(&start, &step, &indices, 1, vDSP_Length(outputCount))

        var output = [Float](repeating: 0, count: outputCount)
        vDSP_vlint(samples, indices, 1, &output, 1, vDSP_Length(outputCount), vDSP_Length(samples.count))

        return output
    }
}
