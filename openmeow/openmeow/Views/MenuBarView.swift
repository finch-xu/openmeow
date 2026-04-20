import SwiftUI

struct MenuBarView: View {
    @Environment(\.omTheme) private var theme
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                OMDot(color: appState.serverRunning ? theme.ok : theme.err,
                      pulse: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(appState.serverRunning ? "Running" : "Stopped")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text("127.0.0.1:\(appState.serverPort)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.ink3)
                }
                Spacer()
                if !appState.loadedModels.isEmpty {
                    Text("\(appState.loadedModels.count) loaded")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.ink3)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(theme.surface2))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 10)

            Divider().overlay(theme.divider2).padding(.horizontal, 8)

            VStack(spacing: 2) {
                if appState.serverRunning {
                    MenuBarButton(title: "Copy API URL", icon: OMSymbol.copy) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            "http://localhost:\(appState.serverPort)/v1", forType: .string)
                    }
                }

                MenuBarButton(
                    title: appState.serverRunning ? "Stop Server" : "Start Server",
                    icon: appState.serverRunning ? OMSymbol.stop : OMSymbol.play
                ) {
                    Task {
                        if appState.serverRunning { await appState.stopServer() }
                        else { await appState.startServer() }
                    }
                }
            }
            .padding(.horizontal, 6).padding(.top, 4)

            Divider().overlay(theme.divider2).padding(.horizontal, 8).padding(.vertical, 4)

            VStack(spacing: 2) {
                MenuBarButton(title: "Open Dashboard", icon: "macwindow") {
                    openWindow(id: "dashboard")
                    NSApplication.shared.activate()
                }
                MenuBarButton(title: "Quit OpenMeow", icon: "power", destructive: true) {
                    Task {
                        await appState.stopServer()
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            .padding(.horizontal, 6).padding(.bottom, 6)
        }
        .frame(width: 220)
        .background(theme.surface)
        .transaction { $0.animation = nil }
    }
}

private struct MenuBarButton: View {
    @Environment(\.omTheme) private var theme
    let title: LocalizedStringKey
    let icon: String
    var destructive: Bool = false
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(destructive ? theme.err : (hover ? theme.ink : theme.ink2))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(destructive ? theme.err : theme.ink)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: OMRadius.sm)
                    .fill(hover ? theme.surface2 : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
