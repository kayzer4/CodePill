import SwiftUI

public struct ConversationsSheet: View {
    @ObservedObject public var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            ZStack {
                LiquidAmbientBackground()

                VStack(spacing: 16) {
                    // New Chat Action
                    Button {
                        viewModel.startNewChat()
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.purple)
                            Text("Start New Vibe Session")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding()
                        .liquidGlass(cornerRadius: 16, glowColor: Color.purple.opacity(0.3), isHighlighted: true)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)

                    if viewModel.conversations.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("No saved conversations yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(viewModel.conversations) { item in
                                    Button {
                                        viewModel.selectConversation(item)
                                        dismiss()
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.title)
                                                    .font(.subheadline.bold())
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                Text("\(item.message_count) messages")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if viewModel.currentConversationId == item.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                        .padding()
                                        .liquidGlass(cornerRadius: 14, isHighlighted: viewModel.currentConversationId == item.id)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .navigationTitle("Vibe Sessions")
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
