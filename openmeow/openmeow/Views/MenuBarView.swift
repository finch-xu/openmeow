import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Status header
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.serverRunning ? .green : .red.opacity(0.6))
                        .frame(width: 8, height: 8)
                    Text(appState.serverRunning ? "Running" : "Stopped")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                if !appState.loadedModels.isEmpty {
                    Text("\(appState.loadedModels.count) models loaded")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider().padding(.vertical, 2)

            // Actions
            if appState.serverRunning {
                MenuBarButton(title: "Copy API URL", icon: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        "http://localhost:\(appState.serverPort)/v1", forType: .string)
                }
            }

            MenuBarButton(
                title: appState.serverRunning ? "Stop Server" : "Start Server",
                icon: appState.serverRunning ? "stop.circle" : "play.circle"
            ) {
                Task {
                    if appState.serverRunning { await appState.stopServer() }
                    else { await appState.startServer() }
                }
            }

            Divider().padding(.vertical, 2)

            MenuBarButton(title: "Open Dashboard", icon: "macwindow") {
                openWindow(id: "dashboard")
                NSApplication.shared.activate()
            }

            Divider().padding(.vertical, 2)

            MenuBarButton(title: "Quit OpenMeow", icon: "power") {
                Task {
                    await appState.stopServer()
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(6)
        .frame(width: 220)
    }
}

private struct MenuBarButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer()
            }
            .font(.subheadline)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovered ? Color.accentColor.opacity(0.1) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
