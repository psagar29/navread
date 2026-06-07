import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: NavReadStore
    @Environment(\.dismiss) private var dismiss
    @State private var callback = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 24, weight: .semibold))
                    Text("Account and local storage.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsBlock(title: "Codex", icon: "brain.head.profile") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(store.authState.authenticated ? "Connected" : "Not connected")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(store.authState.statusMessage)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 20)
                                Button(settingsAuthButtonTitle) {
                                    Task {
                                        if store.authState.authenticated {
                                            store.signOutCodex()
                                        } else {
                                            await store.startCodexLogin()
                                        }
                                    }
                                }
                                .buttonStyle(LiquidButtonStyle())
                                .disabled(store.authState.pending)
                            }

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
                    }

                    SettingsBlock(title: "Library", icon: "externaldrive") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                MiniStat(value: "\(store.books.count)", label: "books")
                                MiniStat(value: "\(store.totalQuoteCount)", label: "quotes")
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Location")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(LibraryPaths.root.path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }

                            Button {
                                store.openLibraryFolder()
                            } label: {
                                Label("Show in Finder", systemImage: "folder")
                            }
                            .buttonStyle(GhostButtonStyle())
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
        }
        .frame(minWidth: 560, idealWidth: 560, maxWidth: 560, minHeight: 420, idealHeight: 500, maxHeight: 620)
        .background(.regularMaterial)
        .task {
            await store.refreshCodexAuthStatus(validate: true)
        }
    }
}

private extension SettingsView {
    var settingsAuthButtonTitle: String {
        if store.authState.pending { return "Opening..." }
        return store.authState.authenticated ? "Disconnect" : "Sign In"
    }
}

struct SettingsBlock<Content: View>: View {
    var title: String
    var icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            content
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct MiniStat: View {
    var value: String
    var label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
