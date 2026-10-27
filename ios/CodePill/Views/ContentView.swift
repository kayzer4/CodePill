import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

public struct ContentView: View {
    @StateObject private var viewModel: ChatViewModel
    @State private var showSettings: Bool = false
    @State private var showConversations: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showFilePicker: Bool = false
    @State private var isAtBottom: Bool = true
    @State private var hasInitialScrolled: Bool = false

    public init(client: CodePillClient) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(client: client))
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = false) {
        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Dynamic Island mirror preview when busy
                if let island = viewModel.currentIslandState {
                    LiveIslandPreview(state: island)
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Chat stream with smart auto-scroll & floating bottom button
                ScrollViewReader { proxy in
                    ZStack(alignment: .bottomTrailing) {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(viewModel.messages) { msg in
                                    MessageRow(
                                        message: msg,
                                        onRollback: {
                                            viewModel.rollbackTurn()
                                        },
                                        onEdit: { prompt in
                                            viewModel.inputText = prompt
                                        }
                                    )
                                    .id(msg.id)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.96, anchor: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                                }

                                // Dedicated bottom scroll anchor & viewport detector
                                Color.clear
                                    .frame(height: 8)
                                    .id("chatBottomAnchor")
                                    .onAppear {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isAtBottom = true
                                        }
                                    }
                                    .onDisappear {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isAtBottom = false
                                        }
                                    }
                            }
                            .padding(.vertical, 12)
                        }
                        .defaultScrollAnchorBottom()
                        .refreshable {
                            await viewModel.refreshCurrentSessionAsync()
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onTapGesture {
                            hideKeyboard()
                        }
                        .onAppear {
                            scrollToBottom(proxy: proxy, animated: false)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                scrollToBottom(proxy: proxy, animated: false)
                            }
                        }
                        .onChange(of: viewModel.currentConversationId) { _ in
                            hasInitialScrolled = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                scrollToBottom(proxy: proxy, animated: false)
                            }
                        }
                        .onChange(of: viewModel.isExecuting) { executing in
                            if executing {
                                isAtBottom = true
                                scrollToBottom(proxy: proxy, animated: true)
                            }
                        }
                        .onChange(of: viewModel.messages.last?.text) { _ in
                            if isAtBottom {
                                proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
                            }
                        }
                        .onChange(of: viewModel.messages.last?.toolCalls.count) { _ in
                            if isAtBottom {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: viewModel.messages.count) { newCount in
                            if !hasInitialScrolled && newCount > 0 {
                                hasInitialScrolled = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    scrollToBottom(proxy: proxy, animated: false)
                                }
                            } else if isAtBottom {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
                                }
                            }
                        }

                        // Floating "Scroll to Bottom" Button (like ChatGPT & Telegram)
                        if !isAtBottom {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
                                }
                                Haptics.shared.impact(.light)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isAtBottom = true
                                    }
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(UIColor.secondarySystemBackground))
                                        .frame(width: 40, height: 40)
                                        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                        )

                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.primary)

                                    if viewModel.isExecuting {
                                        Circle()
                                            .fill(Color.accentColor)
                                            .frame(width: 9, height: 9)
                                            .offset(x: 13, y: -13)
                                    }
                                }
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, 12)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                }

                // Attachment preview strip above input
                if !viewModel.attachments.isEmpty {
                    AttachmentPreviewBar(attachments: viewModel.attachments) { id in
                        viewModel.removeAttachment(id: id)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                }

                // Input Bar
                strictInputBar
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            .background(Color(UIColor.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.client.requestConversationsList()
                        showConversations = true
                        Haptics.shared.selection()
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }

                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(currentConversationTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: 5) {
                            Circle()
                                .fill(statusIndicatorColor)
                                .frame(width: 6, height: 6)

                            Text(statusIndicatorText)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            if viewModel.isExecuting {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        // New Chat
                        Button {
                            viewModel.startNewChat()
                            Haptics.shared.impact(.light)
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                        }

                        // Options Menu (Apple standard ellipsis.circle)
                        Menu {
                            Button {
                                viewModel.refreshCurrentSession()
                            } label: {
                                Label("Reload / Sync Chat", systemImage: "arrow.clockwise")
                            }

                            Button {
                                viewModel.rollbackTurn()
                            } label: {
                                Label("Undo Last Turn", systemImage: "arrow.uturn.backward")
                            }
                            .disabled(viewModel.isExecuting)

                            Divider()

                            Button {
                                showSettings = true
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    }
                }
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
        .onChange(of: selectedPhotoItem) { newItem in
            guard let newItem = newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    viewModel.addPhotoData(data, filename: "photo_\(Int(Date().timeIntervalSince1970)).jpg")
                }
                selectedPhotoItem = nil
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.addFileUrl(url)
                }
            case .failure(let err):
                print("[CodePill] File picker error: \(err)")
            }
        }
    }

    private var currentConversationTitle: String {
        if let currentId = viewModel.currentConversationId,
           let conv = viewModel.conversations.first(where: { $0.id == currentId }) {
            return conv.title
        }
        return "CodePill"
    }

    private var statusIndicatorColor: Color {
        if !viewModel.isConnected {
            return .orange
        }
        if viewModel.isExecuting {
            return Color.accentColor
        }
        return .green
    }

    private var statusIndicatorText: String {
        if !viewModel.isConnected {
            return "Offline"
        }
        if viewModel.isExecuting {
            if let file = viewModel.currentIslandState?.currentFile {
                return file
            }
            return viewModel.currentIslandState?.status ?? "Thinking"
        }
        return "Connected"
    }

    private var canSend: Bool {
        let hasText = !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !viewModel.attachments.isEmpty
        return hasText || hasAttachments
    }

    private var strictInputBar: some View {
        HStack(spacing: 8) {
            // Attachment menu
            Menu {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Attach Photo", systemImage: "photo.on.rectangle")
                }
                Button {
                    showFilePicker = true
                } label: {
                    Label("Attach File / Code", systemImage: "doc.badge.plus")
                }
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .padding(.leading, 6)

            TextField("Message or instruction...", text: $viewModel.inputText, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 8)
                .padding(.vertical, 9)
                .foregroundStyle(.primary)

            ChatInputActionButton(
                isExecuting: viewModel.isExecuting,
                canSend: canSend,
                onSend: { viewModel.sendMessage() },
                onCancel: { viewModel.cancelTurn() }
            )
            .padding(.trailing, 6)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

fileprivate extension View {
    @ViewBuilder
    func defaultScrollAnchorBottom() -> some View {
        if #available(iOS 17.0, *) {
            self.defaultScrollAnchor(.bottom)
        } else {
            self
        }
    }
}
