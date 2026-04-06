import Foundation
import Observation
import OSLog

#if SPEECH_SWIFT_AVAILABLE
import Qwen3TTS
import Qwen3ASR
import MLX
#endif

@Observable
final class AppState {
    private(set) var serverRunning = false
    private(set) var loadedModels: [String] = []
    private(set) var errorMessage: String?
    private(set) var availableModels: [ModelRegistryEntry] = []
    private(set) var downloadStates: [String: ModelDownloadState] = [:]
    private(set) var memoryInfo: MemoryInfo?
    var serverPort: Int = AppConstants.defaultPort

    private var serverTask: Task<Void, any Error>?
    private let providerRouter = ProviderRouter()
    let modelManager = ModelManager()
    private var registry: ModelRegistry?
    private let memoryMonitor = MemoryMonitor()
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "AppState")
    private var startupTask: Task<Void, Never>?

    init() {
        startupTask = Task { await self.startServer() }
        Task {
            await self.memoryMonitor.start { [weak self] info in
                Task { @MainActor in self?.memoryInfo = info }
            }
        }
    }

    // MARK: - Server Lifecycle

    func startServer() async {
        guard !serverRunning else { return }

        do {
            try await modelManager.ensureDirectoryExists()

            // Load registry
            let reg = try ModelRegistry()
            self.registry = reg
            self.availableModels = await reg.allModels()
            await refreshDownloadStates()

            // Start HTTP server FIRST (so health/models endpoints respond immediately)
            let router = providerRouter
            let port = serverPort
            serverTask = Task.detached {
                let listen = UserDefaults.standard.string(forKey: "listenAddress") ?? "127.0.0.1"
                try await HTTPServer.run(port: port, listenAddress: listen, providerRouter: router)
            }

            serverRunning = true
            errorMessage = nil
            logger.info("Server started on port \(port)")

            // Load models in background (can be slow for large models)
            Task {
                await self.loadInstalledModels()
                await self.refreshDownloadStates()
                self.logger.info("All models loaded")
            }

            // Background registry update
            Task.detached { await reg.checkForUpdates() }
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to start server: \(error)")
        }
    }

    func stopServer() async {
        // Unload all models first to release C/GPU/CoreML resources
        await providerRouter.unregisterAll()
        loadedModels = []

        serverTask?.cancel()
        serverTask = nil
        serverRunning = false

        // Reset all model states to stopped (for installed) or notInstalled
        await refreshDownloadStates()
        logger.info("Server stopped, all models unloaded")
    }

    /// Force release all model resources and framework caches.
    func forceCleanupMemory() async {
        // Unregister all providers (calls cleanup on each)
        await providerRouter.unregisterAll()
        loadedModels = []

        // Clear framework-level GPU/MLX caches
        #if SPEECH_SWIFT_AVAILABLE
        MLX.GPU.clearCache()
        #endif

        await refreshDownloadStates()
        logger.info("Force memory cleanup completed")
    }

    // MARK: - Model Loading

    private func loadInstalledModels() async {
        guard let registry else { return }
        let allEntries = await registry.allModels()

        // Auto-load all installed models (skip user-disabled ones and unimplemented engines)
        let disabledIDs = Set(UserDefaults.standard.stringArray(forKey: AppConstants.disabledModelsKey) ?? [])
        for entry in allEntries where entry.engine == .sherpaOnnx || entry.engine == .whisperKit || entry.engine == .speechSwift || entry.engine.isCloud {
            guard !disabledIDs.contains(entry.id) else { continue }
            if entry.engine.isCloud {
                guard isCloudModelConfigured(entry) else { continue }
            } else {
                guard await modelManager.effectiveModelPath(entry.id) != nil else { continue }
            }
            await loadModelEngine(entry)
        }

        await registerApiNames()
        await updateAliases()
        await loadUserAliases()
        loadedModels = await providerRouter.allModels().map(\.id)
    }

    /// Load a single model into the engine.
    func loadModel(_ modelID: String) async {
        guard let entry = availableModels.first(where: { $0.id == modelID }) else { return }

        // Remove from disabled set (user explicitly re-enabled)
        var disabled = Set(UserDefaults.standard.stringArray(forKey: AppConstants.disabledModelsKey) ?? [])
        disabled.remove(modelID)
        UserDefaults.standard.set(Array(disabled), forKey: AppConstants.disabledModelsKey)

        await loadModelEngine(entry)
        await registerApiNames()
        await updateAliases()
        loadedModels = await providerRouter.allModels().map(\.id)
        await refreshDownloadStates()
    }

    /// Unload a single model from the engine (keep files).
    func unloadModel(_ modelID: String) async {
        guard let entry = availableModels.first(where: { $0.id == modelID }) else { return }
        if entry.type == .tts {
            await providerRouter.unregisterTTS(modelID)
        } else {
            await providerRouter.unregisterASR(modelID)
        }
        await modelManager.setModelStopped(modelID)

        // Persist user's choice to keep model stopped
        var disabled = Set(UserDefaults.standard.stringArray(forKey: AppConstants.disabledModelsKey) ?? [])
        disabled.insert(modelID)
        UserDefaults.standard.set(Array(disabled), forKey: AppConstants.disabledModelsKey)

        await registerApiNames()
        await updateAliases()
        loadedModels = await providerRouter.allModels().map(\.id)
        await refreshDownloadStates()
        logger.info("Unloaded model: \(modelID)")
    }

    private func loadModelEngine(_ entry: ModelRegistryEntry) async {
        let modelID = entry.id

        // speech-swift uses its own cache path, not effectiveModelPath
        if entry.engine == .speechSwift {
            guard !(await providerRouter.isModelLoaded(modelID)) else { return }
            do {
                await modelManager.setModelState(modelID, .extracting)
                await refreshDownloadStates()

                let hfModelID = entry.config.hfModelId ?? ""

                #if SPEECH_SWIFT_AVAILABLE
                if entry.type == .tts {
                    let model = try await SpeechSwiftTTS.loadModel(
                        hfModelID: hfModelID, progressHandler: { _, _ in }
                    )
                    let provider = SpeechSwiftTTS(
                        modelID: modelID, model: model as! Qwen3TTSModel,
                        voices: entry.voiceList ?? []
                    )
                    await providerRouter.registerTTS(provider, for: modelID)
                } else {
                    let model = try await SpeechSwiftASR.loadModel(
                        hfModelID: hfModelID, progressHandler: { _, _ in }
                    )
                    let provider = SpeechSwiftASR(
                        modelID: modelID, model: model as! Qwen3ASRModel,
                        languages: entry.languages
                    )
                    await providerRouter.registerASR(provider, for: modelID)
                }
                #else
                logger.warning("speech-swift not available at compile time for \(modelID)")
                await modelManager.setModelError(modelID, "speech-swift engine not compiled")
                return
                #endif

                await modelManager.setModelRunning(modelID)
                logger.info("Loaded speech-swift model: \(modelID)")
            } catch {
                logger.warning("Failed to load speech-swift \(modelID): \(error)")
                await modelManager.setModelError(modelID, error.localizedDescription)
                await refreshDownloadStates()
            }
            return
        }

        // Cloud engines: no local files, just create the provider
        if entry.engine.isCloud {
            guard !(await providerRouter.isModelLoaded(modelID)) else { return }
            do {
                let endpoint = entry.config.cloudEndpoint ?? ""
                let cloudModel = entry.config.cloudModel ?? modelID
                let keySettingsKey = entry.config.apiKeySettingsKey ?? ""
                let authHeader = entry.config.authHeader ?? "Authorization"
                let authPrefix = entry.config.authPrefix ?? "Bearer "
                let voices = entry.voiceList ?? []

                if entry.engine == .openaiCloud {
                    let provider = OpenAICloudTTS(
                        modelID: modelID, endpoint: endpoint, cloudModel: cloudModel,
                        apiKeySettingsKey: keySettingsKey, authHeader: authHeader,
                        authPrefix: authPrefix, voices: voices
                    )
                    await providerRouter.registerTTS(provider, for: modelID)
                } else if entry.engine == .mimoCloud {
                    let provider = MiMoCloudTTS(
                        modelID: modelID, endpoint: endpoint, cloudModel: cloudModel,
                        apiKeySettingsKey: keySettingsKey, authHeader: authHeader,
                        authPrefix: authPrefix, voices: voices
                    )
                    await providerRouter.registerTTS(provider, for: modelID)
                }

                await modelManager.setModelRunning(modelID)
                logger.info("Loaded cloud model: \(modelID)")
            } catch {
                logger.warning("Failed to load cloud \(modelID): \(error)")
                await modelManager.setModelError(modelID, error.localizedDescription)
                await refreshDownloadStates()
            }
            return
        }

        guard let modelPath = await modelManager.effectiveModelPath(modelID) else { return }
        guard !(await providerRouter.isModelLoaded(modelID)) else { return }

        do {
            // Show loading spinner for WhisperKit (CoreML compilation can be slow)
            if entry.engine == .whisperKit {
                await modelManager.setModelState(modelID, .extracting)
                await refreshDownloadStates()
            }

            switch entry.engine {
            case .sherpaOnnx:
                if entry.type == .tts {
                    guard let family = SherpaOnnxTTS.ModelFamily(rawValue: entry.family) else { return }
                    let provider = try SherpaOnnxTTS(
                        modelPath: modelPath, modelID: modelID, family: family,
                        config: entry.config, sampleRate: entry.sampleRate ?? 24000,
                        voices: entry.voiceList ?? []
                    )
                    await providerRouter.registerTTS(provider, for: modelID)
                } else {
                    let provider = try SherpaOnnxASR(
                        modelPath: modelPath, modelID: modelID,
                        family: entry.family, config: entry.config, languages: entry.languages
                    )
                    await providerRouter.registerASR(provider, for: modelID)
                }

            case .whisperKit:
                if entry.type == .tts {
                    let variant = entry.config.ttsKitVariant ?? "qwen3TTS_0_6b"
                    let provider = try await WhisperKitTTS(
                        modelID: modelID, modelPath: modelPath,
                        variant: variant, voices: entry.voiceList ?? []
                    )
                    await providerRouter.registerTTS(provider, for: modelID)
                } else {
                    let variant = entry.config.whisperKitVariant ?? "openai_whisper-base"
                    let provider = try await WhisperKitASR(
                        modelID: modelID, modelPath: modelPath,
                        variant: variant, languages: entry.languages
                    )
                    await providerRouter.registerASR(provider, for: modelID)
                }

            case .speechSwift:
                break // handled above

            case .openaiCloud, .mimoCloud:
                break // handled above (cloud early return)
            }

            await modelManager.setModelRunning(modelID)
            logger.info("Loaded model: \(modelID)")
        } catch {
            logger.warning("Failed to load \(modelID): \(error)")
            await modelManager.setModelError(modelID, error.localizedDescription)
            await refreshDownloadStates()
        }
    }

    private func updateAliases() async {
        let loadedIDs = Set(await providerRouter.allModels().map(\.id))
        if let firstTTS = availableModels.first(where: { $0.type == .tts && loadedIDs.contains($0.id) }) {
            await providerRouter.setAlias("tts-1", to: firstTTS.id)
            await providerRouter.setAlias("tts-1-hd", to: firstTTS.id)
        }
        if let firstASR = availableModels.first(where: { $0.type == .asr && loadedIDs.contains($0.id) }) {
            await providerRouter.setAlias("whisper-1", to: firstASR.id)
        }
    }

    /// Register api_id aliases for all loaded models (api_id → internal id).
    private func registerApiNames() async {
        let loadedIDs = Set(await providerRouter.allModels().map(\.id))
        for entry in availableModels where loadedIDs.contains(entry.id) {
            if let apiId = entry.apiId, apiId != entry.id {
                await providerRouter.setApiName(apiId, for: entry.id)
                await providerRouter.setAlias(apiId, to: entry.id)
            }
        }
    }

    // MARK: - User Aliases

    private func loadUserAliases() async {
        let saved = UserDefaults.standard.dictionary(forKey: AppConstants.userAliasesKey) as? [String: String] ?? [:]
        for (alias, target) in saved {
            await providerRouter.setAlias(alias, to: target)
        }
    }

    func setUserAlias(_ alias: String, to target: String) {
        var saved = UserDefaults.standard.dictionary(forKey: AppConstants.userAliasesKey) as? [String: String] ?? [:]
        saved[alias] = target
        UserDefaults.standard.set(saved, forKey: AppConstants.userAliasesKey)
        Task { await providerRouter.setAlias(alias, to: target) }
    }

    func removeUserAlias(_ alias: String) {
        var saved = UserDefaults.standard.dictionary(forKey: AppConstants.userAliasesKey) as? [String: String] ?? [:]
        saved.removeValue(forKey: alias)
        UserDefaults.standard.set(saved, forKey: AppConstants.userAliasesKey)
        Task { await providerRouter.removeAlias(alias) }
    }

    var userAliases: [String: String] {
        UserDefaults.standard.dictionary(forKey: AppConstants.userAliasesKey) as? [String: String] ?? [:]
    }

    // MARK: - Download Management

    func downloadModel(_ modelID: String) {
        guard let entry = availableModels.first(where: { $0.id == modelID }) else { return }

        // Cloud models don't download; just load them
        if entry.engine.isCloud {
            Task {
                await loadModelEngine(entry)
                await registerApiNames()
                await updateAliases()
                loadedModels = await providerRouter.allModels().map(\.id)
                await refreshDownloadStates()
            }
            return
        }

        // WhisperKit models use their SDK's download API
        if entry.engine == .whisperKit {
            downloadWhisperKitModel(entry)
            return
        }

        // speech-swift models use fromPretrained (download + init combined)
        if entry.engine == .speechSwift {
            downloadSpeechSwiftModel(entry)
            return
        }

        // Start progress polling
        let pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                await refreshDownloadStates()
            }
        }

        Task {
            do {
                try await modelManager.downloadModel(entry)
                pollTask.cancel()
                await refreshDownloadStates()
                await loadInstalledModels()
            } catch {
                pollTask.cancel()
                await refreshDownloadStates()
                logger.error("Download failed for \(modelID): \(error)")
            }
        }
    }

    private func downloadWhisperKitModel(_ entry: ModelRegistryEntry) {
        let modelID = entry.id
        Task {
            do {
                await modelManager.setModelDownloading(modelID)
                await refreshDownloadStates()

                let modelsDir = AppConstants.modelsDirectory
                try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

                let downloadedURL: URL
                if entry.type == .tts {
                    let variant = entry.config.ttsKitVariant ?? "qwen3TTS_0_6b"
                    downloadedURL = try await WhisperKitTTS.downloadModel(variant: variant, to: modelsDir)
                } else {
                    let variant = entry.config.whisperKitVariant ?? "openai_whisper-base"
                    downloadedURL = try await WhisperKitASR.downloadModel(variant: variant, to: modelsDir)
                }

                // Rename downloaded directory to our modelID so ModelManager recognizes it
                let modelDir = modelsDir.appendingPathComponent(modelID)
                if downloadedURL.lastPathComponent != modelID {
                    if FileManager.default.fileExists(atPath: modelDir.path) {
                        try FileManager.default.removeItem(at: modelDir)
                    }
                    try FileManager.default.moveItem(at: downloadedURL, to: modelDir)
                }

                // Pre-compile CoreML models so "Start" is instant for the user
                await modelManager.setModelState(modelID, .extracting)
                await refreshDownloadStates()
                logger.info("Pre-compiling CoreML models for \(modelID)...")
                await loadModelEngine(entry)

                // loadModelEngine sets .running on success or .error on failure
                await refreshDownloadStates()
                logger.info("WhisperKit model ready: \(modelID)")
            } catch {
                await modelManager.setModelError(modelID, error.localizedDescription)
                await refreshDownloadStates()
                logger.error("WhisperKit download failed for \(modelID): \(error)")
            }
        }
    }

    private func downloadSpeechSwiftModel(_ entry: ModelRegistryEntry) {
        let modelID = entry.id
        Task {
            do {
                await modelManager.setModelDownloading(modelID)
                await refreshDownloadStates()

                let hfModelID = entry.config.hfModelId ?? ""

                // fromPretrained combines download + init; bridge progress to our state
                let progressHandler: @Sendable (Double, String) -> Void = { [weak self] fraction, _ in
                    Task { @MainActor in
                        guard let self else { return }
                        await self.modelManager.setModelState(
                            modelID, .downloading(progress: fraction)
                        )
                        await self.refreshDownloadStates()
                    }
                }

                #if SPEECH_SWIFT_AVAILABLE
                if entry.type == .tts {
                    let model = try await SpeechSwiftTTS.loadModel(
                        hfModelID: hfModelID, progressHandler: progressHandler
                    )
                    let provider = SpeechSwiftTTS(
                        modelID: modelID, model: model as! Qwen3TTSModel,
                        voices: entry.voiceList ?? []
                    )
                    await providerRouter.registerTTS(provider, for: modelID)
                } else {
                    let model = try await SpeechSwiftASR.loadModel(
                        hfModelID: hfModelID, progressHandler: progressHandler
                    )
                    let provider = SpeechSwiftASR(
                        modelID: modelID, model: model as! Qwen3ASRModel,
                        languages: entry.languages
                    )
                    await providerRouter.registerASR(provider, for: modelID)
                }
                #else
                throw SpeechSwiftError.modelNotAvailable("SPEECH_SWIFT_AVAILABLE not set")
                #endif

                // Create sentinel directory so ModelManager recognizes as installed
                let sentinelDir = AppConstants.modelsDirectory.appendingPathComponent(modelID)
                try FileManager.default.createDirectory(at: sentinelDir, withIntermediateDirectories: true)
                let meta: [String: Any] = [
                    "engine": "speech-swift",
                    "hfModelId": hfModelID
                ]
                let metaData = try JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted)
                try metaData.write(to: sentinelDir.appendingPathComponent(".speech-swift-meta.json"))

                await modelManager.setModelRunning(modelID)
                await registerApiNames()
                await updateAliases()
                loadedModels = await providerRouter.allModels().map(\.id)
                await refreshDownloadStates()
                logger.info("speech-swift model ready: \(modelID)")
            } catch {
                await modelManager.setModelError(modelID, error.localizedDescription)
                await refreshDownloadStates()
                logger.error("speech-swift download failed for \(modelID): \(error)")
            }
        }
    }

    func deleteModel(_ modelID: String) {
        Task {
            // Unload first if running
            await unloadModel(modelID)
            do {
                // Clean up speech-swift's own model cache if applicable
                if let entry = availableModels.first(where: { $0.id == modelID }),
                   entry.engine == .speechSwift,
                   let hfModelID = entry.config.hfModelId {
                    let cacheBase = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/Caches/qwen3-speech")
                    let cacheDir = cacheBase.appendingPathComponent(
                        hfModelID.replacingOccurrences(of: "/", with: "_")
                    )
                    try? FileManager.default.removeItem(at: cacheDir)
                }
                try await modelManager.deleteModel(modelID)
                await refreshDownloadStates()
            } catch {
                logger.error("Delete failed for \(modelID): \(error)")
            }
        }
    }

    func cancelDownload(_ modelID: String) {
        Task {
            await modelManager.cancelDownload(modelID)
            await refreshDownloadStates()
        }
    }

    func downloadState(for modelID: String) -> ModelDownloadState {
        downloadStates[modelID] ?? .notInstalled
    }

    private func refreshDownloadStates() async {
        downloadStates = await modelManager.allStates(for: availableModels)
        // Override states for cloud models (they have no local files)
        for entry in availableModels where entry.engine.isCloud {
            if await providerRouter.isModelLoaded(entry.id) {
                downloadStates[entry.id] = .running
            } else if isCloudModelConfigured(entry) {
                downloadStates[entry.id] = .stopped
            } else {
                downloadStates[entry.id] = .notInstalled
            }
        }
    }

    // MARK: - Computed Helpers

    var ttsModels: [ModelRegistryEntry] {
        availableModels.filter { $0.type == .tts }
    }

    var localTTSModels: [ModelRegistryEntry] {
        availableModels.filter { $0.type == .tts && !$0.engine.isCloud }
    }

    var cloudTTSModels: [ModelRegistryEntry] {
        availableModels.filter { $0.type == .tts && $0.engine.isCloud }
    }

    var asrModels: [ModelRegistryEntry] {
        availableModels.filter { $0.type == .asr }
    }

    private func isCloudModelConfigured(_ entry: ModelRegistryEntry) -> Bool {
        guard let key = entry.config.apiKeySettingsKey else { return false }
        let apiKey = UserDefaults.standard.string(forKey: key) ?? ""
        return !apiKey.isEmpty
    }
}
