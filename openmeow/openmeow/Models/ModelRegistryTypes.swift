import Foundation

// MARK: - Localized String

nonisolated struct LocalizedString: Codable, Sendable, Hashable {
    let en: String
    let zh: String?

    var localized: String {
        if let langCode = Locale.current.language.languageCode?.identifier,
           langCode.hasPrefix("zh"), let zh {
            return zh
        }
        return en
    }

    init(en: String, zh: String? = nil) {
        self.en = en
        self.zh = zh
    }

    init(from decoder: Decoder) throws {
        // Support both object {"en":"...", "zh":"..."} and plain string "..."
        if let container = try? decoder.singleValueContainer(),
           let plain = try? container.decode(String.self) {
            self.en = plain
            self.zh = nil
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.en = try container.decode(String.self, forKey: .en)
            self.zh = try container.decodeIfPresent(String.self, forKey: .zh)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case en, zh
    }
}

// MARK: - Registry Manifest

nonisolated struct ModelRegistryManifest: Codable, Sendable {
    let version: Int
    let updatedAt: String
    let models: [ModelRegistryEntry]
}

// MARK: - Enums

nonisolated enum ModelType: String, Codable, Sendable {
    case tts, asr
}

nonisolated enum EngineType: String, Codable, Sendable {
    case sherpaOnnx = "sherpa-onnx"
    case speechSwift = "speech-swift"
    case whisperKit = "whisper-kit"
    case openaiCloud = "openai-cloud"
    case mimoCloud = "mimo-cloud"
    case qwenCloud = "qwen-cloud"

    var isCloud: Bool {
        switch self {
        case .openaiCloud, .mimoCloud, .qwenCloud: true
        default: false
        }
    }
}

nonisolated enum ModelStatus: String, Codable, Sendable {
    case stable, beta, experimental
}

nonisolated enum DownloadSource: String, Codable, Sendable {
    case githubRelease = "github-release"
    case huggingface
    case modelscope
    case customUrl = "custom-url"
    case whisperKitManaged = "whisperkit-managed"
    case cloudManaged = "cloud-managed"
}

nonisolated enum ExtractFormat: String, Codable, Sendable {
    case tarBz2 = "tar.bz2"
    case tarGz = "tar.gz"
    case zip
    case none
}

// MARK: - Model Entry

nonisolated struct ModelRegistryEntry: Codable, Sendable, Identifiable {
    let id: String
    let apiId: String?         // API-facing name, e.g., "qwen3-tts-0.6b-mlx"
    let type: ModelType
    let engine: EngineType
    let family: String
    let version: String?
    let license: String?

    // Localized text
    let displayName: LocalizedString
    let description: LocalizedString
    let notes: LocalizedString?

    // Capabilities
    let languages: [String]
    let voiceList: [VoiceInfo]?  // available voices for TTS
    let sampleRate: Int?         // output sample rate
    let streaming: Bool?         // ASR streaming support

    var voiceCount: Int { voiceList?.count ?? 0 }

    // Requirements
    let requirements: ModelRequirements?

    // Size
    let size: ModelSize

    // Download
    let download: ModelDownload

    // Engine config (relative file paths)
    let config: ModelConfig

    // Status
    // Bundled
    let bundled: Bool?

    // Status
    let status: ModelStatus
    let testedOn: String?

    var isBundled: Bool { bundled == true }
}

// MARK: - Nested Types

nonisolated struct ModelRequirements: Codable, Sendable {
    let minMemoryGb: Double?
    let recommendedMemoryGb: Double?
    let appleSiliconOnly: Bool?
    let gpuRequired: Bool?
}

nonisolated struct ModelSize: Codable, Sendable {
    let downloadMb: Int
    let diskMb: Int
}

nonisolated struct ModelDownload: Codable, Sendable {
    let source: DownloadSource
    let url: String
    let checksumSha256: String?
    let extractFormat: ExtractFormat
    let extractedDirName: String?
    let additionalFiles: [AdditionalDownload]?
}

nonisolated struct AdditionalDownload: Codable, Sendable {
    let url: String
    let destinationPath: String  // relative to model dir
    let checksumSha256: String?
}

nonisolated struct ModelConfig: Codable, Sendable {
    // sherpa-onnx TTS
    let modelFile: String?
    let voicesFile: String?
    let tokensFile: String?
    let dataDir: String?
    let dictDir: String?
    let lexicon: String?
    let ruleFsts: String?

    // sherpa-onnx TTS matcha
    let acousticModel: String?
    let vocoder: String?

    // sherpa-onnx ASR
    let asrModelType: String?     // "sense_voice", "whisper", "paraformer", "ctc"
    let encoder: String?
    let decoder: String?
    let asrSampleRate: Int?
    let featureDim: Int?
    let decodingMethod: String?

    // speech-swift (HuggingFace)
    let hfModelId: String?
    let quantizationBits: Int?   // 4 or 8

    // WhisperKit / TTSKit
    let whisperKitVariant: String?
    let ttsKitVariant: String?

    // Cloud TTS
    let cloudEndpoint: String?
    let cloudModel: String?
    let apiKeySettingsKey: String?
    let authHeader: String?
    let authPrefix: String?

    // Common
    let numThreads: Int?
}

// MARK: - Download State (used by ModelManager)

nonisolated enum ModelDownloadState: Sendable, Equatable {
    case notInstalled
    case downloading(progress: Double)
    case extracting
    case stopped     // installed but not loaded
    case running     // installed and loaded into engine
    case error(String)

    var isInstalled: Bool {
        switch self {
        case .stopped, .running: true
        default: false
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.notInstalled, .notInstalled): true
        case (.downloading(let a), .downloading(let b)): a == b
        case (.extracting, .extracting): true
        case (.stopped, .stopped): true
        case (.running, .running): true
        case (.error(let a), .error(let b)): a == b
        default: false
        }
    }
}
