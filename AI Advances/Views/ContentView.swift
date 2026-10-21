import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case trends = "Trends"
    case forecasts = "Forecasts"
    case labs = "Labs"
    case advances = "Latest Advances"
    case capabilities = "Capabilities"
    case models = "Models"
    case cost = "Cost"
    case context = "Context & Modalities"
    case compute = "Compute"

    var id: String { rawValue }

    /// Reads a saved or launch-argument page name: the current names, the case names
    /// ("advances"), and names from older versions ("Direction Trends").
    init?(stored: String) {
        let s = stored.trimmingCharacters(in: .whitespaces)
        if s == "Direction Trends" { self = .trends; return }
        guard let p = Page.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(s) == .orderedSame || "\($0)".caseInsensitiveCompare(s) == .orderedSame
        }) else { return nil }
        self = p
    }

    /// `-page <name>` on the command line, read once; it picks the first page shown but doesn't
    /// pin it (as a UserDefaults argument it used to override every later choice).
    static let launchArgument: Page? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-page"), i + 1 < args.count else { return nil }
        return Page(stored: args[i + 1])
    }()

    var symbol: String {
        switch self {
        case .trends: "chart.line.uptrend.xyaxis"
        case .forecasts: "binoculars"
        case .labs: "building.2"
        case .advances: "sparkles"
        case .capabilities: "target"
        case .models: "tablecells"
        case .cost: "dollarsign.circle"
        case .context: "text.page"
        case .compute: "cpu"
        }
    }
}

struct ContentView: View {
    @Environment(DataStore.self) private var store
    /// Per window; empty until the first page is picked (see `restorePage`).
    @SceneStorage("page") private var pageName = ""
    @State private var showSources = false
    @State private var showFeedback = false
    private static var launchPageApplied = false

    private var page: Page { Page(stored: pageName) ?? .trends }
    private var pageBinding: Binding<Page> {
        Binding(get: { page }, set: { pageName = $0.rawValue })
    }

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: Binding<Page?>(get: { page }, set: { if let p = $0 { pageName = p.rawValue } })) { p in
                Label(p.rawValue, systemImage: p.symbol).tag(p)
                    .badge(p == .advances ? store.newFeedIDs.count : 0)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                Button { showFeedback = true } label: {
                    Label("Feedback", systemImage: "bubble.left")
                        .font(.caption)
                        .foregroundStyle(Palette.text2)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .help("Send feedback about AI Advances")
            }
        } detail: {
            Group {
                if store.data.results.isEmpty {
                    if let error = store.loadError {
                        ContentUnavailableView {
                            Label("Couldn’t load data", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("Retry") { Task { await store.retryLoading() } }
                            Button("Reset to Bundled Data") { Task { await store.resetToBundledData() } }
                        }
                    } else {
                        ProgressView("Loading data…")
                    }
                } else {
                    VStack(spacing: 0) {
                        StatusBanner()
                        if page == .models {
                            // The table scrolls itself; its details sit in an inspector.
                            ModelsView().padding(24)
                        } else {
                            ScrollView {
                                detail.padding(24).frame(maxWidth: 1300, alignment: .leading)
                            }
                            .id(page) // each page starts at the top
                        }
                    }
                }
            }
            .navigationTitle(page.rawValue)
        }
        .toolbar {
            ToolbarItemGroup {
                if let update = store.update {
                    Link(destination: update.page) {
                        Label("Version \(update.version) available", systemImage: "arrow.down.circle")
                            .labelStyle(.titleAndIcon)
                    }
                    .help("A newer AI Advances is on GitHub. Opens the download page.")
                }
                Button { showSources.toggle() } label: {
                    // Re-render every minute so "Updated 5 minutes ago" keeps up.
                    TimelineView(.everyMinute) { context in
                        Label(statusText(now: context.date), systemImage: sourceSymbol).labelStyle(.titleAndIcon)
                    }
                }
                .help("Where the data comes from, and when it last updated")
                .popover(isPresented: $showSources) { SourcesView() }

                Button { Task { await store.refresh() } } label: {
                    if store.isRefreshing { ProgressView().controlSize(.small) } else { Label("Refresh", systemImage: "arrow.clockwise") }
                }
                .disabled(store.isRefreshing)
                .help("Download the latest data now (⌘R)")
            }
        }
        .sheet(isPresented: $showFeedback) { FeedbackView() }
        .alert("Check for Updates", isPresented: Binding(get: { store.updateCheckMessage != nil },
                                                        set: { if !$0 { store.updateCheckMessage = nil } })) {
            if let update = store.update { Link("Open Download Page", destination: update.page) }
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.updateCheckMessage ?? "")
        }
        .focusedSceneValue(\.page, pageBinding)
        .focusedSceneValue(\.showFeedback, $showFeedback)
        .focusedSceneValue(\.showSources, $showSources)
        .onAppear(perform: restorePage)
    }

    /// The launch argument wins once per launch; otherwise a window with no saved page picks up the
    /// page older versions saved in UserDefaults.
    private func restorePage() {
        if !Self.launchPageApplied, let p = Page.launchArgument {
            Self.launchPageApplied = true
            pageName = p.rawValue
        } else if pageName.isEmpty {
            pageName = (UserDefaults.standard.string(forKey: "page").flatMap(Page.init(stored:)) ?? .trends).rawValue
        }
    }

    @ViewBuilder private var detail: some View {
        switch page {
        case .trends: TrendsView()
        case .forecasts: ForecastsView()
        case .labs: LabsView()
        case .advances: AdvancesView()
        case .capabilities: CapabilitiesView()
        case .models: ModelsView()
        case .cost: CostView()
        case .context: ContextView()
        case .compute: ComputeView()
        }
    }

    private var sourceSymbol: String {
        store.status.values.contains { $0.error != nil } ? "exclamationmark.icloud" : "icloud"
    }

    private func statusText(now: Date) -> String {
        if store.isRefreshing { return "Updating…" }
        guard let last = store.lastRefresh else { return "Using bundled snapshot" }
        return "Updated " + last.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }
}

/// Above every page: a warning when the data is out of date, and why the last refresh failed.
struct StatusBanner: View {
    @Environment(DataStore.self) private var store
    /// Advanced every minute so the banner appears once data goes stale. (A TimelineView here made
    /// the window's content taller than the window, shifting every page and the sidebar up.)
    @State private var now = Date()

    var body: some View {
        let stale = DataStore.staleDays(lastRefresh: store.lastRefresh, latestData: store.latestDataDate, now: now)
        VStack(spacing: 0) {
            if store.refreshError != nil || stale != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.color(1))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        if let stale { Text(staleText(days: stale)) }
                        if let error = store.refreshError {
                            Text("The last update failed. \(error)").font(.callout).foregroundStyle(Palette.text2)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Refresh Now") { Task { await store.refresh() } }
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.color(1).opacity(0.1))
                .accessibilityElement(children: .combine)
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private func staleText(days: Int) -> String {
        if let last = store.lastRefresh, Int(Date().timeIntervalSince(last) / 86_400) >= days {
            return "This data was last updated \(counted(days, "day")) ago (\(Format.date.string(from: last))). The app normally updates every morning."
        }
        if let newest = store.latestDataDate {
            return store.lastRefresh == nil
                ? "Showing the snapshot bundled with the app, with data through \(Format.date.string(from: newest)). It updates once it can reach the sources."
                : "The newest entry in the data is \(counted(days, "day")) old (\(Format.date.string(from: newest))); the sources may have stopped updating."
        }
        return "This data is \(counted(days, "day")) old."
    }
}

struct SourcesView: View {
    @Environment(DataStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data sources").font(.headline)
            ForEach(DataStore.sources) { s in
                let st = store.status[s.file]
                VStack(alignment: .leading, spacing: 2) {
                    Link(s.name, destination: s.page).font(.body.weight(.medium))
                    Text(s.credit).font(.caption).foregroundStyle(Palette.text2)
                    Group {
                        if let st, st.fromSnapshot {
                            Text("Using the snapshot bundled with the app" + (st.newestEntry.map { " (data through \(Format.date.string(from: $0)))" } ?? ""))
                        } else if let d = st?.updated {
                            Text("Downloaded \(d.formatted(date: .abbreviated, time: .shortened))")
                        }
                    }
                    .font(.caption)
                    if let e = st?.error { Label("Last update failed: \(e)", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Link("Claude's daily outlook", destination: URL(string: "https://amalmehta.github.io/ai-advances/#/forecasts")!).font(.body.weight(.medium))
                Text(store.claudeOutlook.map { "Written \(displayDate($0.generatedAt)) by \($0.model), from the website's daily build" }
                     ?? "Not downloaded yet; it appears once the website's daily build has written one")
                    .font(.caption).foregroundStyle(Palette.text2)
            }
            Divider()
            Text("The app updates each morning: at launch, at 7:00 AM if it's open, or when your Mac wakes, whichever comes first after 7. ⌘R updates now.")
                .font(.caption).foregroundStyle(Palette.text2)
            if let d = store.latestDataDate {
                Text("Newest entry in the data: \(Format.date.string(from: d))").font(.caption).foregroundStyle(Palette.text2)
            }
            if store.status.values.contains(where: { !$0.fromSnapshot }) {
                Button("Reset to Bundled Data") { Task { await store.resetToBundledData() } }
                    .font(.caption)
                    .help("Delete the downloaded copies and use the snapshot that came with the app until the next update")
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
