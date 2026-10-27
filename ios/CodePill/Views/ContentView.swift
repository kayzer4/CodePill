import SwiftUI

public struct ContentView: View {
    @StateObject private var viewModel: ChatViewModel
    @State private var showSettings: Bool = false
    @State private var showConversations: Bool = false

    public init(client: CodePillClient) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(client: client))
    }

    public var body: some View {
        ZStack {
            // Ambient Liquid Neon Glass Background
            LiquidAmbientBackground()

            VStack(spacing: 0) {
                // Floating Glass Header Capsule
                liquidHeaderBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                // Dynamic Island mirror preview when busy
                if let island = viewModel.currentIslandState {
                    LiveIslandPreview(state: island)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Chat stream
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(viewModel.messages) { msg in
                                MessageRow(
                                    message: msg,
                                    onRollback: {
                                        viewModel.rollbackTurn()
                                    }
                                )
                                .id(msg.id)
                            }
                        }
                        .padding(.vertical, 14)
                    }
                    .onChange(of: viewModel.messages.last?.text) { _ in
                        if let last = viewModel.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        if let last = viewModel.messages.last {
                            withAnimation(.spring(response: 0.3)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Floating Liquid Glass Input Bar
                liquidInputBar
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                client: viewModel.client,
                selectedModel: $viewModel.selectedModel
            )
        }
        .sheet(isPresented: $showConversations) {
            ConversationsSheet(viewModel: viewModel)
        }
    }

    private var liquidHeaderBar: some View {
        HStack(spacing: 12) {
            // Conversations / Chat Switcher Button
            Button {
                viewModel.client.requestConversationsList()
                showConversations = true
            } label: {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.subheadline)
                    .foregroundStyle(.purple)
            }

            Spacer()

            // Center Branding & Connection Dot
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: viewModel.isConnected ? Color.green.opacity(0.8) : Color.red.opacity(0.8), radius: 4)

                Text(viewModel.isConnected ? "CodePill (Live)" : "CodePill (Offline)")
                    .font(.headline.monospaced())
                    .foregroundStyle(.white)
            }

            Spacer()

            // Rollback last turn button
            Button {
                viewModel.rollbackTurn()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption.bold())
                    .foregroundColor(viewModel.isExecuting ? Color.secondary : Color.orange)
            }
            .disabled(viewModel.isExecuting)

            // Settings Button
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlass(cornerRadius: 24, glowColor: Color.purple.opacity(0.18))
    }

    private var liquidInputBar: some View {
        HStack(spacing: 10) {
            TextField("Vibe a prompt, bugfix, or feature...", text: $viewModel.inputText, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(.white)

            if viewModel.isExecuting {
                Button {
                    viewModel.cancelTurn()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                        .shadow(color: .red.opacity(0.5), radius: 6)
                }
                .padding(.trailing, 6)
            } else {
                Button {
                    viewModel.sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.2) : Color.purple)
                        .shadow(color: viewModel.inputText.isEmpty ? .clear : Color.purple.opacity(0.6), radius: 8)
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.trailing, 6)
            }
        }
        .liquidGlass(cornerRadius: 26, glowColor: Color.purple.opacity(0.2), isHighlighted: !viewModel.inputText.isEmpty)
    }
}
