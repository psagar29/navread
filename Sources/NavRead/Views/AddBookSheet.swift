import SwiftUI

struct AddBookSheet: View {
    @EnvironmentObject private var store: NavReadStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var title = ""
    @State private var author = ""
    @State private var isbn = ""
    @State private var appeared = false

    var body: some View {
        ZStack {
            MorphingBackground(accentHex: "#000000")
                .opacity(0.28)

            VStack(spacing: 0) {
                GlassPanel(cornerRadius: NavReadTheme.cornerRadiusXL, padding: 32, intensity: .regular) {
                    VStack(alignment: .leading, spacing: 22) {
                        // Header
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Text("Add Book")
                                        .font(.system(size: 32, weight: .bold, design: .serif))
                                }
                                Text("Enter the title and author. Cover, metadata, and AI chapter scaffolds load automatically.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(2)
                            }
                            Spacer()
                            if store.isWorking {
                                InkScanView()
                                    .transition(.opacity)
                            }
                        }

                        // Form fields
                        VStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Title")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                TextField("e.g. The Great Gatsby", text: $title)
                                    .font(.system(size: 16))
                                    .textFieldStyle(NavReadTextFieldStyle())
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Author")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                TextField("e.g. F. Scott Fitzgerald", text: $author)
                                    .textFieldStyle(NavReadTextFieldStyle())
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("ISBN")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Text("optional")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                TextField("e.g. 978-0743273565", text: $isbn)
                                    .textFieldStyle(NavReadTextFieldStyle())
                            }
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text("Cover lookup runs via Google Books & Open Library. AI drafts chapters after metadata resolves.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineSpacing(1)
                        }
                        .padding(12)
                        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                        )

                        // Actions
                        HStack {
                            Button("Cancel") {
                                dismiss()
                            }
                            .buttonStyle(GhostButtonStyle())
                            .keyboardShortcut(.cancelAction)

                            Spacer()

                            Button {
                                Task {
                                    await store.addBook(title: title, author: author, isbn: isbn)
                                    dismiss()
                            }
                        } label: {
                                Label("Resolve + Create", systemImage: "plus")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWorking)
                        }
                    }
                    .frame(width: 580)
                }
                .padding(36)
                .scaleEffect(appeared ? 1 : 0.96)
                .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(NavReadTheme.animationBouncy) {
                appeared = true
            }
        }
    }
}
