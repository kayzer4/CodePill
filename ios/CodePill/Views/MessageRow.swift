import SwiftUI

public struct MessageRow: View {
    public let message: ChatMessage
    public var onRollback: (() -> Void)? = nil

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                Image(systemName: "pill.fill")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                    .padding(6)
                    .background(Color.purple.opacity(0.15))
                    .clipShape(Circle())
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Tool calls
                if !message.toolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(message.toolCalls) { tool in
                            ToolCallBadge(item: tool)
                        }
                    }
                }

                // Message bubble
                if !message.text.isEmpty {
                    HStack(alignment: .bottom, spacing: 8) {
                        if message.role == .user, let rollback = onRollback {
                            Button {
                                rollback()
                            } label: {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Text(message.text)
                            .font(message.role == .system ? .caption.monospaced() : .body)
                            .foregroundStyle(textColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(bubbleBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    }
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
        .padding(.horizontal, 14)
    }

    private var textColor: Color {
        switch message.role {
        case .user: return .white
        case .assistant: return .primary
        case .system: return .secondary
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.role {
        case .user:
            Color.purple
        case .assistant:
            Color(UIColor.secondarySystemBackground)
        case .system:
            Color.clear
        }
    }
}
