import QuickLook
import SwiftUI

public struct FilePreviewSheet: View {
    public let localURL: URL
    public let originalPath: String
    @Environment(\.dismiss) private var dismiss

    public init(localURL: URL, originalPath: String) {
        self.localURL = localURL
        self.originalPath = originalPath
    }

    private var fileSizeString: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: localURL.path),
              let size = attrs[.size] as? Int64 else {
            return ""
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // iOS 26 Subheader with file metadata & quick save pill
                HStack(spacing: 10) {
                    Image(systemName: fileIconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(localURL.lastPathComponent)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            if !fileSizeString.isEmpty {
                                Text(fileSizeString)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Text("•")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(originalPath)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer()

                    ShareLink(item: localURL) {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Save")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.18))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemBackground).opacity(0.5))

                Divider()

                // Native Apple QuickLook Preview (supports code, images, pdf, markdown, json, etc.)
                QuickLookControllerRepresentable(fileURL: localURL)
                    .ignoresSafeArea(edges: .bottom)
            }
            .background(Color(UIColor.systemBackground))
            .navigationTitle(localURL.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: localURL) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    private var fileIconName: String {
        let ext = localURL.pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "rs": return "gearshape.2"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "jpg", "jpeg", "png", "webp", "gif": return "photo"
        case "pdf": return "doc.richtext"
        case "md", "txt": return "doc.plaintext"
        case "json", "toml", "yaml", "yml": return "curlybraces"
        default: return "doc"
        }
    }
}

public struct QuickLookControllerRepresentable: UIViewControllerRepresentable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    public func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, QLPreviewControllerDataSource {
        let parent: QuickLookControllerRepresentable

        init(_ parent: QuickLookControllerRepresentable) {
            self.parent = parent
        }

        public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            parent.fileURL as NSURL
        }
    }
}
