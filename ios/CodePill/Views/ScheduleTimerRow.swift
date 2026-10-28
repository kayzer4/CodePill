import SwiftUI

public struct ScheduleTimerRow: View {
    public let item: ToolCallItem
    @State private var showDetails: Bool = false

    public init(item: ToolCallItem) {
        self.item = item
    }

    public var body: some View {
        Button {
            showDetails = true
            Haptics.shared.selection()
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.18))
                        .frame(width: 26, height: 26)
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.summary.isEmpty ? "Schedule Timer" : item.summary)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer()

                if item.isRunning {
                    HStack(spacing: 5) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.55)
                        Text("Waiting")
                            .font(.caption2.bold().monospaced())
                            .foregroundStyle(Color.purple)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.15))
                    .clipShape(Capsule())
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Triggered")
                            .font(.caption2.bold().monospaced())
                    }
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.14))
                    .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlass(cornerRadius: 12, specularOpacity: 0.22)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetails) {
            ToolDetailSheet(item: item)
        }
    }
}
