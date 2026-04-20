import SwiftUI

private let cachedAppVersionString: String = {
    let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    return "v\(v)"
}()

struct MainContentView: View {
    @Environment(AppState.self) private var appState

    enum SidebarTab: String, Hashable, CaseIterable {
        case playground, models, api, resources, settings

        var label: String {
            switch self {
            case .playground: "Playground"
            case .models:     "Models"
            case .api:        "API"
            case .resources:  "Resources"
            case .settings:   "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .playground: OMSymbol.playground
            case .models:     OMSymbol.models
            case .api:        OMSymbol.api
            case .resources:  OMSymbol.resources
            case .settings:   OMSymbol.settings
            }
        }
    }

    @State private var selectedTab: SidebarTab = .playground

    var body: some View {
        HStack(spacing: 0) {
            OMSidebar(selected: $selectedTab)

            Group {
                switch selectedTab {
                case .playground: PlaygroundView()
                case .models:     ModelStoreView()
                case .api:        APISettingsView()
                case .resources:  ResourcesView()
                case .settings:   SettingsContentView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
        .omTheme()
    }
}

// MARK: - Sidebar

struct OMSidebar: View {
    @Environment(\.omTheme) private var theme
    @Environment(AppState.self) private var appState
    @Binding var selected: MainContentView.SidebarTab

    var body: some View {
        VStack(spacing: 0) {
            // Top brand block (traffic-light spacer row handled by window chrome)
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(theme.ink)
                        .frame(width: 30, height: 30)
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .colorInvert()
                        .brightness(theme.name == "dark" ? -0.05 : 0.85)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("OpenMeow")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(theme.ink)
                        .kerning(-0.2)
                    Text(cachedAppVersionString)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(theme.ink3)
                }
                Spacer()
            }
            .padding(.top, 44) // leave room for native traffic lights
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            // Nav
            VStack(spacing: 1) {
                ForEach(MainContentView.SidebarTab.allCases, id: \.self) { tab in
                    OMNavItem(
                        symbol: tab.symbol,
                        label: tab.label,
                        badge: badge(for: tab),
                        active: selected == tab
                    ) {
                        selected = tab
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            // LOADED models list
            if !appState.loadedModels.isEmpty {
                loadedSection
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            // Server status footer
            Divider().overlay(theme.divider2)
            serverFooter
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(theme.sidebar)
        .overlay(
            Rectangle().fill(theme.divider2).frame(width: 1),
            alignment: .trailing
        )
    }

    private func badge(for tab: MainContentView.SidebarTab) -> Int? {
        switch tab {
        case .models:
            let count = appState.availableModels.count
            return count > 0 ? count : nil
        default:
            return nil
        }
    }

    private var loadedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LOADED · \(appState.loadedModels.count)")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(theme.ink4)
                .padding(.leading, 2)

            VStack(spacing: 4) {
                ForEach(appState.loadedModelEntries.prefix(4), id: \.id) { entry in
                    HStack(spacing: 7) {
                        OMDot(color: theme.ok, size: 6)
                        Text(entry.displayName.localized)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.ink2)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                        Text(entry.type.rawValue.uppercased())
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(theme.ink4)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(theme.name == "dark" ? Color.white.opacity(0.025) : Color.black.opacity(0.025))
                    )
                }
            }
        }
    }

    private var serverFooter: some View {
        HStack(spacing: 8) {
            OMDot(color: appState.serverRunning ? theme.ok : theme.err,
                  pulse: appState.serverRunning)
            VStack(alignment: .leading, spacing: 1) {
                Text(appState.serverRunning ? "Running" : "Stopped")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text("127.0.0.1:\(appState.serverPort)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.ink3)
            }
            Spacer()
            OMIconButton(
                icon: appState.serverRunning ? OMSymbol.stop : OMSymbol.play,
                size: 24,
                help: appState.serverRunning ? "Stop server" : "Start server"
            ) {
                Task {
                    if appState.serverRunning { await appState.stopServer() }
                    else { await appState.startServer() }
                }
            }
        }
    }
}

// MARK: - Nav item

struct OMNavItem: View {
    @Environment(\.omTheme) private var theme
    let symbol: String
    let label: String
    var badge: Int? = nil
    let active: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(active ? theme.accent : theme.ink3)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? theme.ink : theme.ink2)
                Spacer(minLength: 0)
                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(theme.ink3)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3).fill(theme.surface2)
                        )
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: OMRadius.sm).fill(rowBg)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.1), value: hover)
        .animation(.easeOut(duration: 0.1), value: active)
    }

    private var rowBg: Color {
        if active { return theme.name == "dark" ? Color.white.opacity(0.08) : Color.black.opacity(0.06) }
        if hover  { return theme.name == "dark" ? Color.white.opacity(0.04) : Color.black.opacity(0.03) }
        return .clear
    }
}

