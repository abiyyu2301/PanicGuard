import Foundation
import AVFoundation

// MARK: - Intervention Service
final class InterventionService: ObservableObject {
    static let shared = InterventionService()

    @Published var isInterventionActive: Bool = false
    @Published var currentIntervention: InterventionType?
    @Published var interventionProgress: Double = 0.0

    private var speechSynthesizer: AVSpeechSynthesizer?
    private var timer: Timer?

    private init() {
        speechSynthesizer = AVSpeechSynthesizer()
    }

    // MARK: - Trigger Intervention
    @MainActor
    func triggerIntervention(_ type: InterventionType) {
        isInterventionActive = true
        currentIntervention = type
        interventionProgress = 0.0

        switch type {
        case .breathingExercise:
            performBreathingExercise()
        case .groundingPrompt:
            performGroundingPrompt()
        case .hapticRhythm:
            performHapticRhythm()
        case .checkIn:
            performCheckIn()
        case .escalate:
            // Escalation handled by EscalationService
            break
        case .dismiss:
            dismissIntervention()
        }
    }

    private func performBreathingExercise() {
        let script = "Breathe in for 4 seconds. Hold for 4 seconds. Breathe out for 4 seconds. Hold for 4 seconds."

        // TTS
        let utterance = AVSpeechUtterance(string: script)
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        speechSynthesizer?.speak(utterance)

        // Animation would update interventionProgress over 80 seconds
        startProgressTimer(duration: 80.0)
    }

    private func performGroundingPrompt() {
        let script = "Name five things you can see. Four things you can touch. Three things you can hear. Two things you can smell. One thing you can taste."

        let utterance = AVSpeechUtterance(string: script)
        utterance.rate = 0.5
        speechSynthesizer?.speak(utterance)

        startProgressTimer(duration: 60.0)
    }

    private func performHapticRhythm() {
        // In production: Send haptic pattern via WatchConnectivity
        // For MVP: Just log
        print("Haptic rhythm triggered")
        startProgressTimer(duration: 10.0)
    }

    private func performCheckIn() {
        let script = "Are you okay? If you need help, please respond."

        let utterance = AVSpeechUtterance(string: script)
        utterance.rate = 0.5
        speechSynthesizer?.speak(utterance)

        startProgressTimer(duration: 60.0)
    }

    private func startProgressTimer(duration: TimeInterval) {
        let steps = 100
        let interval = duration / Double(steps)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            DispatchQueue.main.async {
                self.interventionProgress += 1.0 / Double(steps)
                if self.interventionProgress >= 1.0 {
                    timer.invalidate()
                }
            }
        }
    }

    func dismissIntervention() {
        timer?.invalidate()
        speechSynthesizer?.stopSpeaking(at: .immediate)
        isInterventionActive = false
        currentIntervention = nil
        interventionProgress = 0.0
    }
}
