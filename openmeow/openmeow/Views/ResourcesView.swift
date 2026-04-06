import SwiftUI

struct ResourcesView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Memory bar
                GroupBox {
                    if let info = appState.memoryInfo {
                        MemoryBarView(info: info) {
                            Task { await appState.forceCleanupMemory() }
                        }
                    } else {
                        HStack {
                            Spacer()
                            ProgressView("Loading memory info...")
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                } label: {
                    Label("Memory Usage", systemImage: "memorychip")
                        .font(.subheadline.weight(.medium))
                }

                // Loaded models
                GroupBox {
                    if appState.loadedModels.isEmpty {
                        Text("No models loaded")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(appState.loadedModels, id: \.self) { modelID in
                                HStack(spacing: 8) {
                                    let entry = appState.availableModels.first { $0.id == modelID }
                                    Image(systemName: entry?.type == .tts ? "waveform" : "mic")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16)
                                    Text(entry?.displayName.localized ?? modelID)
                                        .font(.caption)
                                    if let entry {
                                        Text(entry.engine.isCloud ? "Cloud" : entry.engine == .whisperKit ? "CoreML" : entry.engine == .speechSwift ? "MLX" : "ONNX")
                                            .font(.system(size: 8, weight: .medium))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(
                                                entry.engine.isCloud ? Color.indigo.opacity(0.12) :
                                                entry.engine == .whisperKit ? Color.teal.opacity(0.12) :
                                                entry.engine == .speechSwift ? Color.purple.opacity(0.12) :
                                                Color.gray.opacity(0.12)
                                            )
                                            .foregroundStyle(
                                                entry.engine.isCloud ? .indigo :
                                                entry.engine == .whisperKit ? .teal :
                                                entry.engine == .speechSwift ? .purple :
                                                .secondary
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                    Spacer()
                                    if let entry {
                                        Text("\(entry.size.diskMb) MB")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Label("Loaded Models", systemImage: "square.stack.3d.up")
                        .font(.subheadline.weight(.medium))
                }

                // System info
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        InfoLine(label: "macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                        InfoLine(label: "CPU", value: cpuName())
                        InfoLine(label: "RAM", value: MemoryInfo.format(ProcessInfo.processInfo.physicalMemory))
                        InfoLine(label: "Cores", value: "\(ProcessInfo.processInfo.processorCount)")
                    }
                } label: {
                    Label("System", systemImage: "desktopcomputer")
                        .font(.subheadline.weight(.medium))
                }
            }
            .padding(20)
        }
    }

    private func cpuName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var result = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &result, &size, nil, 0)
        return String(cString: result)
    }
}

private struct InfoLine: View {
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
