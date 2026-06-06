import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: NavReadStore
    @Environment(\.colorScheme) private var colorScheme
    var namespace: Namespace.ID
    var openBook: (Book) -> Void = { _ in }
    @State private var editingBook: Book?
    @State private var pendingDelete: Book?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            NavReadLogoMark(size: 21)
                            Text("NavRead")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                        }
                        Text("\(store.books.count) books \u{00B7} \(store.totalQuoteCount) quotes")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()
                .padding(.horizontal, 16)
                .opacity(0.5)

            ScrollView {
                if store.filteredBooks.isEmpty {
                    Text(store.books.isEmpty ? "No books yet." : "No matches.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(store.filteredBooks) { book in
                            Button {
                                openBook(book)
                            } label: {
                                CoverShelfRow(book: book, selected: store.selectedBookID == book.id, namespace: namespace)
                            }
                            .buttonStyle(.plain)
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .help("Open \(book.displayTitle)")
                            .contextMenu {
                                Button {
                                    openBook(book)
                                    editingBook = book
                                } label: {
                                    Label("Book Options", systemImage: "slider.horizontal.3")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    pendingDelete = book
                                } label: {
                                    Label("Delete Book", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                }
            }
            .scrollIndicators(.hidden)

            // AI Activity
            if store.isWorking {
                Divider()
                    .padding(.horizontal, 16)
                    .opacity(0.5)
                HStack {
                    InkScanView()
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(
            ZStack {
                if colorScheme == .dark {
                    Color(nsColor: .controlBackgroundColor).opacity(0.5)
                } else {
                    Color(nsColor: .windowBackgroundColor).opacity(0.72)
                }
                VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
            }
        )
        .sheet(item: $editingBook) { book in
            BookOptionsSheet(book: book)
                .environmentObject(store)
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.displayTitle ?? "this book")?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Delete Book", role: .destructive) {
                if let book = pendingDelete {
                    store.deleteBook(book)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("This removes the book, chapters, quotes, cover image, and imported capture files from NavRead.")
        }
    }
}

// MARK: - Visual Effect (NSVisualEffectView bridge)

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Cover Shelf Row

struct CoverShelfRow: View {
    @Environment(\.colorScheme) private var colorScheme
    var book: Book
    var selected: Bool
    var namespace: Namespace.ID
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            CoverView(book: book)
                .frame(width: 34, height: 50)
                .shadow(color: Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.08), radius: 5, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(book.displayTitle)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text(book.nickname.isEmpty ? book.displayAuthor : "\(book.title) · \(book.displayAuthor)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    selected
                        ? AnyShapeStyle(Color.primary.opacity(colorScheme == .dark ? 0.11 : 0.07))
                        : (hovering ? AnyShapeStyle(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.03)) : AnyShapeStyle(.clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            selected ? Color.primary.opacity(colorScheme == .dark ? 0.28 : 0.16) : .clear,
                            lineWidth: selected ? 1 : 0
                        )
                )
        )
        .animation(NavReadTheme.animationSnappy, value: selected)
        .animation(NavReadTheme.animationSnappy, value: hovering)
        .onHover { hovering = $0 }
    }
}

struct BookOptionsSheet: View {
    @EnvironmentObject private var store: NavReadStore
    @Environment(\.dismiss) private var dismiss
    var book: Book
    @State private var title: String
    @State private var nickname: String
    @State private var author: String
    @State private var summary: String
    @State private var confirmingDelete = false

    init(book: Book) {
        self.book = book
        _title = State(initialValue: book.title)
        _nickname = State(initialValue: book.nickname)
        _author = State(initialValue: book.author)
        _summary = State(initialValue: book.summary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Book Options")
                        .font(.title2.weight(.semibold))
                    Text("Rename, add a nickname, or manage this book.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CoverView(book: book)
                    .frame(width: 42, height: 62)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $title)
                    .textFieldStyle(NavReadTextFieldStyle())
                TextField("Nickname", text: $nickname)
                    .textFieldStyle(NavReadTextFieldStyle())
                TextField("Author", text: $author)
                    .textFieldStyle(NavReadTextFieldStyle())
                TextField("Summary", text: $summary, axis: .vertical)
                    .textFieldStyle(NavReadTextFieldStyle())
                    .lineLimit(3...6)
            }

            HStack {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    store.updateBook(book, title: title, nickname: nickname, author: author, summary: summary)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .confirmationDialog("Delete \(book.displayTitle)?", isPresented: $confirmingDelete) {
            Button("Delete Book", role: .destructive) {
                store.deleteBook(book)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the book, chapters, quotes, cover image, and imported capture files from NavRead.")
        }
    }
}

// MARK: - Cover View

struct CoverView: View {
    @Environment(\.colorScheme) private var colorScheme
    var book: Book

    var body: some View {
        ZStack {
            if let path = book.coverAssetPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // Generated cover design
                ZStack {
                    LinearGradient(
                        colors: [
                            colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.92),
                            colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.78)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Subtle pattern overlay
                    GeometryReader { geo in
                        Path { path in
                            let w = geo.size.width
                            let h = geo.size.height
                            for i in stride(from: 0, to: h, by: 12) {
                                path.move(to: CGPoint(x: 0, y: i))
                                path.addLine(to: CGPoint(x: w, y: i + 6))
                            }
                        }
                        .stroke(inverseInk.opacity(0.08), lineWidth: 0.5)
                    }

                    VStack(spacing: 6) {
                        Spacer()
                        Text(String(book.title.prefix(1)))
                            .font(.system(size: 28, weight: .black, design: .serif))
                            .foregroundStyle(inverseInk.opacity(0.9))
                        Rectangle()
                            .fill(inverseInk.opacity(0.42))
                            .frame(width: 24, height: 1)
                        Text(book.title)
                            .font(.system(size: 8, weight: .bold))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 5)
                            .foregroundStyle(inverseInk.opacity(0.82))
                        Spacer()
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.primary.opacity(0.18), Color.primary.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        // Book spine shadow effect
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.black.opacity(0.2), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 3)
        }
    }

    private var inverseInk: Color {
        colorScheme == .dark ? .black : .white
    }
}
