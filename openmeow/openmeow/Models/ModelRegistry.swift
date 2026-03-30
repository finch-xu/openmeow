import Foundation
import OSLog

actor ModelRegistry {
    private var manifest: ModelRegistryManifest
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "ModelRegistry")

    init() throws {
        // Load bundled registry
        guard let bundledURL = Bundle.main.url(forResource: "model-registry", withExtension: "json") else {
            throw ModelRegistryError.bundledRegistryNotFound
        }
        let bundledData = try Data(contentsOf: bundledURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let bundled = try decoder.decode(ModelRegistryManifest.self, from: bundledData)

        // Check for cached version
        let cachedURL = AppConstants.configDirectory.appendingPathComponent("model-registry.json")
        if FileManager.default.fileExists(atPath: cachedURL.path),
           let cachedData = try? Data(contentsOf: cachedURL),
           let cached = try? decoder.decode(ModelRegistryManifest.self, from: cachedData),
           cached.version > bundled.version {
            self.manifest = cached
            logger.info("Loaded cached registry v\(cached.version)")
        } else {
            self.manifest = bundled
            logger.info("Loaded bundled registry v\(bundled.version)")
        }
    }

    // MARK: - Remote Update

    func checkForUpdates() async {
        guard let url = URL(string: AppConstants.registryRemoteURL) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let remote = try decoder.decode(ModelRegistryManifest.self, from: data)

            guard remote.version > manifest.version else {
                logger.info("Registry up to date (v\(self.manifest.version))")
                return
            }

            // Save to cache
            try FileManager.default.createDirectory(
                at: AppConstants.configDirectory,
                withIntermediateDirectories: true
            )
            let cachedURL = AppConstants.configDirectory.appendingPathComponent("model-registry.json")
            try data.write(to: cachedURL)

            manifest = remote
            logger.info("Updated registry to v\(remote.version)")
        } catch {
            logger.warning("Failed to check for registry updates: \(error)")
        }
    }

    // MARK: - Queries

    func allModels() -> [ModelRegistryEntry] {
        manifest.models
    }

    func model(byID id: String) -> ModelRegistryEntry? {
        manifest.models.first { $0.id == id }
    }

    func models(ofType type: ModelType) -> [ModelRegistryEntry] {
        manifest.models.filter { $0.type == type }
    }

    func models(forEngine engine: EngineType) -> [ModelRegistryEntry] {
        manifest.models.filter { $0.engine == engine }
    }

    var version: Int { manifest.version }
}

nonisolated enum ModelRegistryError: Error, CustomStringConvertible {
    case bundledRegistryNotFound

    var description: String {
        switch self {
        case .bundledRegistryNotFound:
            "Bundled model-registry.json not found in app bundle"
        }
    }
}
