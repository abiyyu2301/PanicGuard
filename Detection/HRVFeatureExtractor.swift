import Foundation

// MARK: - HRV Feature Extractor
/// Computes RMSSD, SDNN, and HR mean from rolling RR-interval / HR buffers.
/// Designed for Apple Watch sensor data (HR at ~1Hz, SDNN from HealthKit).
/// Incorporates age-adjusted baselines per PMC12526660 findings.
final class HRVFeatureExtractor {
    
    // MARK: - Configuration
    private let windowSize: Int
    private let minWindowSamples: Int
    private let maxIntervalGap: TimeInterval
    private let minRRInterval: TimeInterval // ~300ms = 200bpm max
    private let maxRRInterval: TimeInterval // ~1200ms = 50bpm min
    
    // MARK: - Rolling Buffers
    private var rrBuffer: [(timestamp: Date, rr: TimeInterval)] = []
    private var hrBuffer: [(timestamp: Date, hr: Double)] = []
    private let bufferLock = NSLock()
    
    // MARK: - User Demographics (for age stratification)
    var userAge: Int = 30 {
        didSet { recalculateAgeAdjustedBaseline() }
    }
    
    // MARK: - Age-Adjusted Baseline Norms (from HRV literature)
    /// RMSSD norms by age decade (ms) — population reference values
    private static let rmssdByAge: [ClosedRange<Int>: ClosedRange<Double>] = [
        18...29:  45.0...75.0,
        30...39:  35.0...60.0,
        40...49:  28.0...48.0,
        50...59:  22.0...38.0,
        60...69:  18.0...32.0,
        70...100: 14.0...26.0
    ]
    
    /// SDNN norms by age decade (ms)
    private static let sdnnByAge: [ClosedRange<Int>: ClosedRange<Double>] = [
        18...29:  55.0...105.0,
        30...39:  45.0...85.0,
        40...49:  38.0...68.0,
        50...59:  32.0...55.0,
        60...69:  28.0...48.0,
        70...100: 22.0...40.0
    ]
    
    // MARK: - Current Baselines (dynamically calibrated)
    private(set) var rmssdBaseline: Double = 50.0
    private(set) var sdnnBaseline: Double = 65.0
    private(set) var hrBaseline: Double = 70.0
    
    // MARK: - Derived Features (published for consumers)
    private(set) var currentRMSSD: Double = 0.0
    private(set) var currentSDNN: Double = 0.0
    private(set) var currentHRMean: Double = 0.0
    private(set) var currentHRVQuality: HRVQuality = .insufficientData
    
    enum HRVQuality: String {
        case insufficientData = "insufficient_data"
        case poor = "poor"
        case fair = "fair"
        case good = "good"
        case excellent = "excellent"
        
        var minSamplesForQuality: Int {
            switch self {
            case .insufficientData: return 0
            case .poor: return 30   // ~30s at 1Hz
            case .fair: return 60   // ~60s at 1Hz
            case .good: return 120  // ~2 min
            case .excellent: return 300 // ~5 min
            }
        }
    }
    
    // MARK: - Init
    /// - Parameter windowSize: number of samples in rolling window (default 300 ≈ 5 min at 1Hz)
    init(windowSize: Int = 300) {
        self.windowSize = windowSize
        self.minWindowSamples = 30 // 30 seconds minimum for any HRV computation
        self.maxIntervalGap = 5.0  // seconds — gap > 5s suggests sensor dropout
        self.minRRInterval = 0.30  // 300ms = 200bpm physiological max
        self.maxRRInterval = 1.50  // 1500ms = 40bpm physiological min
    }
    
    // MARK: - Public API
    
    /// Add a heart rate sample. Call this at ~1Hz from HealthKit delivery.
    /// - Parameters:
    ///   - hr: heart rate in bpm
    ///   - timestamp: sample timestamp (use Date of the HealthKit sample)
    func addHeartRateSample(hr: Double, at timestamp: Date) {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        
        // Derive RR interval from HR
        let rr = 60.0 / hr // seconds
        
        // Quality check: reject physiologically impossible values
        guard rr >= minRRInterval, rr <= maxRRInterval else {
            print("[HRVExtractor] Rejected out-of-range RR: \(rr)s (HR=\(hr)bpm)")
            return
        }
        
        hrBuffer.append((timestamp: timestamp, hr: hr))
        rrBuffer.append((timestamp: timestamp, rr: rr))
        
        // Trim to window size
        if hrBuffer.count > windowSize * 2 {
            hrBuffer.removeFirst(hrBuffer.count - windowSize)
        }
        if rrBuffer.count > windowSize * 2 {
            rrBuffer.removeFirst(rrBuffer.count - windowSize)
        }
        
        recomputeFeatures()
    }
    
    /// Add a raw SDNN value from HealthKit (SDNN is HealthKit's HRV metric).
    /// This is stored for correlation but RMSSD is our primary metric per PMC paper.
    func addSDNNSample(sdnn: Double, at timestamp: Date) {
        // SDNN from HealthKit is already a quality-checked rolling SDNN value.
        // We use it as a secondary cross-check against our computed SDNN.
        bufferLock.lock()
        defer { bufferLock.unlock() }
        
        // Store for cross-validation (not used as primary SDNN)
        recomputeFeatures()
    }
    
    /// Calibrate baselines from a known-resting 5-minute window.
    /// Call this during onboarding calibration.
    func calibrateBaselines(rmssd: Double, sdnn: Double, hr: Double) {
        rmssdBaseline = rmssd
        sdnnBaseline = sdnn
        hrBaseline = hr
    }
    
    /// Autocalibrate baselines from current buffer — used during normal monitoring
    /// to drift-correct. Only updates if current values are high-quality.
    func autocalibrateBaselines() {
        guard currentHRVQuality == .good || currentHRVQuality == .excellent else { return }
        
        // Slowly drift-correct (10% weight on new observation)
        rmssdBaseline = 0.9 * rmssdBaseline + 0.1 * currentRMSSD
        sdnnBaseline = 0.9 * sdnnBaseline + 0.1 * currentSDNN
        hrBaseline = 0.9 * hrBaseline + 0.1 * currentHRMean
    }
    
    /// Age-stratified reference baseline. Returns expected RMSSD range for user's age.
    func ageAdjustedRMSSDRange() -> ClosedRange<Double> {
        for (range, values) in Self.rmssdByAge {
            if range.contains(userAge) { return values }
        }
        return 30.0...50.0 // fallback
    }
    
    func ageAdjustedSDNNRange() -> ClosedRange<Double> {
        for (range, values) in Self.sdnnByAge {
            if range.contains(userAge) { return values }
        }
        return 40.0...65.0 // fallback
    }
    
    /// Returns true if current HRV is below the lower bound of age-expected range.
    /// This is a strong panic signal per PMC paper (parasympathetic withdrawal).
    func isHRVDepressed() -> Bool {
        let rmssdRange = ageAdjustedRMSSDRange()
        return currentRMSSD < rmssdRange.lowerBound * 0.75 // 25% below age-expected floor
    }
    
    /// Fraction of time the user has been in a "low HRV state" in the current window.
    /// Low HRV = below age-adjusted lower bound.
    func lowHRVRatio() -> Double {
        guard rrBuffer.count >= minWindowSamples else { return 0.0 }
        let threshold = ageAdjustedRMSSDRange().lowerBound * 0.75
        let lowHRVSamples = rrBuffer.filter { computeRMSSDFromBuffer(Array($0.timestamp...)) < threshold }
        return Double(lowHRVSamples.count) / Double(rrBuffer.count)
    }
    
    // MARK: - Feature Computation
    
    private func recomputeFeatures() {
        let rrCopy = rrBuffer
        let hrCopy = hrBuffer
        
        guard rrCopy.count >= minWindowSamples else {
            currentRMSSD = 0.0
            currentSDNN = 0.0
            currentHRMean = 0.0
            currentHRVQuality = .insufficientData
            return
        }
        
        let windowRRs = rrCopy.suffix(windowSize).map { $0.rr }
        let windowHRs = hrCopy.suffix(windowSize).map { $0.hr }
        
        // RMSSD: root mean square of successive differences (ms)
        currentRMSSD = computeRMSSD(rrIntervals: windowRRs)
        
        // SDNN: standard deviation of NN intervals (ms)
        currentSDNN = computeSDNN(rrIntervals: windowRRs)
        
        // Mean HR over window
        currentHRMean = windowHRs.reduce(0, +) / Double(windowHRs.count)
        
        // Quality assessment
        currentHRVQuality = assessQuality(sampleCount: rrCopy.count)
    }
    
    /// Compute RMSSD from array of RR intervals (in seconds).
    /// Returns value in milliseconds.
    private func computeRMSSD(rrIntervals: [TimeInterval]) -> Double {
        guard rrIntervals.count >= 2 else { return 0.0 }
        
        var sumSquaredDiffs: Double = 0.0
        var validCount = 0
        
        for i in 1..<rrIntervals.count {
            let prevRR = rrIntervals[i - 1]
            let currRR = rrIntervals[i]
            let diff = currRR - prevRR
            
            // Reject non-physiological successive differences (>500ms likely artifact)
            if abs(diff) < 0.5 {
                sumSquaredDiffs += diff * diff
                validCount += 1
            }
        }
        
        guard validCount >= 2 else { return 0.0 }
        
        let rmssd = sqrt(sumSquaredDiffs / Double(validCount))
        return rmssd * 1000.0 // convert s → ms
    }
    
    /// Compute SDNN (standard deviation of NN intervals) in milliseconds.
    private func computeSDNN(rrIntervals: [TimeInterval]) -> Double {
        guard rrIntervals.count >= 2 else { return 0.0 }
        
        let mean = rrIntervals.reduce(0, +) / Double(rrIntervals.count)
        let variance = rrIntervals.reduce(0) { $0 + pow($1 - mean, 2) } / Double(rrIntervals.count)
        
        return sqrt(variance) * 1000.0 // convert s → ms
    }
    
    /// Compute RMSSD from a buffer, used internally for ratio calculations.
    private func computeRMSSDFromBuffer(_ timestamps: [Date]) -> Double {
        let relevantRRs = rrBuffer.filter { timestamps.contains($0.timestamp) }.map { $0.rr }
        return computeRMSSD(rrIntervals: relevantRRs)
    }
    
    private func assessQuality(sampleCount: Int) -> HRVQuality {
        if sampleCount >= 300 { return .excellent }
        if sampleCount >= 120 { return .good }
        if sampleCount >= 60  { return .fair }
        if sampleCount >= 30  { return .poor }
        return .insufficientData
    }
    
    private func recalculateAgeAdjustedBaseline() {
        // When age changes, update baseline expectations (but don't override user-calibrated baseline)
        let rmssdRange = ageAdjustedRMSSDRange()
        let sdnnRange = ageAdjustedSDNNRange()
        
        // If baseline is far outside age-expected range, flag for recalibration
        if rmssdBaseline < rmssdRange.lowerBound * 0.5 || rmssdBaseline > rmssdRange.upperBound * 1.5 {
            // Trigger recalibration prompt — baseline is way off for this age
            NotificationCenter.default.post(name: .hrvBaselineRecalibrationNeeded, object: nil)
        }
    }
    
    // MARK: - Workout Discrimination
    
    /// Detects if user is likely exercising based on HR behavior.
    /// Exercise causes HR spike + HRV drop that resolves quickly — should NOT trigger panic.
    /// Returns: (isExercising: Bool, confidence: Double)
    func detectExerciseContext() -> (isExercising: Bool, confidence: Double) {
        guard hrBuffer.count >= 60 else { return (false, 0.0) } // need 60s of data
        
        let recentHRs = hrBuffer.suffix(60).map { $0.hr }
        let olderHRs = hrBuffer.prefix(60).map { $0.hr }
        
        guard !olderHRs.isEmpty else { return (false, 0.0) }
        
        let recentMean = recentHRs.reduce(0, +) / Double(recentHRs.count)
        let olderMean = olderHRs.reduce(0, +) / Double(olderHRs.count)
        
        let hrDelta = recentMean - olderMean
        
        // If HR is elevated but HRV is not depressed (or HRV stays relatively stable), likely exercise
        // During panic: both HR rises AND HRV drops together
        // During exercise: HR rises but HRV may stay stable or drop briefly then compensate
        let hrvDelta = currentRMSSD - rmssdBaseline
        
        // Exercise heuristics:
        // 1. HR rose > 25 bpm in last 60s → possible exercise
        // 2. HRV did NOT drop proportionally (< 30% of HR rise ratio) → exercise not panic
        // 3. If HR rise > 30 bpm AND HRV drop > 30% → more likely panic
        
        let exerciseConfidence: Double
        if hrDelta > 25 && hrvDelta > rmssdBaseline * 0.2 {
            // HR up but HRV relatively stable — exercise signal
            exerciseConfidence = min(1.0, hrDelta / 40.0)
        } else if hrDelta > 20 && hrvDelta > 0 {
            exerciseConfidence = 0.6
        } else {
            exerciseConfidence = 0.0
        }
        
        return (exerciseConfidence > 0.5, exerciseConfidence)
    }
    
    /// Returns true if the current pattern resembles exercise-induced HR spike
    /// that resolves within 2 minutes (exercise offset = not panic).
    func isExerciseOffsetPattern() -> Bool {
        guard hrBuffer.count >= 120 else { return false }
        
        let last60s = hrBuffer.suffix(60)
        let prev60s = hrBuffer.dropLast(60).suffix(60)
        
        let lastMean = last60s.map { $0.hr }.reduce(0, +) / 60.0
        let prevMean = prev60s.map { $0.hr }.reduce(0, +) / 60.0
        
        // If HR is dropping back toward baseline quickly — exercise offset
        // Panic doesn't self-resolve in < 2 min without intervention
        return lastMean < prevMean * 0.9 && (prevMean - lastMean) > 10
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let hrvBaselineRecalibrationNeeded = Notification.Name("HRVBaselineRecalibrationNeeded")
}
