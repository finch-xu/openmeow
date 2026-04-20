import SwiftUI

struct SettingsContentView: View {
    @Environment(\.omTheme) private var theme
    @Environment(AppState.self) private var appState
    @AppStorage(AppConstants.serverPortKey) private var port = AppConstants.defaultPort
    @AppStorage(AppConstants.listenAddressKey) private var listenAddress = "127.0.0.1"
    @AppStorage("appLanguage") private var appLanguage = "system"
    @AppStorage("omAccentColor") private var accentRaw: Int = Int(OMAccent.inkBlue.rawValue)
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    @State private var pendingPort: String = ""
    @State private var needsRestart = false
    @State private var languageNeedsRestart = false
    @State private var showDeleteAllAlert = false
    @State private var isDeletingAllModels = false

    var body: some View {
        VStack(spacing: 0) {
            OMPageHeader(title: "Settings",
                         subtitle: "Server, appearance, and language")

            ScrollView {
                VStack(spacing: 14) {
                    serverCard
                    appearanceCard
                    storageCard
                    aboutCard
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(theme.bg)
        }
        .background(theme.bg)
        .onAppear { pendingPort = "\(port)" }
        .alert("Delete all downloaded models?", isPresented: $showDeleteAllAlert) {
            Button("Delete all", role: .destructive) {
                isDeletingAllModels = true
                Task {
                    await appState.deleteAllModels()
                    isDeletingAllModels = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop all running engines and permanently remove every model file in \(AppConstants.modelsDirectory.path). You will need to re-download any model you want to use again.")
        }
    }

    private var serverCard: some View {
        OMCard(title: "Server", subtitle: "Changes require a restart") {
            VStack(spacing: 14) {
                SettingsRow("Port") {
                    HStack(spacing: 8) {
                        TextField("23333", text: $pendingPort)
                            .textFieldStyle(.plain)
                            .font(.omMono)
                            .foregroundStyle(theme.ink)
                            .padding(.horizontal, 10)
                            .frame(width: 120, height: 28)
                            .background(RoundedRectangle(cornerRadius: OMRadius.sm).fill(theme.surface))
                            .overlay(RoundedRectangle(cornerRadius: OMRadius.sm).strokeBorder(theme.divider, lineWidth: 1))
                            .onSubmit { applyPort() }
                        if needsRestart { restartInline }
                    }
                }

                SettingsRow("Listen on") {
                    HStack(spacing: 4) {
                        chipButton(label: "Localhost only", active: listenAddress == "127.0.0.1") {
                            listenAddress = "127.0.0.1"; needsRestart = true
                        }
                        chipButton(label: "All interfaces", active: listenAddress == "0.0.0.0") {
                            listenAddress = "0.0.0.0"; needsRestart = true
                        }
                    }
                }

                SettingsRow("Launch at login") {
                    OMSwitch(isOn: $launchAtLogin)
                }
            }
        }
    }

    private var restartInline: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10)).foregroundStyle(theme.warn)
            Text("Restart required")
                .font(.omCaption).foregroundStyle(theme.ink3)
            OMButton(title: "Restart", variant: .primary, size: .sm) {
                Task {
                    await appState.stopServer()
                    appState.serverPort = port
                    await appState.startServer()
                    needsRestart = false
                }
            }
        }
    }

    private func applyPort() {
        if let newPort = Int(pendingPort), newPort > 0, newPort < 65536 {
            port = newPort
            needsRestart = true
        } else {
            pendingPort = "\(port)"
        }
    }

    private var appearanceCard: some View {
        OMCard(title: "Appearance") {
            VStack(spacing: 14) {
                SettingsRow("Theme") {
                    Text("Follows the system — toggle macOS light/dark to switch.")
                        .font(.omCaption)
                        .foregroundStyle(theme.ink3)
                }

                SettingsRow("Accent") {
                    HStack(spacing: 10) {
                        ForEach(OMAccent.allCases) { option in
                            accentSwatch(option)
                        }
                    }
                }

                SettingsRow("Language") {
                    OMMenuPicker(languageLabel, width: 220) {
                        Button("System default") { setLanguage("system") }
                        Button("English") { setLanguage("en") }
                        Button("简体中文") { setLanguage("zh-Hans") }
                    }
                }

                if languageNeedsRestart {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10)).foregroundStyle(theme.warn)
                        Text("Restart the app to apply the language change.")
                            .font(.omCaption).foregroundStyle(theme.ink3)
                    }
                }
            }
        }
    }

    private func accentSwatch(_ accent: OMAccent) -> some View {
        let isActive = UInt32(accentRaw) == accent.rawValue
        return Button {
            accentRaw = Int(accent.rawValue)
        } label: {
            Circle()
                .fill(accent.color)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle().strokeBorder(
                        isActive ? theme.ink : theme.divider,
                        lineWidth: isActive ? 2 : 1
                    )
                )
                .padding(isActive ? 2 : 0)
                .overlay(
                    Circle().strokeBorder(theme.bg, lineWidth: isActive ? 2 : 0)
                        .padding(2)
                )
        }
        .buttonStyle(.plain)
    }

    private var languageLabel: String {
        switch appLanguage {
        case "en": "English"
        case "zh-Hans": "简体中文"
        default: "System default"
        }
    }

    private func setLanguage(_ code: String) {
        appLanguage = code
        if code == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
        languageNeedsRestart = true
    }

    private var storageCard: some View {
        OMCard(title: "Storage", subtitle: "Local model files") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Stops every loaded engine and deletes all downloaded model files. Cloud-only models are unaffected.")
                    .font(.omCaption)
                    .foregroundStyle(theme.ink3)

                OMButton(
                    title: isDeletingAllModels ? "Deleting…" : "Delete all models",
                    variant: .danger
                ) {
                    showDeleteAllAlert = true
                }
                .disabled(isDeletingAllModels)
            }
        }
    }

    private var aboutCard: some View {
        OMCard(title: "About") {
            VStack(spacing: 0) {
                OMKV(key: "Version", value: "v\(appVersion) (build \(appBuild))")
                OMKV(key: "License", value: "MIT")
                OMKV(key: "Repository", value: "github.com/finch-xu/openmeow")
                OMKV(key: "API base", value: "http://\(listenAddress):\(port)/v1")

                HStack(spacing: 8) {
                    OMButton(title: "Sponsor", icon: OMSymbol.heart) {
                        if let url = URL(string: "https://github.com/sponsors/finch-xu") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    OMButton(title: "Report issue", icon: OMSymbol.link) {
                        if let url = URL(string: "https://github.com/finch-xu/openmeow/issues/new") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .padding(.top, 14)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? AppConstants.version
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    private func chipButton(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? theme.accent : theme.ink2)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: OMRadius.sm)
                        .fill(active ? theme.accentSoft : theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OMRadius.sm)
                        .strokeBorder(active ? .clear : theme.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings row (140px label | value)

private struct SettingsRow<Value: View>: View {
    @Environment(\.omTheme) private var theme
    let label: String
    let value: Value

    init(_ label: String, @ViewBuilder _ value: () -> Value) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .font(.omBody)
                .foregroundStyle(theme.ink3)
                .frame(width: 140, alignment: .leading)
            value
            Spacer(minLength: 0)
        }
    }
}
