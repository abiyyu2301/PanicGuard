import SwiftUI

// MARK: - Journal View
/// Daily companion journal tab — free-text entry, emotional tags,
/// attach-to-episode toggle, Gemma response display, scrollable history.
struct JournalView: View {
    @StateObject private var viewModel = JournalViewModel()
    @State private var journalText: String = ""
    @State private var selectedTags: Set<EmotionalTag> = []
    @State private var attachToEpisode: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Input section
            inputSection
                .padding(.horizontal, 16)
                .padding(.top, 16)

            Divider()
                .padding(.top, 12)

            // Gemma response
            if let response = viewModel.gemmaResponse {
                gemmaResponseSection(response)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            // History
            historySection
        }
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Free-text field
            TextField("How are you feeling today?", text: $journalText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .lineLimit(3...8)

            // Emotional tags
            HStack(spacing: 8) {
                ForEach(EmotionalTag.allCases, id: \.self) { tag in
                    TagChip(
                        tag: tag,
                        isSelected: selectedTags.contains(tag)
                    ) {
                        if selectedTags.contains(tag) {
                            selectedTags.remove(tag)
                        } else {
                            selectedTags.insert(tag)
                        }
                    }
                }
                Spacer()
            }

            // Attach to episode toggle
            if viewModel.lastEpisodeId != nil {
                Toggle(isOn: $attachToEpisode) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.caption)
                        Text("Attach to last episode")
                            .font(.subheadline)
                    }
                    .foregroundColor(.secondary)
                }
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            }

            // Submit button
            Button {
                Task {
                    await viewModel.submitEntry(
                        content: journalText,
                        tags: Array(selectedTags),
                        attachToEpisode: attachToEpisode
                    )
                    journalText = ""
                    selectedTags = []
                    attachToEpisode = false
                }
            } label: {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Share with Gemma")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(journalText.isEmpty ? Color.gray : Color.accentColor)
                .cornerRadius(12)
            }
            .disabled(journalText.isEmpty || viewModel.isLoading)
        }
    }

    // MARK: - Gemma Response Section

    private func gemmaResponseSection(_ response: GemmaJournalResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentColor)
                Text("Gemma")
                    .font(.headline)
                Spacer()
                Text(response.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let summary = response.summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !response.insights.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(response.insights, id: \.self) { insight in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                            Text(insight)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            if viewModel.history.isEmpty {
                emptyHistoryView
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.history) { entry in
                            JournalHistoryCard(entry: entry)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var emptyHistoryView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No journal entries yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Your entries will appear here after you share them with Gemma.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }
}

// MARK: - Tag Chip

private struct TagChip: View {
    let tag: EmotionalTag
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(tag.emoji)
                    .font(.caption)
                Text(tag.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? tagColor.opacity(0.2) : Color(.systemGray5))
            .foregroundColor(isSelected ? tagColor : .secondary)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? tagColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var tagColor: Color {
        switch tag {
        case .anxious:  return .red
        case .stressed: return .orange
        case .okay:     return .gray
        case .calm:     return .green
        }
    }
}

// MARK: - Journal History Card

private struct JournalHistoryCard: View {
    let entry: EpisodeLogger.JournalEntry
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                Text(entry.timestamp, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !entry.emotionalTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(entry.emotionalTags, id: \.self) { tagString in
                            if let tag = EmotionalTag(rawValue: tagString) {
                                Text(tag.emoji)
                                    .font(.caption2)
                            }
                        }
                    }
                }

                Spacer()

                if entry.linkedEpisodeId != nil {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }

                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Content
            Text(entry.content)
                .font(.subheadline)
                .lineLimit(isExpanded ? nil : 2)

            // Gemma summary (if present)
            if let summary = entry.gemmaSummary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                        Text("Gemma")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                    }
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.accentColor.opacity(0.06))
                .cornerRadius(8)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Emotional Tag (View-layer enum for UI selection)

enum EmotionalTag: String, CaseIterable {
    case anxious
    case stressed
    case okay
    case calm

    var displayName: String {
        rawValue.capitalized
    }

    var emoji: String {
        switch self {
        case .anxious: return "😰"
        case .stressed: return "😣"
        case .okay: return "😐"
        case .calm: return "😌"
        }
    }

    init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "anxious": self = .anxious
        case "stressed": self = .stressed
        case "okay": self = .okay
        case "calm": self = .calm
        default: return nil
        }
    }
}

// MARK: - Gemma Journal Response

struct GemmaJournalResponse {
    let summary: String?
    let insights: [String]
    let timestamp: Date
}

// MARK: - Journal View Model

@MainActor
final class JournalViewModel: ObservableObject {
    @Published var history: [EpisodeLogger.JournalEntry] = []
    @Published var gemmaResponse: GemmaJournalResponse?
    @Published var isLoading: Bool = false

    private let episodeLogger = EpisodeLogger()
    private let correlator = GemmaJournalCorrelator()

    /// ID of the most recent panic episode (for attach-to-episode toggle)
    var lastEpisodeId: UUID? {
        let episodes = (try? episodeLogger.queryRecentEpisodes(hours: 24)) ?? []
        return episodes.first?.id
    }

    init() {
        loadHistory()
    }

    func loadHistory() {
        history = (try? episodeLogger.queryAllJournalEntries()) ?? []
    }

    func submitEntry(content: String, tags: [EmotionalTag], attachToEpisode: Bool) async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isLoading = true
        gemmaResponse = nil

        let entry = EpisodeLogger.JournalEntry(
            id: UUID(),
            timestamp: Date(),
            content: content,
            emotionalTags: tags.map { $0.rawValue },
            linkedEpisodeId: attachToEpisode ? lastEpisodeId : nil,
            gemmaSummary: nil,
            gemmaInsights: []
        )

        // Save to local store
        try? episodeLogger.insert(entry)

        // Run Gemma correlation analysis
        let (summary, insights) = await correlator.analyzeJournalEntry(entry)

        // Update entry with Gemma's analysis
        var annotatedEntry = entry
        annotatedEntry.gemmaSummary = summary
        annotatedEntry.gemmaInsights = insights

        // Re-save with Gemma data
        try? episodeLogger.insert(annotatedEntry)

        // Show response
        gemmaResponse = GemmaJournalResponse(
            summary: summary,
            insights: insights,
            timestamp: Date()
        )

        loadHistory()
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        JournalView()
    }
}
