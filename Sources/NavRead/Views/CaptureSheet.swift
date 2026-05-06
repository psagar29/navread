import SwiftUI
import UniformTypeIdentifiers

struct CaptureSheet: View {
    @EnvironmentObject private var store: NavReadStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var rawText = ""
    @State private var cleanedText = ""
    @State private var pageLocator = ""
    @State private var note = ""
    @State private var tags = ""
    @State private var webURL = ""
    @State private var candidates: [QuoteCandidate] = []
    @State private var fileImporterPresented = false
    @State private var appeared = false
    @State private var selectedSource: CaptureSource = .text
    @State private var selectedKind: CapturedContentKind = .quote

    enum CaptureSource: String, CaseIterable {
        case text = "Text"
        case file = "File"
        case web = "Web"

        var icon: String {
            switch self {
            case .text: return "text.cursor"
            case .file: return "doc.viewfinder"
            case .web: return "globe"
            }
        }
    }

    var body: some View {
        ZStack {
            MorphingBackground(accentHex: "#000000")
                .opacity(0.4)

            VStack(spacing: 0) {
                GlassPanel(cornerRadius: NavReadTheme.cornerRadiusXL, padding: 28, intensity: .regular) {
                    VStack(alignment: .leading, spacing: 18) {
                        // Header
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    Image(systemName: "text.quote")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Text("Capture")
                                        .font(.system(size: 30, weight: .bold, design: .serif))
                                }
                                Text(store.selectedChapter?.title ?? store.selectedBook?.title ?? "No book selected")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.isWorking {
                                InkScanView()
                                    .transition(.opacity)
                            }
                        }

                        HStack(spacing: 8) {
                            ForEach(CaptureSource.allCases, id: \.self) { source in
                                Button {
                                    withAnimation(NavReadTheme.animationSnappy) {
                                        selectedSource = source
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: source.icon)
                                            .font(.system(size: 11))
                                        Text(source.rawValue)
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        selectedSource == source ?
                                            AnyShapeStyle(.regularMaterial) :
                                            AnyShapeStyle(.clear)
                                    , in: Capsule())
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(
                                                selectedSource == source ? Color.primary.opacity(0.15) : Color.primary.opacity(0.06),
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }

                        classificationSection

                        // Source-specific input
                        switch selectedSource {
                        case .text:
                            textInputSection
                        case .file:
                            fileInputSection
                        case .web:
                            webInputSection
                        }

                        // Metadata fields
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Page")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                TextField("e.g. p.42", text: $pageLocator)
                                    .textFieldStyle(NavReadTextFieldStyle())
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tags")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                TextField("comma-separated", text: $tags)
                                    .textFieldStyle(NavReadTextFieldStyle())
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Note")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                            TextField("Optional note...", text: $note)
                                .textFieldStyle(NavReadTextFieldStyle())
                        }

                        // Candidates
                        CandidateList(candidates: candidates) { candidate in
                            store.acceptCandidate(candidate)
                            dismiss()
                        }

                        // Close button
                        HStack {
                            Spacer()
                            Button("Close") { dismiss() }
                                .buttonStyle(GhostButtonStyle())
                                .keyboardShortcut(.cancelAction)
                        }
                    }
                    .frame(width: 720)
                }
                .padding(30)
                .scaleEffect(appeared ? 1 : 0.96)
                .opacity(appeared ? 1 : 0)
            }
        }
        .fileImporter(
            isPresented: $fileImporterPresented,
            allowedContentTypes: [.pdf, .image, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task {
                    candidates = await store.importFileCapture(url)
                    if let first = candidates.first {
                        selectedKind = first.kind
                    }
                }
            }
        }
        .onAppear {
            withAnimation(NavReadTheme.animationBouncy) {
                appeared = true
            }
        }
    }

    // MARK: - Text Input

    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $rawText)
                    .font(.system(size: 15, design: .serif))
                    .lineSpacing(3)
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: NavReadTheme.cornerRadiusMedium, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: NavReadTheme.cornerRadiusMedium, style: .continuous)
                            .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                    )

                if rawText.isEmpty {
                    Text("Paste a paragraph, screenshot OCR text, or exact quote...")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 15, design: .serif))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 10) {
                Button {
                    cleanedText = rawText
                    store.addManualQuote(
                        rawText: rawText,
                        cleanedText: cleanedText,
                        pageLocator: pageLocator,
                        note: note,
                        tags: classifiedTags
                    )
                    dismiss()
                } label: {
                    Label("Save Exact", systemImage: "text.quote")
                }
                .buttonStyle(LiquidButtonStyle())
                .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    Task {
                        selectedKind = classify(rawText)
                        candidates = await store.extractManualCapture(rawText)
                        if let first = candidates.first {
                            selectedKind = first.kind
                        }
                    }
                } label: {
                    Label("Classify + Extract", systemImage: "brain.head.profile")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - File Input

    private var fileInputSection: some View {
        VStack(spacing: 14) {
            Button {
                fileImporterPresented = true
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Import Image or PDF")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Supports PDF, PNG, JPG, HEIC, TIFF, WebP")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: NavReadTheme.cornerRadiusMedium, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 5]))
                        .foregroundStyle(.primary.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Web Input

    private var webInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Web URL")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    TextField("https://example.com/article", text: $webURL)
                        .textFieldStyle(NavReadTextFieldStyle())
                    Button {
                        Task {
                            candidates = await store.importWebCapture(webURL)
                            if let first = candidates.first {
                                selectedKind = first.kind
                            }
                        }
                    } label: {
                        Label("Extract", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(webURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var classificationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("AI classification", systemImage: "brain.head.profile")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if selectedSource == .text {
                    Button {
                        selectedKind = classify(rawText)
                    } label: {
                        Label("Classify", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            HStack(spacing: 6) {
                ForEach(CapturedContentKind.allCases) { kind in
                    Button {
                        selectedKind = kind
                    } label: {
                        Text(kind.title)
                            .font(.system(size: 11, weight: selectedKind == kind ? .semibold : .regular))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                selectedKind == kind ? Color.primary.opacity(0.08) : Color.clear,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(.primary.opacity(selectedKind == kind ? 0.18 : 0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var classifiedTags: [String] {
        tags.components(separatedBy: ",") + ["type-\(selectedKind.rawValue)"]
    }

    private func classify(_ text: String) -> CapturedContentKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        let codeMarkers = ["func ", "let ", "var ", "const ", "class ", "struct ", "import ", "return ", "{", "};", "```", "=>", "def "]
        if codeMarkers.contains(where: { lowered.contains($0) }) {
            return .code
        }
        if trimmed.hasSuffix("?") || lowered.hasPrefix("why ") || lowered.hasPrefix("how ") {
            return .question
        }
        if trimmed.count > 280 {
            return .passage
        }
        return .quote
    }
}

// MARK: - Candidate List

struct CandidateList: View {
    var candidates: [QuoteCandidate]
    var accept: (QuoteCandidate) -> Void

    var body: some View {
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "AI Candidates", subtitle: "\(candidates.count) found", icon: "brain.head.profile")

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(candidates) { candidate in
                            HStack(alignment: .top, spacing: 14) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\u{201C}\(candidate.cleanedText)\u{201D}")
                                        .font(.system(size: 14, design: .serif))
                                        .lineSpacing(2)
                                    HStack(spacing: 8) {
                                        TagPill(text: candidate.kind.title)
                                        ConfidenceBadge(confidence: candidate.confidence)
                                        ForEach(candidate.tags.prefix(3), id: \.self) { tag in
                                            TagPill(text: tag)
                                        }
                                    }
                                }
                                Spacer()
                                Button {
                                    accept(candidate)
                                } label: {
                                    Label("Accept", systemImage: "checkmark.circle")
                                }
                                .buttonStyle(LiquidButtonStyle())
                            }
                            .padding(14)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: NavReadTheme.cornerRadiusMedium, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: NavReadTheme.cornerRadiusMedium, style: .continuous)
                                    .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
                            )
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }
}

struct ConfidenceBadge: View {
    var confidence: Double

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.primary.opacity(confidence > 0.8 ? 0.88 : confidence > 0.5 ? 0.62 : 0.36))
                .frame(width: 6, height: 6)
            Text("\(Int(confidence * 100))%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }
}
