import SwiftUI

enum OMTagVariant {
    case plain, solid, ok, warn, err, accent
    case engine(OMEngine)
}

struct OMTag: View {
    @Environment(\.omTheme) private var theme
    let variant: OMTagVariant
    let text: String

    init(_ text: String, variant: OMTagVariant = .plain) {
        self.text = text
        self.variant = variant
    }

    var body: some View {
        Text(text.uppercased())
            .font(.omMeta)
            .tracking(0.3)
            .foregroundStyle(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: OMRadius.xs, style: .continuous)
                    .fill(bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: OMRadius.xs, style: .continuous)
                            .strokeBorder(stroke, lineWidth: 1)
                    )
            )
    }

    private var fg: Color {
        switch variant {
        case .plain:   return theme.ink3
        case .solid:   return theme.ink2
        case .ok:      return theme.ok
        case .warn:    return theme.warn
        case .err:     return theme.err
        case .accent:  return theme.accent
        case .engine(let e): return e.color(in: theme)
        }
    }

    private var bg: Color {
        switch variant {
        case .plain:   return .clear
        case .solid:   return theme.surface2
        case .ok:      return theme.okSoft
        case .warn:    return theme.warnSoft
        case .err:     return theme.errSoft
        case .accent:  return theme.accentSoft
        case .engine:  return .clear
        }
    }

    private var stroke: Color {
        switch variant {
        case .plain: return theme.divider
        case .engine(let e): return e.color(in: theme).opacity(0.4)
        default: return .clear
        }
    }
}
