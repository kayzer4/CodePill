import SwiftUI

public struct ToolDetailSheet: View {
    public let item: ToolCallItem
    @Environment(\.dismiss) private var dismiss
    @State private var copied: Bool = false

    public init(item: ToolCallItem) {
        self.item = item
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    // Header card
                    headerCard

                    // Formatted Parameters / Input
                    parametersSection

                    // Clean Output (Exact output returned to model, no traffic light, strictly vertical)
                    terminalOutputSection
                }
                .padding(16)
            }
            .background(Color(UIColor.systemBackground))
            .navigationTitle("Tool Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.bold())
                }
            }
        }
    }

    // MARK: - Header
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
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if item.isRunning {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text(item.name == "schedule" ? "Waiting" : "Running")
                            .font(.caption2.bold())
                            .foregroundStyle(item.name == "schedule" ? Color.purple : .orange)
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
        .padding(14)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Parameters
    @ViewBuilder
    private var parametersSection: some View {
        if let params = item.parametersText, !params.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Input & Parameters", systemImage: "arrow.down.forward.and.arrow.up.backward")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    if let parsedDict = parseJsonDict(params) {
                        ForEach(parsedDict.sorted(by: { $0.key < $1.key }), id: \.key) { key, val in
                            HStack(alignment: .top, spacing: 8) {
                                Text(key)
                                    .font(.caption2.bold().monospaced())
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 100, alignment: .leading)
                                Text(val)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 2)
                            if key != parsedDict.keys.sorted().last {
                                Divider().opacity(0.4)
                            }
                        }
                    } else {
                        Text(params)
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // MARK: - Clean Output
    private var terminalOutputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with Share & Copy
            HStack {
                Label("Model Result", systemImage: "arrow.turn.down.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                let textToCopy = item.fullOutput ?? item.output ?? ""
                if !textToCopy.isEmpty {
                    ShareLink(item: textToCopy) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.caption.bold())
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            // Output Box (Clean styling, no traffic lights, raw text returned to model)
            VStack(spacing: 0) {
                // Clean Topbar
                HStack {
                    Image(systemName: "terminal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(terminalTitle)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))

                    Spacer()

                    let textToCopy = item.fullOutput ?? item.output ?? ""
                    Button {
                        UIPasteboard.general.string = textToCopy
                        copied = true
                        Haptics.shared.notify(.success)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Copied" : "Copy")
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(copied ? Color.green : Color.accentColor)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 0.12, green: 0.13, blue: 0.16))

                Divider().overlay(Color.white.opacity(0.08))

                // Exact output delivered to model (Strictly vertical, word-wrapped, clean)
                ScrollView(.vertical, showsIndicators: true) {
                    let outText = (item.fullOutput ?? item.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(outText.isEmpty ? "(No output returned)" : outText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(outText.isEmpty ? .white.opacity(0.35) : .white.opacity(0.92))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 160, maxHeight: 440)
                .background(Color(red: 0.07, green: 0.08, blue: 0.10))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
    }

    // MARK: - Helpers
    private var terminalTitle: String {
        switch item.name {
        case "run_command": return "bash stdout"
        case "schedule": return "schedule timer"
        case "read_file", "view_file": return "reader"
        case "write_file", "edit_file": return "editor"
        default: return "\(item.name) result"
        }
    }

    private func parseJsonDict(_ json: String) -> [String: String]? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var result: [String: String] = [:]
        for (k, v) in obj {
            if let str = v as? String {
                result[k] = str
            } else if let num = v as? NSNumber {
                result[k] = num.stringValue
            } else if let b = v as? Bool {
                result[k] = b ? "true" : "false"
            } else if let subData = try? JSONSerialization.data(withJSONObject: v),
                      let subStr = String(data: subData, encoding: .utf8) {
                result[k] = subStr
            }
        }
        return result
    }

    private var statusColor: Color {
        if item.name == "schedule" { return .purple }
        if item.isRunning { return .orange }
        return item.isSuccess ? .green : .red
    }

    private func iconForTool(_ name: String) -> String {
        switch name {
        case "schedule": return "clock.badge.checkmark"
        case "manage_task": return "list.bullet.rectangle"
        case "run_command": return "terminal.fill"
        case "write_file", "edit_file", "write_to_file", "replace_file_content": return "doc.badge.gearshape.fill"
        case "read_file", "view_file": return "eye.fill"
        case "search_web": return "globe"
        default: return "wrench.and.screwdriver.fill"
        }
    }
}
