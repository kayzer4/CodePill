import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

public struct HeaderScaleButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
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
                // Header Bar
                strictHeaderBar
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 4)

                // Main Screen Status Bar (Clean connection & execution indicator)
                mainStatusBanner

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

    private var strictHeaderBar: some View {
        HStack(spacing: 14) {
            Button {
                viewModel.client.requestConversationsList()
                DispatchQueue.main.async {
                    showConversations = true
                }
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .clipShape(Circle())
            }
            .buttonStyle(HeaderScaleButtonStyle())

            Spacer()

            Text("CodePill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                viewModel.rollbackTurn()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption.bold())
                    .foregroundColor(viewModel.isExecuting ? Color.secondary : Color.orange)
                    .frame(width: 34, height: 34)
                    .background(Color(UIColor.tertiarySystemBackground))
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
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .clipShape(Circle())
            }
            .buttonStyle(HeaderScaleButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var mainStatusBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusIndicatorColor)
                .frame(width: 8, height: 8)

            Text(statusIndicatorText)
                .font(.caption.bold().monospaced())
                .foregroundStyle(.primary)

            Spacer()

            if viewModel.isExecuting {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.65)
                    .tint(Color.accentColor)
            } else {
                Text(viewModel.selectedModel.replacingOccurrences(of: "gemini-", with: ""))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(UIColor.secondarySystemBackground).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.top, 4)
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
                return "Running: \(file)"
            }
            return viewModel.currentIslandState?.status ?? "Thinking..."
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

            if viewModel.isExecuting {
                Button {
                    viewModel.cancelTurn()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .padding(.trailing, 6)
            } else {
                Button {
                    viewModel.sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
                }
                .disabled(!canSend)
                .padding(.trailing, 6)
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
