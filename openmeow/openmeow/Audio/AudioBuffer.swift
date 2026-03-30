import Foundation

nonisolated struct AudioBuffer: Sendable {
    let samples: [Float]
    let sampleRate: Int
    let channels: Int

    init(samples: [Float], sampleRate: Int, channels: Int = 1) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.channels = channels
    }
}
