import SwiftUI

public struct ConversationsSheet: View {
    @ObservedObject public var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        viewModel.startNewChat()
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                            Text("New Session")
                                .font(.headline)
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                }

                Section("Antigravity & CodePill Sessions") {
                    if viewModel.conversations.isEmpty {
                        VStack(alignment: .center, spacing: 8) {
                            Text("No sessions found")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Refresh from Server") {
                                viewModel.client.requestConversationsList()
                            }
                            .font(.caption.bold())
                        }
                        .padding(.vertical, 8)
                    } else {
                        ForEach(viewModel.conversations) { item in
                            Button {
                                viewModel.selectConversation(item)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(viewModel.currentConversationId == item.id ? Color.accentColor : Color.secondary)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        HStack(spacing: 6) {
                                            Text("\(item.message_count) steps")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)

                                            if !item.updated_at.isEmpty {
                                                Text("•")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                Text(formatDate(item.updated_at))
                                                    .font(.caption2.monospaced())
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }

                                    Spacer()

                                    if viewModel.currentConversationId == item.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                            .font(.subheadline)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                viewModel.client.requestConversationsList()
            }
            .onAppear {
                viewModel.client.requestConversationsList()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.client.requestConversationsList()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatDate(_ dateStr: String) -> String {
        // Simple substring for ISO timestamps e.g. "2026-10-27 08:34" or "2026-10-27T08:34"
        if dateStr.count >= 16 {
            let prefix = String(dateStr.prefix(16))
            return prefix.replacingOccurrences(of: "T", with: " ")
        }
        return dateStr
    }
}
