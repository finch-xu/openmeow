import SwiftUI

struct MainContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: SidebarTab = .home

    enum SidebarTab: String, Hashable {
        case home, models, api, resources, settings
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // App branding
                HStack(spacing: 8) {
                    Image("AppLogo")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("OpenMeow")
                        .font(.headline)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Nav items
                List(selection: $selectedTab) {
                    Label("Home", systemImage: "house")
                        .tag(SidebarTab.home)
                    Label("Models", systemImage: "square.stack.3d.up")
                        .tag(SidebarTab.models)
                    Label("API", systemImage: "bolt.horizontal")
                        .tag(SidebarTab.api)
                    Label("Resources", systemImage: "gauge.open.with.lines.needle.33percent")
                        .tag(SidebarTab.resources)
                    Label("Settings", systemImage: "gearshape")
                        .tag(SidebarTab.settings)
                }
                .listStyle(.sidebar)

                Divider()

                // Server status footer
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.serverRunning ? .green : .red.opacity(0.6))
                        .frame(width: 8, height: 8)
                    Text(appState.serverRunning ? "Running" : "Stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    if !appState.loadedModels.isEmpty {
                        Text("\(appState.loadedModels.count)")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .frame(minWidth: 170)
        } detail: {
            switch selectedTab {
            case .home: HomeView()
            case .models: ModelStoreView()
            case .api: APISettingsView()
            case .resources: ResourcesView()
            case .settings: SettingsContentView()
            }
        }
        .frame(minWidth: 720, minHeight: 460)
    }
}
