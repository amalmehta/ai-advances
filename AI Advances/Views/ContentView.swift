import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case trends = "Direction Trends"
    case forecasts = "Forecasts"
    case labs = "Labs"
    case advances = "Latest Advances"
    case capabilities = "Capabilities"
    case models = "Models"
    case cost = "Cost"
    case context = "Context & Modalities"
    case compute = "Compute"

    var id: String { rawValue }

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
    @AppStorage("page") private var page: Page = .trends
    @State private var showSources = false
    @State private var showFeedback = false

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { p in
                Label(p.rawValue, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                Button { showFeedback = true } label: {
                    Label("Feedback", systemImage: "bubble.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        ContentUnavailableView("Couldn’t load data", systemImage: "exclamationmark.triangle", description: Text(error))
                    } else {
                        ProgressView("Loading data…")
                    }
                } else {
                    ScrollView {
                        detail.padding(24).frame(maxWidth: 1300, alignment: .leading)
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
                    Label(statusText, systemImage: sourceSymbol).labelStyle(.titleAndIcon)
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

    private var statusText: String {
        if store.isRefreshing { return "Updating…" }
        guard let last = store.lastRefresh else { return "Using bundled snapshot" }
        return "Updated " + last.formatted(.relative(presentation: .named))
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
                    Text(s.credit).font(.caption).foregroundStyle(.secondary)
                    Group {
                        if let st, st.fromSnapshot { Text("Using the snapshot bundled with the app (Sept 30, 2026)") }
                        else if let d = st?.updated { Text("Downloaded \(d.formatted(date: .abbreviated, time: .shortened))") }
                    }
                    .font(.caption)
                    if let e = st?.error { Label("Last update failed: \(e)", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Link("Claude's daily outlook", destination: URL(string: "https://amalmehta.github.io/ai-advances/#/forecasts")!).font(.body.weight(.medium))
                Text(store.claudeOutlook.map { "Written \($0.generatedAt.prefix(10)) by \($0.model), from the website's daily build" }
                     ?? "Not downloaded yet; it appears once the website's daily build has written one")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("The app checks for new data on launch when the last update is over 12 hours old, and every 6 hours while it's open.")
                .font(.caption).foregroundStyle(.secondary)
            if let d = store.latestDataDate {
                Text("Newest entry in the data: \(Format.date.string(from: d))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
