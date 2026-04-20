import SwiftUI

/// Menu trigger styled as an OM field (rounded surface + chevron).
struct OMMenuPicker<MenuContent: View>: View {
    @Environment(\.omTheme) private var theme
    let title: String
    var width: CGFloat? = nil
    var monospace: Bool = false
    let menu: () -> MenuContent

    init(_ title: String,
         width: CGFloat? = nil,
         monospace: Bool = false,
         @ViewBuilder menu: @escaping () -> MenuContent) {
        self.title = title
        self.width = width
        self.monospace = monospace
        self.menu = menu
    }

    var body: some View {
        Menu(content: menu) {
            HStack {
                Text(title)
                    .font(monospace ? .omMono : .omControl)
                    .foregroundStyle(theme.ink)
                Spacer()
                Image(systemName: OMSymbol.chevronDown)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.ink3)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .frame(maxWidth: width)
            .background(
                RoundedRectangle(cornerRadius: OMRadius.sm).fill(theme.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OMRadius.sm).strokeBorder(theme.divider2, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}
