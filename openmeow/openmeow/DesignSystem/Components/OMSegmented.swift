import SwiftUI

/// Compact chip group with monospace uppercase labels — used for audio format pickers.
struct OMSegmented: View {
    @Environment(\.omTheme) private var theme
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let active = selection == option
                Button { selection = option } label: {
                    Text(option.uppercased())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(active ? theme.accent : theme.ink2)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: OMRadius.xs)
                                .fill(active ? theme.accentSoft : theme.surface2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Small capsule showing "Running" with a pulsing green dot.
struct OMRunningPill: View {
    @Environment(\.omTheme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            OMDot(color: theme.ok, size: 6, pulse: true)
            Text("Running")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.ok)
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(theme.okSoft))
    }
}
