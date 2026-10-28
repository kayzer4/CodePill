import SwiftUI

public struct CompactToolsAccordion: View {
    public let toolCalls: [ToolCallItem]
    @State private var isExpanded: Bool = false

    public init(toolCalls: [ToolCallItem]) {
        self.toolCalls = toolCalls
    }

    private var activeCount: Int {
        toolCalls.filter { $0.isRunning }.count
    }

    private var successCount: Int {
        toolCalls.filter { $0.isSuccess && !$0.isRunning }.count
    }

    private var errorCount: Int {
        toolCalls.filter { !$0.isSuccess && !$0.isRunning }.count
    }

    private var latestTool: ToolCallItem? {
        toolCalls.last
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header summary button
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
                Haptics.shared.selection()
            } label: {
                HStack(spacing: 8) {
                    // Status indicator dot or spinner
                    if activeCount > 0 {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.65)
                            .frame(width: 14, height: 14)
                    } else if errorCount > 0 {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                    } else {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                    }

                    // Count badge
                    Text("\(toolCalls.count) tool\(toolCalls.count > 1 ? "s" : "")")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())

                    // Latest active tool summary
                    if let latest = latestTool {
                        Text(latest.summary)
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .liquidGlass(cornerRadius: 12, specularOpacity: 0.2)
            }
            .buttonStyle(.plain)

            // Expanded view with all tools listed individually
            if isExpanded {
                VStack(spacing: 5) {
                    ForEach(toolCalls) { tool in
                        ToolCallBadge(item: tool)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.leading, 6)
            }
        }
    }
}
