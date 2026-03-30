import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Top status bar
            HStack(spacing: 10) {
                Circle()
                    .fill(appState.serverRunning ? .green : .red.opacity(0.6))
                    .frame(width: 8, height: 8)
                Text(appState.serverRunning ? "Running" : "Stopped")
                    .font(.subheadline.weight(.medium))

                Spacer()

                if !appState.loadedModels.isEmpty {
                    Text("\(appState.loadedModels.count) models loaded")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Playground tabs
            TabView(selection: $selectedTab) {
                TTSPlaygroundView()
                    .tabItem { Label("TTS", systemImage: "waveform") }
                    .tag(0)
                ASRPlaygroundView()
                    .tabItem { Label("ASR", systemImage: "mic") }
                    .tag(1)
            }
        }
    }
}
