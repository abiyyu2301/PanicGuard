import SwiftUI

@main
struct PanicGuardApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App State
final class AppState: ObservableObject {
    @Published var isMonitoring: Bool = false
    @Published var currentHeartRate: Double?
    @Published var currentHRV: Double?
    @Published var showOnboarding: Bool

    // Intervention state (wired from PanicGuardCoordinator)
    @Published var showIntervention: Bool = false
    @Published var currentIntervention: InterventionType?
    @Published var interventionProgress: Double = 0.0
    @Published var escalationActive: Bool = false

    // Escalation confirmation prompt state
    @Published var showEscalationPrompt: Bool = false
    @Published var pendingEscalationContact: EmergencyContact?
    @Published var pendingEscalationEpisodeId: UUID?
    @Published var pendingEscalationUserFirstName: String = "User"

    // Daily companion state
    @Published var hasNewPatterns: Bool = false  // Gemma found new trigger patterns
    @Published var weeklySummaryReady: Bool = false  // Therapy report generated

    // Navigation destination for companion screens
    enum CompanionDestination: Hashable {
        case journal
        case patterns
        case weeklySummary
    }
    @Published var companionDestination: CompanionDestination? = nil

    private let coordinator = PanicGuardCoordinator.shared

    init() {
        self.showOnboarding = !UserDefaults.standard.bool(forKey: "onboardingCompleted")
        bindCoordinator()
        coordinator.bindFromAppState(self)
    }

    private func bindCoordinator() {
        coordinator.$showIntervention
            .assign(to: &$showIntervention)
        coordinator.$currentIntervention
            .assign(to: &$currentIntervention)
        coordinator.$interventionProgress
            .assign(to: &$interventionProgress)
        coordinator.$escalationActive
            .assign(to: &$escalationActive)
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        showOnboarding = false
        isMonitoring = true
        coordinator.startMonitoring()
    }

    func startDemo() {
        coordinator.startDemo()
    }

    func stopDemo() {
        coordinator.stopDemo()
    }

    // MARK: - Escalation Prompt Actions
    func confirmEscalation() {
        Task { @MainActor in
            await coordinator.confirmPendingEscalation()
        }
    }

    func cancelEscalation() {
        coordinator.cancelPendingEscalation()
    }
}

// MARK: - Content View (Router)
struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            if appState.showOnboarding {
                OnboardingView()
            } else {
                HomeView()
            }

            // Intervention overlay (presented modally over all content)
            if appState.showIntervention {
                InterventionOverlayView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .navigationDestination(for: AppState.CompanionDestination.self) { destination in
            switch destination {
            case .journal:
                JournalView()
            case .patterns:
                TriggerCorrelationView()
            case .weeklySummary:
                TherapyReportView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.showIntervention)
        .alert("Notify Emergency Contact?", isPresented: $appState.showEscalationPrompt) {
            Button("Cancel", role: .cancel) {
                appState.cancelEscalation()
            }
            Button("Send SMS", role: .destructive) {
                appState.confirmEscalation()
            }
        } message: {
            if let contact = appState.pendingEscalationContact {
                Text("I'm about to notify \(contact.name) (\(contact.relationship)) that you may need help. Do you want to send the emergency SMS?")
            } else {
                Text("I'm about to notify your emergency contact that you may need help. Do you want to send the emergency SMS?")
            }
        }
    }
}
