import SwiftUI

private let cachedCPUName: String = {
    var size = 0
    sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
    var result = [CChar](repeating: 0, count: size)
    sysctlbyname("machdep.cpu.brand_string", &result, &size, nil, 0)
    return String(cString: result)
}()

private let cachedOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
private let cachedRAM = MemoryInfo.format(ProcessInfo.processInfo.physicalMemory)
private let cachedCores = "\(ProcessInfo.processInfo.processorCount)"
private let cachedAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
private let cachedAppBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

struct ResourcesView: View {
    @Environment(\.omTheme) private var theme
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            OMPageHeader(title: "Resources",
                         subtitle: "Memory, system, and loaded models")

            ScrollView {
                VStack(spacing: 14) {
                    memoryCard
                    loadedCard
                    systemCard
                }
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(theme.bg)
        }
        .background(theme.bg)
    }

    private var memoryCard: some View {
        OMCard(
            title: "Memory usage",
            subtitle: memorySubtitle
        ) {
            OMButton(title: "Force cleanup", icon: OMSymbol.refresh, size: .sm) {
                Task { await appState.forceCleanupMemory() }
            }
        } content: {
            if let info = appState.memoryInfo {
                MemoryBarView(info: info)
            } else {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Text("Loading memory info…")
                        .font(.omCaption)
                        .foregroundStyle(theme.ink3)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
        }
    }

    private var memorySubtitle: LocalizedStringKey {
        guard let info = appState.memoryInfo else { return "—" }
        let used = info.appBytes + info.otherBytes
        let pct = Int(Double(used) / Double(max(info.totalBytes, 1)) * 100)
        return "\(MemoryInfo.format(used)) used of \(MemoryInfo.format(info.totalBytes)) · \(pct)% pressure"
    }

    private var loadedCard: some View {
        OMCard(
            title: "Loaded models",
            subtitle: "\(appState.loadedModels.count) active"
        ) {
            if appState.loadedModels.isEmpty {
                Text("No models loaded — start a model from the Models page.")
                    .font(.omCaption)
                    .foregroundStyle(theme.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 6) {
                    ForEach(appState.loadedModelEntries) { entry in
                        loadedRow(entry)
                    }
                }
            }
        }
    }

    private func loadedRow(_ entry: ModelRegistryEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.type == .tts ? OMSymbol.waveform : OMSymbol.mic)
                .font(.system(size: 14))
                .foregroundStyle(theme.accent)
                .frame(width: 16)
            Text(entry.displayName.localized)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(theme.ink)
            let eng = OMEngine.from(entry.engine)
            OMTag(eng.label, variant: .engine(eng))
            Spacer()
            Text("\(entry.size.diskMb) MB")
                .font(.omMono)
                .foregroundStyle(theme.ink3)
            OMIconButton(icon: OMSymbol.stop, size: 24, help: "Unload") {
                Task { await appState.unloadModel(entry.id) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: OMRadius.sm).fill(theme.surface2)
        )
    }

    private var systemCard: some View {
        OMCard(title: "System") {
            VStack(spacing: 0) {
                OMKV(key: "macOS", value: cachedOSVersion)
                OMKV(key: "Processor", value: cachedCPUName)
                OMKV(key: "Memory", value: cachedRAM)
                OMKV(key: "Cores", value: cachedCores)
                OMKV(key: "OpenMeow", value: "v\(cachedAppVersion) · build \(cachedAppBuild)")
            }
        }
    }
}
