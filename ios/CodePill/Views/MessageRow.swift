import SwiftUI

public struct MessageRow: View {
    public let message: ChatMessage
    public var onRollback: (() -> Void)? = nil

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                Image(systemName: "pill.fill")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().stroke(Color.purple.opacity(0.4), lineWidth: 1))
                    )
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
                                Image(systemName: "arrow.uturn.backward.circle")
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
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            stops: [
                                                .init(color: .white.opacity(message.role == .user ? 0.35 : 0.2), location: 0),
                                                .init(color: .clear, location: 0.8)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: message.role == .user ? Color.purple.opacity(0.2) : .clear, radius: 8, y: 3)
                    }
                }
            }

            if message.role == .user {
                Image(systemName: "person.crop.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.purple.opacity(0.8))
                    .padding(8)
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

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.role {
        case .user:
            LinearGradient(
                colors: [Color.purple.opacity(0.75), Color.indigo.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .assistant:
            Color.black.opacity(0.25)
                .background(.ultraThinMaterial)
        case .system:
            Color.clear
        }
    }
}
