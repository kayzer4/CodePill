import SwiftUI

public struct ConversationsSheet: View {
    @ObservedObject public var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var sortNewestFirst: Bool = true

    private var filteredConversations: [ConversationItem] {
        var list = viewModel.conversations

        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.workspace?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        list.sort { a, b in
            if sortNewestFirst {
                return a.updated_at > b.updated_at
            } else {
                return a.updated_at < b.updated_at
            }
        }

        return list
    }

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

                Section {
                    if filteredConversations.isEmpty {
                        VStack(alignment: .center, spacing: 8) {
                            Text(searchText.isEmpty ? "No sessions found" : "No matches for \"\(searchText)\"")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if searchText.isEmpty {
                                Button("Refresh from Server") {
                                    viewModel.client.requestConversationsList()
                                }
                                .font(.caption.bold())
                            }
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(filteredConversations) { item in
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
                                            if let ws = item.workspace, !ws.isEmpty {
                                                Text(ws)
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(Color.accentColor)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1.5)
                                                    .background(Color.accentColor.opacity(0.12))
                                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                            }

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
                        .onDelete(perform: deleteItems)
                    }
                } header: {
                    HStack {
                        Text("Antigravity & CodePill Sessions")
                        Spacer()
                        Text("\(filteredConversations.count)")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search conversations...")
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
                        withAnimation {
                            sortNewestFirst.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: sortNewestFirst ? "arrow.down" : "arrow.up")
                                .font(.caption.bold())
                            Text(sortNewestFirst ? "Newest" : "Oldest")
                                .font(.caption)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.bold())
                }
            }
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = filteredConversations[index]
            viewModel.deleteConversation(id: item.id)
        }
    }

    private func formatDate(_ dateStr: String) -> String {
        if dateStr.count >= 16 {
            let prefix = String(dateStr.prefix(16))
            return prefix.replacingOccurrences(of: "T", with: " ")
        }
        return dateStr
    }
}
