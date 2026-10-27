import SwiftUI

public struct MessageRow: View {
    public let message: ChatMessage
    public var onRollback: (() -> Void)? = nil
    public var onEdit: ((String) -> Void)? = nil

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                Image(systemName: "pill.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                    .padding(6)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Circle())
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Attachments if any
                if !message.attachments.isEmpty {
                    attachmentsView
                }

                // Tool calls (show even if text is empty!)
                if !message.toolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(message.toolCalls) { tool in
                            ToolCallBadge(item: tool)
                        }
                    }
                    .padding(.vertical, 2)
                }

                // Message bubble or typing loader
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

                        bubbleContent
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = message.text
                                    Haptics.shared.notify(.success)
                                } label: {
                                    Label("Copy Text", systemImage: "doc.on.doc")
                                }

                                if message.role == .user, let onEdit = onEdit {
                                    Button {
                                        onEdit(message.text)
                                        Haptics.shared.impact(.light)
                                    } label: {
                                        Label("Edit Prompt", systemImage: "pencil")
                                    }
                                }

                                if let rollback = onRollback, message.role == .user {
                                    Button(role: .destructive) {
                                        rollback()
                                    } label: {
                                        Label("Rollback Turn", systemImage: "arrow.uturn.backward")
                                    }
                                }
                            }
                    }
                } else if message.role == .assistant && message.toolCalls.isEmpty {
                    // ChatGPT / Claude style typing indicator while waiting for first tokens
                    ThinkingBubbleView()
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

    @ViewBuilder
    private var bubbleContent: some View {
        if message.role == .system {
            Text(message.text)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else {
            MarkdownMessageView(text: message.text, isUser: message.role == .user)
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

    @ViewBuilder
    private var attachmentsView: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            ForEach(message.attachments) { att in
                if att.isImage, let data = Data(base64Encoded: att.base64Data), let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                        Text(att.name)
                            .font(.caption.bold())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
            }
        }
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
            Color.accentColor
        case .assistant:
            Color(UIColor.secondarySystemBackground)
        case .system:
            Color.clear
        }
    }
}
