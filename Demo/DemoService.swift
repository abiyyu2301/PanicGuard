import Foundation
import Combine

// MARK: - Demo Service
final class DemoService: ObservableObject {
    static let shared = DemoService()

    @Published var isRunning: Bool = false
    @Published var currentPhase: DemoPhase = .resting
    @Published var simulatedHeartRate: Double = 72.0
    @Published var simulatedHRV: Double = 45.0

    private var timer: Timer?
    private var phaseIndex: Int = 0

    private init() {}

    // MARK: - Demo Phases
    enum DemoPhase: String, CaseIterable {
        case resting = "Resting"
        case onset = "Onset"
        case panicConfirmed = "Panic Confirmed"
        case breathingExercise = "Breathing Exercise"
        case resolution = "Resolution"
    }

    // MARK: - Run Demo
    func runDemo(
        onHeartRateUpdate: @escaping (Double) -> Void,
        onHRVUpdate: @escaping (Double) -> Void,
        onPhaseChange: @escaping (DemoPhase) -> Void,
        onComplete: @escaping () -> Void
    ) {
        isRunning = true
        phaseIndex = 0

        let phases: [(DemoPhase, TimeInterval, Double, Double, Double, Double)] = [
            // (phase, duration, startHR, endHR, startHRV, endHRV)
            (.resting, 30, 72, 72, 45, 45),
            (.onset, 60, 72, 108, 45, 32),
            (.panicConfirmed, 5, 108, 108, 32, 30),
            (.breathingExercise, 80, 108, 90, 30, 38),
            (.resolution, 30, 90, 72, 38, 45)
        ]

        func runPhase(index: Int) {
            guard index < phases.count, isRunning else {
                isRunning = false
                onComplete()
                return
            }

            let (phase, duration, startHR, endHR, startHRV, endHRV) = phases[index]
            currentPhase = phase
            onPhaseChange(phase)

            let steps = Int(duration)
            let hrStep = (endHR - startHR) / Double(steps)
            let hrvStep = (endHRV - startHRV) / Double(steps)

            var currentStep = 0
            simulatedHeartRate = startHR
            simulatedHRV = startHRV

            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self, self.isRunning else {
                    timer.invalidate()
                    return
                }

                currentStep += 1
                self.simulatedHeartRate = startHR + (hrStep * Double(currentStep))
                self.simulatedHRV = startHRV + (hrvStep * Double(currentStep))

                onHeartRateUpdate(self.simulatedHeartRate)
                onHRVUpdate(self.simulatedHRV)

                if currentStep >= steps {
                    timer.invalidate()
                    self.phaseIndex = index + 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        runPhase(index: index + 1)
                    }
                }
            }
        }

        runPhase(index: 0)
    }

    func stopDemo() {
        isRunning = false
        timer?.invalidate()
        currentPhase = .resting
        simulatedHeartRate = 72.0
        simulatedHRV = 45.0
    }
}
