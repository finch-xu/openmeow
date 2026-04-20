import SwiftUI

struct OMPageTab: Identifiable, Equatable {
    let id: String
    let label: LocalizedStringKey
    var count: Int? = nil

    init(id: String, label: LocalizedStringKey, count: Int? = nil) {
        self.id = id
        self.label = label
        self.count = count
    }
}

struct OMPageHeader<Action: View>: View {
    @Environment(\.omTheme) private var theme
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let action: Action
    let tabs: [OMPageTab]
    @Binding var activeTab: String

    init(title: LocalizedStringKey,
         subtitle: LocalizedStringKey? = nil,
         tabs: [OMPageTab] = [],
         activeTab: Binding<String> = .constant(""),
         @ViewBuilder action: () -> Action = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.tabs = tabs
        self._activeTab = activeTab
        self.action = action()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: OMSpace.lg) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.omDisplay)
                        .foregroundStyle(theme.ink)
                        .kerning(-0.3)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.ink3)
                    }
                }
                Spacer(minLength: 0)
                action
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, tabs.isEmpty ? 16 : 14)

            if !tabs.isEmpty {
                HStack(spacing: 2) {
                    ForEach(tabs) { tab in
                        TabButton(tab: tab, active: activeTab == tab.id) {
                            activeTab = tab.id
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
                .padding(.top, 4)
            }
        }
        .background(theme.bg)
        .overlay(
            Rectangle().fill(theme.divider2).frame(height: 1),
            alignment: .bottom
        )
    }
}

private struct TabButton: View {
    @Environment(\.omTheme) private var theme
    let tab: OMPageTab
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(tab.label)
                    .font(.system(size: 12.5, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? theme.ink : theme.ink3)
                if let count = tab.count {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(active ? theme.accent : theme.ink4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(
                Rectangle()
                    .fill(active ? theme.accent : .clear)
                    .frame(height: 2)
                    .cornerRadius(1),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
    }
}
