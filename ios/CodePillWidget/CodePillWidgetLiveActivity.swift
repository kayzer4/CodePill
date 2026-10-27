import ActivityKit
import SwiftUI
import WidgetKit

public struct CodePillWidgetLiveActivity: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: CodePillAttributes.self) { context in
            // Lock Screen Banner / Notification view
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: toolIcon(status: context.state.status, desc: context.state.stepDescription))
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)

                    Text(context.attributes.projectName)
                        .font(.headline.bold())
                        .foregroundStyle(.primary)

                    Spacer()

                    StatusBadge(status: context.state.status, isBusy: context.state.isBusy)
                }

                Text(context.state.stepDescription)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let file = context.state.currentFile {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.caption)
                        Text(file)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .activityBackgroundTint(Color.black.opacity(0.90))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI (When holding or long-pressing the Dynamic Island)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: toolIcon(status: context.state.status, desc: context.state.stepDescription))
                            .foregroundStyle(Color.accentColor)
                        Text(toolHeading(status: context.state.status, desc: context.state.stepDescription))
                            .font(.subheadline.bold())
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StatusBadge(status: context.state.isBusy ? "Active" : context.state.status, isBusy: context.state.isBusy)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.stepDescription)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if let file = context.state.currentFile {
                            HStack(spacing: 6) {
                                Image(systemName: "terminal.fill")
                                    .font(.caption2)
                                Text(file)
                                    .font(.caption2.monospaced())
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                    .padding(.top, 2)
                }
            } compactLeading: {
                // Dynamic Island compact left (shows active tool icon + spinner)
                HStack(spacing: 4) {
                    Image(systemName: toolIcon(status: context.state.status, desc: context.state.stepDescription))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    if context.state.isBusy {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.55)
                    }
                }
            } compactTrailing: {
                // Dynamic Island compact right (shows file/tool short label)
                Text(compactTrailingLabel(context.state))
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(context.state.isBusy ? .orange : .green)
                    .lineLimit(1)
            } minimal: {
                // Minimal single icon
                Image(systemName: toolIcon(status: context.state.status, desc: context.state.stepDescription))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func toolIcon(status: String, desc: String) -> String {
        let lower = (status + " " + desc).lowercased()
        if lower.contains("run") || lower.contains("command") || lower.contains("bash") || lower.contains("terminal") {
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

    private func toolHeading(status: String, desc: String) -> String {
        let lower = (status + " " + desc).lowercased()
        if lower.contains("run") || lower.contains("command") || lower.contains("bash") {
            return "Terminal"
        }
        if lower.contains("edit") || lower.contains("write") || lower.contains("replace") {
            return "Editor"
        }
        if lower.contains("view") || lower.contains("read") {
            return "Reader"
        }
        if lower.contains("search") {
            return "Search"
        }
        return "CodePill"
    }

    private func compactTrailingLabel(_ state: CodePillAttributes.ContentState) -> String {
        if !state.isBusy {
            return "Done"
        }
        if let file = state.currentFile, !file.isEmpty {
            let last = file.split(separator: "/").last.map(String.init) ?? file
            if last.count > 7 {
                return String(last.prefix(6)) + "…"
            }
            return last
        }
        if state.status.lowercased().contains("tool") {
            return "Tool"
        }
        return "Live"
    }
}

struct StatusBadge: View {
    let status: String
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isBusy ? Color.orange : Color.green)
                .frame(width: 7, height: 7)
            Text(status)
                .font(.caption2.bold().monospaced())
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.12))
        .clipShape(Capsule())
    }
}
