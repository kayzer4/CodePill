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
                .foregroundStyle(.primary)

            Spacer()

            Text(state.status)
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(state.isBusy ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                .foregroundStyle(state.isBusy ? .orange : .green)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        )
        .padding(.horizontal)
    }
}
