import SwiftUI

public struct ToolCallBadge: View {
    public let item: ToolCallItem
    @State private var showDetails: Bool = false

    public var body: some View {
        Button {
            showDetails = true
            Haptics.shared.selection()
        } label: {
            HStack(spacing: 8) {
                // Tool specific icon
                Image(systemName: iconForTool(item.name))
                    .font(.caption2)
                    .foregroundStyle(iconColor)

                Text(item.summary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if item.name == "schedule" && item.isRunning {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass")
                            .font(.caption2)
                            .foregroundStyle(Color.purple)
                        Text("Waiting")
                            .font(.caption2.bold().monospaced())
                            .foregroundStyle(Color.purple)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.15))
                    .clipShape(Capsule())
                } else if item.isRunning {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                } else if let dur = item.duration {
                    Text(String(format: "%.1fs", dur))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .liquidGlass(cornerRadius: 12, specularOpacity: 0.18)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetails) {
            ToolDetailSheet(item: item)
        }
    }

    private var iconColor: Color {
        if item.name == "schedule" {
            return Color.purple
        }
        return item.isRunning ? .orange : (item.isSuccess ? .green : .red)
    }

    private func iconForTool(_ name: String) -> String {
        switch name {
        case "schedule": return "clock.badge.checkmark"
        case "manage_task": return "list.bullet.rectangle"
        case "run_command": return "terminal.fill"
        case "write_file", "edit_file", "write_to_file", "replace_file_content": return "pencil.and.outline"
        case "read_file", "view_file": return "eye.fill"
        case "search_web": return "globe"
        default: return "gearshape.fill"
        }
    }
}
