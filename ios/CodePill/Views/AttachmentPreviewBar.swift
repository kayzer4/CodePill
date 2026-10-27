import SwiftUI

public struct AttachmentPreviewBar: View {
    public let attachments: [AttachmentItem]
    public let onRemove: (String) -> Void

    public init(attachments: [AttachmentItem], onRemove: @escaping (String) -> Void) {
        self.attachments = attachments
        self.onRemove = onRemove
    }

    public var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { item in
                        AttachmentItemPill(item: item) {
                            onRemove(item.id)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .background(Color(UIColor.secondarySystemBackground).opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct AttachmentItemPill: View {
    let item: AttachmentItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if item.isImage, let data = Data(base64Encoded: item.base64Data), let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.caption2.bold())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 120, alignment: .leading)
                
                Text(item.mimeType)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(Color(UIColor.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var iconName: String {
        if item.isImage { return "photo.fill" }
        if item.mimeType.contains("pdf") { return "doc.richtext.fill" }
        if item.mimeType.contains("text") || item.mimeType.contains("json") { return "doc.text.fill" }
        return "doc.fill"
    }
}
