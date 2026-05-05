import Foundation
import Combine
import CoreML

// MARK: - Detection Engine
/// Panic attack detection engine using Random Forest CoreML inference.
/// HRVFeatureExtractor computes the RF input features (RMSSD, SDNN, HR mean/std).
/// Threshold logic replaced with RF inference per APP_AUDIT.md C3.
/// Random Forest output: panic_confidence ≥ 0.85 → crisis, 0.6–0.85 → elevated check-in.
final class DetectionEngine: ObservableObject {
    static let shared = DetectionEngine()

    // MARK: - Published State
    @Published var state: DetectionState = .idle
    @Published var currentConfidence: Double = 0.0
    @Published var isExercising: Bool = false

    // MARK: - HRV Feature Extractor (computes RF input features)
    let hrvExtractor = HRVFeatureExtractor(windowSize: 300)

    // MARK: - Random Forest Model
    /// CoreML model loaded from bundled PanicGuardRF.mlpackage.
    /// Lazily initialized on first use; falls back to rule-based if unavailable.
    private var rfModel: PanicGuardRF?
    private let rfQueue = DispatchQueue(label: "com.panicguard.rf.inference", qos: .userInteractive)
    private let modelLoadQueue = DispatchQueue(label: "com.panicguard.rf.load", qos: .utility)

    // MARK: - Baseline Properties
    @Published private(set) var baselineHeartRate: Double = 70.0
    @Published private(set) var baselineRMSSD: Double = 45.0
    @Published private(set) var baselineSDNN: Double = 65.0

    // MARK: - Rolling Buffers
    private var rollingHRBuffer: [(timestamp: Date, value: Double)] = []
    private var rollingRMSSDBuffer: [(timestamp: Date, value: Double)] = []
    private var rollingSDNNBuffer: [(timestamp: Date, value: Double)] = []
    private let bufferDuration: TimeInterval = 120.0 // 2-minute window for detection

    // MARK: - Panic Onset Tracking (30-second sustained signal rule)
    private var panicOnsetTimer: Date?
    private let requiredPanicDuration: TimeInterval = 30.0

    // MARK: - Escalation Timer (5-minute rule)
    private var escalationTimer: Timer?
    private var firstPanicDetectedAt: Date?
    private let escalationTimeout: TimeInterval = 300.0 // 5 minutes

    // MARK: - Exercise False-Positive Suppression
    private var exerciseContextActive: Bool = false
    private var exerciseRecoveryTimer: Date?
    private let exerciseRecoveryWindow: TimeInterval = 120.0 // 2-min recovery = not panic

    // MARK: - Workout Session Tracking (HealthKit)
    private var activeWorkoutStartTime: Date?
    private var workoutAdjustedThresholds: Bool = false

    // MARK: - HealthKit Integration
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Notifications
    static let panicEscalatedNotification = Notification.Name("PanicGuardPanicEscalated")
    static let panicDetectedNotification = Notification.Name("PanicGuardPanicDetected")

    // MARK: - User Settings
    var userAge: Int = 30 {
        didSet {
            hrvExtractor.userAge = userAge
        }
    }

    /// Hours slept last night — from HealthKit or manual entry.
    /// Used as RF feature input. Defaults to population average.
    var sleepHoursLastNight: Double = 7.0

    enum DetectionSensitivity: String, CaseIterable {
        case low, moderate, high
    }
    var detectionSensitivity: DetectionSensitivity = .moderate

    // MARK: - Init
    private init() {
        loadBaseline()
        setupWorkoutObserver()
        loadRFModelAsync()
    }

    // MARK: - RF Model Loading
    /// Loads PanicGuardRF.mlpackage from the app bundle asynchronously.
    /// Safe to call multiple times; only loads once.
    private func loadRFModelAsync() {
        modelLoadQueue.async { [weak self] in
            self?.loadRFModel()
        }
    }

    private func loadRFModel() {
        guard rfModel == nil else { return }

        // PanicGuardRF.mlpackage is bundled in the Detection folder
        // Try to locate it in the main bundle
        guard let modelURL = Bundle.main.url(forResource: "PanicGuardRF", withExtension: "mlpackage") else {
            print("[DetectionEngine] PanicGuardRF.mlpackage not found in bundle — RF inference unavailable")
            return
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all // CPU + Apple Neural Engine for fast inference

        do {
            rfModel = try PanicGuardRF(contentsOf: modelURL, configuration: config)
            print("[DetectionEngine] PanicGuardRF model loaded successfully")
        } catch {
            print("[DetectionEngine] Failed to load PanicGuardRF: \(error.localizedDescription)")
            rfModel = nil
        }
    }

    // MARK: - RF Feature Vector
    /// Feature vector matching the PanicGuardRF training schema from APP_AUDIT.md C3.
    /// WESAD features per 30-second window: RMSSD, SDNN, HR_mean, HR_std,
    /// LF/HF_ratio, age_group, time_of_day, sleep_hours
    struct RFFeatureVector {
        let rmssd: Float
        let sdnn: Float
        let hrMean: Float
        let hrStd: Float
        let lfHfRatio: Float
        let ageGroup: Int   // 0 = 18-30, 1 = 31-45, 2 = 46+
        let timeOfDay: Int  // 0 = night (0-5h), 1 = morning (6-11h), 2 = afternoon (12-17h), 3 = evening (18-23h)
        let sleepHours: Float
    }

    /// Builds the RF feature vector from current HRV extractor state.
    private func buildFeatureVector() -> RFFeatureVector {
        let rmssd = Float(hrvExtractor.currentRMSSD)
        let sdnn = Float(hrvExtractor.currentSDNN)
        let hrMean = Float(hrvExtractor.currentHRMean)

        // HR standard deviation from rolling buffer
        let hrStd = computeHRStd()

        // LF/HF ratio — estimated from RMSSD/SDNN ratio as a proxy
        // (Actual LF/HF requires frequency-domain analysis; RF trained on this approximation)
        let lfHfRatio = sdnn > 0 ? Float(rmssd / sdnn) : 0.5

        // Age group encoding (matching training: 0=18-30, 1=31-45, 2=46+)
        let ageGroup: Int
        switch userAge {
        case 18...30:  ageGroup = 0
        case 31...45:  ageGroup = 1
        default:       ageGroup = 2
        }

        // Time of day encoding (0=night, 1=morning, 2=afternoon, 3=evening)
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: Int
        switch hour {
        case 0...5:  timeOfDay = 0
        case 6...11: timeOfDay = 1
        case 12...17: timeOfDay = 2
        default:     timeOfDay = 3
        }

        return RFFeatureVector(
            rmssd: rmssd,
            sdnn: sdnn,
            hrMean: hrMean,
            hrStd: hrStd,
            lfHfRatio: lfHfRatio,
            ageGroup: ageGroup,
            timeOfDay: timeOfDay,
            sleepHours: Float(sleepHoursLastNight)
        )
    }

    /// Computes HR standard deviation from the rolling HR buffer.
    private func computeHRStd() -> Float {
        guard !rollingHRBuffer.isEmpty else { return 0.0 }
        let values = rollingHRBuffer.map { $0.value }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return Float(sqrt(variance))
    }

    // MARK: - Baseline Calibration
    func calibrateBaseline(heartRate: Double, rmssd: Double, sdnn: Double) {
        baselineHeartRate = heartRate
        baselineRMSSD = rmssd
        baselineSDNN = sdnn
        hrvExtractor.calibrateBaselines(rmssd: rmssd, sdnn: sdnn, hr: heartRate)
        saveBaseline()
    }

    private func loadBaseline() {
        if UserDefaults.standard.object(forKey: "baselineHeartRate") != nil {
            baselineHeartRate = UserDefaults.standard.double(forKey: "baselineHeartRate")
        }
        if UserDefaults.standard.object(forKey: "baselineRMSSD") != nil {
            baselineRMSSD = UserDefaults.standard.double(forKey: "baselineRMSSD")
        }
        if UserDefaults.standard.object(forKey: "baselineSDNN") != nil {
            baselineSDNN = UserDefaults.standard.double(forKey: "baselineSDNN")
        }
        if UserDefaults.standard.object(forKey: "userAge") != nil {
            userAge = UserDefaults.standard.integer(forKey: "userAge")
        }
        if UserDefaults.standard.object(forKey: "sleepHoursLastNight") != nil {
            sleepHoursLastNight = UserDefaults.standard.double(forKey: "sleepHoursLastNight")
        }
    }

    private func saveBaseline() {
        UserDefaults.standard.set(baselineHeartRate, forKey: "baselineHeartRate")
        UserDefaults.standard.set(baselineRMSSD, forKey: "baselineRMSSD")
        UserDefaults.standard.set(baselineSDNN, forKey: "baselineSDNN")
        UserDefaults.standard.set(sleepHoursLastNight, forKey: "sleepHoursLastNight")
    }

    // MARK: - Workout Context Integration
    private func setupWorkoutObserver() {
        NotificationCenter.default.publisher(for: .workoutSessionStarted)
            .sink { [weak self] notification in
                self?.handleWorkoutStarted(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .workoutSessionEnded)
            .sink { [weak self] _ in
                self?.handleWorkoutEnded()
            }
            .store(in: &cancellables)
    }

    func handleWorkoutStarted(_ notification: Notification) {
        exerciseContextActive = true
        workoutAdjustedThresholds = true
        if let startTime = notification.userInfo?["startDate"] as? Date {
            activeWorkoutStartTime = startTime
        }
    }

    func handleWorkoutEnded() {
        activeWorkoutStartTime = nil
        workoutAdjustedThresholds = false
        exerciseRecoveryTimer = Date()
        exerciseContextActive = false
    }

    func setWorkoutContext(isActive: Bool, startDate: Date? = nil) {
        if isActive {
            exerciseContextActive = true
            workoutAdjustedThresholds = true
            activeWorkoutStartTime = startDate ?? Date()
        } else {
            handleWorkoutEnded()
        }
    }

    // MARK: - Detection
    /// Primary entry point for HealthKit heart rate data.
    /// Call this at ~1Hz from HKAnchoredObjectQuery delivery.
    func processHeartRateData(heartRate: Double, hrvSDNN: Double?, timestamp: Date) {
        hrvExtractor.addHeartRateSample(hr: heartRate, at: timestamp)

        rollingHRBuffer.append((timestamp: timestamp, value: heartRate))
        rollingRMSSDBuffer.append((timestamp: timestamp, value: hrvExtractor.currentRMSSD))
        rollingSDNNBuffer.append((timestamp: timestamp, value: hrvExtractor.currentSDNN))

        let cutoff = timestamp.addingTimeInterval(-bufferDuration)
        rollingHRBuffer.removeAll { $0.timestamp < cutoff }
        rollingRMSSDBuffer.removeAll { $0.timestamp < cutoff }
        rollingSDNNBuffer.removeAll { $0.timestamp < cutoff }

        let (isExercising, exerciseConfidence) = hrvExtractor.detectExerciseContext()
        isExercising = isExercising || exerciseContextActive

        // Exercise false-positive suppression:
        // If recovering from exercise and HR/HRV normalize within 2 min → not panic
        if let recoveryStart = exerciseRecoveryTimer {
            let recoveryElapsed = timestamp.timeIntervalSince(recoveryStart)
            if recoveryElapsed < exerciseRecoveryWindow {
                handleExerciseRecovery()
                return
            } else {
                exerciseRecoveryTimer = nil
            }
        }

        // During active workout: widen thresholds significantly to avoid false positives
        if workoutAdjustedThresholds {
            handleActiveWorkout(hr: heartRate)
            return
        }

        // Run panic detection via Random Forest
        runPanicDetection(heartRate: heartRate, timestamp: timestamp)
    }

    /// Legacy single-shot HRV input.
    func processSensorData(heartRate: Double, instantHRV: Double) {
        processHeartRateData(heartRate: heartRate, hrvSDNN: instantHRV, timestamp: Date())
    }

    private func handleActiveWorkout(hr: Double) {
        // During workouts, panic signals must be very large to register
        let workoutHRThreshold = baselineHeartRate + 50
        let workoutHRVThreshold = baselineRMSSD * 0.5

        let hrSpike = hr - baselineHeartRate
        let currentRMSSD = hrvExtractor.currentRMSSD
        let hrvDropRatio = currentRMSSD > 0 ? (baselineRMSSD - currentRMSSD) / baselineRMSSD : 0

        if hrSpike >= workoutHRThreshold && hrvDropRatio >= 0.5 {
            let confidence = min(1.0, (hrSpike - workoutHRThreshold) / 20.0 + hrvDropRatio) * 0.5
            state = .signalElevated(confidence: confidence)
            currentConfidence = confidence
        } else {
            state = .monitoring
            currentConfidence = 0.0
        }
    }

    private func handleExerciseRecovery() {
        if hrvExtractor.isExerciseOffsetPattern() {
            currentConfidence = 0.0
        } else {
            currentConfidence = 0.0
        }
        state = .monitoring
        panicOnsetTimer = nil
    }

    // MARK: - Random Forest Panic Detection
    /// Runs RF inference on the current feature vector.
    /// Replaces the old rule-based threshold logic (APP_AUDIT.md C3).
    private func runPanicDetection(heartRate: Double, timestamp: Date) {
        // Require minimum buffer before running RF (30 seconds of data)
        guard rollingHRBuffer.count >= 30 else {
            state = .monitoring
            currentConfidence = 0.0
            return
        }

        let featureVector = buildFeatureVector()

        // Run inference on background queue
        rfQueue.async { [weak self] in
            guard let self = self else { return }

            let panicProbability: Double

            if let rfModel = self.rfModel {
                panicProbability = self.runRFInference(rfModel: rfModel, featureVector: featureVector)
            } else {
                // Fallback to rule-based if model not loaded
                panicProbability = self.ruleBasedPanicProbability()
            }

            // Process result on main thread
            DispatchQueue.main.async {
                self.applyDetectionResult(panicProbability: panicProbability, timestamp: timestamp, heartRate: heartRate)
            }
        }
    }

    /// Executes CoreML RF inference and returns panic probability.
    private func runRFInference(rfModel: PanicGuardRF, featureVector: RFFeatureVector) -> Double {
        do {
            // Build the input — PanicGuardRF accepts a 8-element feature vector
            // The input name is generated by CoreML; we use the model directly
            let inputVector: [Double] = [
                Double(featureVector.rmssd),
                Double(featureVector.sdnn),
                Double(featureVector.hrMean),
                Double(featureVector.hrStd),
                Double(featureVector.lfHfRatio),
                Double(featureVector.ageGroup),
                Double(featureVector.timeOfDay),
                Double(featureVector.sleepHours)
            ]

            // Construct MLMultiArray for the 8 input features
            guard let inputArray = try? MLMultiArray(shape: [8], dataType: .double) else {
                return ruleBasedPanicProbability()
            }

            for (index, value) in inputVector.enumerated() {
                inputArray[index] = NSNumber(value: value)
            }

            // Create input using the model's input name
            // CoreML-generated models typically use "featureVector" as the input name
            let modelInput = try PanicGuardRFInput(featureVector: inputArray)
            let output = try rfModel.prediction(input: modelInput)

            // Read panic probability from output
            // The output schema is PanicGuardRFOutput with panic_probability field
            let panicProb = output.panicProbability

            return panicProb

        } catch {
            print("[DetectionEngine] RF inference error: \(error.localizedDescription)")
            return ruleBasedPanicProbability()
        }
    }

    /// Rule-based fallback when RF model is unavailable.
    /// Uses a simplified version of the original threshold logic.
    private func ruleBasedPanicProbability() -> Double {
        let currentRMSSD = hrvExtractor.currentRMSSD
        let hrMean = hrvExtractor.currentHRMean

        let hrSpike = hrMean - baselineHeartRate
        let hrvDropRatio = currentRMSSD > 0 ? (baselineRMSSD - currentRMSSD) / baselineRMSSD : 0

        // Simplified panic probability from spike + HRV drop
        let hrSignal = min(1.0, hrSpike / 40.0)
        let hrvSignal = min(1.0, hrvDropRatio / 0.30)

        let combined = 0.6 * hrvSignal + 0.4 * hrSignal

        // Apply age-adjusted floor check
        if hrvExtractor.isHRVDepressed() {
            return min(1.0, combined * 1.3)
        }

        return combined
    }

    /// Applies the RF output probability to detection state.
    /// Implements 30-second sustained signal requirement before crisis trigger.
    private func applyDetectionResult(panicProbability: Double, timestamp: Date, heartRate: Double) {
        if panicProbability >= 0.85 {
            // Start or continue panic onset timer (sustained signal requirement)
            if panicOnsetTimer == nil {
                panicOnsetTimer = timestamp
            }

            if let onsetTime = panicOnsetTimer {
                let elapsed = timestamp.timeIntervalSince(onsetTime)

                if elapsed >= requiredPanicDuration {
                    // Sustained signal for 30+ seconds → confirmed crisis
                    triggerPanicDetected(confidence: panicProbability)
                } else {
                    // Still in onset window
                    state = .signalElevated(confidence: panicProbability)
                    currentConfidence = panicProbability
                }
            }
        } else if panicProbability >= 0.6 {
            // Elevated signal — check-in prompt
            panicOnsetTimer = nil
            state = .signalElevated(confidence: panicProbability)
            currentConfidence = panicProbability
        } else {
            // Below threshold — monitoring
            panicOnsetTimer = nil
            state = .monitoring
            currentConfidence = 0.0

            // Autocalibrate baselines during normal monitoring
            hrvExtractor.autocalibrateBaselines()
        }
    }

    private func triggerPanicDetected(confidence: Double) {
        if firstPanicDetectedAt == nil {
            firstPanicDetectedAt = Date()
            startEscalationTimer()
        }

        state = .panicDetected(confidence: confidence)
        currentConfidence = confidence

        NotificationCenter.default.post(
            name: DetectionEngine.panicDetectedNotification,
            object: nil,
            userInfo: [
                "timestamp": Date(),
                "confidence": confidence,
                "hrSpike": hrvExtractor.currentHRMean - baselineHeartRate,
                "hrvDropRatio": baselineRMSSD > 0 ? (baselineRMSSD - hrvExtractor.currentRMSSD) / baselineRMSSD : 0
            ]
        )
    }

    private func startEscalationTimer() {
        escalationTimer?.invalidate()
        escalationTimer = Timer.scheduledTimer(withTimeInterval: escalationTimeout, repeats: false) { [weak self] _ in
            self?.triggerEscalation()
        }
    }

    private func triggerEscalation() {
        NotificationCenter.default.post(
            name: DetectionEngine.panicEscalatedNotification,
            object: nil,
            userInfo: [
                "timestamp": Date(),
                "state": state,
                "duration": firstPanicDetectedAt.map { Date().timeIntervalSince($0) } ?? 0,
                "hrMean": hrvExtractor.currentHRMean,
                "rmssd": hrvExtractor.currentRMSSD,
                "sdnn": hrvExtractor.currentSDNN
            ]
        )
        objectWillChange.send()
    }

    // MARK: - Reset & Dismiss
    func reset() {
        rollingHRBuffer.removeAll()
        rollingRMSSDBuffer.removeAll()
        rollingSDNNBuffer.removeAll()
        panicOnsetTimer = nil
        escalationTimer?.invalidate()
        escalationTimer = nil
        firstPanicDetectedAt = nil
        exerciseRecoveryTimer = nil
        exerciseContextActive = false
        workoutAdjustedThresholds = false
        activeWorkoutStartTime = nil
        state = .idle
        currentConfidence = 0.0
        isExercising = false
    }

    func dismissPanic() {
        escalationTimer?.invalidate()
        escalationTimer = nil
        firstPanicDetectedAt = nil
        panicOnsetTimer = nil
        exerciseRecoveryTimer = nil
        state = .monitoring
        currentConfidence = 0.0
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let workoutSessionStarted = Notification.Name("WorkoutSessionStarted")
    static let workoutSessionEnded = Notification.Name("WorkoutSessionEnded")
}
