import SwiftUI

@main
struct AIAdvancesApp: App {
    @State private var store = DataStore()

    /// The unit tests run inside this app; they must not load, refresh or write the user's data.
    static var shouldStartStore: Bool { !DataStore.isRunningTests }

    var body: some Scene {
        // One window: the app has one dataset and one set of timers, so a second window would only
        // duplicate work.
        Window("AI Advances", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 980, minHeight: 680)
                .task { if Self.shouldStartStore { await store.start() } }
        }
        .defaultSize(width: 1280, height: 860)
        .commands { AppCommands(store: store) }
    }
}

struct AppCommands: Commands {
    let store: DataStore
    @FocusedBinding(\.page) private var page
    @FocusedBinding(\.showFeedback) private var showFeedback
    @FocusedBinding(\.showSources) private var showSources

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Task { await store.checkForUpdate(manual: true) } }
        }
        CommandGroup(after: .toolbar) {
            Button("Refresh Data") { Task { await store.refresh() } }
                .keyboardShortcut("r")
                .disabled(store.isRefreshing)
        }
        CommandMenu("Go") {
            ForEach(Array(Page.allCases.enumerated()), id: \.element) { i, p in
                Button(p.rawValue) { page = p }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    .disabled(page == nil)
            }
        }
        CommandGroup(replacing: .help) {
            Button("AI Advances Website") { NSWorkspace.shared.open(DataStore.websiteURL) }
            Button("Data Sources") { showSources = true }
                .disabled(showSources == nil)
            Divider()
            Button("Send Feedback…") { showFeedback = true }
                .disabled(showFeedback == nil)
        }
    }
}

struct PageKey: FocusedValueKey { typealias Value = Binding<Page> }
struct ShowFeedbackKey: FocusedValueKey { typealias Value = Binding<Bool> }
struct ShowSourcesKey: FocusedValueKey { typealias Value = Binding<Bool> }

extension FocusedValues {
    var page: Binding<Page>? {
        get { self[PageKey.self] }
        set { self[PageKey.self] = newValue }
    }
    var showFeedback: Binding<Bool>? {
        get { self[ShowFeedbackKey.self] }
        set { self[ShowFeedbackKey.self] = newValue }
    }
    var showSources: Binding<Bool>? {
        get { self[ShowSourcesKey.self] }
        set { self[ShowSourcesKey.self] = newValue }
    }
}
