import SwiftUI

public struct MarkdownMessageView: View {
    public let text: String
    public let isUser: Bool

    public init(text: String, isUser: Bool = false) {
        self.text = text
        self.isUser = isUser
    }

    public var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            ForEach(parseBlocks(text), id: \.id) { block in
                switch block.type {
                case .code(let lang, let code):
                    CodeBlockCard(language: lang, code: code)
                case .text(let content):
                    Text(LocalizedStringKey(content))
                        .font(isUser ? .body : .body)
                        .foregroundStyle(isUser ? .white : .primary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private struct MarkdownBlock: Identifiable {
        let id = UUID()
        enum BlockType {
            case text(String)
            case code(language: String, code: String)
        }
        let type: BlockType
    }

    private func parseBlocks(_ raw: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let components = raw.components(separatedBy: "```")

        for (index, component) in components.enumerated() {
            if index % 2 == 1 {
                // Fenced code block
                var lines = component.components(separatedBy: .newlines)
                let firstLine = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
                let language: String
                let code: String
                if !firstLine.isEmpty && !firstLine.contains(" ") && lines.count > 1 {
                    language = firstLine
                    lines.removeFirst()
                    code = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    language = "code"
                    code = component.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if !code.isEmpty {
                    blocks.append(MarkdownBlock(type: .code(language: language, code: code)))
                }
            } else {
                // Regular markdown text
                let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    blocks.append(MarkdownBlock(type: .text(trimmed)))
                }
            }
        }

        if blocks.isEmpty && !raw.isEmpty {
            blocks.append(MarkdownBlock(type: .text(raw)))
        }

        return blocks
    }
}

public struct CodeBlockCard: View {
    public let language: String
    public let code: String
    @State private var copied: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // iOS 26 Cyber-Glass Header bar
            HStack(spacing: 8) {
                // Language pill
                Text(language.isEmpty ? "CODE" : language.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.16))
                    .clipShape(Capsule())

                Spacer()

                // Share snippet
                ShareLink(item: code) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(5)
                }
                .buttonStyle(.plain)

                // Copy code
                Button {
                    UIPasteboard.general.string = code
                    Haptics.shared.notify(.success)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(copied ? .green : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(copied ? 0.12 : 0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(UIColor.secondarySystemBackground).opacity(0.6))

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
    }
}
