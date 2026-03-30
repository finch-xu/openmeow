actor ProviderRouter {
    // Key: modelID (not providerID) — each model gets its own provider instance
    private var ttsProviders: [String: any TTSProvider] = [:]
    private var asrProviders: [String: any ASRProvider] = [:]
    private var aliases: [String: String] = [:]
    private var apiNames: [String: String] = [:]  // id → api_id

    // MARK: - Register

    func registerTTS(_ provider: any TTSProvider, for modelID: String) {
        ttsProviders[modelID] = provider
    }

    func registerASR(_ provider: any ASRProvider, for modelID: String) {
        asrProviders[modelID] = provider
    }

    // MARK: - Unregister

    func unregisterTTS(_ modelID: String) async {
        if let provider = ttsProviders.removeValue(forKey: modelID) {
            await provider.cleanup()
        }
        aliases = aliases.filter { $0.value != modelID }
    }

    func unregisterASR(_ modelID: String) async {
        if let provider = asrProviders.removeValue(forKey: modelID) {
            await provider.cleanup()
        }
        aliases = aliases.filter { $0.value != modelID }
    }

    func unregisterAll() async {
        for (_, provider) in ttsProviders {
            await provider.cleanup()
        }
        for (_, provider) in asrProviders {
            await provider.cleanup()
        }
        ttsProviders.removeAll()
        asrProviders.removeAll()
        aliases.removeAll()
        apiNames.removeAll()
    }

    // MARK: - Aliases

    func setAlias(_ alias: String, to model: String) {
        aliases[alias] = model
    }

    func removeAlias(_ alias: String) {
        aliases.removeValue(forKey: alias)
    }

    func allAliases() -> [String: String] { aliases }

    func setApiName(_ apiName: String, for modelID: String) {
        apiNames[modelID] = apiName
    }

    // MARK: - Resolution

    struct ResolvedTTS: Sendable {
        let provider: any TTSProvider
        let resolvedModel: String
    }

    struct ResolvedASR: Sendable {
        let provider: any ASRProvider
        let resolvedModel: String
    }

    func resolveTTS(model: String) -> ResolvedTTS? {
        let resolved = aliases[model] ?? model
        guard let provider = ttsProviders[resolved] else { return nil }
        return ResolvedTTS(provider: provider, resolvedModel: resolved)
    }

    func resolveASR(model: String) -> ResolvedASR? {
        let resolved = aliases[model] ?? model
        guard let provider = asrProviders[resolved] else { return nil }
        return ResolvedASR(provider: provider, resolvedModel: resolved)
    }

    // MARK: - Listings

    struct ModelInfo: Sendable {
        let id: String
        let apiId: String?
        let type: String
        let provider: String
        let ready: Bool
    }

    func allModels() -> [ModelInfo] {
        var result: [ModelInfo] = []
        for (modelID, provider) in ttsProviders {
            result.append(ModelInfo(id: modelID, apiId: apiNames[modelID], type: "tts", provider: provider.providerID, ready: true))
        }
        for (modelID, provider) in asrProviders {
            result.append(ModelInfo(id: modelID, apiId: apiNames[modelID], type: "asr", provider: provider.providerID, ready: true))
        }
        return result.sorted { $0.id < $1.id }
    }

    func allTTSModelNames() -> [String] {
        Array(ttsProviders.keys.sorted())
    }

    func allASRModelNames() -> [String] {
        Array(asrProviders.keys.sorted())
    }

    func voices(for model: String) -> [VoiceInfo] {
        let resolved = aliases[model] ?? model
        guard let provider = ttsProviders[resolved] else { return [] }
        return provider.listVoices(for: resolved)
    }

    func allVoices() -> [VoiceInfo] {
        var result: [VoiceInfo] = []
        for (model, provider) in ttsProviders {
            result.append(contentsOf: provider.listVoices(for: model))
        }
        return result
    }

    func isModelLoaded(_ modelID: String) -> Bool {
        ttsProviders[modelID] != nil || asrProviders[modelID] != nil
    }
}
