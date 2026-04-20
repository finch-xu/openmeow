import SwiftUI

enum OMButtonVariant { case primary, ghost, subtle, danger }
enum OMButtonSize { case sm, md, lg

    var height: CGFloat {
        switch self { case .sm: return 22; case .md: return 28; case .lg: return 36 }
    }
    var horizontalPadding: CGFloat {
        switch self { case .sm: return 8; case .md: return 12; case .lg: return 16 }
    }
    var font: Font {
        switch self {
        case .sm: return .system(size: 11.5, weight: .medium)
        case .md: return .system(size: 12.5, weight: .medium)
        case .lg: return .system(size: 13.5, weight: .medium)
        }
    }
    var iconSize: CGFloat {
        switch self { case .sm: return 11; case .md: return 12; case .lg: return 14 }
    }
}

struct OMButton: View {
    @Environment(\.omTheme) private var theme
    let title: LocalizedStringKey
    var icon: String? = nil
    var variant: OMButtonVariant = .ghost
    var size: OMButtonSize = .md
    var action: () -> Void = {}

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: size.iconSize, weight: .medium))
                }
                Text(title).font(size.font)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, size.horizontalPadding)
            .frame(height: size.height)
            .background(
                RoundedRectangle(cornerRadius: OMRadius.sm, style: .continuous)
                    .fill(bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: OMRadius.sm, style: .continuous)
                            .strokeBorder(stroke, lineWidth: 1)
                    )
            )
            .shadow(color: shadowColor, radius: hover && variant == .primary ? 6 : 0,
                    x: 0, y: hover && variant == .primary ? 2 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }

    private var fg: Color {
        switch variant {
        case .primary: return theme.accentInk
        case .ghost, .subtle: return theme.ink
        case .danger: return theme.err
        }
    }
    private var bg: Color {
        switch variant {
        case .primary: return theme.accent
        case .ghost:   return hover ? theme.surface2 : .clear
        case .subtle:  return hover ? theme.surface2 : theme.surface
        case .danger:  return hover ? theme.errSoft : .clear
        }
    }
    private var stroke: Color {
        switch variant {
        case .primary: return .clear
        case .ghost, .subtle, .danger: return theme.divider
        }
    }
    private var shadowColor: Color {
        variant == .primary ? theme.accent.opacity(0.25) : .clear
    }
}
