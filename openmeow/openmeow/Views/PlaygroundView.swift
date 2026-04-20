import SwiftUI

struct PlaygroundView: View {
    @Environment(\.omTheme) private var theme
    @State private var mode: String = "tts"

    var body: some View {
        VStack(spacing: 0) {
            OMPageHeader(
                title: "Playground",
                subtitle: "Test your loaded models — generate speech or transcribe audio",
                tabs: [
                    .init(id: "tts", label: "Text → Speech"),
                    .init(id: "asr", label: "Speech → Text")
                ],
                activeTab: $mode
            )

            Group {
                if mode == "tts" {
                    TTSPlaygroundView()
                } else {
                    ASRPlaygroundView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
        }
        .background(theme.bg)
    }
}

struct OMWaveform: View {
    @Environment(\.omTheme) private var theme
    let active: Bool
    var bars: Int = 48

    @State private var phase = 0.0

    private static let baseHeights: [Double] = {
        var heights: [Double] = []
        heights.reserveCapacity(96)
        for i in 0..<96 {
            let d = Double(i)
            let a = abs(sin(d * 0.45) * 16.0)
            let b = abs(cos(d * 0.8) * 4.0)
            heights.append(6.0 + a + b)
        }
        return heights
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<bars, id: \.self) { i in
                bar(at: i)
            }
        }
        .frame(height: 28)
        .onAppear { guard active else { return }; animate() }
        .onChange(of: active) { _, isActive in if isActive { animate() } }
    }

    private func bar(at i: Int) -> some View {
        let baseH = Self.baseHeights[i % Self.baseHeights.count]
        let idle = 0.35
        let wave = 0.4 + 0.6 * abs(sin(phase * 2 + Double(i) * 0.3))
        let scale: Double = active ? wave : idle
        return RoundedRectangle(cornerRadius: 2)
            .fill(active ? theme.accent : theme.ink4)
            .opacity(active ? 0.9 : 0.35)
            .frame(width: 2.5, height: baseH * scale)
    }

    private func animate() {
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
            phase = .pi * 4
        }
    }
}

struct OMFieldGroup<Content: View>: View {
    @Environment(\.omTheme) private var theme
    let label: LocalizedStringKey
    let content: Content

    init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .textCase(.uppercase)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(theme.ink4)
            content
        }
    }
}

/// 260-wide settings rail used by both TTS and ASR playgrounds.
/// Caller supplies the field groups; the panel handles chrome + bottom curl hint.
struct PlaygroundSettingsPanel<Content: View>: View {
    @Environment(\.omTheme) private var theme
    @Environment(AppState.self) private var appState
    let endpointPath: String
    let content: Content

    init(endpointPath: String, @ViewBuilder content: () -> Content) {
        self.endpointPath = endpointPath
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content
            Spacer(minLength: 0)
            curlHint
        }
        .padding(16)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: OMRadius.lg).fill(theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OMRadius.lg).strokeBorder(theme.divider, lineWidth: 1)
        )
    }

    private var curlHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("curl -X POST \\")
            Text("localhost:\(appState.serverPort)\(endpointPath)")
        }
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(theme.ink4)
        .lineLimit(2)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OMRadius.sm).fill(theme.surface2)
        )
    }
}
