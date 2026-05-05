import SwiftUI

// MARK: - Therapy Report View
/// Displays the generated weekly report with an editable text area
/// and a "Share with therapist" button that exports as text/email.
struct TherapyReportView: View {
    @StateObject private var viewModel = TherapyReportViewModel()
    @State private var selectedTab: Tab = .current
    @State private var editedReportBody: String = ""
    @State private var showingShareSheet: Bool = false
    @State private var shareText: String = ""

    enum Tab: String, CaseIterable {
        case current = "Current"
        case history = "History"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("Tab", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if selectedTab == .current {
                currentReportView
            } else {
                historyView
            }
        }
        .navigationTitle("Weekly Summary")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { viewModel.load() }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [shareText])
        }
    }

    // MARK: - Current Report

    @ViewBuilder
    private var currentReportView: some View {
        if viewModel.isGenerating {
            generatingView
        } else if let report = viewModel.currentReport {
            reportContentView(report)
        } else {
            emptyReportView
        }
    }

    private var generatingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
            Text("Generating your report...")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("This may take a moment while Gemma analyzes your week.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }

    private var emptyReportView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No report yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Generate your first weekly therapy report.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                Task { await viewModel.generateReport() }
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Generate Report")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .cornerRadius(12)
            }
            .padding(.horizontal, 48)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.top, 48)
    }

    private func reportContentView(_ report: TherapyReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Report header
                reportHeader(report)

                Divider()

                // Editable report body
                reportBodyEditor(report)

                Divider()

                // Share button
                shareSection(report)
            }
            .padding(16)
        }
    }

    private func reportHeader(_ report: TherapyReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Week of \(report.weekRangeLabel)")
                        .font(.headline)

                    Text("Generated \(report.createdAt, style: .relative) ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if report.isShared {
                    Label("Shared", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            // Stats row
            HStack(spacing: 16) {
                StatPill(icon: "bolt.fill", value: "\(report.episodeCount)", label: report.episodeCountLabel, color: .orange)
                if let avgDuration = report.averageEpisodeDurationMinutes {
                    StatPill(icon: "clock", value: String(format: "%.0fm", avgDuration), label: "avg duration", color: .blue)
                }
                if let sleep = report.averageSleepHours {
                    StatPill(icon: "bed.double", value: String(format: "%.0fh", sleep), label: "avg sleep", color: .purple)
                }
            }
        }
    }

    private func reportBodyEditor(_ report: TherapyReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Report")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("Editable")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .cornerRadius(4)
            }

            TextEditor(text: $editedReportBody)
                .font(.body)
                .frame(minHeight: 200)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .onAppear { editedReportBody = report.gemmaReportBody }
                .onChange(of: report.id) { _, _ in
                    editedReportBody = report.gemmaReportBody
                }
        }
    }

    private func shareSection(_ report: TherapyReport) -> some View {
        VStack(spacing: 12) {
            Button {
                let text = buildShareText(report: report, body: editedReportBody)
                shareText = text
                showingShareSheet = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share with therapist")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .cornerRadius(12)
            }

            Text("Exports your report as text for email or messaging.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func buildShareText(report: TherapyReport, body: String) -> String {
        var text = "PanicGuard Weekly Therapy Report\n"
        text += "Week of \(report.weekRangeLabel)\n"
        text += "Generated: \(report.createdAt, style: .date)\n\n"
        text += "---\n"
        text += body
        text += "\n---\n"
        text += "\nEpisode count: \(report.episodeCount)"
        if let avgDuration = report.averageEpisodeDurationMinutes {
            text += String(format: "\nAverage episode duration: %.0f minutes", avgDuration)
        }
        if !report.dominantPatterns.isEmpty {
            text += "\nPatterns identified: \(report.dominantPatterns.joined(separator: ", "))"
        }
        return text
    }

    // MARK: - History

    private var historyView: some View {
        Group {
            if viewModel.reportHistory.isEmpty {
                emptyHistoryView
            } else {
                historyList
            }
        }
    }

    private var emptyHistoryView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No past reports")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Your generated reports will appear here.")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.top, 48)
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.reportHistory) { report in
                    HistoryReportCard(report: report) { updatedBody in
                        viewModel.updateReportBody(report.id, body: updatedBody)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Stat Pill

private struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - History Report Card

private struct HistoryReportCard: View {
    let report: TherapyReport
    let onUpdateBody: (String) -> Void

    @State private var isExpanded: Bool = false
    @State private var editedBody: String = ""
    @State private var hasChanges: Bool = false
    @State private var showingShareSheet: Bool = false
    @State private var shareText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.weekRangeLabel)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("\(report.episodeCountLabel) • \(report.createdAt, style: .date)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if report.isShared {
                    Label("Shared", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }

                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Summary preview
            Text(report.gemmaReportBody.prefix(150) + (report.gemmaReportBody.count > 150 ? "..." : ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(isExpanded ? nil : 2)

            if isExpanded {
                Divider()

                // Editable body
                TextEditor(text: $editedBody)
                    .font(.caption)
                    .frame(minHeight: 120)
                    .padding(6)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .onAppear {
                        editedBody = report.gemmaReportBody
                        hasChanges = false
                    }
                    .onChange(of: editedBody) { _, newValue in
                        hasChanges = newValue != report.gemmaReportBody
                    }

                // Action buttons
                HStack(spacing: 12) {
                    if hasChanges {
                        Button("Save changes") {
                            onUpdateBody(editedBody)
                            hasChanges = false
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }

                    Spacer()

                    Button {
                        var text = "PanicGuard Weekly Therapy Report\n"
                        text += "Week of \(report.weekRangeLabel)\n"
                        text += "---\n"
                        text += editedBody
                        text += "\n---\nEpisode count: \(report.episodeCount)"
                        shareText = text
                        showingShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [shareText])
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - View Model

@MainActor
final class TherapyReportViewModel: ObservableObject {
    @Published var currentReport: TherapyReport?
    @Published var reportHistory: [TherapyReport] = []
    @Published var isGenerating: Bool = false

    private let generator = GemmaTherapyReportGenerator()

    func load() {
        reportHistory = generator.reportHistory
        currentReport = generator.lastGeneratedReport
    }

    func generateReport() async {
        isGenerating = true
        await generator.generateWeeklyReport()
        currentReport = generator.lastGeneratedReport
        reportHistory = generator.reportHistory
        isGenerating = false
    }

    func updateReportBody(_ reportId: UUID, body: String) {
        guard var report = reportHistory.first(where: { $0.id == reportId }) else { return }
        report.gemmaReportBody = body

        // Persist to store
        let store = TherapyReportStore()
        try? store.update(report)

        // Update local state
        if let index = reportHistory.firstIndex(where: { $0.id == reportId }) {
            reportHistory[index] = report
        }
        if currentReport?.id == reportId {
            currentReport = report
        }
    }
}

#Preview {
    NavigationStack {
        TherapyReportView()
    }
}
