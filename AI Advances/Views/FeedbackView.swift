import SwiftUI

struct FeedbackView: View {
    static let issuesURL = "https://github.com/amalmehta/ai-advances/issues/new"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var kind = "Idea"
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Feedback").font(.title2.weight(.semibold))
            Text("What's missing, wrong, or confusing? This opens a pre-filled GitHub issue you can review before posting.")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Type", selection: $kind) {
                ForEach(["Idea", "Bug", "Data looks wrong"], id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.grid))
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("[\(kind)] \(text)", forType: .string)
                }
                .disabled(text.isEmpty)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Open GitHub Issue") {
                    if let url = issueURL { openURL(url) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var issueURL: URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        var c = URLComponents(string: Self.issuesURL)
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
        c?.queryItems = [
            URLQueryItem(name: "title", value: "[\(kind)] \(firstLine.prefix(70))"),
            URLQueryItem(name: "body", value: "\(text)\n\n---\nAI Advances \(version), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"),
        ]
        return c?.url
    }
}
