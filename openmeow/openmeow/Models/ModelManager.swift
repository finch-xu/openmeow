import Foundation
import CryptoKit
import OSLog

actor ModelManager {
    private let modelsDirectory: URL
    private var downloadStates: [String: ModelDownloadState] = [:]
    private var activeTasks: [String: Task<Void, any Error>] = [:]
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "ModelManager")

    init() {
        modelsDirectory = AppConstants.modelsDirectory
    }

    // MARK: - Directory Management

    func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Model State

    func isModelReady(_ modelID: String) -> Bool {
        FileManager.default.fileExists(
            atPath: modelsDirectory.appendingPathComponent(modelID).path
        )
    }

    func modelPath(_ modelID: String) -> String {
        modelsDirectory.appendingPathComponent(modelID).path
    }

    /// Returns model path if installed, nil otherwise.
    func effectiveModelPath(_ modelID: String) -> String? {
        isModelReady(modelID) ? modelPath(modelID) : nil
    }

    func installedModels() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: modelsDirectory.path))?
            .filter { !$0.hasPrefix(".") } ?? []
    }

    func stateForModel(_ modelID: String) -> ModelDownloadState {
        if let state = downloadStates[modelID] {
            return state
        }
        return isModelReady(modelID) ? .stopped : .notInstalled
    }

    func allStates(for entries: [ModelRegistryEntry]) -> [String: ModelDownloadState] {
        var result: [String: ModelDownloadState] = [:]
        for entry in entries {
            result[entry.id] = stateForModel(entry.id)
        }
        return result
    }

    private func updateState(_ modelID: String, _ state: ModelDownloadState) {
        downloadStates[modelID] = state
    }

    func setModelRunning(_ modelID: String) {
        downloadStates[modelID] = .running
    }

    func setModelStopped(_ modelID: String) {
        if isModelReady(modelID) {
            downloadStates[modelID] = .stopped
        }
    }

    func setModelError(_ modelID: String, _ message: String) {
        downloadStates[modelID] = .error(message)
    }

    func setModelDownloading(_ modelID: String) {
        downloadStates[modelID] = .downloading(progress: 0)
    }

    func setModelState(_ modelID: String, _ state: ModelDownloadState) {
        downloadStates[modelID] = state
    }

    // MARK: - Download

    func downloadModel(_ entry: ModelRegistryEntry) async throws {
        let modelID = entry.id
        guard stateForModel(modelID) != .stopped else { return }
        // If files already exist on disk (e.g. after an error state), restore to stopped
        if isModelReady(modelID) {
            updateState(modelID, .stopped)
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }

            do {
                await self.updateState(modelID, .downloading(progress: 0))

                switch entry.download.source {
                case .githubRelease, .customUrl:
                    try await self.downloadHTTP(entry)
                case .huggingface:
                    try await self.downloadHuggingFace(entry)
                case .modelscope:
                    throw ModelManagerError.unsupportedSource("modelscope")
                case .whisperKitManaged:
                    throw ModelManagerError.unsupportedSource("whisperkit-managed: use AppState.downloadWhisperKitModel instead")
                case .cloudManaged:
                    throw ModelManagerError.unsupportedSource("cloud-managed: cloud models are handled by AppState directly")
                }

                await self.updateState(modelID, .stopped)
                await self.logger.info("Model \(modelID) installed successfully")
            } catch {
                if !Task.isCancelled {
                    await self.updateState(modelID, .error(error.localizedDescription))
                    await self.logger.error("Failed to download \(modelID): \(error)")
                }
                throw error
            }
        }

        activeTasks[modelID] = task
        try await task.value
        activeTasks[modelID] = nil
    }

    // MARK: - HTTP Download (GitHub Releases)

    private func downloadHTTP(_ entry: ModelRegistryEntry) async throws {
        guard let url = URL(string: entry.download.url) else {
            throw ModelManagerError.invalidURL(entry.download.url)
        }

        let modelID = entry.id

        // Download with progress tracking
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("download")

        let (bytes, response) = try await URLSession.shared.bytes(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            throw ModelManagerError.downloadFailed("HTTP \(httpResponse.statusCode)")
        }

        let totalBytes = response.expectedContentLength
        var downloadedBytes: Int64 = 0
        let fileHandle = try FileHandle(forWritingTo: {
            FileManager.default.createFile(atPath: tempURL.path, contents: nil)
            return tempURL
        }())

        defer {
            try? fileHandle.close()
            try? FileManager.default.removeItem(at: tempURL)
        }

        var buffer = Data()
        let chunkSize = 256 * 1024 // 256KB chunks for progress updates

        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= chunkSize {
                try fileHandle.write(contentsOf: buffer)
                downloadedBytes += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                if totalBytes > 0 {
                    let progress = Double(downloadedBytes) / Double(totalBytes)
                    await updateState(modelID, .downloading(progress: progress))
                }
            }
        }

        // Write remaining bytes
        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: buffer)
        }
        try fileHandle.close()

        // Verify checksum before extraction
        try verifyChecksum(tempURL, expected: entry.download.checksumSha256)

        // Extract
        await updateState(modelID, .extracting)
        try ensureDirectoryExists()

        switch entry.download.extractFormat {
        case .tarBz2:
            try extractTarBz2(tempURL, to: modelsDirectory)
        case .tarGz:
            try extractTarGz(tempURL, to: modelsDirectory)
        case .zip:
            try extractZip(tempURL, to: modelsDirectory)
        case .none:
            // Move file directly
            let dest = modelsDirectory.appendingPathComponent(modelID)
            try FileManager.default.moveItem(at: tempURL, to: dest)
        }

        // Rename extracted directory to model ID if needed
        if let extractedName = entry.download.extractedDirName, extractedName != modelID {
            let extractedPath = try validatePathWithinContainer(extractedName, container: modelsDirectory)
            let targetPath = try validatePathWithinContainer(modelID, container: modelsDirectory)
            if FileManager.default.fileExists(atPath: extractedPath.path),
               !FileManager.default.fileExists(atPath: targetPath.path) {
                try FileManager.default.moveItem(at: extractedPath, to: targetPath)
            }
        }

        // Download additional files
        if let additionalFiles = entry.download.additionalFiles {
            let modelDir = modelsDirectory.appendingPathComponent(modelID)
            for file in additionalFiles {
                guard let fileURL = URL(string: file.url) else { continue }
                let (fileTempURL, _) = try await URLSession.shared.download(from: fileURL)
                let destPath = try validatePathWithinContainer(file.destinationPath, container: modelDir)
                let destSubdir = destPath.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: destSubdir, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: destPath)
                try FileManager.default.moveItem(at: fileTempURL, to: destPath)
            }
        }
    }

    // MARK: - HuggingFace Download

    private func downloadHuggingFace(_ entry: ModelRegistryEntry) async throws {
        // For HuggingFace models, we use the HF HTTP API to download
        // The URL is like https://huggingface.co/aufklarer/Qwen3-TTS-12Hz-0.6B-CustomVoice-MLX-4bit
        // We need to list files via API and download each one

        let modelID = entry.id
        let hfModelID = entry.config.hfModelId ?? extractHFModelID(from: entry.download.url)
        guard let hfModelID else {
            throw ModelManagerError.invalidURL(entry.download.url)
        }

        let destDir = modelsDirectory.appendingPathComponent(modelID)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        // List files via HF API
        let apiURL = URL(string: "https://huggingface.co/api/models/\(hfModelID)")!
        let (data, _) = try await URLSession.shared.data(from: apiURL)

        // Parse siblings (file list)
        struct HFModelInfo: Codable {
            struct Sibling: Codable { let rfilename: String }
            let siblings: [Sibling]?
        }

        let modelInfo = try JSONDecoder().decode(HFModelInfo.self, from: data)
        let files = modelInfo.siblings?.map(\.rfilename) ?? []
        let totalFiles = files.count
        guard totalFiles > 0 else {
            throw ModelManagerError.downloadFailed("No files found in HuggingFace repo")
        }

        // Download each file
        for (index, filename) in files.enumerated() {
            let progress = Double(index) / Double(totalFiles)
            await updateState(modelID, .downloading(progress: progress))

            // Validate filename doesn't escape the model directory
            let destFile = try validatePathWithinContainer(filename, container: destDir)

            let encodedFilename = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
            let fileURL = URL(string: "https://huggingface.co/\(hfModelID)/resolve/main/\(encodedFilename)")!
            let (tempURL, _) = try await URLSession.shared.download(from: fileURL)

            let destSubdir = destFile.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: destSubdir, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destFile)
            try FileManager.default.moveItem(at: tempURL, to: destFile)
        }
    }

    private func extractHFModelID(from url: String) -> String? {
        // https://huggingface.co/aufklarer/Qwen3-ASR-0.6B-MLX-4bit -> aufklarer/Qwen3-ASR-0.6B-MLX-4bit
        guard let parsed = URL(string: url),
              parsed.host?.contains("huggingface") == true else { return nil }
        let components = parsed.pathComponents.filter { $0 != "/" }
        guard components.count >= 2 else { return nil }
        return "\(components[0])/\(components[1])"
    }

    // MARK: - Delete

    func deleteModel(_ modelID: String) throws {
        let path = modelsDirectory.appendingPathComponent(modelID)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
        downloadStates[modelID] = .notInstalled
        logger.info("Model \(modelID) deleted")
    }

    // MARK: - Cancel

    func cancelDownload(_ modelID: String) {
        activeTasks[modelID]?.cancel()
        activeTasks[modelID] = nil
        downloadStates[modelID] = .notInstalled
    }

    // MARK: - Path Safety

    /// Validate that a relative path doesn't escape its container directory.
    /// Rejects paths containing ".." components and verifies the resolved absolute path stays within the container.
    private func validatePathWithinContainer(_ relativePath: String, container: URL) throws -> URL {
        let components = relativePath.components(separatedBy: "/")
        guard !components.contains("..") else {
            throw ModelManagerError.downloadFailed("Rejected path with '..': \(relativePath)")
        }
        let resolved = container.appendingPathComponent(relativePath).standardizedFileURL
        let containerStd = container.standardizedFileURL
        guard resolved.path.hasPrefix(containerStd.path + "/") || resolved.path == containerStd.path else {
            throw ModelManagerError.downloadFailed("Path escapes container: \(relativePath)")
        }
        return resolved
    }

    // MARK: - Checksum Verification

    /// Verify SHA256 checksum of a downloaded file. Skips if expected is nil.
    private func verifyChecksum(_ fileURL: URL, expected: String?) throws {
        guard let expected, !expected.isEmpty else { return }
        let data = try Data(contentsOf: fileURL)
        let hash = SHA256.hash(data: data)
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        guard hex == expected.lowercased() else {
            throw ModelManagerError.downloadFailed(
                "Checksum mismatch: expected \(expected.prefix(16))..., got \(hex.prefix(16))..."
            )
        }
    }

    // MARK: - Archive Extraction

    private func runProcess(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ModelManagerError.extractionFailed("\(executable) exited with \(process.terminationStatus)")
        }
    }

    private func extractTarBz2(_ archive: URL, to destination: URL) throws {
        try runProcess(executable: "/usr/bin/tar", arguments: [
            "xjf", archive.path, "-C", destination.path,
            "--no-same-owner", "--no-same-permissions"
        ])
    }

    private func extractTarGz(_ archive: URL, to destination: URL) throws {
        try runProcess(executable: "/usr/bin/tar", arguments: [
            "xzf", archive.path, "-C", destination.path,
            "--no-same-owner", "--no-same-permissions"
        ])
    }

    private func extractZip(_ archive: URL, to destination: URL) throws {
        try runProcess(executable: "/usr/bin/unzip", arguments: ["-o", "-q", archive.path, "-d", destination.path])
    }
}

// MARK: - Errors

nonisolated enum ModelManagerError: Error, CustomStringConvertible {
    case invalidURL(String)
    case downloadFailed(String)
    case extractionFailed(String)
    case unsupportedSource(String)

    var description: String {
        switch self {
        case .invalidURL(let url): "Invalid download URL: \(url)"
        case .downloadFailed(let msg): "Download failed: \(msg)"
        case .extractionFailed(let msg): "Extraction failed: \(msg)"
        case .unsupportedSource(let src): "Unsupported download source: \(src)"
        }
    }
}
