import SwiftUI

struct BookWorkspaceView: View {
    @EnvironmentObject private var store: NavReadStore
    var namespace: Namespace.ID

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Color.clear
                        .frame(height: 0)
                        .id(BookWorkspaceScrollTarget.top)

                    if !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SearchResultsView()
                    } else if let book = store.selectedBook {
                        MinimalBookHeader(book: book, namespace: namespace)
                        ReadingWorkspace()
                    } else {
                        OnboardingView()
                    }
                }
                .frame(maxWidth: 1080, alignment: .leading)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .onChange(of: store.selectedBookID) { _, _ in
                withAnimation(NavReadTheme.animationSnappy) {
                    proxy.scrollTo(BookWorkspaceScrollTarget.top, anchor: .top)
                }
            }
        }
    }
}

private enum BookWorkspaceScrollTarget {
    case top
}

// MARK: - Search Results

struct SearchResultsView: View {
    @EnvironmentObject private var store: NavReadStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Search")
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                    Text("\(store.filteredBooks.count) books · \(store.searchQuoteMatches.count) book quotes · \(store.searchSavedQuoteMatches.count) standalone quotes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear") {
                    withAnimation(NavReadTheme.animationSnappy) {
                        store.searchText = ""
                    }
                }
                .buttonStyle(GhostButtonStyle())
            }

            if store.filteredBooks.isEmpty && store.searchQuoteMatches.isEmpty && store.searchSavedQuoteMatches.isEmpty {
                MinimalPanel {
                    ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text("Try another title, author, tag, note, learning, or quote."))
                        .frame(maxWidth: .infinity, minHeight: 180)
                }
            }

            if !store.filteredBooks.isEmpty {
                Text("Books")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                    ForEach(store.filteredBooks) { book in
                        Button {
                            withAnimation(NavReadTheme.animationSnappy) {
                                store.selectBook(book)
                                store.searchText = ""
                            }
                        } label: {
                            HStack(spacing: 12) {
                                CoverView(book: book)
                                    .frame(width: 40, height: 58)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(book.displayTitle)
                                        .font(.system(size: 14, weight: .semibold))
                                        .lineLimit(2)
                                    Text(book.displayAuthor)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !store.searchQuoteMatches.isEmpty {
                Text("Book Quotes")
                    .font(.headline)
                VStack(spacing: 10) {
                    ForEach(store.searchQuoteMatches) { quote in
                        QuoteRow(quote: quote)
                    }
                }
            }

            if !store.searchSavedQuoteMatches.isEmpty {
                HStack {
                    Text("Standalone Quotes")
                        .font(.headline)
                    Spacer()
                    Button("Open Quotes") {
                        NotificationCenter.default.post(name: .navReadOpenQuoteVault, object: nil)
                    }
                    .buttonStyle(GhostButtonStyle())
                }
                VStack(spacing: 10) {
                    ForEach(store.searchSavedQuoteMatches) { quote in
                        SavedQuoteSearchRow(quote: quote)
                    }
                }
            }
        }
    }
}

// MARK: - Book Header

struct MinimalBookHeader: View {
    var book: Book
    var namespace: Namespace.ID

    var body: some View {
        MinimalPanel {
            HStack(alignment: .center, spacing: 18) {
                CoverView(book: book)
                    .frame(width: 86, height: 128)
                    .shadow(color: Color.primary.opacity(0.12), radius: 14, y: 8)

                VStack(alignment: .leading, spacing: 10) {
                    Text(book.displayTitle)
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .lineLimit(3)
                        .minimumScaleFactor(0.65)

                    Text(book.displayAuthor)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                    if !book.nickname.isEmpty {
                        Text(book.title)
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }

                    if !book.summary.isEmpty {
                        Text(book.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                Spacer(minLength: 16)
                BookMetricStack()
                    .frame(width: 150)
            }
        }
    }
}

struct BookMetricStack: View {
    @EnvironmentObject private var store: NavReadStore

    var body: some View {
        VStack(spacing: 8) {
            BookMetric(value: "\(store.chapters.count)", label: "chapters")
            BookMetric(value: "\(store.quotes.count)", label: "quotes")
            BookMetric(value: "\(store.captures.count)", label: "captures")
        }
    }
}

struct BookMetric: View {
    var value: String
    var label: String

    var body: some View {
        HStack {
            Text(value)
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Workspace

struct ReadingWorkspace: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    ChapterListPanel()
                    BookLearningsPanel()
                }
                .frame(width: 280)

                VStack(alignment: .leading, spacing: 16) {
                    QuotePanel()
                    ChapterLearningsPanel()
                }
                .frame(minWidth: 460)
            }

            VStack(alignment: .leading, spacing: 16) {
                ChapterListPanel()
                BookLearningsPanel()
                QuotePanel()
                ChapterLearningsPanel()
            }
        }
    }
}

struct ChapterListPanel: View {
    @EnvironmentObject private var store: NavReadStore
    @State private var editingChapter = false

    var body: some View {
        MinimalPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Chapters")
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation(NavReadTheme.animationSnappy) {
                            store.addChapter()
                            editingChapter = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Add chapter")
                }

                if store.chapters.isEmpty {
                    Text("Add chapters for this book, then save quotes inside the chapter they belong to.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(store.chapters) { chapter in
                                ChapterListRow(chapter: chapter, selected: store.selectedChapterID == chapter.id)
                            }
                        }
                        .padding(.trailing, 4)
                    }
                    .frame(maxHeight: 245)
                    .scrollIndicators(.visible)
                }

                Divider()
                    .opacity(0.45)

                Button {
                    editingChapter = true
                } label: {
                    Label("Edit Selected Chapter", systemImage: "pencil")
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(store.selectedChapter == nil)
            }
        }
        .sheet(isPresented: $editingChapter) {
            if let chapter = store.selectedChapter {
                ChapterEditSheet(chapter: chapter)
                    .environmentObject(store)
            }
        }
    }
}

struct ChapterLearningsPanel: View {
    @EnvironmentObject private var store: NavReadStore
    @State private var draft = ""
    @State private var activeChapterID: UUID?

    private var isDirty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines) != (store.selectedChapter?.learnings ?? "")
    }

    var body: some View {
        MinimalPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Chapter Learnings")
                            .font(.headline)
                        Text("Notes for the selected chapter. AI sees these separately.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Save") {
                        if let chapter = store.selectedChapter {
                            store.updateChapterLearnings(chapter, learnings: draft)
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(store.selectedChapter == nil || !isDirty)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .frame(height: 78)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Write the insight, pattern, or reminder from this chapter.")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .onAppear(perform: syncDraft)
        .onChange(of: store.selectedChapter?.id) { _, _ in
            syncDraft()
        }
    }

    private func syncDraft() {
        guard activeChapterID != store.selectedChapter?.id else { return }
        activeChapterID = store.selectedChapter?.id
        draft = store.selectedChapter?.learnings ?? ""
    }
}

struct BookLearningsPanel: View {
    @EnvironmentObject private var store: NavReadStore
    @State private var draft = ""
    @State private var activeBookID: UUID?

    private var isDirty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines) != (store.selectedBook?.learnings ?? "")
    }

    var body: some View {
        MinimalPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Book Learnings")
                            .font(.headline)
                        Text("Whole-book takeaways. Kept separate from chapter notes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Save") {
                        if let book = store.selectedBook {
                            store.updateBookLearnings(book, learnings: draft)
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(store.selectedBook == nil || !isDirty)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .frame(height: 128)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Type the principles, ideas, warnings, frameworks, or recurring patterns from the book.")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .onAppear(perform: syncDraft)
        .onChange(of: store.selectedBook?.id) { _, _ in
            syncDraft()
        }
    }

    private func syncDraft() {
        guard activeBookID != store.selectedBook?.id else { return }
        activeBookID = store.selectedBook?.id
        draft = store.selectedBook?.learnings ?? ""
    }
}

struct ChapterListRow: View {
    @EnvironmentObject private var store: NavReadStore
    var chapter: Chapter
    var selected: Bool

    var body: some View {
        Button {
            withAnimation(NavReadTheme.animationSnappy) {
                store.selectChapter(chapter)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%02d", chapter.orderIndex + 1))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(selected ? .primary : .tertiary)
                    .frame(width: 24, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .lineLimit(2)
                    if !chapter.summary.isEmpty {
                        Text(chapter.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(selected ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct QuotePanel: View {
    @EnvironmentObject private var store: NavReadStore
    @State private var showingComposer = false

    private var chapterQuotes: [Quote] {
        guard let chapterID = store.selectedChapterID else { return store.quotes }
        return store.quotes.filter { $0.chapterID == chapterID }
    }

    private var title: String {
        store.selectedChapter?.title ?? "Quotes"
    }

    var body: some View {
        MinimalPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(2)
                        Text("\(chapterQuotes.count) quotes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !showingComposer {
                        Button {
                            showingComposer = true
                        } label: {
                            Label("Add Quote", systemImage: "plus")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(store.selectedBook == nil)
                    }
                }

                if showingComposer {
                    QuoteComposer {
                        withAnimation(NavReadTheme.animationSnappy) {
                            showingComposer = false
                        }
                    }
                } else if chapterQuotes.isEmpty {
                    EmptyQuoteState()
                } else {
                    VStack(spacing: 10) {
                        ForEach(chapterQuotes) { quote in
                            QuoteRow(quote: quote)
                        }
                    }
                }
            }
        }
    }
}

struct EmptyQuoteState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No quotes in this chapter yet.")
                .font(.system(size: 14, weight: .semibold))
            Text("Use Add Quote for manual entry, or Capture for OCR, PDFs, images, and web import.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct QuoteComposer: View {
    @EnvironmentObject private var store: NavReadStore
    @State private var quoteText = ""
    @State private var page = ""
    @State private var tags = ""
    @State private var note = ""
    var onCancel: () -> Void

    private var canSave: Bool {
        !quoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $quoteText)
                    .font(.system(size: 15, design: .serif))
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                if quoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Paste or type a quote")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            )

            HStack(spacing: 10) {
                TextField("Page or location", text: $page)
                    .textFieldStyle(NavReadTextFieldStyle())
                TextField("Tags", text: $tags)
                    .textFieldStyle(NavReadTextFieldStyle())
            }

            TextField("Note", text: $note)
                .textFieldStyle(NavReadTextFieldStyle())

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(GhostButtonStyle())
                Spacer()
                Button {
                    store.addManualQuote(
                        rawText: quoteText,
                        cleanedText: quoteText,
                        pageLocator: page,
                        note: note,
                        tags: tags.components(separatedBy: ",")
                    )
                    quoteText = ""
                    page = ""
                    tags = ""
                    note = ""
                    onCancel()
                } label: {
                    Label("Save Quote", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSave)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct QuoteRow: View {
    @EnvironmentObject private var store: NavReadStore
    @State private var editing = false
    var quote: Quote

    var body: some View {
        Button {
            store.selectQuote(quote)
            editing = true
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                Text("\"\(quote.text)\"")
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .lineSpacing(4)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if !quote.pageLocator.isEmpty {
                        Text(quote.pageLocator)
                    }
                    Text(quote.sourceType.rawValue)
                    Spacer()
                    ForEach(quote.tags.prefix(3), id: \.self) { tag in
                        TagPill(text: tag)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(store.selectedQuoteID == quote.id ? Color.primary.opacity(0.24) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit") {
                store.selectQuote(quote)
                editing = true
            }
            Button(role: .destructive) {
                store.selectQuote(quote)
                store.deleteSelectedQuote()
            } label: {
                Text("Delete")
            }
        }
        .sheet(isPresented: $editing) {
            QuoteEditSheet(quote: quote)
                .environmentObject(store)
        }
    }
}

struct SavedQuoteSearchRow: View {
    @EnvironmentObject private var store: NavReadStore
    var quote: SavedQuote

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("\"\(quote.text)\"")
                .font(.system(size: 17, weight: .medium, design: .serif))
                .lineSpacing(4)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Text(quote.attribution)
                Spacer()
                ForEach(quote.tags.prefix(3), id: \.self) { tag in
                    TagPill(text: tag)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .contextMenu {
            Button {
                store.copySavedQuoteCard(quote)
            } label: {
                Label("Copy Card", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                store.deleteSavedQuote(quote)
            } label: {
                Text("Delete")
            }
        }
    }
}

// MARK: - Editors

struct ChapterEditSheet: View {
    @EnvironmentObject private var store: NavReadStore
    @Environment(\.dismiss) private var dismiss
    var chapter: Chapter
    @State private var title: String
    @State private var summary: String
    @State private var pageStart: String
    @State private var pageEnd: String

    init(chapter: Chapter) {
        self.chapter = chapter
        _title = State(initialValue: chapter.title)
        _summary = State(initialValue: chapter.summary)
        _pageStart = State(initialValue: chapter.pageStart.map(String.init) ?? "")
        _pageEnd = State(initialValue: chapter.pageEnd.map(String.init) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Chapter")
                .font(.title2.weight(.semibold))

            TextField("Title", text: $title)
                .textFieldStyle(NavReadTextFieldStyle())
            TextField("Summary", text: $summary, axis: .vertical)
                .textFieldStyle(NavReadTextFieldStyle())
                .lineLimit(3...6)
            HStack(spacing: 10) {
                TextField("Start page", text: $pageStart)
                    .textFieldStyle(NavReadTextFieldStyle())
                TextField("End page", text: $pageEnd)
                    .textFieldStyle(NavReadTextFieldStyle())
            }

            HStack {
                Button(role: .destructive) {
                    store.deleteSelectedChapter()
                    dismiss()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(store.chapters.count < 2)

                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    store.updateChapter(
                        chapter,
                        title: title,
                        summary: summary,
                        pageStart: Int(pageStart.trimmingCharacters(in: .whitespacesAndNewlines)),
                        pageEnd: Int(pageEnd.trimmingCharacters(in: .whitespacesAndNewlines))
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

struct QuoteEditSheet: View {
    @EnvironmentObject private var store: NavReadStore
    @Environment(\.dismiss) private var dismiss
    var quote: Quote
    @State private var text: String
    @State private var page: String
    @State private var tags: String
    @State private var note: String

    init(quote: Quote) {
        self.quote = quote
        _text = State(initialValue: quote.text)
        _page = State(initialValue: quote.pageLocator)
        _tags = State(initialValue: quote.tags.joined(separator: ", "))
        _note = State(initialValue: quote.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Quote")
                .font(.title2.weight(.semibold))

            TextEditor(text: $text)
                .font(.system(size: 15, design: .serif))
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                )
            TextField("Page or location", text: $page)
                .textFieldStyle(NavReadTextFieldStyle())
            TextField("Tags", text: $tags)
                .textFieldStyle(NavReadTextFieldStyle())
            TextField("Note", text: $note, axis: .vertical)
                .textFieldStyle(NavReadTextFieldStyle())
                .lineLimit(2...5)

            HStack {
                Button(role: .destructive) {
                    store.deleteSelectedQuote()
                    dismiss()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    store.updateQuote(
                        quote,
                        cleanedText: text,
                        pageLocator: page,
                        note: note,
                        tags: tags.components(separatedBy: ",")
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

// MARK: - Shared Surface

struct MinimalPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

struct EmptyLibraryView: View {
    var body: some View {
        OnboardingView()
    }
}
