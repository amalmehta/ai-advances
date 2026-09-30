import SwiftUI

@main
struct AIAdvancesApp: App {
    @State private var store = DataStore()

    var body: some Scene {
        WindowGroup("AI Advances") {
            ContentView()
                .environment(store)
                .frame(minWidth: 980, minHeight: 680)
                .task { await store.start() }
        }
        .defaultSize(width: 1280, height: 860)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh Data") { Task { await store.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(store.isRefreshing)
            }
        }
    }
}
