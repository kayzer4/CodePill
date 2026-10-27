import SwiftUI

public struct LiveIslandPreview: View {
    public let state: CodePillAttributes.ContentState

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconFor(state))
                .foregroundStyle(Color.accentColor)
                .font(.footnote)

            if state.isBusy {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.65)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(state.stepDescription)
                    .font(.caption.bold().monospaced())
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let file = state.currentFile, !file.isEmpty, file != state.stepDescription {
                    Text(file)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(state.status)
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(state.isBusy ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
                .foregroundStyle(state.isBusy ? .orange : .green)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 14)
    }

    private func iconFor(_ state: CodePillAttributes.ContentState) -> String {
        let lower = (state.status + " " + state.stepDescription).lowercased()
        if lower.contains("run") || lower.contains("command") || lower.contains("bash") {
            return "terminal.fill"
        }
        if lower.contains("edit") || lower.contains("write") || lower.contains("replace") {
            return "pencil.and.outline"
        }
        if lower.contains("view") || lower.contains("read") {
            return "eye.fill"
        }
        if lower.contains("search") || lower.contains("web") {
            return "globe"
        }
        return "pill.fill"
    }
}
