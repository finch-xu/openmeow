import SwiftUI

struct OMTheme: Equatable {
    let name: String
    let bg: Color
    let surface: Color
    let surface2: Color
    let sidebar: Color
    let divider: Color
    let divider2: Color
    let ink: Color
    let ink2: Color
    let ink3: Color
    let ink4: Color
    var accent: Color
    var accentSoft: Color
    let accentInk: Color
    let ok: Color
    let okSoft: Color
    let warn: Color
    let warnSoft: Color
    let err: Color
    let errSoft: Color
    let mlx: Color
    let coreml: Color
    let onnx: Color
    let cloud: Color
    let codeBg: Color
}

extension OMTheme {
    static let light = OMTheme(
        name: "light",
        bg:        Color(hex: 0xF6F3EC),
        surface:   Color(hex: 0xFFFDF8),
        surface2:  Color(hex: 0xEDE8DD),
        sidebar:   Color(hex: 0xEAE4D5),
        divider:   Color(hex: 0x12141C, opacity: 0.08),
        divider2:  Color(hex: 0x12141C, opacity: 0.05),
        ink:       Color(hex: 0x14161C),
        ink2:      Color(hex: 0x3B3D44),
        ink3:      Color(hex: 0x6B6C71),
        ink4:      Color(hex: 0xA2A099),
        accent:    Color(hex: 0x1F3A5F),
        accentSoft:Color(hex: 0x1F3A5F, opacity: 0.10),
        accentInk: .white,
        ok:        Color(hex: 0x2E7D4F),
        okSoft:    Color(hex: 0x2E7D4F, opacity: 0.10),
        warn:      Color(hex: 0xA7641C),
        warnSoft:  Color(hex: 0xA7641C, opacity: 0.10),
        err:       Color(hex: 0xB03A2E),
        errSoft:   Color(hex: 0xB03A2E, opacity: 0.10),
        mlx:       Color(hex: 0x6B3FA0),
        coreml:    Color(hex: 0x0F6E74),
        onnx:      Color(hex: 0x8A5A14),
        cloud:     Color(hex: 0x3A5680),
        codeBg:    Color(hex: 0xF3EDDF)
    )

    static let dark = OMTheme(
        name: "dark",
        bg:        Color(hex: 0x14161C),
        surface:   Color(hex: 0x1C1F27),
        surface2:  Color(hex: 0x22252E),
        sidebar:   Color(hex: 0x111318),
        divider:   Color.white.opacity(0.07),
        divider2:  Color.white.opacity(0.04),
        ink:       Color(hex: 0xEDEBE4),
        ink2:      Color(hex: 0xBEBDB6),
        ink3:      Color(hex: 0x8A8983),
        ink4:      Color(hex: 0x5C5B56),
        accent:    Color(hex: 0x7FA8D8),
        accentSoft:Color(hex: 0x7FA8D8, opacity: 0.16),
        accentInk: Color(hex: 0x0C1018),
        ok:        Color(hex: 0x6FCB97),
        okSoft:    Color(hex: 0x6FCB97, opacity: 0.16),
        warn:      Color(hex: 0xE0A25C),
        warnSoft:  Color(hex: 0xE0A25C, opacity: 0.16),
        err:       Color(hex: 0xE58476),
        errSoft:   Color(hex: 0xE58476, opacity: 0.16),
        mlx:       Color(hex: 0xC0A4E0),
        coreml:    Color(hex: 0x6DC7CC),
        onnx:      Color(hex: 0xD4A968),
        cloud:     Color(hex: 0x9BB5D8),
        codeBg:    Color(hex: 0x0B0D12)
    )

    /// Resolve the active theme for the current color scheme, with optional accent override.
    /// Accent override lightens for dark mode automatically.
    static func resolve(colorScheme: ColorScheme, accentHex: UInt32?) -> OMTheme {
        var theme = colorScheme == .dark ? dark : light
        guard let hex = accentHex else { return theme }
        theme.accent = Color(hex: hex)
        theme.accentSoft = Color(hex: hex, opacity: colorScheme == .dark ? 0.18 : 0.10)
        return theme
    }
}

// MARK: - Environment

private struct OMThemeKey: EnvironmentKey {
    static let defaultValue: OMTheme = .light
}

extension EnvironmentValues {
    var omTheme: OMTheme {
        get { self[OMThemeKey.self] }
        set { self[OMThemeKey.self] = newValue }
    }
}

// MARK: - Color hex helper

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Accent color palette (brand-approved options)

enum OMAccent: UInt32, CaseIterable, Identifiable {
    case inkBlue   = 0x1F3A5F
    case violet    = 0x6B3FA0
    case forest    = 0x2E7D4F
    case amber     = 0xA7641C
    case crimson   = 0xB03A2E
    case steel     = 0x3F5B8F

    var id: UInt32 { rawValue }
    var color: Color { Color(hex: rawValue) }
}

// MARK: - ViewModifier to apply theme from colorScheme + stored accent

struct OMThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("omAccentColor") private var accentRaw: Int = Int(OMAccent.inkBlue.rawValue)

    func body(content: Content) -> some View {
        let theme = OMTheme.resolve(colorScheme: colorScheme, accentHex: UInt32(accentRaw))
        return content
            .environment(\.omTheme, theme)
            .tint(theme.accent)
    }
}

extension View {
    /// Install the OpenMeow theme into the environment. Apply at the root view once.
    func omTheme() -> some View { modifier(OMThemeModifier()) }
}
