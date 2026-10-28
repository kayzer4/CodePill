import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

public struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: ChatViewModel
    @State private var showSettings: Bool = false
    @State private var showSideDrawer: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showFilePicker: Bool = false
    @State private var isAtBottom: Bool = true
    @State private var hasInitialScrolled: Bool = false
    @State private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    private let drawerWidth: CGFloat = 300

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
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
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
                                // Кнопка "загрузить ещё" вверху списка
                                if viewModel.canLoadMore {
                                    Button {
                                        viewModel.loadMoreMessages()
                                    } label: {
                                        HStack(spacing: 6) {
                                            if viewModel.isLoadingMore {
                                                ProgressView().scaleEffect(0.7)
                                            } else {
                                                Image(systemName: "arrow.up.circle")
                                            }
                                            Text(viewModel.isLoadingMore ? "Загрузка..." : "Загрузить ещё")
                                                .font(.system(size: 13, weight: .medium))
                                        }
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                        .liquidGlass(cornerRadius: 14)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 4)
                                    .onAppear {
                                        // Автоподгрузка при скролле к самому верху
                                        viewModel.loadMoreMessages()
                                    }
                                }
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
                                        .fill(Color(UIColor.secondarySystemBackground).opacity(0.82))
                                        .frame(width: 42, height: 42)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1
                                                )
                                        )
                                        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)

                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.primary)

                                    if viewModel.isExecuting {
                                        Circle()
                                            .fill(Color.accentColor)
                                            .frame(width: 9, height: 9)
                                            .offset(x: 13, y: -13)
                                            .shadow(color: Color.accentColor.opacity(0.8), radius: 4, x: 0, y: 0)
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

                // File downloading indicator HUD
                if viewModel.isDownloadingFile {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.75)
                        Text("Fetching file from server...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .liquidGlass(cornerRadius: 16)
                    .padding(.bottom, 6)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }

                if let err = viewModel.downloadError {
                    Text(err)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(.bottom, 6)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                                withAnimation { viewModel.downloadError = nil }
                            }
                        }
                }

                // Input Bar
                strictInputBar
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            .background(LiquidAmbientBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.client.requestConversationsList()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            showSideDrawer.toggle()
                        }
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
                                .frame(width: 6.5, height: 6.5)
                                .shadow(color: statusIndicatorColor.opacity(0.85), radius: 4, x: 0, y: 0)

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

        .sheet(isPresented: Binding(
            get: { viewModel.activeWebURL != nil },
            set: { if !$0 { viewModel.activeWebURL = nil } }
        )) {
            if let url = viewModel.activeWebURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.previewLocalURL != nil },
            set: { if !$0 { viewModel.previewLocalURL = nil } }
        )) {
            if let localURL = viewModel.previewLocalURL {
                FilePreviewSheet(
                    localURL: localURL,
                    originalPath: viewModel.previewOriginalPath
                )
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            handleURLTap(url)
            return .handled
        })
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
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                if viewModel.isExecuting {
                    backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "CodePillTurnExecution") {
                        if backgroundTaskId != .invalid {
                            UIApplication.shared.endBackgroundTask(backgroundTaskId)
                            backgroundTaskId = .invalid
                        }
                    }
                }
            case .active:
                if backgroundTaskId != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskId)
                    backgroundTaskId = .invalid
                }
                viewModel.handleAppForeground()
            default:
                break
            }
        }
        .onAppear {
            viewModel.syncCurrentConversation()
        }

        // Darkened Backdrop for Drawer
        if showSideDrawer || dragOffset > 0 {
            let opacity = Double(min(0.5, (showSideDrawer ? 0.45 : 0) + (dragOffset / drawerWidth) * 0.45))
            Color.black.opacity(opacity)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        showSideDrawer = false
                        dragOffset = 0
                    }
                }
                .transition(.opacity)
        }

        // Sliding Side Drawer
        let currentX: CGFloat = showSideDrawer
            ? min(0, dragOffset)
            : -drawerWidth + max(0, dragOffset)

        SideConversationsDrawer(
            viewModel: viewModel,
            isOpen: $showSideDrawer
        )
        .frame(width: drawerWidth)
        .offset(x: currentX)
        .shadow(color: Color.black.opacity(showSideDrawer ? 0.35 : 0), radius: 16, x: 6, y: 0)

        // Window-level directional pan gesture helper:
        // Works across left ~60% of the screen without conflicting with vertical chat scrolling
        WindowDrawerPanHelper(
            isOpen: showSideDrawer,
            drawerWidth: drawerWidth,
            onPanChanged: { translationX in
                if showSideDrawer {
                    dragOffset = min(0, max(-drawerWidth, translationX))
                } else {
                    dragOffset = max(0, min(drawerWidth, translationX))
                }
            },
            onPanEnded: { translationX, velocityX in
                if showSideDrawer {
                    let shouldClose = translationX < -50 || velocityX < -150
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        if shouldClose {
                            showSideDrawer = false
                        }
                        dragOffset = 0
                    }
                } else {
                    let shouldOpen = translationX > 60 || velocityX > 150
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        if shouldOpen {
                            showSideDrawer = true
                        }
                        dragOffset = 0
                    }
                }
            }
        )
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
        .liquidGlass(cornerRadius: 22, specularOpacity: 0.28)
    }

    private func handleURLTap(_ url: URL) {
        let urlString = url.absoluteString
        if url.scheme == "http" || url.scheme == "https" {
            viewModel.activeWebURL = url
            Haptics.shared.impact(.light)
        } else {
            let clean = urlString
                .replacingOccurrences(of: "file://", with: "")
                .components(separatedBy: "#").first ?? urlString
            viewModel.openFilePreview(path: clean)
            Haptics.shared.impact(.medium)
        }
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
