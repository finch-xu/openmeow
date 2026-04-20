import SwiftUI

// MARK: - Fonts

extension Font {
    /// Page title — 18pt semibold.
    static let omDisplay = Font.system(size: 18, weight: .bold).leading(.tight)
    /// Card title — 13pt semibold.
    static let omSectionTitle = Font.system(size: 13, weight: .semibold)
    /// Card content title — 14pt medium+.
    static let omTitle = Font.system(size: 14, weight: .semibold)
    /// Default body — 12.5pt.
    static let omBody = Font.system(size: 12.5)
    /// Controls / dense — 12pt.
    static let omControl = Font.system(size: 12)
    /// Caption — 11.5pt.
    static let omCaption = Font.system(size: 11.5)
    /// Meta / small-caps label — 10.5pt semibold.
    static let omMeta = Font.system(size: 10.5, weight: .semibold)
    /// Monospace body.
    static let omMono = Font.system(size: 11.5, design: .monospaced)
    /// Monospace hero (for base URL).
    static let omMonoHero = Font.system(size: 17, weight: .semibold, design: .monospaced)
}

// MARK: - Radii & spacing

enum OMRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 14
}

enum OMSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let xxxl: CGFloat = 24
}

// MARK: - Engine mapping

enum OMEngine: String {
    case onnx, mlx, coreml, cloud

    var label: String {
        switch self {
        case .onnx: return "ONNX"
        case .mlx: return "MLX"
        case .coreml: return "CoreML"
        case .cloud: return "Cloud"
        }
    }

    func color(in theme: OMTheme) -> Color {
        switch self {
        case .onnx: return theme.onnx
        case .mlx: return theme.mlx
        case .coreml: return theme.coreml
        case .cloud: return theme.cloud
        }
    }

    static func from(_ engine: EngineType) -> OMEngine {
        switch engine {
        case .sherpaOnnx: .onnx
        case .speechSwift: .mlx
        case .openaiCloud, .mimoCloud, .qwenCloud: .cloud
        }
    }
}

extension String {
    /// Mask a secret so only the first 3 and last 4 characters are visible.
    func maskedSecret() -> String {
        guard count > 8 else { return self }
        return String(prefix(3)) + String(repeating: "•", count: max(count - 7, 8)) + String(suffix(4))
    }
}

// MARK: - SF Symbol helpers

enum OMSymbol {
    static let home        = "house"
    static let models      = "square.stack.3d.up"
    static let playground  = "play.circle"
    static let api         = "bolt.horizontal"
    static let resources   = "chart.bar"
    static let settings    = "gearshape"
    static let play        = "play.fill"
    static let pause       = "pause.fill"
    static let stop        = "stop.fill"
    static let mic         = "mic.fill"
    static let download    = "arrow.down.circle.fill"
    static let trash       = "trash"
    static let copy        = "doc.on.doc"
    static let check       = "checkmark"
    static let plus        = "plus"
    static let search      = "magnifyingglass"
    static let chevronDown = "chevron.down"
    static let chevronRight = "chevron.right"
    static let waveform    = "waveform"
    static let sparkle     = "sparkle"
    static let cpu         = "cpu"
    static let memory      = "memorychip"
    static let key         = "key.fill"
    static let lock        = "lock.fill"
    static let globe       = "globe"
    static let bolt        = "bolt.fill"
    static let link        = "arrow.up.right.square"
    static let refresh     = "arrow.clockwise"
    static let close       = "xmark"
    static let eye         = "eye"
    static let heart       = "heart.fill"
}
