import SwiftUI

public struct SideConversationsDrawer: View {
    @ObservedObject public var viewModel: ChatViewModel
    @Binding public var isOpen: Bool

    @State private var searchText: String = ""
    @State private var sortNewestFirst: Bool = true
    @State private var conversationToRename: ConversationItem? = nil
    @State private var newTitleText: String = ""
    @State private var showRenameAlert: Bool = false
    @State private var conversationToDelete: ConversationItem? = nil
    @State private var showDeleteConfirm: Bool = false

    private var filteredConversations: [ConversationItem] {
        var list = viewModel.conversations

        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
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
        VStack(spacing: 0) {
            // Header with search & new chat
            VStack(spacing: 12) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                        Text("Antigravity")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            sortNewestFirst.toggle()
                        }
                        Haptics.shared.selection()
                    } label: {
                        Image(systemName: sortNewestFirst ? "arrow.down.circle" : "arrow.up.circle")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            isOpen = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 56) // Clean padding under Dynamic Island / notch and status bar

                // Search field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))

                    TextField("Search chats...", text: $searchText)
                        .font(.system(size: 14))

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 13))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemBackground).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)

                // New Session Button
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        viewModel.startNewChat()
                        isOpen = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .bold))
                        Text("New Chat")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 16)

            // Conversations List
            ScrollView {
                LazyVStack(spacing: 6) {
                    if filteredConversations.isEmpty {
                        VStack(spacing: 8) {
                            Text(searchText.isEmpty ? "No conversations yet" : "No results for \"\(searchText)\"")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)

                            Button("Sync from Antigravity") {
                                viewModel.client.requestConversationsList()
                                Haptics.shared.impact(.light)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        }
                        .padding(.top, 40)
                    } else {
                        ForEach(filteredConversations) { item in
                            let isSelected = viewModel.currentConversationId == item.id
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    viewModel.selectConversation(item)
                                    isOpen = false
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: isSelected ? "bubble.left.and.text.bubble.right.fill" : "bubble.left")
                                        .font(.system(size: 15))
                                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title)
                                            .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        HStack(spacing: 6) {
                                            Text("\(item.message_count) msgs")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)

                                            if !item.updated_at.isEmpty {
                                                Text("•")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.secondary)
                                                Text(formatDate(item.updated_at))
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }

                                    Spacer()

                                    if isSelected {
                                        Circle()
                                            .fill(Color.accentColor)
                                            .frame(width: 7, height: 7)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    conversationToRename = item
                                    newTitleText = item.title
                                    showRenameAlert = true
                                    Haptics.shared.selection()
                                } label: {
                                    Label("Rename Title", systemImage: "pencil")
                                }

                                Button {
                                    UIPasteboard.general.string = item.id
                                    Haptics.shared.notify(.success)
                                } label: {
                                    Label("Copy Session ID", systemImage: "doc.on.doc")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    conversationToDelete = item
                                    showDeleteConfirm = true
                                    Haptics.shared.notify(.warning)
                                } label: {
                                    Label("Delete Chat", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color(UIColor.systemBackground)
                .opacity(0.96)
        )
        .alert("Rename Chat", isPresented: $showRenameAlert) {
            TextField("New title", text: $newTitleText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let item = conversationToRename {
                    viewModel.renameConversation(id: item.id, newTitle: newTitleText)
                }
            }
        } message: {
            Text("Enter a new title for this Antigravity session")
        }
        .confirmationDialog(
            "Delete \"\(conversationToDelete?.title ?? "this chat")\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Chat", role: .destructive) {
                if let item = conversationToDelete {
                    viewModel.deleteConversation(id: item.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the conversation history and transcript files on the server.")
        }
        .onAppear {
            viewModel.client.requestConversationsList()
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
