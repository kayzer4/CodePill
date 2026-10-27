import SwiftUI

public struct LiveIslandPreview: View {
    public let state: CodePillAttributes.ContentState

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pill.fill")
                .foregroundStyle(.purple)
                .font(.footnote)

            if state.isBusy {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.65)
            }

            Text(state.stepDescription)
                .font(.caption.monospaced())
                .lineLimit(1)
                .foregroundStyle(.white)

            Spacer()

            Text(state.status)
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(state.isBusy ? Color.orange.opacity(0.25) : Color.green.opacity(0.25))
                .foregroundStyle(state.isBusy ? .orange : .green)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .liquidGlass(cornerRadius: 22, glowColor: Color.purple.opacity(0.25), isHighlighted: true)
        .padding(.horizontal, 16)
    }
}
