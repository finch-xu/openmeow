import SwiftUI

/// Flex memory bar with segments proportional to bytes.
/// Design-aligned: single 28px rounded bar (app=accent / other=ink4 / free=surface2) + inline legend.
struct MemoryBarView: View {
    @Environment(\.omTheme) private var theme
    let info: MemoryInfo

    private let barHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                segment(for: info.appBytes, color: theme.accent)
                segment(for: info.otherBytes, color: theme.ink4)
                segment(for: info.freeBytes, color: theme.surface2)
            }
            .frame(height: barHeight)
            .clipShape(RoundedRectangle(cornerRadius: OMRadius.sm))

            HStack(spacing: 20) {
                legend(color: theme.accent, label: "OpenMeow",      value: MemoryInfo.format(info.appBytes))
                legend(color: theme.ink4,   label: "System & other", value: MemoryInfo.format(info.otherBytes))
                legend(color: theme.surface2, label: "Free",         value: MemoryInfo.format(info.freeBytes), ring: true)
                Spacer(minLength: 0)
            }
        }
    }

    private func segment(for bytes: UInt64, color: Color) -> some View {
        let ratio = Double(bytes) / Double(max(info.totalBytes, 1))
        return Rectangle()
            .fill(color)
            .frame(maxWidth: .infinity)
            .layoutPriority(ratio > 0 ? ratio : 0.001)
            .opacity(bytes == 0 ? 0 : 1)
    }

    private func legend(color: Color, label: String, value: String, ring: Bool = false) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(ring ? theme.divider : .clear, lineWidth: 1)
                )
            Text(label).font(.omBody).foregroundStyle(theme.ink3)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.ink)
        }
    }
}
