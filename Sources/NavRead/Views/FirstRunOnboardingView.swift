import SwiftUI

struct FirstRunOnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: NavReadStore
    @AppStorage("hasCompletedFirstRunOnboarding") private var hasCompletedFirstRunOnboarding = false
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @State private var step: OnboardingStep = .welcome
    @State private var starterBooks: [StarterBookInput] = [
        StarterBookInput(title: "", author: ""),
        StarterBookInput(title: "", author: ""),
        StarterBookInput(title: "", author: "")
    ]
    @State private var callback = ""
    @State private var isAddingBooks = false
    @State private var addProgress = ""

    private var enteredBooks: [StarterBookInput] {
        starterBooks
            .map { $0.cleaned }
            .filter { !$0.title.isEmpty }
    }

    private var canContinue: Bool {
        switch step {
        case .welcome:
            true
        case .books:
            (!enteredBooks.isEmpty || !store.books.isEmpty) && !isAddingBooks
        case .codex:
            !store.authState.pending
        }
    }

    var body: some View {
        ZStack {
            OnboardingBackdrop()

            GlassPanel(cornerRadius: 38, padding: 0, intensity: .regular) {
                HStack(spacing: 0) {
                    onboardingRail

                    Divider()
                        .opacity(0.5)

                    VStack(alignment: .leading, spacing: 0) {
                        stepContent

                        Spacer(minLength: 0)

                        Divider()
                            .opacity(0.45)

                        footer
                    }
                    .frame(width: 560, height: 520)
                }
            }
            .frame(width: 820, height: 520)
            .padding(32)
        }
        .interactiveDismissDisabled(true)
    }

    private var onboardingRail: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                NavReadLogoMark(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NavRead")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                    Text("First setup")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(OnboardingStep.allCases) { item in
                    OnboardingStepRow(step: item, selected: step == item, completed: item.rawValue < step.rawValue)
                }
            }

            Spacer()

            Button {
                toggleAppearance()
            } label: {
                Label(appearanceToggleTitle, systemImage: appearanceToggleIcon)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(GhostButtonStyle())
            .help(appearanceToggleHelp)

            Text("Local library. Codex-powered extraction, chapter scaffolds, quote cleanup, and search context.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .padding(24)
        .frame(width: 260, height: 520, alignment: .topLeading)
        .background(railBackground)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .books:
            booksStep
        case .codex:
            codexStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 8)

            NavReadLogoMark(size: 72)

            VStack(alignment: .leading, spacing: 10) {
                Text("Build your reading desk.")
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)

                Text("Add your first books, connect Codex, then NavRead can resolve covers, draft chapters, classify captures, and keep quotes plus book and chapter learnings searchable.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                OnboardingCapability(icon: "books.vertical", title: "Books first", text: "Book quotes live inside chapter context. Standalone quotes get their own section.")
                OnboardingCapability(icon: "brain.head.profile", title: "Codex connected", text: "AI stays user-triggered and scoped to current library context.")
                OnboardingCapability(icon: "square.and.arrow.up", title: "Ready to export", text: "Markdown, CSV, JSON, quote cards, and Notes sharing stay local-first.")
            }

            Spacer(minLength: 0)
        }
        .padding(34)
    }

    private var booksStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Start with a few books.")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                Text("Enter titles you care about. Author helps matching; ISBN can be added later. NavRead will fetch covers and create editable chapter scaffolds.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach($starterBooks) { $book in
                        StarterBookRow(book: $book, removable: starterBooks.count > 1) {
                            starterBooks.removeAll { $0.id == book.id }
                        }
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(maxHeight: 210)
            .scrollIndicators(.visible)

            Button {
                starterBooks.append(StarterBookInput(title: "", author: ""))
            } label: {
                Label("Add another book", systemImage: "plus")
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(isAddingBooks || starterBooks.count >= 8)

            if isAddingBooks || !addProgress.isEmpty {
                HStack(spacing: 10) {
                    if isAddingBooks {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(addProgress)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }

            Spacer()
        }
        .padding(34)
    }

    private var codexStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connect Codex.")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                Text("Connect now for AI chapter scaffolds, capture classification, saved-item cleanup, and chat. You can also finish setup and connect later from Settings.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: store.authState.authenticated ? "checkmark.circle.fill" : "person.crop.circle.badge.plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.primary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.authState.authenticated ? "Codex connected" : "Codex not connected")
                            .font(.system(size: 16, weight: .semibold))
                        Text(store.authState.statusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                Button {
                    Task { await store.startCodexLogin() }
                } label: {
                    Label(store.authState.pending ? "Opening Sign-In" : "Connect Codex", systemImage: "arrow.up.right")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(store.authState.pending || store.authState.authenticated)

                DisclosureGroup("Manual callback fallback") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Paste callback URL or code", text: $callback)
                            .textFieldStyle(NavReadTextFieldStyle())
                            .onSubmit {
                                Task { await store.completeCodexCallback(callback) }
                            }
                        Button("Complete Sign-In") {
                            Task { await store.completeCodexCallback(callback) }
                        }
                        .buttonStyle(GhostButtonStyle())
                        .disabled(callback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.top, 8)
                }
                .font(.system(size: 12))
            }
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            )

            Spacer()
        }
        .padding(34)
    }

    private var footer: some View {
        HStack {
            Button("Back") {
                withAnimation(NavReadTheme.animationSnappy) {
                    step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
                }
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(step == .welcome || isAddingBooks)

            Spacer()

            if step == .books && !isAddingBooks {
                Text(booksFooterText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(primaryActionTitle) {
                primaryAction()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canContinue)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var railBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.035) : Color.black.opacity(0.025)
    }

    private var appearanceToggleTitle: String {
        AppearanceMode(rawValue: appearanceMode) == .light ? "Dark" : "Light"
    }

    private var appearanceToggleIcon: String {
        AppearanceMode(rawValue: appearanceMode) == .light ? "moon.fill" : "sun.max.fill"
    }

    private var appearanceToggleHelp: String {
        AppearanceMode(rawValue: appearanceMode) == .light ? "Switch to Dark Mode" : "Switch to Light Mode"
    }

    private func toggleAppearance() {
        appearanceMode = AppearanceMode(rawValue: appearanceMode) == .light
            ? AppearanceMode.dark.rawValue
            : AppearanceMode.light.rawValue
    }

    private var primaryActionTitle: String {
        switch step {
        case .welcome:
            return "Get Started"
        case .books:
            if isAddingBooks { return "Adding..." }
            return enteredBooks.isEmpty ? "Continue" : "Add Books"
        case .codex:
            return store.authState.authenticated ? "Finish Setup" : "Finish Without Codex"
        }
    }

    private var booksFooterText: String {
        if !enteredBooks.isEmpty {
            return "\(enteredBooks.count) selected"
        }
        return "\(store.books.count) already in library"
    }

    private func primaryAction() {
        switch step {
        case .welcome:
            withAnimation(NavReadTheme.animationSnappy) {
                step = .books
            }
        case .books:
            Task { await addStarterBooks() }
        case .codex:
            hasCompletedFirstRunOnboarding = true
        }
    }

    private func addStarterBooks() async {
        let books = enteredBooks
        guard !books.isEmpty else {
            addProgress = store.books.isEmpty ? "" : "Using existing library."
            withAnimation(NavReadTheme.animationSnappy) {
                step = .codex
            }
            return
        }
        isAddingBooks = true
        for (index, book) in books.enumerated() {
            addProgress = "Adding \(index + 1) of \(books.count): \(book.title)"
            await store.addBook(title: book.title, author: book.author, isbn: "")
        }
        addProgress = "Books added."
        isAddingBooks = false
        withAnimation(NavReadTheme.animationSnappy) {
            step = .codex
        }
    }
}

private struct OnboardingBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.035),
                    .clear,
                    Color.primary.opacity(colorScheme == .dark ? 0.03 : 0.018)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.18 : 0.44)
        }
        .ignoresSafeArea()
    }

    private var backgroundColors: [Color] {
        if colorScheme == .dark {
            return [
                Color.black,
                Color(nsColor: .windowBackgroundColor),
                Color.black.opacity(0.94)
            ]
        }

        return [
            Color.white,
            Color(nsColor: .textBackgroundColor),
            Color.white.opacity(0.96)
        ]
    }
}

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case books
    case codex

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .books: "Books"
        case .codex: "Codex"
        }
    }

    var icon: String {
        switch self {
        case .welcome: "house"
        case .books: "books.vertical"
        case .codex: "brain.head.profile"
        }
    }
}

private struct StarterBookInput: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var author: String

    var cleaned: StarterBookInput {
        StarterBookInput(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            author: author.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    init(id: UUID = UUID(), title: String, author: String) {
        self.id = id
        self.title = title
        self.author = author
    }
}

private struct StarterBookRow: View {
    @Binding var book: StarterBookInput
    var removable: Bool
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Book title", text: $book.title)
                .textFieldStyle(NavReadTextFieldStyle())
            TextField("Author", text: $book.author)
                .textFieldStyle(NavReadTextFieldStyle())
                .frame(width: 170)
            Button {
                remove()
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(!removable)
            .opacity(removable ? 1 : 0.25)
        }
    }
}

private struct OnboardingStepRow: View {
    @Environment(\.colorScheme) private var colorScheme
    var step: OnboardingStep
    var selected: Bool
    var completed: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(selected ? Color.primary : Color.primary.opacity(0.08))
                    .frame(width: 28, height: 28)
                Image(systemName: completed ? "checkmark" : step.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? inverseInk : .primary)
            }
            Text(step.title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? Color.primary.opacity(0.06) : Color.clear, in: Capsule())
    }

    private var inverseInk: Color {
        colorScheme == .dark ? .black : .white
    }
}

private struct OnboardingCapability: View {
    var icon: String
    var title: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(.primary.opacity(0.06), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
