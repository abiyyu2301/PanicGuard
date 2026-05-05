import Foundation
import Combine

// MARK: - Panic Guard Coordinator
/// Wires HealthKit → DetectionEngine → GemmaService → InterventionService → EscalationService
/// into a complete panic detection and intervention pipeline per PRD Sections 4.1-4.4, 6.
final class PanicGuardCoordinator: ObservableObject {
    static let shared = PanicGuardCoordinator()

    // MARK: - Services
    private let healthKitService = HealthKitService.shared
    private let detectionEngine = DetectionEngine.shared
    private let gemmaService = GemmaService.shared
    private let interventionService = InterventionService.shared
    private let escalationService = EscalationService.shared
    private let episodeLogger = EpisodeLogger()

    // MARK: - Published State (bound to AppState)
    @Published var showIntervention: Bool = false
    @Published var currentIntervention: InterventionType?
    @Published var interventionProgress: Double = 0.0
    @Published var escalationActive: Bool = false

    // MARK: - Private State
    private var cancellables = Set<AnyCancellable>()
    private var episodeStartTime: Date?
    private var currentEpisodeId: UUID?
    private var isDemoMode: Bool = false

    // MARK: - Notification Observers
    private var panicEscalatedObserver: NSObjectProtocol?

    private init() {
        setupDetectionEngineObserver()
        setupInterventionServiceObserver()
    }

    deinit {
        if let observer = panicEscalatedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Start Pipeline
    func startMonitoring() {
        // 0. Enable background delivery (entitlements already configured)
        Task {
            await healthKitService.enableBackgroundDelivery()
        }

        // 1. Load Gemma model
        Task {
            await gemmaService.loadModel()
        }

        // 2. Listen for escalation events from DetectionEngine
        setupEscalationListener()

        // 3. Start HealthKit monitoring → DetectionEngine
        healthKitService.startMonitoring(
            onHeartRateUpdate: { [weak self] heartRate in
                self?.handleHeartRateUpdate(heartRate)
            },
            onHRVUpdate: { [weak self] hrv in
                self?.handleHRVUpdate(hrv)
            }
        )
    }

    func stopMonitoring() {
        healthKitService.stopMonitoring()
        detectionEngine.reset()
        interventionService.dismissIntervention()
        escalationActive = false
    }

    // MARK: - Demo Mode
    func startDemo() {
        isDemoMode = true
        let demoService = DemoService.shared

        demoService.runDemo(
            onHeartRateUpdate: { [weak self] heartRate in
                self?.handleHeartRateUpdate(heartRate)
            },
            onHRVUpdate: { [weak self] hrv in
                self?.handleHRVUpdate(hrv)
            },
            onPhaseChange: { phase in
                print("Demo phase: \(phase.rawValue)")
            },
            onComplete: { [weak self] in
                self?.isDemoMode = false
            }
        )
    }

    func stopDemo() {
        isDemoMode = false
        DemoService.shared.stopDemo()
    }

    // MARK: - Sensor Data Handlers
    private func handleHeartRateUpdate(_ heartRate: Double) {
        guard let hrv = healthKitService.latestHRV else { return }
        detectionEngine.processSensorData(heartRate: heartRate, hrv: hrv)
    }

    private func handleHRVUpdate(_ hrv: Double) {
        guard let heartRate = healthKitService.latestHeartRate else { return }
        detectionEngine.processSensorData(heartRate: heartRate, hrv: hrv)
    }

    // MARK: - Detection Engine Observer
    private func setupDetectionEngineObserver() {
        detectionEngine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleDetectionStateChange(state)
            }
            .store(in: &cancellables)
    }

    private func handleDetectionStateChange(_ state: DetectionState) {
        switch state {
        case .panicDetected(let confidence):
            triggerInterventionPipeline(confidence: confidence)

        case .signalElevated(let confidence):
            // Signal elevated but not yet confirmed - could show subtle UI hint
            print("Signal elevated: \(confidence)")

        case .monitoring, .idle, .interventionActive, .escalationActive:
            break
        }
    }

    // MARK: - Intervention Pipeline
    /// 4. Coordinator calls GemmaService.makeDecision()
    /// 5. GemmaService decision → InterventionService.triggerIntervention(type)
    private func triggerInterventionPipeline(confidence: Double) {
        let heartRate = healthKitService.latestHeartRate ?? 0
        let hrv = healthKitService.latestHRV ?? 0

        // Start episode tracking
        episodeStartTime = Date()
        currentEpisodeId = UUID()

        // Gemma decision
        let decision = gemmaService.makeDecision(
            confidence: confidence,
            heartRate: heartRate,
            hrv: hrv
        )

        // If Gemma says dismiss, don't intervene
        if decision == .dismiss {
            print("Gemma decision: dismiss")
            return
        }

        // Trigger intervention
        Task { @MainActor in
            self.interventionService.triggerIntervention(decision)
            self.currentIntervention = decision
            self.showIntervention = true
            self.interventionProgress = 0.0
        }
    }

    // MARK: - Intervention Service Observer
    private func setupInterventionServiceObserver() {
        interventionService.$isInterventionActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                if !isActive {
                    self?.handleInterventionDismissed()
                }
            }
            .store(in: &cancellables)

        interventionService.$interventionProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.interventionProgress = progress
            }
            .store(in: &cancellables)
    }

    private func handleInterventionDismissed() {
        // 9. User dismissed → EpisodeLogger.insert()
        showIntervention = false
        currentIntervention = nil
        interventionProgress = 0.0

        if let episodeId = currentEpisodeId, let startTime = episodeStartTime {
            let episode = EpisodeLogger.Episode(
                id: episodeId,
                detectedAt: startTime,
                confidence: detectionEngine.currentConfidence,
                resolvedAs: .userDismissed,
                escalationTriggered: false,
                contactNotified: false,
                episodeDuration: Date().timeIntervalSince(startTime)
            )
            try? episodeLogger.insert(episode)
        }

        // Reset detection engine
        detectionEngine.dismissPanic()
        currentEpisodeId = nil
        episodeStartTime = nil
    }

    // MARK: - Escalation Listener
    private func setupEscalationListener() {
        // 7. 5-minute escalation timer fires → check consent setting
        panicEscalatedObserver = NotificationCenter.default.addObserver(
            forName: DetectionEngine.panicEscalatedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleEscalation(notification)
        }
    }

    private func handleEscalation(_ notification: Notification) {
        escalationActive = true

        // Get emergency contact from UserDefaults
        guard let contactData = UserDefaults.standard.data(forKey: "emergencyContact"),
              let contact = try? JSONDecoder().decode(EmergencyContact.self, from: contactData) else {
            print("No emergency contact configured")
            return
        }

        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? "User"
        let episodeId = currentEpisodeId ?? UUID()

        // Check auto-escalate setting
        let autoEscalate = UserDefaults.standard.bool(forKey: "autoEscalate")
        if !autoEscalate {
            // Show confirmation prompt instead of auto-sending
            // Store pending escalation data on AppState
            DispatchQueue.main.async {
                self.appStateForPrompt?.showEscalationPrompt = true
                self.appStateForPrompt?.pendingEscalationContact = contact
                self.appStateForPrompt?.pendingEscalationEpisodeId = episodeId
                self.appStateForPrompt?.pendingEscalationUserFirstName = userFirstName
            }
            return
        }

        // Auto-escalate ON: proceed immediately
        Task { @MainActor in
            let success = await escalationService.escalate(
                contact: contact,
                userFirstName: userFirstName,
                episodeId: episodeId
            )

            if success {
                // Log escalated episode
                if let startTime = episodeStartTime {
                    let episode = EpisodeLogger.Episode(
                        id: episodeId,
                        detectedAt: startTime,
                        confidence: detectionEngine.currentConfidence,
                        resolvedAs: .escalated,
                        escalationTriggered: true,
                        contactNotified: true,
                        episodeDuration: Date().timeIntervalSince(startTime)
                    )
                    try? episodeLogger.insert(episode)
                }

                // Trigger escalate intervention
                await interventionService.triggerIntervention(.escalate)
            }
        }
    }

    /// Executes a pending escalation after user confirms. Called by AppState.
    @MainActor
    func confirmPendingEscalation() async {
        guard let contact = appStateForPrompt?.pendingEscalationContact,
              let episodeId = appStateForPrompt?.pendingEscalationEpisodeId else {
            return
        }
        let userFirstName = appStateForPrompt?.pendingEscalationUserFirstName ?? "User"

        clearPendingEscalation()

        let success = await escalationService.escalate(
            contact: contact,
            userFirstName: userFirstName,
            episodeId: episodeId
        )

        if success {
            // Log escalated episode
            if let startTime = episodeStartTime {
                let episode = EpisodeLogger.Episode(
                    id: episodeId,
                    detectedAt: startTime,
                    confidence: detectionEngine.currentConfidence,
                    resolvedAs: .escalated,
                    escalationTriggered: true,
                    contactNotified: true,
                    episodeDuration: Date().timeIntervalSince(startTime)
                )
                try? episodeLogger.insert(episode)
            }

            // Trigger escalate intervention
            await interventionService.triggerIntervention(.escalate)
        }
    }

    /// Cancels a pending escalation after user dismisses the prompt. Called by AppState.
    func cancelPendingEscalation() {
        if let episodeId = appStateForPrompt?.pendingEscalationEpisodeId {
            _ = escalationService.cancelEscalation(episodeId: episodeId)
        }
        clearPendingEscalation()
        escalationActive = false
    }

    private func clearPendingEscalation() {
        appStateForPrompt?.showEscalationPrompt = false
        appStateForPrompt?.pendingEscalationContact = nil
        appStateForPrompt?.pendingEscalationEpisodeId = nil
        appStateForPrompt?.pendingEscalationUserFirstName = "User"
    }

    /// Reference to AppState for prompt coordination (set during bindFromAppState)
    private weak var appStateForPrompt: AppState?

    // MARK: - Manual Escalation
    func triggerManualEscalation() {
        guard let episodeId = currentEpisodeId else { return }

        guard let contactData = UserDefaults.standard.data(forKey: "emergencyContact"),
              let contact = try? JSONDecoder().decode(EmergencyContact.self, from: contactData) else {
            return
        }

        let userFirstName = UserDefaults.standard.string(forKey: "userFirstName") ?? "User"

        Task { @MainActor in
            _ = await escalationService.escalate(
                contact: contact,
                userFirstName: userFirstName,
                episodeId: episodeId
            )
        }
    }

    // MARK: - Sync with AppState
    func syncToAppState(_ appState: AppState) {
        appState.showIntervention = showIntervention
        appState.currentIntervention = currentIntervention
        appState.interventionProgress = interventionProgress
        appState.escalationActive = escalationActive
    }

    func bindFromAppState(_ appState: AppState) {
        // Observe AppState changes if needed
        appState.$isMonitoring
            .sink { [weak self] isMonitoring in
                if isMonitoring {
                    self?.startMonitoring()
                } else {
                    self?.stopMonitoring()
                }
            }
            .store(in: &cancellables)
        // Store reference for escalation prompt coordination
        appStateForPrompt = appState
    }
}
