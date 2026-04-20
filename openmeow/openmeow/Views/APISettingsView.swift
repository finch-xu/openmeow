import SwiftUI

struct APISettingsView: View {
    @Environment(\.omTheme) private var theme
    @Environment(AppState.self) private var appState
    @AppStorage(AppConstants.listenAddressKey) private var listenAddress = "127.0.0.1"
    @AppStorage(AppConstants.serverPortKey) private var port = AppConstants.defaultPort
    @AppStorage(AppConstants.authEnabledKey) private var authEnabled = false
    @AppStorage(AppConstants.authTokenKey) private var authToken = ""
    @AppStorage(AppConstants.corsEnabledKey) private var corsEnabled = true

    @State private var corsOrigins: [String] = []
    @State private var newOrigin = ""
    @State private var isAddingOrigin = false
    @State private var isAddingAlias = false
    @State private var newRedirectAlias = ""
    @State private var newRedirectTarget = ""
    @State private var copiedURL = false

    private var baseURL: String { "http://\(listenAddress):\(port)/v1" }

    var body: some View {
        VStack(spacing: 0) {
            OMPageHeader(
                title: "API",
                subtitle: "HTTP endpoint configuration and examples"
            )

            ScrollView {
                VStack(spacing: 14) {
                    heroCard
                    endpointsCard
                    exampleCard
                    securityCard
                    aliasesCard
                }
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(theme.bg)
        }
        .background(theme.bg)
        .onAppear { loadCorsOrigins() }
    }

    private var heroCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BASE URL")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(theme.ink3)
                Text(baseURL)
                    .font(.omMonoHero)
                    .foregroundStyle(theme.ink)
            }
            Spacer()
            OMButton(title: copiedURL ? "Copied" : "Copy",
                     icon: copiedURL ? OMSymbol.check : OMSymbol.copy) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(baseURL, forType: .string)
                copiedURL = true
                Task { try? await Task.sleep(for: .seconds(1.2)); copiedURL = false }
            }
            OMButton(title: "Open docs", icon: OMSymbol.link, variant: .primary) {
                if let url = URL(string: "https://github.com/finch-xu/openmeow#api") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: OMRadius.lg).fill(theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OMRadius.lg).strokeBorder(theme.divider, lineWidth: 1)
        )
    }

    private struct Endpoint { let method: String; let path: String; let desc: String }
    private let endpoints: [Endpoint] = [
        .init(method: "POST", path: "/v1/audio/speech", desc: "Text-to-Speech"),
        .init(method: "POST", path: "/v1/audio/transcriptions", desc: "Speech-to-Text"),
        .init(method: "POST", path: "/v1/chat/completions", desc: "Chat-style TTS"),
        .init(method: "GET",  path: "/v1/models", desc: "List loaded models"),
        .init(method: "GET",  path: "/v1/voices", desc: "List available voices"),
        .init(method: "GET",  path: "/health", desc: "Health check")
    ]

    private var endpointsCard: some View {
        OMCard(title: "Endpoints", subtitle: "OpenAI-compatible — drop into any client") {
            VStack(spacing: 6) {
                ForEach(endpoints, id: \.path) { e in
                    HStack(spacing: 12) {
                        Text(e.method)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(e.method == "GET" ? theme.ok : theme.accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .frame(minWidth: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(e.method == "GET" ? theme.okSoft : theme.accentSoft)
                            )
                        Text(e.path)
                            .font(.omMono).foregroundStyle(theme.ink)
                        Spacer()
                        Text(e.desc)
                            .font(.omCaption).foregroundStyle(theme.ink3)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: OMRadius.sm).fill(theme.surface2)
                    )
                }
            }
        }
    }

    private var exampleCard: some View {
        OMCard(title: "Example · TTS") {
            OMButton(title: "Copy", icon: OMSymbol.copy, size: .sm) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ttsExample, forType: .string)
            }
        } content: {
            Text(ttsExample)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(theme.ink)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .background(
                    RoundedRectangle(cornerRadius: OMRadius.sm).fill(theme.codeBg)
                )
        }
    }

    private var ttsExample: String {
        let auth = authEnabled && !authToken.isEmpty
            ? "\n  -H \"Authorization: Bearer \(authToken)\" \\" : ""
        return """
        # Generate speech from text
        curl -X POST \\\(auth)
          \(baseURL)/audio/speech \\
          -H "Content-Type: application/json" \\
          -d '{"model":"tts-1","input":"Hello!","voice":"af_heart"}' \\
          --output speech.mp3
        """
    }

    private var securityCard: some View {
        OMCard(title: "Security") {
            VStack(alignment: .leading, spacing: 14) {
                OMToggleRow(
                    icon: OMSymbol.lock,
                    label: "Bearer token auth",
                    desc: "Require Authorization: Bearer <token> on all requests",
                    isOn: $authEnabled
                )
                if authEnabled {
                    HStack(spacing: 6) {
                        Text(authToken.isEmpty ? "No token set" : authToken.maskedSecret())
                            .font(.omMono)
                            .foregroundStyle(theme.ink)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: OMRadius.sm).fill(theme.surface2)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: OMRadius.sm).strokeBorder(theme.divider2, lineWidth: 1)
                            )
                        OMIconButton(icon: OMSymbol.refresh, variant: .bordered, help: "Regenerate") {
                            authToken = generateToken()
                        }
                        OMIconButton(icon: OMSymbol.copy, variant: .bordered, help: "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(authToken, forType: .string)
                        }
                    }
                    .padding(.leading, 28)
                }

                OMToggleRow(
                    icon: OMSymbol.globe,
                    label: "CORS",
                    desc: "Cross-origin requests from browsers",
                    isOn: $corsEnabled
                )
                if corsEnabled {
                    originChipRow
                        .padding(.leading, 28)
                }
            }
        }
    }

    private var originChipRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(["Local", "LAN", "All"], id: \.self) { preset in
                    Button {
                        switch preset {
                        case "Local": corsOrigins = AppConstants.corsLocalOrigins
                        case "LAN":   corsOrigins = AppConstants.corsLANOrigins
                        default:      corsOrigins = ["*"]
                        }
                        saveCorsOrigins()
                    } label: {
                        Text(preset)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.ink2)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .overlay(
                                RoundedRectangle(cornerRadius: OMRadius.xs).strokeBorder(theme.divider, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            FlowLayout(spacing: 6) {
                ForEach(corsOrigins, id: \.self) { origin in
                    originChip(origin)
                }
                if isAddingOrigin {
                    HStack(spacing: 4) {
                        TextField("domain or IP", text: $newOrigin, onCommit: commitOrigin)
                            .textFieldStyle(.plain)
                            .font(.omMono)
                            .frame(width: 130)
                        Button("Add", action: commitOrigin)
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.accent)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: OMRadius.xs).fill(theme.surface2)
                    )
                } else {
                    Button {
                        isAddingOrigin = true
                    } label: {
                        Text("+ Add origin")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.ink3)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .overlay(
                                RoundedRectangle(cornerRadius: OMRadius.xs)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                    .foregroundStyle(theme.divider)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func originChip(_ origin: String) -> some View {
        HStack(spacing: 5) {
            Text(origin)
                .font(.omMono)
                .foregroundStyle(theme.ink2)
            Button {
                corsOrigins.removeAll { $0 == origin }
                saveCorsOrigins()
            } label: {
                Image(systemName: OMSymbol.close)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.ink4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: OMRadius.xs).fill(theme.surface2)
        )
    }

    private func commitOrigin() {
        let trimmed = newOrigin.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { isAddingOrigin = false; return }
        if !corsOrigins.contains(trimmed) {
            corsOrigins.append(trimmed)
            saveCorsOrigins()
        }
        newOrigin = ""
        isAddingOrigin = false
    }

    private var aliasesCard: some View {
        OMCard(
            title: "Model Aliases",
            subtitle: "Redirect OpenAI-style names to your loaded models"
        ) {
            OMButton(title: "Add", icon: OMSymbol.plus, size: .sm) {
                isAddingAlias.toggle()
            }
        } content: {
            VStack(spacing: 4) {
                ForEach(appState.userAliases.sorted(by: { $0.key < $1.key }), id: \.key) { alias, target in
                    aliasRow(alias: alias, target: target)
                }
                if isAddingAlias {
                    addAliasRow
                }
                if appState.userAliases.isEmpty && !isAddingAlias {
                    Text("No aliases set. Clients can use \"tts-1\" / \"whisper-1\" which map automatically to loaded models.")
                        .font(.omCaption)
                        .foregroundStyle(theme.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func aliasRow(alias: String, target: String) -> some View {
        HStack(spacing: 10) {
            Text(alias)
                .font(.omMono).foregroundStyle(theme.ink)
                .frame(minWidth: 90, alignment: .leading)
            Image(systemName: OMSymbol.chevronRight)
                .font(.system(size: 10)).foregroundStyle(theme.ink4)
            Text(target)
                .font(.omMono).foregroundStyle(theme.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
            OMTag(aliasType(target).uppercased(), variant: .solid)
            OMIconButton(icon: OMSymbol.trash, size: 24) {
                appState.removeUserAlias(alias)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: OMRadius.sm).fill(theme.surface2)
        )
    }

    private var addAliasRow: some View {
        HStack(spacing: 8) {
            TextField("alias", text: $newRedirectAlias)
                .textFieldStyle(.plain)
                .font(.omMono)
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 8).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: OMRadius.xs).fill(theme.surface))
                .overlay(RoundedRectangle(cornerRadius: OMRadius.xs).strokeBorder(theme.divider, lineWidth: 1))
                .frame(maxWidth: 150)

            Image(systemName: OMSymbol.chevronRight)
                .font(.system(size: 10)).foregroundStyle(theme.ink4)

            Menu {
                ForEach(installedModels) { m in
                    Button(m.apiId ?? m.id) { newRedirectTarget = m.apiId ?? m.id }
                }
            } label: {
                HStack {
                    Text(newRedirectTarget.isEmpty ? "Select target" : newRedirectTarget)
                        .font(.omMono)
                        .foregroundStyle(newRedirectTarget.isEmpty ? theme.ink3 : theme.ink)
                    Spacer()
                    Image(systemName: OMSymbol.chevronDown)
                        .font(.system(size: 10)).foregroundStyle(theme.ink3)
                }
                .padding(.horizontal, 10).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: OMRadius.xs).fill(theme.surface))
                .overlay(RoundedRectangle(cornerRadius: OMRadius.xs).strokeBorder(theme.divider, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            OMButton(title: "Add", variant: .primary, size: .sm) {
                let a = newRedirectAlias.trimmingCharacters(in: .whitespaces)
                let t = newRedirectTarget.trimmingCharacters(in: .whitespaces)
                guard !a.isEmpty, !t.isEmpty else { return }
                appState.setUserAlias(a, to: t)
                newRedirectAlias = ""
                newRedirectTarget = ""
                isAddingAlias = false
            }
            OMButton(title: "Cancel", size: .sm) {
                newRedirectAlias = ""
                newRedirectTarget = ""
                isAddingAlias = false
            }
        }
    }

    private func aliasType(_ target: String) -> String {
        guard let entry = appState.availableModels.first(where: { ($0.apiId ?? $0.id) == target || $0.id == target }) else {
            return ""
        }
        return entry.type.rawValue
    }

    private var installedModels: [ModelRegistryEntry] {
        appState.availableModels.filter { appState.downloadState(for: $0.id).isInstalled }
    }

    private func generateToken() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let random = (0..<32).map { _ in chars.randomElement()! }
        return "sk-" + String(random)
    }

    private func loadCorsOrigins() {
        corsOrigins = UserDefaults.standard.stringArray(forKey: AppConstants.corsOriginsKey)
            ?? AppConstants.corsLocalOrigins
    }

    private func saveCorsOrigins() {
        UserDefaults.standard.set(corsOrigins, forKey: AppConstants.corsOriginsKey)
    }
}

// MARK: - FlowLayout — wraps children onto multiple lines

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if lineWidth + s.width > width, lineWidth > 0 {
                totalHeight += lineHeight + spacing
                maxLineWidth = max(maxLineWidth, lineWidth - spacing)
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
        totalHeight += lineHeight
        maxLineWidth = max(maxLineWidth, lineWidth - spacing)
        return CGSize(width: maxLineWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
    }
}
