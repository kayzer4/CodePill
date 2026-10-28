import SwiftUI

public struct LiveIslandPreview: View {
    public let state: CodePillAttributes.ContentState
    @State private var isPulsing: Bool = false

    public init(state: CodePillAttributes.ContentState) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 10) {
            // Icon container with soft theme glow
            ZStack {
                Circle()
                    .fill(toolThemeColor.opacity(0.18))
                    .frame(width: 30, height: 30)

                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(toolThemeColor)
            }

            // Description & Target File
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if state.isBusy {
                        Circle()
                            .fill(toolThemeColor)
                            .frame(width: 5, height: 5)
                            .scaleEffect(isPulsing ? 1.3 : 0.8)
                            .opacity(isPulsing ? 1.0 : 0.5)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                    }
                }

                if let subtitle = displaySubtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            // Right status pill
            HStack(spacing: 5) {
                if state.isBusy {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(toolThemeColor)
                }

                Text(statusBadgeText)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(toolThemeColor)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(toolThemeColor.opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(toolThemeColor.opacity(0.25), lineWidth: 0.8)
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            ZStack {
                Color.black.opacity(0.78)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            toolThemeColor.opacity(0.35),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
        .onAppear {
            isPulsing = true
        }
    }

    private var displayTitle: String {
        let desc = state.stepDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !desc.isEmpty && desc != "Finished task" && desc != "Error during execution" {
            return desc
        }
        if !state.status.isEmpty {
            return state.status
        }
        return "Executing"
    }

    private var displaySubtitle: String? {
        if let file = state.currentFile, !file.isEmpty, file != state.stepDescription {
            return file
        }
        if state.stepDescription != state.status && !state.status.isEmpty {
            return state.status
        }
        return nil
    }

    private var statusBadgeText: String {
        if state.needsApproval {
            return "CONFIRM"
        }
        if state.isBusy {
            return "ACTIVE"
        }
        return state.status.uppercased()
    }

    private var toolThemeColor: Color {
        let lower = (state.status + " " + state.stepDescription).lowercased()
        if lower.contains("run") || lower.contains("command") || lower.contains("bash") || lower.contains("terminal") {
            return Color.green
        }
        if lower.contains("edit") || lower.contains("write") || lower.contains("replace") || lower.contains("patch") {
            return Color.cyan
        }
        if lower.contains("view") || lower.contains("read") || lower.contains("grep") || lower.contains("find") {
            return Color.blue
        }
        if lower.contains("search") || lower.contains("web") || lower.contains("browser") {
            return Color.orange
        }
        if lower.contains("error") || lower.contains("failed") {
            return Color.red
        }
        return Color.accentColor
    }

    private var iconName: String {
        let lower = (state.status + " " + state.stepDescription).lowercased()
        if lower.contains("run") || lower.contains("command") || lower.contains("bash") || lower.contains("terminal") {
            return "terminal.fill"
        }
        if lower.contains("edit") || lower.contains("write") || lower.contains("replace") || lower.contains("patch") {
            return "square.and.pencil"
        }
        if lower.contains("view") || lower.contains("read") || lower.contains("cat") {
            return "doc.text.magnifyingglass"
        }
        if lower.contains("search") || lower.contains("web") || lower.contains("browser") {
            return "globe"
        }
        if lower.contains("error") || lower.contains("failed") {
            return "exclamationmark.triangle.fill"
        }
        return "gearshape.2.fill"
    }
}
