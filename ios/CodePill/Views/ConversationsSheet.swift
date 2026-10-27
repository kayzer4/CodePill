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
                        Label("New Session", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.purple)
                    }
                }

                Section("Saved Sessions") {
                    if viewModel.conversations.isEmpty {
                        Text("No sessions recorded yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.conversations) { item in
                            Button {
                                viewModel.selectConversation(item)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text("\(item.message_count) messages")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if viewModel.currentConversationId == item.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.purple)
                                            .font(.caption.bold())
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sessions")
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
}
