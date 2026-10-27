import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

public struct HeaderScaleButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

public struct ContentView: View {
    @StateObject private var viewModel: ChatViewModel
    @State private var showSettings: Bool = false
    @State private var showConversations: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showFilePicker: Bool = false

    public init(client: CodePillClient) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(client: client))
    }

    public var body: some View {
        ZStack {
            // Strict Clean Apple Dark Background
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Native Apple iOS Navigation Header
                nativeHeaderBar

                // Dynamic Island mirror preview when busy
                if let island = viewModel.currentIslandState {
                    LiveIslandPreview(state: island)
                        .padding(.horizontal, 14)
                        .padding(.top, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Chat stream
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
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

                            // Dedicated bottom scroll anchor
                            Color.clear
                                .frame(height: 1)
                                .id("chatBottomAnchor")
                        }
                        .padding(.vertical, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture {
                        hideKeyboard()
                    }
                    .onChange(of: viewModel.messages.last?.text) { _ in
                        proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
                    }
                    .onChange(of: viewModel.messages.last?.toolCalls.count) { _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
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

    private var nativeHeaderBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Conversations list button
                Button {
                    viewModel.client.requestConversationsList()
                    DispatchQueue.main.async {
                        showConversations = true
                    }
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36, height: 36)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .buttonStyle(HeaderScaleButtonStyle())

                Spacer()

                // Center Title & Status subtitle
                VStack(spacing: 2) {
                    Text("CodePill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)

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
                                .progressViewStyle(.circular)
                                .scaleEffect(0.5)
                        }
                    }
                }

                Spacer()

                // Actions: New Chat, Rollback, Settings
                HStack(spacing: 8) {
                    Button {
                        viewModel.startNewChat()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 34, height: 34)
                            .background(Color(UIColor.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                    .buttonStyle(HeaderScaleButtonStyle())

                    Button {
                        viewModel.rollbackTurn()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(viewModel.isExecuting ? Color.secondary.opacity(0.3) : Color.orange)
                            .frame(width: 34, height: 34)
                            .background(Color(UIColor.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                    .buttonStyle(HeaderScaleButtonStyle())
                    .disabled(viewModel.isExecuting)

                    Button {
                        DispatchQueue.main.async {
                            showSettings = true
                        }
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background(Color(UIColor.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                    .buttonStyle(HeaderScaleButtonStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .background(Color(UIColor.systemBackground).opacity(0.96))

            Divider()
                .opacity(0.35)
        }
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
