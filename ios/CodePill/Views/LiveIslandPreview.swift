import SwiftUI

public struct LiveIslandPreview: View {
    public let state: CodePillAttributes.ContentState

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pill.fill")
                .foregroundStyle(Color.accentColor)
                .font(.footnote)

            if state.isBusy {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.65)
            }

            Text(state.stepDescription)
                .font(.caption.monospaced())
                .lineLimit(1)
                .foregroundStyle(.primary)

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
        .padding(.horizontal, 14)
    }
}
