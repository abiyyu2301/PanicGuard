import SwiftUI

// MARK: - TriggerCorrelation PatternType Extension
extension EpisodeLogger.TriggerCorrelation.PatternType {
    var displayName: String {
        switch self {
        case .timeOfDay:    return "Time of Day"
        case .calendarEvent: return "Calendar Event"
        case .sleepDebt:    return "Sleep Debt"
        case .journalTheme: return "Journal Theme"
        case .exerciseContext: return "Exercise Context"
        case .none:         return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .timeOfDay:    return "clock.fill"
        case .calendarEvent: return "calendar.badge.exclamationmark"
        case .sleepDebt:    return "moon.zzz.fill"
        case .journalTheme: return "book.fill"
        case .exerciseContext: return "figure.run"
        case .none:         return "questionmark.circle"
        }
    }

    var confidenceLabel: String {
        switch self {
        case .timeOfDay:    return "Time"
        case .calendarEvent: return "Calendar"
        case .sleepDebt:    return "Sleep"
        case .journalTheme: return "Journal"
        case .exerciseContext: return "Exercise"
        case .none:         return "Unknown"
        }
    }
}

extension EpisodeLogger.TriggerCorrelation {
    var confidenceLabel: String {
        switch confidence {
        case 0.8...: return "High"
        case 0.5..<0.8: return "Moderate"
        default: return "Low"
        }
    }
}

// MARK: - Trigger Correlation View
/// Shows all TriggerCorrelation records with active vs. inactive tabs,
/// "Help me understand this" → Gemma explains the pattern,
/// and a toggle to disable a pattern.
struct TriggerCorrelationView: View {
    @StateObject private var viewModel = TriggerCorrelationViewModel()
    @State private var selectedTab: Tab = .active

    enum Tab: String, CaseIterable {
        case active = "Active"
        case inactive = "Inactive"
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

            // Content
            if filteredCorrelations.isEmpty {
                emptyStateView
            } else {
                correlationsList
            }
        }
        .navigationTitle("Trigger Patterns")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { viewModel.load() }
    }

    private var filteredCorrelations: [EpisodeLogger.TriggerCorrelation] {
        switch selectedTab {
        case .active:   return viewModel.activeCorrelations
        case .inactive: return viewModel.inactiveCorrelations
        }
    }

    // MARK: - Correlations List

    private var correlationsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredCorrelations) { correlation in
                    CorrelationCard(
                        correlation: correlation,
                        explanation: viewModel.explanations[correlation.id],
                        isLoadingExplanation: viewModel.loadingExplanations[correlation.id] ?? false,
                        onExplain: { viewModel.requestExplanation(for: correlation) },
                        onToggleActive: { viewModel.toggleActive(for: correlation) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: selectedTab == .active ? "sparkles" : "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(selectedTab == .active ? "No active patterns yet" : "No inactive patterns")
                .font(.headline)
                .foregroundColor(.secondary)
            Text(selectedTab == .active
                 ? "Gemma analyzes your episode history to find patterns. Keep logging and check back soon."
                 : "Patterns you disable will appear here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .padding(.top, 48)
    }
}

// MARK: - Correlation Card

private struct CorrelationCard: View {
    let correlation: EpisodeLogger.TriggerCorrelation
    let explanation: String?
    let isLoadingExplanation: Bool
    let onExplain: () -> Void
    let onToggleActive: () -> Void

    @State private var showExplanation: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(alignment: .top) {
                // Pattern type icon
                Image(systemName: correlation.patternType.icon)
                    .font(.title3)
                    .foregroundColor(colorForType(correlation.patternType))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(correlation.patternType.displayName)
                        .font(.headline)

                    Text(correlation.patternDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Confidence badge
                ConfidenceBadge(confidence: correlation.confidence)
            }

            // Supporting details
            Text(correlation.supportingDetails)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(showExplanation ? nil : 2)

            // Footer row
            HStack {
                // Episode count
                Label("\(correlation.episodeCount) episodes", systemImage: "bolt.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                // Help me understand button
                Button {
                    if explanation != nil {
                        withAnimation { showExplanation.toggle() }
                    } else {
                        onExplain()
                        showExplanation = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isLoadingExplanation {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "questionmark.circle")
                        }
                        Text(explanation == nil ? "Help me understand this" : (showExplanation ? "Hide explanation" : "Show explanation"))
                            .font(.caption)
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }

            // Explanation text
            if showExplanation, let explanation = explanation {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        Text(explanation)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }
            }

            Divider()

            // Toggle active / inactive
            Toggle(isOn: Binding(
                get: { correlation.isActive },
                set: { _ in onToggleActive() }
            )) {
                Text(correlation.isActive ? "Pattern active" : "Pattern disabled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
        }
        .padding(14)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func colorForType(_ type: EpisodeLogger.TriggerCorrelation.PatternType) -> Color {
        switch type {
        case .timeOfDay:    return .blue
        case .calendarEvent: return .purple
        case .sleepDebt:    return .indigo
        case .journalTheme: return .orange
        case .exerciseContext: return .green
        case .none:         return .gray
        }
    }
}

// MARK: - Confidence Badge

private struct ConfidenceBadge: View {
    let confidence: Double

    var body: some View {
        Text(confidenceLabel)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(colorForConfidence)
            .cornerRadius(8)
    }

    private var confidenceLabel: String {
        switch confidence {
        case 0.8...: return "High"
        case 0.5..<0.8: return "Moderate"
        default: return "Low"
        }
    }

    private var colorForConfidence: Color {
        switch confidence {
        case 0.8...: return .green
        case 0.5..<0.8: return .orange
        default: return .gray
        }
    }
}

// MARK: - View Model

@MainActor
final class TriggerCorrelationViewModel: ObservableObject {
    @Published var activeCorrelations: [EpisodeLogger.TriggerCorrelation] = []
    @Published var inactiveCorrelations: [EpisodeLogger.TriggerCorrelation] = []
    @Published var explanations: [UUID: String] = [:]
    @Published var loadingExplanations: [UUID: Bool] = [:]

    private let episodeLogger = EpisodeLogger()
    private let gemmaService = GemmaService.shared

    func load() {
        activeCorrelations = (try? episodeLogger.queryActiveTriggerCorrelations()) ?? []
        inactiveCorrelations = (try? episodeLogger.queryAllTriggerCorrelations())?.filter { !$0.isActive } ?? []
    }

    func requestExplanation(for correlation: EpisodeLogger.TriggerCorrelation) {
        loadingExplanations[correlation.id] = true

        Task {
            let explanation = await gemmaService.explainPattern(correlation)
            explanations[correlation.id] = explanation
            loadingExplanations[correlation.id] = false
        }
    }

    func toggleActive(for correlation: EpisodeLogger.TriggerCorrelation) {
        let newValue = !correlation.isActive
        var updated = correlation
        // Rebuild with isActive flipped using the initializer (TriggerCorrelation has let properties)
        let toggled = EpisodeLogger.TriggerCorrelation(
            id: correlation.id,
            patternType: correlation.patternType,
            patternDescription: correlation.patternDescription,
            confidence: correlation.confidence,
            episodeCount: correlation.episodeCount,
            supportingDetails: correlation.supportingDetails,
            lastUpdated: correlation.lastUpdated,
            isActive: newValue
        )
        try? episodeLogger.updateTriggerCorrelation(toggled)

        // Refresh lists
        if newValue {
            // Move from inactive to active
            inactiveCorrelations.removeAll { $0.id == correlation.id }
            activeCorrelations.append(toggled)
            activeCorrelations.sort { $0.confidence > $1.confidence }
        } else {
            // Move from active to inactive
            activeCorrelations.removeAll { $0.id == correlation.id }
            inactiveCorrelations.append(toggled)
        }
    }
}

#Preview {
    NavigationStack {
        TriggerCorrelationView()
    }
}
