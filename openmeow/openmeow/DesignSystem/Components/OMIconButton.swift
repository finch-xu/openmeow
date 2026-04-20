import SwiftUI

enum OMIconButtonVariant { case ghost, bordered, primary, danger }

struct OMIconButton: View {
    @Environment(\.omTheme) private var theme
    let icon: String
    var variant: OMIconButtonVariant = .ghost
    var size: CGFloat = 28
    var active: Bool = false
    var help: String? = nil
    var action: () -> Void = {}

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(fg)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: OMRadius.sm, style: .continuous).fill(bg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OMRadius.sm, style: .continuous)
                        .strokeBorder(stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(help ?? "")
    }

    private var fg: Color {
        switch variant {
        case .ghost:    return active ? theme.ink : theme.ink2
        case .bordered: return theme.ink2
        case .primary:  return theme.accentInk
        case .danger:   return theme.err
        }
    }
    private var bg: Color {
        switch variant {
        case .ghost:    return (hover || active) ? theme.surface2 : .clear
        case .bordered: return hover ? theme.surface2 : theme.surface
        case .primary:  return theme.accent
        case .danger:   return hover ? theme.errSoft : .clear
        }
    }
    private var stroke: Color {
        switch variant {
        case .bordered: return theme.divider
        default: return .clear
        }
    }
}
