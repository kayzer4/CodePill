import SwiftUI

public struct ToolCallBadge: View {
    public let item: ToolCallItem
    @State private var isExpanded: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    if item.isRunning {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.65)
                    } else {
                        Image(systemName: item.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(item.isSuccess ? .green : .red)
                            .font(.caption)
                    }

                    Text(item.summary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .liquidGlass(cornerRadius: 12)
            }
            .buttonStyle(.plain)

            if isExpanded, let output = item.output, !output.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(output)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(10)
                }
                .liquidGlass(cornerRadius: 10, glowColor: .clear)
            }
        }
    }
}
