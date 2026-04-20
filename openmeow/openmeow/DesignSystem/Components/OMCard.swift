import SwiftUI

struct OMCard<Action: View, Content: View>: View {
    @Environment(\.omTheme) private var theme
    let title: LocalizedStringKey?
    let subtitle: LocalizedStringKey?
    let action: Action
    let content: Content

    init(title: LocalizedStringKey? = nil,
         subtitle: LocalizedStringKey? = nil,
         @ViewBuilder action: () -> Action = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.action = action()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if title != nil || subtitle != nil {
                HStack(alignment: .center, spacing: OMSpace.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let title {
                            Text(title)
                                .font(.omSectionTitle)
                                .foregroundStyle(theme.ink)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(.omCaption)
                                .foregroundStyle(theme.ink3)
                        }
                    }
                    Spacer(minLength: 0)
                    action
                }
                .padding(.horizontal, OMSpace.xl)
                .padding(.top, 13)
                .padding(.bottom, 11)
                .overlay(
                    Rectangle()
                        .fill(theme.divider2)
                        .frame(height: 1),
                    alignment: .bottom
                )
            }
            content
                .padding(OMSpace.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: OMRadius.lg, style: .continuous)
                .fill(theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OMRadius.lg, style: .continuous)
                .strokeBorder(theme.divider, lineWidth: 1)
        )
    }
}

struct OMKV: View {
    @Environment(\.omTheme) private var theme
    let key: String
    let value: String
    var mono: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.omBody)
                .foregroundStyle(theme.ink3)
                .frame(minWidth: 100, alignment: .leading)
            Text(value)
                .font(mono ? .omMono : .omBody)
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 7)
        .overlay(
            Rectangle().fill(theme.divider2).frame(height: 1),
            alignment: .bottom
        )
    }
}
