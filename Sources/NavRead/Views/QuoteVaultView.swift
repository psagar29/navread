import SwiftUI

struct QuoteVaultView: View {
    @State private var query = ""

    var body: some View {
        QuotesWorkspaceView(query: $query, embedded: false)
    }
}

struct QuotesWorkspaceView: View {
    @EnvironmentObject private var store: NavReadStore
    @Environment(\.dismiss) private var dismiss
    @Binding var query: String
    var embedded = true
    @State private var selectedQuoteID: UUID?
    @State private var draftText = ""
    @State private var draftAuthor = ""
    @State private var draftSource = ""
    @State private var draftNote = ""
    @State private var draftTags = ""
    @State private var isNewDraft = true
    @State private var confirmingDelete = false
    @State private var importMode = false
    @State private var bulkText = ""
    @State private var bulkCandidates: [SavedQuoteCandidate] = []
    @State private var selectedBulkCandidateIDs = Set<UUID>()
    @State private var bulkImporting = false
    @State private var bulkMessage = ""

    private var selectedQuote: SavedQuote? {
        guard let selectedQuoteID else { return nil }
        return store.savedQuotes.first { $0.id == selectedQuoteID }
    }

    private var filteredQuotes: [SavedQuote] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return store.savedQuotes }
        return store.savedQuotes.filter { quote in
            quote.text.lowercased().contains(term)
                || quote.author.lowercased().contains(term)
                || quote.source.lowercased().contains(term)
                || quote.note.lowercased().contains(term)
                || quote.tags.contains { $0.lowercased().contains(term) }
        }
    }

    private var canSave: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        content
            .frame(
                minWidth: embedded ? nil : 760,
                idealWidth: embedded ? nil : 860,
                maxWidth: embedded ? .infinity : nil,
                minHeight: embedded ? nil : 560,
                idealHeight: embedded ? nil : 620,
                maxHeight: embedded ? .infinity : nil,
                alignment: .topLeading
            )
            .background {
                if embedded {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.regularMaterial)
                }
            }
            .overlay {
                if embedded {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: embedded ? 18 : 0, style: .continuous))
            .onAppear(perform: prepareInitialSelection)
            .onChange(of: store.savedQuotes) { _, _ in
                guard let selectedQuoteID, store.savedQuotes.contains(where: { $0.id == selectedQuoteID }) else {
                    prepareInitialSelection()
                    return
                }
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
                .padding(22)

            Divider()
                .opacity(0.45)

            HStack(alignment: .top, spacing: 0) {
                quoteList
                    .frame(width: 260)
                Divider()
                    .opacity(0.45)
                editor
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Quotes")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                Text("\(store.savedQuotes.count) standalone quotes. AI can use these with your book context.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                withAnimation(NavReadTheme.animationSnappy) {
                    importMode.toggle()
                    if importMode {
                        isNewDraft = true
                        selectedQuoteID = nil
                    }
                }
            } label: {
                Label(importMode ? "Single" : "AI Import", systemImage: importMode ? "square.and.pencil" : "sparkles")
            }
            .buttonStyle(GhostButtonStyle())
            Button {
                startNew()
                importMode = false
            } label: {
                Label("New", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            if !embedded {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close")
            }
        }
    }

    private var quoteList: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search quotes", text: $query)
                .textFieldStyle(NavReadTextFieldStyle())

            if filteredQuotes.isEmpty {
                ContentUnavailableView(
                    query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No standalone quotes yet" : "No matches",
                    systemImage: "quote.opening",
                    description: Text("Save quotes you found online, in conversations, screenshots, or anywhere outside a book.")
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredQuotes) { quote in
                            SavedQuoteVaultRow(
                                quote: quote,
                                selected: quote.id == selectedQuoteID
                            ) {
                                select(quote)
                            }
                            .contextMenu {
                                Button {
                                    select(quote)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button {
                                    store.copySavedQuoteCard(quote)
                                } label: {
                                    Label("Copy Card", systemImage: "doc.on.doc")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    store.deleteSavedQuote(quote)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.trailing, 4)
                }
            }
        }
        .padding(22)
    }

    private var editor: some View {
        Group {
            if importMode {
                bulkImportEditor
            } else {
                singleQuoteEditor
            }
        }
    }

    private var singleQuoteEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isNewDraft ? "Add Quote" : "Edit Quote")
                        .font(.headline)
                    Text("Standalone quotes from online reading, conversations, screenshots, or anything worth keeping.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if let selectedQuote, !isNewDraft {
                    shareMenu(for: selectedQuote)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $draftText)
                    .font(.system(size: 16, design: .serif))
                    .lineSpacing(4)
                    .frame(height: 132)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Paste a quote...")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            )

            HStack(spacing: 10) {
                TextField("Author / person", text: $draftAuthor)
                    .textFieldStyle(NavReadTextFieldStyle())
                TextField("Source / link / book", text: $draftSource)
                    .textFieldStyle(NavReadTextFieldStyle())
            }

            TextField("Tags", text: $draftTags)
                .textFieldStyle(NavReadTextFieldStyle())
            TextField("Why this matters", text: $draftNote, axis: .vertical)
                .textFieldStyle(NavReadTextFieldStyle())
                .lineLimit(2...5)

            HStack {
                if !isNewDraft {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

                Spacer()

                Button("New") {
                    startNew()
                }
                .buttonStyle(GhostButtonStyle())

                Button {
                    saveDraft()
                } label: {
                    Label(isNewDraft ? "Save" : "Update", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(22)
        .confirmationDialog("Delete quote?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                if let selectedQuote {
                    store.deleteSavedQuote(selectedQuote)
                    startNew()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the quote and generated cards from NavRead.")
        }
    }

    private var bulkImportEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI Import")
                        .font(.headline)
                    Text("Paste many quotes. Codex extracts text, author, source, tags, and notes; local parsing is used when Codex is offline.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if bulkImporting {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $bulkText)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .frame(height: 150)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                if bulkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Paste quotes here. One per line works. Attribution like \"quote\" - author is supported.")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            )

            HStack {
                Button {
                    parseBulkQuotes()
                } label: {
                    Label("Parse Quotes", systemImage: "sparkles")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(bulkImporting || bulkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if !bulkCandidates.isEmpty {
                    Button(selectedBulkCandidateIDs.count == bulkCandidates.count ? "Deselect All" : "Select All") {
                        if selectedBulkCandidateIDs.count == bulkCandidates.count {
                            selectedBulkCandidateIDs = []
                        } else {
                            selectedBulkCandidateIDs = Set(bulkCandidates.map(\.id))
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                }

                Spacer()

                Button {
                    saveSelectedBulkQuotes()
                } label: {
                    Label("Save Selected", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedBulkCandidateIDs.isEmpty)
            }

            if !bulkMessage.isEmpty {
                Text(bulkMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !bulkCandidates.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(bulkCandidates) { candidate in
                            BulkSavedQuoteCandidateRow(
                                candidate: candidate,
                                selected: selectedBulkCandidateIDs.contains(candidate.id)
                            ) {
                                if selectedBulkCandidateIDs.contains(candidate.id) {
                                    selectedBulkCandidateIDs.remove(candidate.id)
                                } else {
                                    selectedBulkCandidateIDs.insert(candidate.id)
                                }
                            }
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(22)
    }

    private func shareMenu(for quote: SavedQuote) -> some View {
        Menu {
            ForEach(QuoteCardFormat.allCases) { format in
                Menu(format.title) {
                    Button {
                        store.copySavedQuoteCard(quote, format: format)
                    } label: {
                        Label("Copy Card", systemImage: "doc.on.doc")
                    }
                    Button {
                        store.saveSavedQuoteCard(quote, format: format)
                    } label: {
                        Label("Save PNG", systemImage: "arrow.down.doc")
                    }
                    Divider()
                    ForEach(SocialShareDestination.allCases) { destination in
                        Button {
                            store.shareSavedQuoteCard(quote, destination: destination, format: format)
                        } label: {
                            Label(destination.title, systemImage: destination.icon)
                        }
                    }
                }
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    private func prepareInitialSelection() {
        if let quote = store.savedQuotes.first {
            select(quote)
        } else {
            startNew()
        }
    }

    private func startNew() {
        isNewDraft = true
        selectedQuoteID = nil
        draftText = ""
        draftAuthor = ""
        draftSource = ""
        draftNote = ""
        draftTags = ""
    }

    private func parseBulkQuotes() {
        bulkImporting = true
        bulkMessage = ""
        Task {
            let candidates = await store.importSavedQuoteCandidates(bulkText)
            await MainActor.run {
                bulkCandidates = candidates
                selectedBulkCandidateIDs = Set(candidates.map(\.id))
                bulkMessage = candidates.isEmpty ? "No quotes found. Try one quote per line with author after a dash." : "Found \(candidates.count) quotes. Review, deselect anything wrong, then save."
                bulkImporting = false
            }
        }
    }

    private func saveSelectedBulkQuotes() {
        let selected = bulkCandidates.filter { selectedBulkCandidateIDs.contains($0.id) }
        let savedCount = store.saveSavedQuoteCandidates(selected)
        guard savedCount > 0 else {
            bulkMessage = "Nothing saved."
            return
        }
        let savedIDs = Set(selected.map(\.id))
        bulkCandidates.removeAll { savedIDs.contains($0.id) }
        selectedBulkCandidateIDs.subtract(savedIDs)
        bulkText = ""
        bulkMessage = "Saved \(savedCount) quotes."
        if bulkCandidates.isEmpty {
            withAnimation(NavReadTheme.animationSnappy) {
                importMode = false
            }
            prepareInitialSelection()
        }
    }

    private func select(_ quote: SavedQuote) {
        isNewDraft = false
        selectedQuoteID = quote.id
        draftText = quote.text
        draftAuthor = quote.author
        draftSource = quote.source
        draftNote = quote.note
        draftTags = quote.tags.joined(separator: ", ")
    }

    private func saveDraft() {
        if let selectedQuote, !isNewDraft {
            store.updateSavedQuote(
                selectedQuote,
                text: draftText,
                author: draftAuthor,
                source: draftSource,
                note: draftNote,
                tags: draftTags.components(separatedBy: ",")
            )
        } else {
            store.addSavedQuote(
                text: draftText,
                author: draftAuthor,
                source: draftSource,
                note: draftNote,
                tags: draftTags.components(separatedBy: ",")
            )
            if let quote = store.savedQuotes.first {
                select(quote)
            }
        }
    }
}

struct SavedQuoteVaultRow: View {
    var quote: SavedQuote
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Text(quote.text)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular, design: .serif))
                    .lineLimit(3)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(quote.attribution)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !quote.tags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(quote.tags.prefix(3), id: \.self) { tag in
                            TagPill(text: tag)
                        }
                    }
                }
            }
            .padding(11)
            .background(selected ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.primary.opacity(0.18) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct BulkSavedQuoteCandidateRow: View {
    var candidate: SavedQuoteCandidate
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? .primary : .tertiary)
                    .frame(width: 18, alignment: .center)

                VStack(alignment: .leading, spacing: 7) {
                    Text("\"\(candidate.text)\"")
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .lineLimit(3)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        Text(candidate.author.isEmpty ? "Unknown author" : candidate.author)
                        if !candidate.source.isEmpty {
                            Text(candidate.source)
                        }
                        Spacer()
                        ForEach(candidate.tags.prefix(3), id: \.self) { tag in
                            TagPill(text: tag)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if !candidate.note.isEmpty {
                        Text(candidate.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(11)
            .background(selected ? Color.primary.opacity(0.07) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.primary.opacity(0.18) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
