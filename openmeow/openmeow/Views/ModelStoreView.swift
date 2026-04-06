import SwiftUI

struct ModelStoreView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: ModelTab = .tts

    enum ModelTab: String, CaseIterable, Hashable {
        case tts = "TTS"
        case cloudTTS = "Cloud TTS"
        case asr = "ASR"
        // case cloudASR = "Cloud ASR"
    }

    private var currentModels: [ModelRegistryEntry] {
        switch selectedTab {
        case .tts: appState.localTTSModels
        case .cloudTTS: appState.cloudTTSModels
        case .asr: appState.asrModels
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(ModelTab.allCases, id: \.self) { tab in
                    TabButton(
                        title: tab.rawValue,
                        count: {
                            switch tab {
                            case .tts: appState.localTTSModels.count
                            case .cloudTTS: appState.cloudTTSModels.count
                            case .asr: appState.asrModels.count
                            }
                        }(),
                        isSelected: selectedTab == tab
                    ) {
                        selectedTab = tab
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.bar)

            Divider()

            // Model list
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(currentModels) { model in
                        if model.engine.isCloud {
                            CloudModelCard(
                                model: model,
                                state: appState.downloadState(for: model.id),
                                onEnable: { appState.downloadModel(model.id) },
                                onStart: { Task { await appState.loadModel(model.id) } },
                                onStop: { Task { await appState.unloadModel(model.id) } }
                            )
                        } else {
                            ModelCard(
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
                        VStack(spacing: 8) {
                            Image(systemName: "square.stack.3d.up.slash")
                                .font(.largeTitle)
                                .foregroundStyle(.quaternary)
                            Text("No \(selectedTab.rawValue) models available")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                }
                .padding(20)
            }
        }
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                Text("\(count)")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.2))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
    }
}

// MARK: - Model Card

private struct ModelCard: View {
    let model: ModelRegistryEntry
    let state: ModelDownloadState
    let onDownload: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(model.displayName.localized)
                        .font(.subheadline.weight(.semibold))
                    StatusBadge(status: model.status)
                    if model.engine == .speechSwift {
                        TagView(text: "MLX", color: .purple)
                    }
                    if model.engine == .whisperKit {
                        TagView(text: "CoreML", color: .teal)
                    }
                }

                Text(model.description.localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    TagView(text: model.languages.joined(separator: ", "), color: .blue)
                    Text("\(model.size.downloadMb) MB")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if model.voiceCount > 0 {
                        Text("\(model.voiceCount) voices")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if model.requirements?.appleSiliconOnly == true {
                    Label("Apple Silicon required", systemImage: "chip")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            actionView.frame(width: 90)
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
    }

    @ViewBuilder
    private var actionView: some View {
        switch state {
        case .notInstalled:
            Button("Download", action: onDownload)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

        case .downloading(let progress):
            VStack(spacing: 4) {
                ProgressView(value: progress).progressViewStyle(.linear)
                Text("\(Int(progress * 100))%")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.red)
            }

        case .extracting:
            VStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Installing...").font(.caption2).foregroundStyle(.secondary)
            }

        case .stopped:
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Button(action: onStart) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Text("Stopped")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .running:
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .controlSize(.small)

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                HStack(spacing: 3) {
                    Circle().fill(.green).frame(width: 5, height: 5)
                    Text("Running")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }

        case .error(let msg):
            VStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
                Text(msg).font(.caption2).lineLimit(2).foregroundStyle(.red)
                HStack(spacing: 6) {
                    Button("Retry", action: onDownload).buttonStyle(.bordered).controlSize(.mini)
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash").font(.caption2)
                    }.buttonStyle(.bordered).controlSize(.mini)
                }
            }
        }
    }
}

// MARK: - Shared Components

struct StatusBadge: View {
    let status: ModelStatus
    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.12)).foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    private var color: Color {
        switch status { case .stable: .green; case .beta: .yellow; case .experimental: .orange }
    }
}

private struct TagView: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.08)).foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Cloud Model Card

private struct CloudModelCard: View {
    let model: ModelRegistryEntry
    let state: ModelDownloadState
    let onEnable: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void

    @State private var apiKeyInput = ""
    @State private var isEditingKey = false

    private var apiKeySettingsKey: String {
        model.config.apiKeySettingsKey ?? ""
    }

    private var savedApiKey: String {
        UserDefaults.standard.string(forKey: apiKeySettingsKey) ?? ""
    }

    private var maskedKey: String {
        let key = savedApiKey
        guard key.count > 8 else { return String(repeating: "*", count: key.count) }
        return String(key.prefix(4)) + "****" + String(key.suffix(4))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(model.displayName.localized)
                        .font(.subheadline.weight(.semibold))
                    StatusBadge(status: model.status)
                    TagView(text: "Cloud", color: .indigo)
                }

                Text(model.description.localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    TagView(text: model.languages.joined(separator: ", "), color: .blue)
                    if model.voiceCount > 0 {
                        Text("\(model.voiceCount) voices")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // API Key section
                if isEditingKey || savedApiKey.isEmpty {
                    HStack(spacing: 6) {
                        SecureField("API Key", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(maxWidth: 200)
                        Button("Save") {
                            UserDefaults.standard.set(apiKeyInput, forKey: apiKeySettingsKey)
                            isEditingKey = false
                            apiKeyInput = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .disabled(apiKeyInput.isEmpty)
                        if !savedApiKey.isEmpty {
                            Button("Cancel") {
                                isEditingKey = false
                                apiKeyInput = ""
                            }
                            .buttonStyle(.plain)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text(maskedKey)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Button {
                            isEditingKey = true
                            apiKeyInput = savedApiKey
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            actionView.frame(width: 90)
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
    }

    @ViewBuilder
    private var actionView: some View {
        switch state {
        case .notInstalled:
            VStack(spacing: 4) {
                Button("Enable", action: onEnable)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(savedApiKey.isEmpty)
                if savedApiKey.isEmpty {
                    Text("Set API Key")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

        case .stopped:
            VStack(spacing: 4) {
                Button(action: onStart) {
                    Image(systemName: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)
                Text("Stopped")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .running:
            VStack(spacing: 4) {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.small)
                HStack(spacing: 3) {
                    Circle().fill(.green).frame(width: 5, height: 5)
                    Text("Running")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }

        case .error(let msg):
            VStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.caption)
                Text(msg).font(.caption2).lineLimit(2).foregroundStyle(.red)
                Button("Retry", action: onEnable)
                    .buttonStyle(.bordered).controlSize(.mini)
            }

        default:
            ProgressView().controlSize(.small)
        }
    }
}
