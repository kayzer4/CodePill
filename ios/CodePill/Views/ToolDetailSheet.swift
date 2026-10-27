import SwiftUI

public struct ToolDetailSheet: View {
    public let item: ToolCallItem
    @Environment(\.dismiss) private var dismiss
    @State private var copied: Bool = false

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header card
                    headerCard

                    // Parameters section
                    if let params = item.parametersText, !params.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Parameters")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(params)
                                .font(.caption.monospaced())
                                .foregroundStyle(.primary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(UIColor.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    // Full Output Console
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Output")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                let textToCopy = item.fullOutput ?? item.output ?? ""
                                UIPasteboard.general.string = textToCopy
                                copied = true
                                Haptics.shared.notify(.success)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copied = false
                                }
                            } label: {
                                Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .font(.caption.bold())
                                    .foregroundStyle(copied ? .green : Color.accentColor)
                            }
                        }

                        let outText = item.fullOutput ?? item.output ?? "(No output)"
                        ScrollView([.horizontal, .vertical]) {
                            Text(outText)
                                .font(.caption.monospaced())
                                .foregroundStyle(.primary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 180, maxHeight: 420)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Tool Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 12) {
            Image(systemName: iconForTool(item.name))
                .font(.title2)
                .foregroundStyle(statusColor)
                .padding(10)
                .background(statusColor.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline.monospaced())
                    .foregroundStyle(.primary)

                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if item.isRunning {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Running")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text(item.isSuccess ? "Success" : "Failed")
                        .font(.caption2.bold())
                        .foregroundStyle(item.isSuccess ? .green : .red)
                }

                if let dur = item.duration {
                    Text(String(format: "%.2fs", dur))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusColor: Color {
        if item.isRunning { return .orange }
        return item.isSuccess ? .green : .red
    }

    private func iconForTool(_ name: String) -> String {
        switch name {
        case "run_command": return "terminal.fill"
        case "write_to_file", "replace_file_content": return "doc.badge.gearshape.fill"
        case "view_file": return "eye.fill"
        case "search_web": return "globe"
        default: return "wrench.and.screwdriver.fill"
        }
    }
}
