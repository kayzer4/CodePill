import SwiftUI

public struct MessageRow: View {
    public let message: ChatMessage

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                Image(systemName: "pill.fill")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .padding(6)
                    .background(Color.purple.opacity(0.15))
                    .clipShape(Circle())
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Tool calls if any
                if !message.toolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(message.toolCalls) { tool in
                            ToolCallBadge(item: tool)
                        }
                    }
                }

                // Message text
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(message.role == .system ? .caption.monospaced() : .body)
                        .foregroundStyle(textColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(bubbleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }

            if message.role == .user {
                Image(systemName: "person.crop.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .padding(.horizontal, 12)
    }

    private var textColor: Color {
        switch message.role {
        case .user: return .white
        case .assistant: return .primary
        case .system: return .secondary
        }
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user:
            return Color.purple.opacity(0.8)
        case .assistant:
            return Color.white.opacity(0.08)
        case .system:
            return Color.clear
        }
    }
}
