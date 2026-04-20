import SwiftUI

struct OMDot: View {
    let color: Color
    var size: CGFloat = 7
    var pulse: Bool = false

    @State private var animating = false

    var body: some View {
        ZStack {
            if pulse {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: size + 4, height: size + 4)
                    .scaleEffect(animating ? 2.0 : 0.9)
                    .opacity(animating ? 0 : 0.6)
            }
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard pulse else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                animating = true
            }
        }
    }
}
