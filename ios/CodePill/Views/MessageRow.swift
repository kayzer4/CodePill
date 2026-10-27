import SwiftUI

public struct MessageRow: View {
    public let message: ChatMessage
    public var onRollback: (() -> Void)? = nil
    public var onEdit: ((String) -> Void)? = nil

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 26, height: 26)

                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 0.8)
                        .frame(width: 26, height: 26)

                    Image(systemName: "pill.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.top, 4)
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
                ZStack {
                    Circle()
                        .fill(Color(UIColor.secondarySystemBackground).opacity(0.85))
                        .frame(width: 26, height: 26)

                    Circle()
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                        .frame(width: 26, height: 26)

                    Image(systemName: "person.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
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
        } else if message.role == .user {
            // iOS 26 User Liquid Gradient Bubble
            MarkdownMessageView(text: message.text, isUser: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.46, blue: 1.0),
                            Color(red: 0.28, green: 0.26, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.35), location: 0.0),
                                    .init(color: .white.opacity(0.08), location: 0.6),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: Color(red: 0.06, green: 0.46, blue: 1.0).opacity(0.24), radius: 8, x: 0, y: 3)
        } else {
            // iOS 26 Assistant Liquid Glass Bubble
            MarkdownMessageView(text: message.text, isUser: false)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(UIColor.secondarySystemBackground).opacity(0.72))
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.22), location: 0.0),
                                    .init(color: .white.opacity(0.04), location: 0.5),
                                    .init(color: .clear, location: 0.8),
                                    .init(color: .white.opacity(0.08), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: Color.black.opacity(0.20), radius: 6, x: 0, y: 3)
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
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
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
                    .liquidGlass(cornerRadius: 12)
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
}
