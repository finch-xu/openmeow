import SwiftUI

struct SettingsContentView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("serverPort") private var port = 23333
    @AppStorage("listenAddress") private var listenAddress = "127.0.0.1"
    @AppStorage("appLanguage") private var appLanguage = "system"

    @State private var pendingPort: String = ""
    @State private var needsRestart = false
    @State private var languageNeedsRestart = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Server
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Port")
                                .frame(width: 70, alignment: .trailing)
                            TextField("23333", text: $pendingPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .onSubmit { applyPort() }
                            Spacer()
                        }

                        HStack {
                            Text("Listen")
                                .frame(width: 70, alignment: .trailing)
                            Picker("", selection: $listenAddress) {
                                Text("Localhost (127.0.0.1)").tag("127.0.0.1")
                                Text("All interfaces (0.0.0.0)").tag("0.0.0.0")
                            }
                            .labelsHidden()
                            Spacer()
                        }
                        .onChange(of: listenAddress) { needsRestart = true }

                        if needsRestart {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                Text("Restart required")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Restart") {
                                    Task {
                                        await appState.stopServer()
                                        appState.serverPort = port
                                        await appState.startServer()
                                        needsRestart = false
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                } label: {
                    Label("Server", systemImage: "network")
                        .font(.subheadline.weight(.medium))
                }

                // Language
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Language")
                                .frame(width: 70, alignment: .trailing)
                            Picker("", selection: $appLanguage) {
                                Text("System Default").tag("system")
                                Text("English").tag("en")
                                Text("简体中文").tag("zh-Hans")
                            }
                            .labelsHidden()
                            Spacer()
                        }
                        .onChange(of: appLanguage) { _, newValue in
                            if newValue == "system" {
                                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                            } else {
                                UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                            }
                            languageNeedsRestart = true
                        }

                        if languageNeedsRestart {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                Text("Restart app to apply")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } label: {
                    Label("Language", systemImage: "globe")
                        .font(.subheadline.weight(.medium))
                }

                // About
                GroupBox {
                    VStack(spacing: 10) {
                        InfoRow(label: "Version", value: AppConstants.version)
                        InfoRow(label: "API URL", value: "http://\(listenAddress):\(port)/v1")
                    }
                } label: {
                    Label("About", systemImage: "info.circle")
                        .font(.subheadline.weight(.medium))
                }
            }
            .padding(20)
        }
        .onAppear { pendingPort = "\(port)" }
    }

    private func applyPort() {
        if let newPort = Int(pendingPort), newPort > 0, newPort < 65536 {
            port = newPort
            needsRestart = true
        } else {
            pendingPort = "\(port)"
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Spacer()
        }
    }
}
