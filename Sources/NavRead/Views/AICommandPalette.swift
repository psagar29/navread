import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AICommandPalette: View {
    @EnvironmentObject private var store: NavReadStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var prompt = ""
    @State private var messages: [AIChatMessage] = []
    @State private var attachments: [AIAttachment] = []
    @State private var attachmentError = ""
    @State private var linkInput = ""
    @State private var showingLinkInput = false
    @State private var fileImporterPresented = false
    @State private var working = false
    @State private var importingAttachment = false
    @State private var isAttachmentDropTargeted = false
    @State private var appeared = false

    private var accent: Color {
        colorScheme == .dark ? .white : .black
    }

    private var scopeLabel: String {
        if store.selectedQuote != nil { return "quote" }
        if store.selectedChapter != nil { return "chapter" }
        return "book"
    }

    private var conversationHistory: String {
        messages
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(8)
            .map { "\($0.role.historyLabel): \($0.content)" }
            .joined(separator: "\n\n")
    }

    var body: some View {
        ZStack {
            MorphingBackground(accentHex: "#000000")
                .opacity(colorScheme == .dark ? 0.42 : 0.58)

            GlassPanel(cornerRadius: NavReadTheme.cornerRadiusXL, padding: 0, intensity: .regular) {
                VStack(spacing: 0) {
                    header

                    Divider()
                        .opacity(0.45)

                    conversationView

                    Divider()
                        .opacity(0.35)

                    VStack(spacing: 12) {
                        quickActions
                        composer
                    }
                    .padding(18)
                }
            }
            .frame(minWidth: 600, idealWidth: 730, maxWidth: 780, minHeight: 500, idealHeight: 560, maxHeight: 640)
            .padding(28)
            .scaleEffect(appeared ? 1 : 0.97)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : NavReadTheme.animationBouncy) {
                appeared = true
            }
        }
        .fileImporter(
            isPresented: $fileImporterPresented,
            allowedContentTypes: [.pdf, .image, .plainText],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07))
                    .frame(width: 42, height: 42)
                NavReadLogoMark(size: 24)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("AI")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                HStack(spacing: 6) {
                    Text(scopeLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.primary.opacity(0.06), in: Capsule())
                    Text(store.authState.authenticated ? "Codex connected" : "Local context ready")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if working {
                AIThinkingPulseView(accent: accent)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("Close")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var conversationView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if messages.isEmpty {
                        AIEmptyStateView(accent: accent)
                            .padding(.top, 26)
                    }

                    ForEach(messages) { message in
                        AIMessageBubble(message: message, accent: accent)
                            .id(message.id)
                    }
                }
                .padding(22)
            }
            .scrollIndicators(.visible)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.015 : 0.01))
            .onChange(of: messages) { _, updated in
                guard let last = updated.last else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(AIQuickAction.allCases) { action in
                Button {
                    prompt = action.prompt
                    run()
                } label: {
                    Label(action.title, systemImage: action.icon)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(AIQuickActionButtonStyle(accent: accent))
                .disabled(working)
                .help(action.prompt)
            }
        }
    }

    private var attachmentStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showingLinkInput {
                HStack(spacing: 8) {
                    TextField("https://example.com/article", text: $linkInput)
                        .textFieldStyle(NavReadTextFieldStyle())
                        .onSubmit { addLinkAttachment() }
                    Button {
                        addLinkAttachment()
                    } label: {
                        Label("Attach Link", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(linkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || importingAttachment || attachments.count >= AIAttachmentPolicy.maxItems)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !attachments.isEmpty || importingAttachment {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            AIAttachmentChip(attachment: attachment) {
                                withAnimation(NavReadTheme.animationSnappy) {
                                    attachments.removeAll { $0.id == attachment.id }
                                }
                            }
                        }
                        if importingAttachment {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Attaching")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.primary.opacity(colorScheme == .dark ? 0.065 : 0.04), in: Capsule())
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
            }

            if !attachmentError.isEmpty {
                Text(attachmentError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showingLinkInput || !attachments.isEmpty || importingAttachment || !attachmentError.isEmpty {
                attachmentStrip
            }

            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    Button {
                        fileImporterPresented = true
                    } label: {
                        Label("Attach File", systemImage: "doc.badge.plus")
                    }
                    .disabled(attachments.count >= AIAttachmentPolicy.maxItems)

                    Button {
                        withAnimation(NavReadTheme.animationSnappy) {
                            showingLinkInput.toggle()
                        }
                    } label: {
                        Label("Attach Link", systemImage: "link.badge.plus")
                    }
                    .disabled(attachments.count >= AIAttachmentPolicy.maxItems)
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04), in: Circle())
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .disabled(working || importingAttachment || attachments.count >= AIAttachmentPolicy.maxItems)
                .help("Attach files, images, PDFs, or links")
                .accessibilityLabel("Attachments")

                ZStack(alignment: .topLeading) {
                    AIPromptTextView(text: $prompt, isEditable: !working, onSubmit: run)
                        .frame(minHeight: 76, idealHeight: 82, maxHeight: 130)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.045) : Color.black.opacity(0.025))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(composerBorder, lineWidth: isAttachmentDropTargeted ? 1.5 : 1)
                        )

                    if prompt.isEmpty {
                        Text(isAttachmentDropTargeted ? "Drop to attach..." : "Ask about this book, chapter, quote, capture, OCR text, or code...")
                            .font(.system(size: 15))
                            .foregroundStyle(isAttachmentDropTargeted ? .primary : .tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }

                    if isAttachmentDropTargeted {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(accent.opacity(0.06))
                            .overlay(
                                Label("Drop files or links", systemImage: "paperclip")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                            )
                            .allowsHitTesting(false)
                    }
                }
                .onDrop(
                    of: [UTType.fileURL.identifier, UTType.url.identifier, UTType.plainText.identifier],
                    isTargeted: $isAttachmentDropTargeted,
                    perform: handleAttachmentDrop
                )

                Button {
                    run()
                } label: {
                    Image(systemName: working ? "waveform" : "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 44, height: 44)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(AISendButtonStyle(accent: accent, working: working))
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working || importingAttachment)
                .help("Send")
            }
        }
    }

    private var composerBorder: Color {
        if isAttachmentDropTargeted { return accent.opacity(0.38) }
        return working ? Color.primary.opacity(0.28) : Color.primary.opacity(0.10)
    }

    private func run() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !working else { return }

        let history = conversationHistory
        let activeAttachments = attachments
        prompt = ""
        attachments = []
        attachmentError = ""
        working = true

        let userMessage = AIChatMessage(role: .user, content: trimmed, attachments: activeAttachments)
        let assistantMessage = AIChatMessage(role: .assistant, content: "", isStreaming: true)
        withAnimation(reduceMotion ? nil : NavReadTheme.animationGentle) {
            messages.append(userMessage)
            messages.append(assistantMessage)
        }

        Task {
            do {
                for try await delta in store.askAIStream(trimmed, conversationHistory: history, attachments: activeAttachments) {
                    await MainActor.run {
                        append(delta, to: assistantMessage.id)
                    }
                }
                await MainActor.run {
                    finishStreaming(assistantMessage.id)
                }
            } catch {
                await MainActor.run {
                    replaceAssistantMessage(assistantMessage.id, with: error.localizedDescription)
                    finishStreaming(assistantMessage.id)
                }
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            addFileAttachments(urls)
        case .failure(let error):
            attachmentError = error.localizedDescription
        }
    }

    private func handleAttachmentDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !working, !importingAttachment else { return false }
        let remaining = max(0, AIAttachmentPolicy.maxItems - attachments.count)
        guard remaining > 0 else {
            attachmentError = "Attachment limit reached."
            return false
        }
        let selected = Array(providers.prefix(remaining))
        if providers.count > remaining {
            attachmentError = "Only \(AIAttachmentPolicy.maxItems) attachments can be sent at once."
        }
        importingAttachment = true
        Task { @MainActor in
            var fileURLs: [URL] = []
            var links: [String] = []
            var texts: [String] = []

            for provider in selected {
                if let url = await loadURL(from: provider, typeIdentifier: UTType.fileURL.identifier), url.isFileURL {
                    fileURLs.append(url)
                    continue
                }
                if let url = await loadURL(from: provider, typeIdentifier: UTType.url.identifier) {
                    if url.isFileURL {
                        fileURLs.append(url)
                    } else {
                        links.append(url.absoluteString)
                    }
                    continue
                }
                if let text = await loadText(from: provider), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if looksLikeURL(text) {
                        links.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        texts.append(text)
                    }
                }
            }

            var imported: [AIAttachment] = []
            var failures: [String] = []
            for url in fileURLs {
                do {
                    imported.append(try await store.importAIAttachmentFile(url))
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            for link in links {
                do {
                    imported.append(try await store.importAIAttachmentLink(link))
                } catch {
                    failures.append("\(link): \(error.localizedDescription)")
                }
            }
            for (index, text) in texts.enumerated() {
                do {
                    imported.append(try await store.importAIAttachmentText(text, name: texts.count == 1 ? "Dropped Text" : "Dropped Text \(index + 1)"))
                } catch {
                    failures.append(error.localizedDescription)
                }
            }

            await MainActor.run {
                withAnimation(reduceMotion ? nil : NavReadTheme.animationGentle) {
                    attachments.append(contentsOf: imported)
                }
                importingAttachment = false
                if !failures.isEmpty {
                    attachmentError = failures.joined(separator: "\n")
                } else if imported.isEmpty {
                    attachmentError = "Nothing readable was dropped."
                } else {
                    attachmentError = "Attached \(imported.count) item\(imported.count == 1 ? "" : "s")."
                }
            }
        }
        return true
    }

    private func addFileAttachments(_ urls: [URL]) {
        let remaining = max(0, AIAttachmentPolicy.maxItems - attachments.count)
        let selected = Array(urls.prefix(remaining))
        guard !selected.isEmpty else {
            attachmentError = "Attachment limit reached."
            return
        }
        if urls.count > remaining {
            attachmentError = "Only \(AIAttachmentPolicy.maxItems) attachments can be sent at once."
        }
        importingAttachment = true
        Task {
            var imported: [AIAttachment] = []
            var failures: [String] = []
            for url in selected {
                do {
                    imported.append(try await store.importAIAttachmentFile(url))
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            await MainActor.run {
                withAnimation(reduceMotion ? nil : NavReadTheme.animationGentle) {
                    attachments.append(contentsOf: imported)
                }
                importingAttachment = false
                if !failures.isEmpty {
                    attachmentError = failures.joined(separator: "\n")
                } else if imported.isEmpty {
                    attachmentError = "No attachments imported."
                } else if attachmentError.isEmpty {
                    attachmentError = "Attached \(imported.count) item\(imported.count == 1 ? "" : "s")."
                }
            }
        }
    }

    private func addLinkAttachment() {
        let value = linkInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, attachments.count < AIAttachmentPolicy.maxItems else { return }
        importingAttachment = true
        attachmentError = ""
        Task {
            do {
                let attachment = try await store.importAIAttachmentLink(value)
                await MainActor.run {
                    withAnimation(reduceMotion ? nil : NavReadTheme.animationGentle) {
                        attachments.append(attachment)
                        linkInput = ""
                        showingLinkInput = false
                    }
                    importingAttachment = false
                    attachmentError = "Attached link."
                }
            } catch {
                await MainActor.run {
                    importingAttachment = false
                    attachmentError = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func loadURL(from provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else { return nil }
        do {
            let value = try await provider.loadItemString(for: typeIdentifier)
            return URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return nil
        }
    }

    @MainActor
    private func loadText(from provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { return nil }
        do {
            return try await provider.loadItemString(for: UTType.plainText.identifier)
        } catch {
            return nil
        }
    }

    private func looksLikeURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "file"].contains(scheme)
    }

    private func append(_ delta: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
            messages[index].content += delta
        }
    }

    private func replaceAssistantMessage(_ id: UUID, with text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = text
    }

    private func finishStreaming(_ id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(reduceMotion ? nil : NavReadTheme.animationGentle) {
            messages[index].isStreaming = false
            working = false
        }
    }
}

private struct AIChatMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant

        var historyLabel: String {
            switch self {
            case .user: "User"
            case .assistant: "Assistant"
            }
        }
    }

    var id = UUID()
    var role: Role
    var content: String
    var attachments: [AIAttachment] = []
    var isStreaming = false
}

private enum AIQuickAction: String, CaseIterable, Identifiable {
    case explain
    case extract
    case cleanOCR
    case tags
    case related
    case chapter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explain: "Explain"
        case .extract: "Extract"
        case .cleanOCR: "Clean OCR"
        case .tags: "Tags"
        case .related: "Related"
        case .chapter: "Chapter"
        }
    }

    var icon: String {
        switch self {
        case .explain: "text.magnifyingglass"
        case .extract: "quote.opening"
        case .cleanOCR: "doc.text.magnifyingglass"
        case .tags: "tag"
        case .related: "link"
        case .chapter: "list.bullet.rectangle"
        }
    }

    var prompt: String {
        switch self {
        case .explain:
            "Explain the selected scope in clear language. Separate library-backed facts from your interpretation."
        case .extract:
            "Extract the best quote candidates from the selected scope. Include suggested chapter, tags, and why each is worth saving."
        case .cleanOCR:
            "Clean OCR or messy pasted text from the selected scope. Preserve wording where possible and flag uncertain fixes."
        case .tags:
            "Generate tight tags and a short note for the selected quote or chapter. Classify the content as quote, passage, idea, note, question, or code."
        case .related:
            "Find related saved quotes or chapters in this library and explain the connection."
        case .chapter:
            "Create editable chapter context: key ideas, likely quote themes, and capture suggestions for the current chapter."
        }
    }
}

private struct AIEmptyStateView: View {
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                NavReadLogoMark(size: 18)
                Text("Ask against the current book context.")
                    .font(.system(size: 15, weight: .semibold))
            }
            Text("NavRead sends the selected book, chapter, quote, saved quotes, and recent captures as context when Codex is connected.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct AIMessageBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    var message: AIChatMessage
    var accent: Color

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser {
                Spacer(minLength: 64)
            } else {
                avatar
            }

            VStack(alignment: .leading, spacing: 8) {
                if message.content.isEmpty, message.isStreaming {
                    AIThinkingSkeleton(accent: accent)
                } else if isUser {
                    Text(message.content)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                    if !message.attachments.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(message.attachments) { attachment in
                                Label(attachment.name, systemImage: attachment.kind.icon)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.07), in: Capsule())
                            }
                        }
                    }
                } else {
                    FormattedAIResponseView(text: message.content, isStreaming: message.isStreaming, accent: accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: 560, alignment: .leading)
            .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isUser ? accent.opacity(0.22) : Color.primary.opacity(0.08), lineWidth: 1)
            )

            if !isUser {
                Spacer(minLength: 54)
            }
        }
    }

    private var avatar: some View {
        Image(systemName: "brain.head.profile")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 28, height: 28)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07), in: Circle())
    }

    private var bubbleBackground: Color {
        if isUser {
            return Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07)
        }
        return colorScheme == .dark ? Color.white.opacity(0.045) : Color.black.opacity(0.025)
    }
}

private struct AIAttachmentChip: View {
    @Environment(\.colorScheme) private var colorScheme
    var attachment: AIAttachment
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: attachment.kind.icon)
                .font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(attachmentSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button {
                remove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 220)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.065 : 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        )
        .help(attachment.textPreview.isEmpty ? attachment.name : attachment.textPreview)
    }

    private var attachmentSubtitle: String {
        let count = attachment.extractedText.count
        if count == 0 {
            return "\(attachment.kind.title) / no text"
        }
        return "\(attachment.kind.title) / \(count) chars"
    }
}

private struct FormattedAIResponseView: View {
    var text: String
    var isStreaming: Bool
    var accent: Color

    private var blocks: [AIResponseBlock] {
        AIResponseBlock.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }

            if isStreaming {
                StreamingCursor(accent: accent)
                    .padding(.top, 2)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: AIResponseBlock) -> some View {
        switch block.kind {
        case .heading:
            inlineText(block.text)
                .font(.system(size: block.level == 1 ? 18 : 15, weight: .bold, design: .serif))
                .padding(.top, block.level == 1 ? 2 : 0)
        case .paragraph:
            inlineText(block.text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(accent.opacity(0.72))
                    .frame(width: 5, height: 5)
                inlineText(block.text)
                    .font(.system(size: 14))
                    .lineSpacing(3)
            }
        case .numbered:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(block.marker)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(minWidth: 18, alignment: .trailing)
                inlineText(block.text)
                    .font(.system(size: 14))
                    .lineSpacing(3)
            }
        case .quote:
            inlineText(block.text)
                .font(.system(size: 14, design: .serif))
                .italic()
                .lineSpacing(3)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(accent.opacity(0.42))
                        .frame(width: 3)
                }
        case .code:
            ScrollView(.horizontal) {
                Text(block.text)
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(3)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func inlineText(_ raw: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(raw)
    }
}

private struct AIResponseBlock: Equatable {
    enum Kind: Equatable {
        case heading
        case paragraph
        case bullet
        case numbered
        case quote
        case code
    }

    var kind: Kind
    var text: String
    var marker: String = ""
    var level: Int = 2

    static func parse(_ value: String) -> [AIResponseBlock] {
        var blocks: [AIResponseBlock] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(AIResponseBlock(kind: .paragraph, text: paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        for rawLine in value.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(AIResponseBlock(kind: .code, text: codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCode = false
                } else {
                    flushParagraph()
                    inCode = true
                }
                continue
            }

            if inCode {
                codeLines.append(rawLine)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = heading(from: trimmed) {
                flushParagraph()
                blocks.append(heading)
                continue
            }

            if let bullet = bullet(from: trimmed) {
                flushParagraph()
                blocks.append(bullet)
                continue
            }

            if let numbered = numbered(from: trimmed) {
                flushParagraph()
                blocks.append(numbered)
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                let text = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(AIResponseBlock(kind: .quote, text: text))
                continue
            }

            paragraph.append(trimmed)
        }

        if inCode {
            blocks.append(AIResponseBlock(kind: .code, text: codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks.isEmpty ? [AIResponseBlock(kind: .paragraph, text: value)] : blocks
    }

    private static func heading(from line: String) -> AIResponseBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...4).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        let text = String(line.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
        return AIResponseBlock(kind: .heading, text: text, level: hashes)
    }

    private static func bullet(from line: String) -> AIResponseBlock? {
        for prefix in ["- ", "* ", "• "] {
            guard line.hasPrefix(prefix) else { continue }
            return AIResponseBlock(kind: .bullet, text: String(line.dropFirst(prefix.count)))
        }
        return nil
    }

    private static func numbered(from line: String) -> AIResponseBlock? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let marker = line[..<dot]
        guard let number = Int(String(marker)), number > 0 else { return nil }
        let afterDot = line.index(after: dot)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        let text = String(line[line.index(after: afterDot)...])
        return AIResponseBlock(kind: .numbered, text: text, marker: "\(number).")
    }
}

private struct AIThinkingPulseView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false
    var accent: Color

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(accent.opacity(0.68))
                        .frame(width: 5, height: phase ? CGFloat(8 + index * 3) : CGFloat(14 - index * 2))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.55).repeatForever(autoreverses: true).delay(Double(index) * 0.08), value: phase)
                }
            }
            Text("Thinking")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.primary.opacity(0.055), in: Capsule())
        .onAppear {
            guard !reduceMotion else { return }
            phase = true
        }
    }
}

private struct AIThinkingSkeleton: View {
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AIThinkingPulseView(accent: accent)
                Spacer()
            }
            ForEach([0.82, 0.64, 0.46], id: \.self) { width in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.09))
                    .frame(width: 260 * width, height: 8)
                    .shimmer()
            }
        }
        .padding(.vertical, 2)
    }
}

private struct StreamingCursor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true
    var accent: Color

    var body: some View {
        Capsule()
            .fill(accent)
            .frame(width: 7, height: 16)
            .opacity(visible ? 1 : 0.25)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

private struct AIQuickActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    var accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(configuration.isPressed ? accent.opacity(0.12) : Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(configuration.isPressed ? accent.opacity(0.28) : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(NavReadTheme.animationSnappy, value: configuration.isPressed)
    }
}

private struct AISendButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    var accent: Color
    var working: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(colorScheme == .dark ? .black : .white)
            .background(
                Circle()
                    .fill(isEnabled || working ? accent : Color.secondary.opacity(0.35))
                    .shadow(color: Color.primary.opacity(isEnabled && !configuration.isPressed ? 0.16 : 0), radius: 12, y: 5)
            )
            .overlay(
                Circle()
                    .strokeBorder((colorScheme == .dark ? Color.black : Color.white).opacity(0.24), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(isEnabled || working ? 1 : 0.48)
            .animation(NavReadTheme.animationSnappy, value: configuration.isPressed)
            .animation(NavReadTheme.animationSnappy, value: working)
    }
}

private struct AIPromptTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = SubmitTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 72)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmitTextView else { return }
        textView.onSubmit = onSubmit
        textView.isEditable = isEditable
        textView.textColor = isEditable ? .labelColor : .secondaryLabelColor
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }

    final class SubmitTextView: NSTextView {
        var onSubmit: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            if isReturn, !event.modifierFlags.contains(.shift) {
                onSubmit?()
                return
            }
            super.keyDown(with: event)
        }
    }
}

private extension NSItemProvider {
    @MainActor
    func loadItemString(for typeIdentifier: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let item else {
                    continuation.resume(throwing: AIError.message("Dropped item could not be read."))
                    return
                }
                if let url = item as? URL {
                    continuation.resume(returning: url.absoluteString)
                    return
                }
                if let url = item as? NSURL {
                    continuation.resume(returning: (url as URL).absoluteString)
                    return
                }
                if let string = item as? String {
                    continuation.resume(returning: string)
                    return
                }
                if let data = item as? Data,
                   let string = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: string)
                    return
                }
                continuation.resume(throwing: AIError.message("Dropped item type is not supported."))
            }
        }
    }
}
