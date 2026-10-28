import SwiftUI

public struct ChatInfoSheet: View {
    @ObservedObject public var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: InfoTab = .files
    @State private var searchText: String = ""
    @State private var showRenameAlert: Bool = false
    @State private var renameTitleText: String = ""
    @State private var copiedId: Bool = false
    @State private var showDeleteConfirm: Bool = false

    private enum InfoTab: String, CaseIterable, Identifiable {
        case files = "Файлы"
        case links = "Ссылки"
        case search = "Поиск"
        case actions = "Действия"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .files: return "doc.on.doc"
            case .links: return "link"
            case .search: return "magnifyingglass"
            case .actions: return "slider.horizontal.3"
            }
        }
    }

    private var currentTitle: String {
        if let currentId = viewModel.currentConversationId,
           let conv = viewModel.conversations.first(where: { $0.id == currentId }) {
            return conv.title
        }
        return "Диалог"
    }

    private var currentId: String {
        viewModel.currentConversationId ?? "Новый диалог"
    }

    /// Extract all attachments from the current conversation
    private var allAttachments: [AttachmentItem] {
        viewModel.messages.flatMap { $0.attachments }
    }

    /// Extract all web URLs and file paths mentioned in conversation messages
    private var extractedLinks: [ExtractedLink] {
        var links: [ExtractedLink] = []
        var seenUrls: Set<String> = []

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

        for msg in viewModel.messages {
            // Find regular URLs
            if let matches = detector?.matches(in: msg.text, options: [], range: NSRange(location: 0, length: msg.text.utf16.count)) {
                for match in matches {
                    if let range = Range(match.range, in: msg.text),
                       let url = match.url {
                        let str = url.absoluteString
                        if !seenUrls.contains(str) {
                            seenUrls.insert(str)
                            links.append(ExtractedLink(
                                title: String(msg.text[range]),
                                url: url,
                                isFile: false
                            ))
                        }
                    }
                }
            }

            // Also check tool calls for generated file paths
            for tool in msg.toolCalls {
                if let path = tool.summary.components(separatedBy: "File: ").last,
                   path.contains("/") {
                    let clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !seenUrls.contains(clean) {
                        seenUrls.insert(clean)
                        if let fileUrl = URL(string: "file://\(clean)") {
                            links.append(ExtractedLink(
                                title: (clean as NSString).lastPathComponent,
                                url: fileUrl,
                                isFile: true
                            ))
                        }
                    }
                }
            }
        }

        return links
    }

    /// Search results
    private var searchResults: [ChatMessage] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return viewModel.messages.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Header Card
                headerCard
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                // Segmented Picker
                Picker("Раздел", selection: $selectedTab) {
                    ForEach(InfoTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                // Tab Content
                TabView(selection: $selectedTab) {
                    filesTabView
                        .tag(InfoTab.files)

                    linksTabView
                        .tag(InfoTab.links)

                    searchTabView
                        .tag(InfoTab.search)

                    actionsTabView
                        .tag(InfoTab.actions)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Информация о чате")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
            .alert("Переименовать чат", isPresented: $showRenameAlert) {
                TextField("Название", text: $renameTitleText)
                Button("Отмена", role: .cancel) {}
                Button("Сохранить") {
                    if let cid = viewModel.currentConversationId {
                        viewModel.renameConversation(id: cid, newTitle: renameTitleText)
                    }
                }
            }
            .confirmationDialog(
                "Удалить этот чат?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Удалить навсегда", role: .destructive) {
                    if let cid = viewModel.currentConversationId {
                        viewModel.deleteConversation(id: cid)
                        dismiss()
                    }
                }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    // MARK: - Header Card
    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                // Chat Glyph
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 50, height: 50)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(currentTitle)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Button {
                            renameTitleText = currentTitle
                            showRenameAlert = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Модель: \(viewModel.selectedModel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            // ID row with copy button
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ID ЧАТА")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(currentId)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    UIPasteboard.general.string = currentId
                    withAnimation { copiedId = true }
                    Haptics.shared.notify(.success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation { copiedId = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedId ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                        Text(copiedId ? "Скопирован" : "Копировать")
                            .font(.caption2.bold())
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(copiedId ? Color.green.opacity(0.18) : Color.accentColor.opacity(0.14))
                    .foregroundStyle(copiedId ? Color.green : Color.accentColor)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Files Tab
    private var filesTabView: some View {
        Group {
            if allAttachments.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                    Text("В этом диалоге нет прикрепленных файлов")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(allAttachments) { att in
                        HStack(spacing: 12) {
                            if att.isImage, let data = Data(base64Encoded: att.base64Data), let uiImg = UIImage(data: data) {
                                Image(uiImage: uiImg)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.orange.opacity(0.15))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "doc.fill")
                                        .foregroundStyle(Color.orange)
                                        .font(.system(size: 20))
                                }
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(att.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(att.mimeType)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                if let data = Data(base64Encoded: att.base64Data) {
                                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(att.name)
                                    try? data.write(to: tempURL)
                                    viewModel.openFilePreview(path: tempURL.path)
                                    dismiss()
                                }
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Links Tab
    private var linksTabView: some View {
        Group {
            if extractedLinks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                    Text("В сообщениях нет ссылок")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(extractedLinks) { item in
                        Button {
                            if item.isFile {
                                viewModel.openFilePreview(path: item.url.path)
                            } else {
                                viewModel.activeWebURL = item.url
                            }
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(item.isFile ? Color.purple.opacity(0.15) : Color.blue.opacity(0.15))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: item.isFile ? "folder.fill" : "globe")
                                        .foregroundStyle(item.isFile ? Color.purple : Color.blue)
                                        .font(.system(size: 16))
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(item.url.absoluteString)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Search Tab
    private var searchTabView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Поиск по тексту сообщений...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)

            if searchText.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                    Text("Введите поисковый запрос для поиска по сообщениям")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty {
                VStack(spacing: 8) {
                    Text("Ничего не найдено")
                        .font(.headline)
                    Text("По запросу \"\(searchText)\" совпадений нет")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(searchResults) { msg in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(msg.role == .user ? "Вы" : "Antigravity")
                                    .font(.caption.bold())
                                    .foregroundStyle(msg.role == .user ? Color.blue : Color.accentColor)
                                Spacer()
                            }
                            Text(msg.text)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIPasteboard.general.string = msg.text
                            Haptics.shared.notify(.success)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Actions Tab
    private var actionsTabView: some View {
        List {
            Section("Управление сессией") {
                Button {
                    viewModel.refreshCurrentSession()
                    dismiss()
                } label: {
                    Label("Синхронизировать историю", systemImage: "arrow.clockwise")
                }

                Button {
                    viewModel.rollbackTurn()
                    dismiss()
                } label: {
                    Label("Откатить последний ход", systemImage: "arrow.uturn.backward")
                }

                Button {
                    renameTitleText = currentTitle
                    showRenameAlert = true
                } label: {
                    Label("Переименовать диалог", systemImage: "pencil")
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Удалить этот диалог", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct ExtractedLink: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
    let isFile: Bool
}
