import SwiftUI

struct OMSwitch: View {
    @Environment(\.omTheme) private var theme
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? theme.accent : (theme.name == "dark" ? Color(hex: 0x3A3D46) : Color(hex: 0xD9D4C8)))
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.15), radius: 1.5, x: 0, y: 1)
                    .padding(2)
            }
            .frame(width: 34, height: 20)
        }
        .buttonStyle(.plain)
    }
}

struct OMToggleRow: View {
    @Environment(\.omTheme) private var theme
    let icon: String
    let label: LocalizedStringKey
    let desc: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? theme.accent : theme.ink3)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: OMRadius.xs)
                        .fill(isOn ? theme.accentSoft : theme.surface2)
                )
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.ink)
                Text(desc)
                    .font(.omCaption)
                    .foregroundStyle(theme.ink3)
            }

            Spacer(minLength: 0)
            OMSwitch(isOn: $isOn)
        }
    }
}

struct OMChipGroup<T: Hashable>: View {
    @Environment(\.omTheme) private var theme
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var monospace: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { opt in
                let isActive = opt.value == selection
                Button {
                    selection = opt.value
                } label: {
                    Text(opt.label)
                        .font(monospace ? .system(size: 11, design: .monospaced)
                                        : .system(size: 12, weight: .medium))
                        .textCase(monospace ? .uppercase : nil)
                        .foregroundStyle(isActive ? theme.accent : theme.ink2)
                        .padding(.horizontal, monospace ? 9 : 12)
                        .padding(.vertical, monospace ? 4 : 5)
                        .background(
                            RoundedRectangle(cornerRadius: monospace ? OMRadius.xs : OMRadius.sm)
                                .fill(isActive ? theme.accentSoft : theme.surface2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: monospace ? OMRadius.xs : OMRadius.sm)
                                .strokeBorder(isActive ? .clear : theme.divider, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
