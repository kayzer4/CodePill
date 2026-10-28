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
                    FormattedTextView(rawText: content, isUser: isUser)
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

/// Renders markdown text using native AttributedString so that inline links, bold, code inside links (`[`code`](url)`) work reliably
public struct FormattedTextView: View {
    public let rawText: String
    public let isUser: Bool

    public var body: some View {
        Text(renderedAttributedString)
            .font(.body)
            .foregroundStyle(isUser ? .white : .primary)
            .textSelection(.enabled)
    }

    private var renderedAttributedString: AttributedString {
        // Fix inline code inside links like [`name`](url) which Swift markdown parser fails on
        let preprocessed = rawText.replacingOccurrences(
            of: #"\[`([^`]+)`\]\(([^)]+)\)"#,
            with: "[$1]($2)",
            options: .regularExpression
        )

        do {
            let options = AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
            return try AttributedString(markdown: preprocessed, options: options)
        } catch {
            return AttributedString(rawText)
        }
    }
}

public struct CodeBlockCard: View {
    public let language: String
    public let code: String
    @State private var copied: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Bar
            HStack {
                Text(language.uppercased())
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    UIPasteboard.general.string = code
                    withAnimation { copied = true }
                    Haptics.shared.notify(.success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                        Text(copied ? "Copied" : "Copy")
                            .font(.caption2.monospaced())
                    }
                    .foregroundStyle(copied ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 0.12, green: 0.13, blue: 0.16))

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Code Body
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .padding(12)
                    .textSelection(.enabled)
            }
            .background(Color(red: 0.08, green: 0.09, blue: 0.11))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .padding(.vertical, 4)
    }
}
