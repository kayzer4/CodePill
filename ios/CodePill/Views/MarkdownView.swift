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
            // Header bar
            HStack {
                Text(language.isEmpty ? "CODE" : language.uppercased())
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    UIPasteboard.general.string = code
                    Haptics.shared.notify(.success)
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy")
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.05))

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(UIColor.black))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
