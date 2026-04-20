import SwiftUI

struct ModelStoreView: View {
    @Environment(\.omTheme) private var theme
    @Environment(AppState.self) private var appState
    @State private var tab: String = "tts"
    @State private var query: String = ""

    private var currentModels: [ModelRegistryEntry] {
        let source: [ModelRegistryEntry]
        switch tab {
        case "tts": source = appState.localTTSModels
        case "cloud": source = appState.cloudTTSModels
        default: source = appState.asrModels
        }
        guard !query.isEmpty else { return source }
        return source.filter {
            $0.displayName.localized.localizedCaseInsensitiveContains(query)
            || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            OMPageHeader(
                title: "Models",
                subtitle: "Manage local and cloud speech models",
                tabs: [
                    .init(id: "tts",   label: "Local TTS",           count: appState.localTTSModels.count),
                    .init(id: "cloud", label: "Cloud TTS",           count: appState.cloudTTSModels.count),
                    .init(id: "asr",   label: "Speech Recognition",  count: appState.asrModels.count)
                ],
                activeTab: $tab
            ) {
                SearchField(query: $query, theme: theme)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(currentModels) { model in
                        if model.engine.isCloud {
                            OMCloudModelCard(
                                model: model,
                                state: appState.downloadState(for: model.id),
                                onEnable: { appState.downloadModel(model.id) },
                                onStart: { Task { await appState.loadModel(model.id) } },
                                onStop: { Task { await appState.unloadModel(model.id) } }
                            )
                        } else {
                            OMLocalModelCard(
                                model: model,
                                state: appState.downloadState(for: model.id),
                                onDownload: { appState.downloadModel(model.id) },
                                onStart: { Task { await appState.loadModel(model.id) } },
                                onStop: { Task { await appState.unloadModel(model.id) } },
                                onDelete: { appState.deleteModel(model.id) },
                                onCancel: { appState.cancelDownload(model.id) }
                            )
                        }
                    }

                    if currentModels.isEmpty {
                        EmptyState(query: query)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 880, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.bg)
        }
        .background(theme.bg)
    }
}

// MARK: - Search field

private struct SearchField: View {
    @Binding var query: String
    let theme: OMTheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: OMSymbol.search)
                .font(.system(size: 11))
                .foregroundStyle(theme.ink3)
            TextField("Search models…", text: $query)
                .textFieldStyle(.plain)
                .font(.omControl)
                .foregroundStyle(theme.ink)
                .frame(width: 160)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: OMRadius.sm).fill(theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OMRadius.sm).strokeBorder(theme.divider, lineWidth: 1)
        )
    }
}

// MARK: - Empty state

private struct EmptyState: View {
    @Environment(\.omTheme) private var theme
    let query: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 28))
                .foregroundStyle(theme.ink4)
            Text(query.isEmpty ? "No models in this category." : "No models match your search.")
                .font(.omBody)
                .foregroundStyle(theme.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Status helpers

private func statusText(_ s: ModelStatus) -> String {
    switch s {
    case .stable: "Stable"
    case .beta: "Beta"
    case .experimental: "Experimental"
    }
}

private func statusColor(_ s: ModelStatus, _ t: OMTheme) -> Color {
    switch s {
    case .stable: t.ok
    case .beta: t.warn
    case .experimental: t.err
    }
}

private func leadingIcon(for entry: ModelRegistryEntry) -> String {
    if entry.engine.isCloud { return OMSymbol.globe }
    if entry.type == .asr { return OMSymbol.mic }
    return OMSymbol.waveform
}

private struct CardContainer<Content: View>: View {
    @Environment(\.omTheme) private var theme
    let isRunning: Bool
    let content: Content

    init(isRunning: Bool, @ViewBuilder content: () -> Content) {
        self.isRunning = isRunning
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: OMRadius.md).fill(theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OMRadius.md)
                    .strokeBorder(isRunning ? theme.ok.opacity(0.5) : theme.divider, lineWidth: 1)
            )
            .shadow(color: isRunning ? theme.ok.opacity(0.12) : .clear, radius: 1, y: 1)
    }
}

// MARK: - Local model card

private struct OMLocalModelCard: View {
    @Environment(\.omTheme) private var theme
    let model: ModelRegistryEntry
    let state: ModelDownloadState
    let onDownload: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    private var isRunning: Bool { state == .running }

    var body: some View {
        CardContainer(isRunning: isRunning) {
            HStack(alignment: .top, spacing: 16) {
                leadingIconView
                infoBlock
                Spacer(minLength: 0)
                actionBlock
            }
        }
    }

    private var leadingIconView: some View {
        let bg = isRunning ? theme.okSoft : theme.surface2
        let fg = isRunning ? theme.ok : theme.ink3
        return Image(systemName: leadingIcon(for: model))
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(fg)
            .frame(width: 36, height: 36)
            .background(RoundedRectangle(cornerRadius: OMRadius.md).fill(bg))
            .overlay(
                RoundedRectangle(cornerRadius: OMRadius.md)
                    .strokeBorder(isRunning ? .clear : theme.divider2, lineWidth: 1)
            )
    }

    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(model.displayName.localized)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .kerning(-0.15)
                OMTag(OMEngine.from(model.engine).label, variant: .engine(OMEngine.from(model.engine)))
                if isRunning { OMRunningPill() }
            }

            Text(model.description.localized)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink2)
                .lineLimit(2)
                .padding(.top, 2)

            metaRow.padding(.top, 6)

            if let note = model.notes?.localized, !note.isEmpty {
                Text(note)
                    .font(.omCaption)
                    .foregroundStyle(theme.warn)
                    .padding(.top, 4)
            } else if model.requirements?.appleSiliconOnly == true {
                Text("Apple Silicon required")
                    .font(.omCaption)
                    .foregroundStyle(theme.warn)
                    .padding(.top, 4)
            }
        }
    }

    private var metaRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: OMSymbol.globe)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.ink4)
                Text(model.languages.prefix(4).joined(separator: " · ")
                     + (model.languages.count > 4 ? " +\(model.languages.count - 4)" : ""))
            }
            Text("·").foregroundStyle(theme.ink4)
            Text(sizeLabel)
            if model.voiceCount > 0 {
                Text("·").foregroundStyle(theme.ink4)
                Text("\(model.voiceCount) voices")
            }
            Text("·").foregroundStyle(theme.ink4)
            Text(statusText(model.status).uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(statusColor(model.status, theme))
        }
        .font(.system(size: 11.5, design: .monospaced))
        .foregroundStyle(theme.ink3)
    }

    private var sizeLabel: String {
        let mb = model.size.downloadMb
        return mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024.0) : "\(mb) MB"
    }

    @ViewBuilder
    private var actionBlock: some View {
        switch state {
        case .notInstalled:
            OMButton(title: "Download", icon: OMSymbol.download, variant: .primary, action: onDownload)

        case .downloading(let p):
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(p * 100))%")
                    .font(.omMono)
                    .foregroundStyle(theme.ink3)
                ProgressView(value: p)
                    .progressViewStyle(.linear)
                    .tint(theme.accent)
                    .frame(width: 120)
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.err)
            }

        case .extracting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Installing…")
                    .font(.omCaption)
                    .foregroundStyle(theme.ink3)
            }

        case .stopped:
            HStack(spacing: 6) {
                OMIconButton(icon: OMSymbol.play, variant: .primary, size: 30, help: "Start", action: onStart)
                OMIconButton(icon: OMSymbol.trash, variant: .ghost, size: 30, help: "Delete", action: onDelete)
            }

        case .running:
            HStack(spacing: 6) {
                OMIconButton(icon: OMSymbol.stop, variant: .bordered, size: 30, help: "Stop", action: onStop)
                OMIconButton(icon: OMSymbol.trash, variant: .ghost, size: 30, help: "Delete", action: onDelete)
            }

        case .error(let msg):
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(theme.err)
                    Text("Error")
                        .font(.omCaption).foregroundStyle(theme.err)
                }
                Text(msg)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.err)
                    .lineLimit(2)
                    .frame(maxWidth: 140, alignment: .trailing)
                HStack(spacing: 6) {
                    OMButton(title: "Retry", size: .sm, action: onDownload)
                    OMIconButton(icon: OMSymbol.trash, size: 22, help: "Delete", action: onDelete)
                }
            }
        }
    }
}

// MARK: - Cloud model card

private struct OMCloudModelCard: View {
    @Environment(\.omTheme) private var theme
    let model: ModelRegistryEntry
    let state: ModelDownloadState
    let onEnable: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void

    @State private var apiKeyInput = ""
    @State private var isEditingKey = false

    private var apiKeySettingsKey: String { model.config.apiKeySettingsKey ?? "" }
    private var savedApiKey: String { UserDefaults.standard.string(forKey: apiKeySettingsKey) ?? "" }
    private var hasKey: Bool { !savedApiKey.isEmpty }
    private var isRunning: Bool { state == .running }

    private var maskedKey: String { savedApiKey.maskedSecret() }

    var body: some View {
        CardContainer(isRunning: isRunning) {
            HStack(alignment: .top, spacing: 16) {
                leadingIconView
                infoBlock
                Spacer(minLength: 0)
                actionBlock
            }
        }
    }

    private var leadingIconView: some View {
        let bg = isRunning ? theme.okSoft : theme.surface2
        let fg = isRunning ? theme.ok : theme.cloud
        return Image(systemName: OMSymbol.globe)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(fg)
            .frame(width: 36, height: 36)
            .background(RoundedRectangle(cornerRadius: OMRadius.md).fill(bg))
    }

    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(model.displayName.localized)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .kerning(-0.15)
                OMTag("Cloud", variant: .engine(.cloud))
                if isRunning { OMRunningPill() }
            }

            Text(model.description.localized)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink2)
                .lineLimit(2)
                .padding(.top, 2)

            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: OMSymbol.globe)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.ink4)
                    Text(model.languages.prefix(3).joined(separator: " · "))
                }
                if model.voiceCount > 0 {
                    Text("·").foregroundStyle(theme.ink4)
                    Text("\(model.voiceCount) voices")
                }
                Text("·").foregroundStyle(theme.ink4)
                Text(statusText(model.status).uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(statusColor(model.status, theme))
            }
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(theme.ink3)
            .padding(.top, 6)

            apiKeyRow.padding(.top, 10)
        }
    }

    @ViewBuilder
    private var apiKeyRow: some View {
        if isEditingKey {
            HStack(spacing: 6) {
                SecureField("API Key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.omControl)
                    .frame(maxWidth: 260)
                OMButton(title: "Save", variant: .primary, size: .sm) {
                    UserDefaults.standard.set(apiKeyInput, forKey: apiKeySettingsKey)
                    isEditingKey = false
                    apiKeyInput = ""
                }
                .disabled(apiKeyInput.isEmpty)
                Button("Cancel") {
                    isEditingKey = false
                    apiKeyInput = ""
                }
                .buttonStyle(.plain)
                .font(.omCaption)
                .foregroundStyle(theme.ink3)
            }
        } else if hasKey {
            HStack(spacing: 8) {
                Image(systemName: OMSymbol.key)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ok)
                Text(maskedKey)
                    .font(.omMono)
                    .foregroundStyle(theme.ink3)
                Button("Edit") {
                    isEditingKey = true
                    apiKeyInput = savedApiKey
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(theme.ink3)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: OMSymbol.key)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.warn)
                Text("API key required")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.warn)
                Button("Add key") {
                    isEditingKey = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.ink2)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: OMRadius.xs).strokeBorder(theme.divider, lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private var actionBlock: some View {
        switch state {
        case .notInstalled:
            OMButton(title: "Enable", icon: "bolt.fill", variant: .primary, action: onEnable)
                .disabled(!hasKey)
                .opacity(hasKey ? 1.0 : 0.5)
        case .stopped:
            OMIconButton(icon: OMSymbol.play, variant: .primary, size: 30, help: "Start", action: onStart)
        case .running:
            OMIconButton(icon: OMSymbol.stop, variant: .bordered, size: 30, help: "Stop", action: onStop)
        case .error(let msg):
            VStack(alignment: .trailing, spacing: 4) {
                Text(msg)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.err)
                    .lineLimit(2)
                    .frame(maxWidth: 140, alignment: .trailing)
                OMButton(title: "Retry", size: .sm, action: onEnable)
            }
        default:
            ProgressView().controlSize(.small)
        }
    }
}
