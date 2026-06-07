import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var store: NavReadStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BookInspector()
                if store.selectedBook != nil {
                    ChapterEditor()
                }
                if let quote = store.selectedQuote {
                    QuoteEditor(quote: quote)
                }
                if !store.captures.isEmpty {
                    CaptureHistory()
                }
            }
            .padding(.leading, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Auth Status Card

struct AuthStatusCard: View {
    @EnvironmentObject private var store: NavReadStore
    @State private var callback = ""

    var body: some View {
        GlassPanel(cornerRadius: NavReadTheme.cornerRadiusLarge, padding: 16, intensity: .thin) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: store.authState.authenticated ? "checkmark.seal.fill" : "brain.head.profile")
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                        Text("Codex")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Spacer()
                    Text(store.authState.authenticated ? "Connected" : "Optional")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(store.authState.authenticated ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            (store.authState.authenticated ? Color.primary : Color.secondary).opacity(0.1),
                            in: Capsule()
                        )
                }
                Text(store.authState.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button(store.authState.authenticated ? "Sign Out" : "Sign In") {
                        Task {
                            if store.authState.authenticated {
                                store.signOutCodex()
                            } else {
                                await store.startCodexLogin()
                            }
                        }
                    }
                    .buttonStyle(LiquidButtonStyle())
                    TextField("Callback URL", text: $callback)
                        .textFieldStyle(NavReadTextFieldStyle())
                        .onSubmit {
                            Task { await store.completeCodexCallback(callback) }
                        }
                }
            }
        }
        .task {
            await store.refreshCodexAuthStatus(validate: true)
        }
    }
}

// MARK: - Book Inspector

struct BookInspector: View {
    @EnvironmentObject private var store: NavReadStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GlassPanel(cornerRadius: NavReadTheme.cornerRadiusLarge, padding: 20, intensity: .regular) {
            VStack(alignment: .leading, spacing: 14) {
                if let book = store.selectedBook {
                    Text(book.title)
                        .font(.system(size: 22, weight: .bold, design: .serif))

                    // Stats row
                    HStack(spacing: 16) {
                        StatBadge(value: "\(store.chapters.count)", label: "chapters")
                        StatBadge(value: "\(store.quotes.count)", label: "quotes")
                        StatBadge(value: "\(store.captures.count)", label: "captures")
                    }

                    if store.chapters.contains(where: { $0.aiGenerated }) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 10))
                            Text("AI chapters are scaffolds. Replace them with the real table of contents.")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if !store.statusMessage.isEmpty {
                        Text(store.statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "book.closed")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                            Text("Book Desk")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        Text("Select or add a book to begin.")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13))
                    }
                }
            }
        }
    }
}

struct StatBadge: View {
    var value: String
    var label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - Chapter Editor

struct ChapterEditor: View {
    @EnvironmentObject private var store: NavReadStore
    @State private var title = ""
    @State private var summary = ""
    @State private var pageStart = ""
    @State private var pageEnd = ""

    private var selectedChapter: Chapter? {
        store.selectedChapter
    }

    var body: some View {
        GlassPanel(cornerRadius: NavReadTheme.cornerRadiusLarge, padding: 18, intensity: .thin) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: "Chapter", icon: "list.number")
                    Spacer()
                    Button {
                        withAnimation(NavReadTheme.animationSnappy) {
                            store.addChapter()
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Add Chapter")
                }

                Picker("Chapter", selection: Binding<UUID?>(
                    get: { store.selectedChapterID },
                    set: { id in
                        guard let id, let chapter = store.chapters.first(where: { $0.id == id }) else { return }
                        withAnimation(NavReadTheme.animationSnappy) {
                            store.selectChapter(chapter)
                        }
                    }
                )) {
                    ForEach(store.chapters) { chapter in
                        Text(chapter.title).tag(Optional(chapter.id))
                    }
                }

                TextField("Title", text: $title)
                    .textFieldStyle(NavReadTextFieldStyle())
                TextField("Summary", text: $summary, axis: .vertical)
                    .textFieldStyle(NavReadTextFieldStyle())
                    .lineLimit(2...5)
                HStack(spacing: 8) {
                    TextField("Start page", text: $pageStart)
                        .textFieldStyle(NavReadTextFieldStyle())
                    TextField("End page", text: $pageEnd)
                        .textFieldStyle(NavReadTextFieldStyle())
                }

                HStack(spacing: 8) {
                    Button {
                        guard let selectedChapter else { return }
                        store.updateChapter(
                            selectedChapter,
                            title: title,
                            summary: summary,
                            pageStart: intValue(pageStart),
                            pageEnd: intValue(pageEnd)
                        )
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .buttonStyle(LiquidButtonStyle())
                    .disabled(selectedChapter == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()

                    Button(role: .destructive) {
                        withAnimation(NavReadTheme.animationSnappy) {
                            store.deleteSelectedChapter()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.62))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.chapters.count < 2)
                    .help("Delete Chapter")
                }
            }
        }
        .onAppear(perform: sync)
        .onChange(of: store.selectedChapterID) { _, _ in sync() }
        .onChange(of: store.chapters) { _, _ in sync() }
    }

    private func sync() {
        guard let chapter = selectedChapter else {
            title = ""
            summary = ""
            pageStart = ""
            pageEnd = ""
            return
        }
        title = chapter.title
        summary = chapter.summary
        pageStart = chapter.pageStart.map(String.init) ?? ""
        pageEnd = chapter.pageEnd.map(String.init) ?? ""
    }

    private func intValue(_ value: String) -> Int? {
        Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Quote Editor

struct QuoteEditor: View {
    @EnvironmentObject private var store: NavReadStore
    @Environment(\.colorScheme) private var colorScheme
    var quote: Quote
    @State private var cleanedText = ""
    @State private var pageLocator = ""
    @State private var note = ""
    @State private var tags = ""

    var body: some View {
        GlassPanel(cornerRadius: NavReadTheme.cornerRadiusLarge, padding: 18, intensity: .thin) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: "Quote", icon: "text.quote")
                    Spacer()
                    Button(role: .destructive) {
                        withAnimation(NavReadTheme.animationSnappy) {
                            store.deleteSelectedQuote()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.62))
                    }
                    .buttonStyle(.plain)
                    .help("Delete Quote")
                }

                TextEditor(text: $cleanedText)
                    .font(.system(size: 15, design: .serif))
                    .lineSpacing(3)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: NavReadTheme.cornerRadiusSmall, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: NavReadTheme.cornerRadiusSmall, style: .continuous)
                            .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                    )

                TextField("Page / location", text: $pageLocator)
                    .textFieldStyle(NavReadTextFieldStyle())
                TextField("Tags, comma-separated", text: $tags)
                    .textFieldStyle(NavReadTextFieldStyle())
                TextField("Note", text: $note, axis: .vertical)
                    .textFieldStyle(NavReadTextFieldStyle())
                    .lineLimit(2...5)

                Button {
                    store.updateQuote(
                        quote,
                        cleanedText: cleanedText,
                        pageLocator: pageLocator,
                        note: note,
                        tags: tags.components(separatedBy: ",")
                    )
                } label: {
                    Label("Save Quote", systemImage: "checkmark.circle")
                }
                .buttonStyle(LiquidButtonStyle())

                QuoteCardPreview(quote: quote, book: store.selectedBook)
            }
        }
        .onAppear(perform: sync)
        .onChange(of: quote.id) { _, _ in sync() }
    }

    private func sync() {
        cleanedText = quote.text
        pageLocator = quote.pageLocator
        note = quote.note
        tags = quote.tags.joined(separator: ", ")
    }
}

// MARK: - Quote Card Preview

struct QuoteCardPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    var quote: Quote
    var book: Book?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 10))
                Text("Card Preview")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 14) {
                Text("\u{201C}\(quote.text)\u{201D}")
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .lineSpacing(4)
                    .lineLimit(5)
                    .foregroundStyle(cardInk)
                Spacer(minLength: 0)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book?.title ?? "NavRead")
                            .font(.system(size: 11, weight: .bold))
                        Text(book?.displayAuthor ?? "")
                            .font(.system(size: 10))
                            .opacity(0.7)
                    }
                    Spacer()
                    if !quote.pageLocator.isEmpty {
                        Text(quote.pageLocator)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(cardInk.opacity(0.15), in: Capsule())
                    }
                }
                .foregroundStyle(cardInk.opacity(0.85))
            }
            .padding(20)
            .frame(height: 200)
            .background(
                RoundedRectangle(cornerRadius: NavReadTheme.cornerRadiusMedium, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                cardPaper,
                                cardPaper.opacity(0.82)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: NavReadTheme.cornerRadiusMedium, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [cardInk.opacity(0.25), cardInk.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.primary.opacity(0.16), radius: 16, y: 8)
        }
    }

    private var cardPaper: Color {
        colorScheme == .dark ? .white : .black
    }

    private var cardInk: Color {
        colorScheme == .dark ? .black : .white
    }
}

// MARK: - Capture History

struct CaptureHistory: View {
    @EnvironmentObject private var store: NavReadStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GlassPanel(cornerRadius: NavReadTheme.cornerRadiusLarge, padding: 16, intensity: .thin) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Source Captures", subtitle: "\(store.captures.count) total", icon: "tray.full")

                if store.captures.isEmpty {
                    Text("No source captures yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(store.captures.prefix(5)) { capture in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: captureIcon(capture.type))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(capture.type.rawValue)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(capture.rawText)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .lineSpacing(1)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                        )
                    }
                }
            }
        }
    }

    private func captureIcon(_ type: CaptureType) -> String {
        switch type {
        case .manualText: return "text.cursor"
        case .screenshot: return "camera.viewfinder"
        case .imageFile: return "photo"
        case .pdfPage: return "doc.richtext"
        case .webURL: return "globe"
        }
    }
}
