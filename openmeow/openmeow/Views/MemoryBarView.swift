import SwiftUI

struct MemoryBarView: View {
    let info: MemoryInfo
    var onForceCleanup: (() -> Void)?

    private let barHeight: CGFloat = 22
    private let barRadius: CGFloat = 6
    private let segmentSpacing: CGFloat = 1.5
    private let minSegmentWidth: CGFloat = 4

    private var segments: [(color: Color, bytes: UInt64, label: String)] {
        var result: [(Color, UInt64, String)] = []
        if info.appBytes > 0 {
            result.append((.blue, info.appBytes, "OpenMeow"))
        }
        if info.freeBytes > 0 {
            result.append((Color(red: 0.18, green: 0.8, blue: 0.44), info.freeBytes, "Free"))
        }
        if info.otherBytes > 0 {
            result.append((Color(red: 0.58, green: 0.65, blue: 0.65), info.otherBytes, "System"))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("Memory")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let onForceCleanup {
                    Button {
                        onForceCleanup()
                    } label: {
                        Label("Force Cleanup", systemImage: "arrow.3.trianglepath")
                            .font(.caption)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .help("Unload all models and release memory")
                }
                Text("Total \(MemoryInfo.format(info.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Bar
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let spacingTotal = segmentSpacing * CGFloat(max(0, segments.count - 1))
                let availableWidth = totalWidth - spacingTotal

                HStack(spacing: segmentSpacing) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        let ratio = Double(segment.bytes) / Double(max(info.totalBytes, 1))
                        let width = max(minSegmentWidth, availableWidth * CGFloat(ratio))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(segment.color)
                            .frame(width: width)
                    }
                }
                .frame(height: barHeight)
                .clipShape(RoundedRectangle(cornerRadius: barRadius))
            }
            .frame(height: barHeight)

            // Legend
            HStack(spacing: 16) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(segment.color)
                            .frame(width: 8, height: 8)
                        Text(segment.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(MemoryInfo.format(segment.bytes))
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
}
