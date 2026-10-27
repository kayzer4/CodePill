import SwiftUI

public struct ToolCallBadge: View {
    public let item: ToolCallItem
    @State private var isExpanded: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
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
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(UIColor.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            if isExpanded, let output = item.output, !output.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(output)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .background(Color.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}
