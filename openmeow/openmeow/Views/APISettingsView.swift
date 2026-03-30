import SwiftUI

struct APISettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("listenAddress") private var listenAddress = "127.0.0.1"
    @AppStorage("serverPort") private var port = 23333
    @AppStorage(AppConstants.authEnabledKey) private var authEnabled = false
    @AppStorage(AppConstants.authTokenKey) private var authToken = ""
    @AppStorage(AppConstants.corsEnabledKey) private var corsEnabled = true
    @AppStorage(AppConstants.defaultTTSFormatKey) private var defaultTTSFormat = "opus"

    @State private var corsOrigins: [String] = []
    @State private var newOrigin = ""
    @State private var showingAddRedirect = false
    @State private var newRedirectAlias = ""
    @State private var newRedirectTarget = ""

    private var baseURL: String { "http://\(listenAddress):\(port)" }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ttsDefaultsSection
                corsSection
                authSection
                aliasSection
                endpointsSection
            }
            .padding(20)
        }
        .onAppear {
            loadCorsOrigins()
        }
    }

    // MARK: - TTS Defaults

    private var ttsDefaultsSection: some View {
        GroupBox {
            HStack(spacing: 8) {
                Text("Default Output Format")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $defaultTTSFormat) {
                    Text("Opus").tag("opus")
                    Text("AAC").tag("aac")
                    Text("WAV").tag("wav")
                    Text("FLAC").tag("flac")
                    Text("MP3").tag("mp3")
                    Text("PCM").tag("pcm")
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Text("Used when clients don't specify response_format")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } label: {
            Label("TTS", systemImage: "waveform")
                .font(.subheadline.weight(.medium))
        }
    }

    // MARK: - CORS

    private var corsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable CORS (Cross-Origin Requests)", isOn: $corsEnabled)

                if corsEnabled {
                    // Quick preset buttons
                    HStack(spacing: 8) {
                        Text("Presets")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Local") {
                            corsOrigins = AppConstants.corsLocalOrigins
                            saveCorsOrigins()
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        Button("LAN") {
                            corsOrigins = AppConstants.corsLANOrigins
                            saveCorsOrigins()
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        Button("All") {
                            corsOrigins = ["*"]
                            saveCorsOrigins()
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    }

                    // Current allowed IPs list
                    VStack(spacing: 2) {
                        ForEach(Array(corsOrigins.enumerated()), id: \.offset) { idx, origin in
                            HStack(spacing: 6) {
                                Text(origin)
                                    .font(.system(.caption, design: .monospaced))
                                Spacer()
                                Button {
                                    corsOrigins.remove(at: idx)
                                    saveCorsOrigins()
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(.red.opacity(0.7))
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                        }
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))

                    // Add custom IP
                    HStack(spacing: 6) {
                        TextField("192.168.0.0/16 or 10.0.0.1", text: $newOrigin)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                        Button("Add") {
                            let trimmed = newOrigin.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty, !corsOrigins.contains(trimmed) else { return }
                            corsOrigins.append(trimmed)
                            saveCorsOrigins()
                            newOrigin = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(newOrigin.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    Text("Enter IPs, hostnames, or CIDR ranges (e.g. 192.168.0.0/16). Use \"*\" to allow all origins.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } label: {
            Label("CORS", systemImage: "globe")
                .font(.subheadline.weight(.medium))
        }
    }

    // MARK: - Authentication

    private var authSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Bearer Token Authentication", isOn: $authEnabled)

                if authEnabled {
                    HStack(spacing: 8) {
                        Text("Token")
                            .frame(width: 50, alignment: .trailing)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        TextField("sk-...", text: $authToken)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                        Button {
                            authToken = generateToken()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .help("Generate random token")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(authToken, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .help("Copy token")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text("Requests must include: `Authorization: Bearer \(authToken.isEmpty ? "<token>" : authToken)`")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        } label: {
            Label("Authentication", systemImage: "lock.shield")
                .font(.subheadline.weight(.medium))
        }
    }

    // MARK: - Model Aliases

    private var aliasSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Available Models")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                let loadedModels = appState.availableModels.filter { entry in
                    appState.downloadState(for: entry.id).isInstalled
                }
                if loadedModels.isEmpty {
                    Text("No models installed")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    VStack(spacing: 2) {
                        ForEach(loadedModels) { entry in
                            HStack(spacing: 6) {
                                Text(entry.apiId ?? entry.id)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer()
                                runtimeBadge(entry.engine)
                                Text(entry.type.rawValue.uppercased())
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.quaternary)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.quaternary.opacity(0.5))
                            )
                        }
                    }
                }

                Divider().padding(.vertical, 4)

                Text("Model Redirects")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                let aliases = appState.userAliases
                if aliases.isEmpty && !showingAddRedirect {
                    Text("No redirects configured")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                ForEach(aliases.sorted(by: { $0.key < $1.key }), id: \.key) { alias, target in
                    redirectRow(alias: alias, target: target)
                }

                if showingAddRedirect {
                    newRedirectRow
                }

                Button {
                    showingAddRedirect = true
                } label: {
                    Label("Add Redirect", systemImage: "plus")
                        .font(.caption)
                }
                .controlSize(.small)
                .disabled(showingAddRedirect)
            }
        } label: {
            Label("Model Aliases", systemImage: "arrow.triangle.swap")
                .font(.subheadline.weight(.medium))
        }
    }

    // MARK: - API Endpoints

    private var endpointsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Base URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(baseURL + "/v1")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    endpointRow(method: "GET", path: "/health", desc: "Health check")
                    endpointRow(method: "GET", path: "/v1/models", desc: "List loaded models")
                    endpointRow(method: "GET", path: "/v1/voices", desc: "List available voices")
                    endpointRow(method: "POST", path: "/v1/audio/speech", desc: "Text-to-Speech (TTS)")
                    endpointRow(method: "POST", path: "/v1/audio/transcriptions", desc: "Speech-to-Text (ASR)")
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("TTS Example")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(ttsExample)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("ASR Example")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(asrExample)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        } label: {
            Label("API Endpoints (OpenAI Compatible)", systemImage: "doc.text")
                .font(.subheadline.weight(.medium))
        }
    }

    // MARK: - Redirect Rows

    private static let presetAliases: [(name: String, type: String)] = [
        ("whisper-1", "ASR"),
        ("sensevoice", "ASR"),
        ("tts-1", "TTS"),
        ("tts-1-hd", "TTS"),
        ("kokoro", "TTS"),
    ]

    private var installedModels: [ModelRegistryEntry] {
        appState.availableModels.filter { appState.downloadState(for: $0.id).isInstalled }
    }

    private func redirectRow(alias: String, target: String) -> some View {
        HStack(spacing: 6) {
            Text(alias)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .frame(maxWidth: 120, alignment: .leading)
                .lineLimit(1)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(target)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                appState.removeUserAlias(alias)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .controlSize(.small)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.5)))
    }

    private var newRedirectRow: some View {
        HStack(spacing: 6) {
            comboBox(
                text: $newRedirectAlias,
                placeholder: "Alias name",
                options: Self.presetAliases
                    .filter { preset in !appState.userAliases.keys.contains(preset.name) }
                    .map { ($0.name, $0.type) }
            )
            .frame(maxWidth: 140)

            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            comboBox(
                text: $newRedirectTarget,
                placeholder: "Target model",
                options: installedModels.map { ($0.apiId ?? $0.id, $0.type.rawValue.uppercased()) }
            )

            Button("Add") {
                let name = newRedirectAlias.trimmingCharacters(in: .whitespaces)
                let target = newRedirectTarget.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, !target.isEmpty else { return }
                appState.setUserAlias(name, to: target)
                newRedirectAlias = ""
                newRedirectTarget = ""
                showingAddRedirect = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(
                newRedirectAlias.trimmingCharacters(in: .whitespaces).isEmpty ||
                newRedirectTarget.trimmingCharacters(in: .whitespaces).isEmpty
            )

            Button("Cancel") {
                showingAddRedirect = false
                newRedirectAlias = ""
                newRedirectTarget = ""
            }
            .controlSize(.small)
        }
    }

    /// A TextField with a dropdown Menu button for preset options.
    private func comboBox(text: Binding<String>, placeholder: String, options: [(String, String)]) -> some View {
        HStack(spacing: 0) {
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))

            Menu {
                ForEach(options, id: \.0) { name, tag in
                    Button {
                        text.wrappedValue = name
                    } label: {
                        HStack {
                            Text(name)
                            Spacer()
                            Text(tag)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    // MARK: - Helpers

    private func endpointRow(method: String, path: String, desc: String) -> some View {
        HStack(spacing: 8) {
            Text(method)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(method == "GET" ? .green : .blue)
                .frame(width: 36, alignment: .trailing)
            Text(path)
                .font(.system(size: 11, design: .monospaced))
            Spacer()
            Text(desc)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func runtimeBadge(_ engine: EngineType) -> some View {
        let (text, color): (String, Color) = switch engine {
        case .sherpaOnnx: ("ONNX", .orange)
        case .speechSwift: ("MLX", .purple)
        case .whisperKit: ("CoreML", .cyan)
        }
        return Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var ttsExample: String {
        let auth = authEnabled && !authToken.isEmpty ? "\n  -H \"Authorization: Bearer \(authToken)\" \\" : ""
        let ext = defaultTTSFormat == "pcm" ? "raw" : defaultTTSFormat
        return """
        curl \(baseURL)/v1/audio/speech \\\(auth)
          -H "Content-Type: application/json" \\
          -d '{"model":"tts-1","input":"Hello!","voice":"af_heart"}' \\
          --output speech.\(ext)
        """
    }

    private var asrExample: String {
        let auth = authEnabled && !authToken.isEmpty ? "\n  -H \"Authorization: Bearer \(authToken)\" \\" : ""
        return """
        curl \(baseURL)/v1/audio/transcriptions \\\(auth)
          -F file=@audio.wav \\
          -F model=whisper-1
        """
    }

    private func generateToken() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let random = (0..<32).map { _ in chars.randomElement()! }
        return "sk-" + String(random)
    }

    // MARK: - CORS Persistence

    private func loadCorsOrigins() {
        corsOrigins = UserDefaults.standard.stringArray(forKey: AppConstants.corsOriginsKey)
            ?? AppConstants.corsLocalOrigins
    }

    private func saveCorsOrigins() {
        UserDefaults.standard.set(corsOrigins, forKey: AppConstants.corsOriginsKey)
    }
}
