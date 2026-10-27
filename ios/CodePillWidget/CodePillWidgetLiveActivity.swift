import ActivityKit
import SwiftUI
import WidgetKit

public struct CodePillWidgetLiveActivity: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: CodePillAttributes.self) { context in
            // Lock Screen Banner / Notification view
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(context.attributes.projectName, systemImage: "terminal.fill")
                        .font(.headline)
                        .foregroundStyle(.purple)
                    Spacer()
                    StatusBadge(status: context.state.status, isBusy: context.state.isBusy)
                }

                Text(context.state.stepDescription)
                    .font(.subheadline)
                    .lineLimit(2)

                if let file = context.state.currentFile {
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.caption)
                        Text(file)
                            .font(.caption.monospaced())
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI (When holding or long pressing the Dynamic Island)
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        Image(systemName: "pill.fill")
                            .foregroundStyle(.purple)
                        Text(context.attributes.projectName)
                            .font(.subheadline.bold())
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StatusBadge(status: context.state.status, isBusy: context.state.isBusy)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.stepDescription)
                            .font(.footnote)
                            .foregroundStyle(.primary)

                        if let file = context.state.currentFile {
                            HStack {
                                Image(systemName: "pencil.and.outline")
                                Text(file)
                                    .font(.caption2.monospaced())
                            }
                            .foregroundStyle(.secondary)
                        }

                        if context.state.needsApproval {
                            HStack(spacing: 12) {
                                Button("Approve", role: .none) {}
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                Button("Cancel", role: .cancel) {}
                                    .buttonStyle(.bordered)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            } compactLeading: {
                // Dynamic Island compact left
                HStack(spacing: 4) {
                    Image(systemName: "pill.fill")
                        .foregroundStyle(.purple)
                    if context.state.isBusy {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.5)
                    }
                }
            } compactTrailing: {
                // Dynamic Island compact right
                Text(context.state.status)
                    .font(.caption2.bold())
                    .foregroundStyle(context.state.isBusy ? .orange : .green)
            } minimal: {
                // Minimal single icon
                Image(systemName: "pill.fill")
                    .foregroundStyle(.purple)
            }
        }
    }
}

struct StatusBadge: View {
    let status: String
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isBusy ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
            Text(status)
                .font(.caption.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
    }
}
