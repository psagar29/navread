import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: NavReadStore
    @AppStorage("hasCompletedFirstRunOnboarding") private var hasCompletedFirstRunOnboarding = false
    @AppStorage("hasStartedFirstRunOnboarding") private var hasStartedFirstRunOnboarding = false
    @Namespace private var coverNamespace
    @State private var showingAddBook = false
    @State private var showingCapture = false
    @State private var showingAI = false
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            SidebarView(namespace: coverNamespace)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            ZStack {
                MorphingBackground(accentHex: "#000000")

                BookWorkspaceView(namespace: coverNamespace)
                    .padding(24)
            }
            .toolbar {
                ToolbarItemGroup {
                    HStack(spacing: 6) {
                        ToolbarButton(icon: "plus", label: "Add Book") {
                            showingAddBook = true
                        }
                        ToolbarButton(icon: "text.quote", label: "Capture") {
                            showingCapture = true
                        }
                        .disabled(store.selectedBook == nil)
                        ToolbarButton(icon: "brain.head.profile", label: "Ask AI") {
                            showingAI = true
                        }
                        .disabled(store.selectedBook == nil)
                        ShareMenu()
                        AppearanceToggleButton()
                        ToolbarButton(icon: "gearshape", label: "Settings") {
                            showingSettings = true
                        }
                    }
                }
            }
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search books, quotes, tags...")
        .sheet(isPresented: $showingAddBook) {
            AddBookSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingCapture) {
            CaptureSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingAI) {
            AICommandPalette()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(store)
        }
        .sheet(
            isPresented: Binding(
                get: { shouldShowFirstRunOnboarding },
                set: { _ in }
            )
        ) {
            FirstRunOnboardingView()
                .environmentObject(store)
        }
        .task {
            prepareFirstRunOnboardingGate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navReadAddBook)) { _ in
            showingAddBook = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .navReadQuickCapture)) { _ in
            showingCapture = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .navReadCodexAuthCompleted)) { notification in
            store.codexCallbackCompleted(accountID: notification.userInfo?["accountID"] as? String ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .navReadCodexAuthFailed)) { notification in
            store.codexCallbackFailed(message: notification.userInfo?["message"] as? String ?? "Codex sign-in failed.")
        }
    }

    private var shouldShowFirstRunOnboarding: Bool {
        !hasCompletedFirstRunOnboarding && hasStartedFirstRunOnboarding
    }

    private func prepareFirstRunOnboardingGate() {
        let state = FirstRunOnboardingGate.resolve(
            hasCompleted: hasCompletedFirstRunOnboarding,
            hasStarted: hasStartedFirstRunOnboarding,
            libraryExistedBeforeSetup: store.libraryExistedBeforeSetup
        )
        hasCompletedFirstRunOnboarding = state.hasCompleted
        hasStartedFirstRunOnboarding = state.hasStarted
    }
}

// MARK: - Toolbar Button

struct ToolbarButton: View {
    var icon: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
        }
        .help(label)
    }
}

// MARK: - Share Menu

struct ShareMenu: View {
    @EnvironmentObject private var store: NavReadStore

    var body: some View {
        Menu {
            Section("Copy to Clipboard") {
                ForEach(ExportFormat.allCases) { format in
                    Button {
                        store.copyExport(format)
                    } label: {
                        Label(format.menuTitle, systemImage: format.icon)
                    }
                }
            }
            Section("Save to File") {
                ForEach(ExportFormat.allCases) { format in
                    Button {
                        store.saveExport(format)
                    } label: {
                        Label("Save \(format.menuTitle)", systemImage: "arrow.down.doc")
                    }
                }
            }
            Divider()
            Section("Integrations") {
                Button {
                    store.addCurrentBookToNotes()
                } label: {
                    Label("Add to Apple Notes", systemImage: "note.text")
                }
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .disabled(store.selectedBook == nil)
    }
}

struct AppearanceToggleButton: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue

    private var switchesToLight: Bool {
        AppearanceMode(rawValue: appearanceMode) != .light
    }

    var body: some View {
        Button {
            appearanceMode = switchesToLight ? AppearanceMode.light.rawValue : AppearanceMode.dark.rawValue
        } label: {
            Label(switchesToLight ? "Light Mode" : "Dark Mode", systemImage: switchesToLight ? "sun.max.fill" : "moon.fill")
        }
        .help(switchesToLight ? "Switch to Light Mode" : "Switch to Dark Mode")
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject private var store: NavReadStore
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    NavReadLogoMark(size: 48)
                    Text("NavRead")
                        .font(.system(size: 54, weight: .bold, design: .serif))
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                Text("Add a book. Pick a chapter. Save the quotes you want to remember.")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)
            }

            HStack(spacing: 14) {
                Button {
                    NotificationCenter.default.post(name: .navReadAddBook, object: nil)
                } label: {
                    Label("Add Book", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.top, 80)
        .onAppear {
            withAnimation(NavReadTheme.animationGentle.delay(0.1)) {
                appeared = true
            }
        }
    }
}

struct OnboardingFeature: View {
    var title: String
    var icon: String
    var text: String
    var delay: Double = 0
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.primary.opacity(0.7))
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: NavReadTheme.cornerRadiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NavReadTheme.cornerRadiusMedium, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        )
        .scaleEffect(appeared ? 1 : 0.95)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(NavReadTheme.animationBouncy.delay(delay)) {
                appeared = true
            }
        }
    }
}
