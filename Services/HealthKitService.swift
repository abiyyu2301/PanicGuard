import Foundation
import HealthKit

// MARK: - HealthKit Service
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    private(set) var healthStore = HKHealthStore()
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var hrvQuery: HKAnchoredObjectQuery?
    private var heartRateAnchor: HKQueryAnchor?
    private var hrvAnchor: HKQueryAnchor?
    private var heartRateObserverQuery: HKObserverQuery?
    private var hrvObserverQuery: HKObserverQuery?

    @Published var latestHeartRate: Double?
    @Published var latestHRV: Double?
    @Published var isAuthorized: Bool = false

    private let backgroundDeliveryQueue = DispatchQueue(label: "com.panicguard.healthkit.delivery", qos: .utility)

    private init() {}

    // MARK: - Authorization
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }

        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!

        let typesToRead: Set<HKObjectType> = [heartRateType, hrvType]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            await MainActor.run {
                self.isAuthorized = true
            }
            return true
        } catch {
            print("HealthKit authorization failed: \(error)")
            return false
        }
    }

    // MARK: - Background Delivery Setup
    func enableBackgroundDelivery() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }

        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!

        do {
            try await healthStore.enableBackgroundDelivery(for: heartRateType, frequency: .immediate)
            try await healthStore.enableBackgroundDelivery(for: hrvType, frequency: .immediate)
            return true
        } catch {
            print("HealthKit background delivery enablement failed: \(error)")
            return false
        }
    }

    // MARK: - Start Monitoring
    func startMonitoring(
        onHeartRateUpdate: @escaping (Double) -> Void,
        onHRVUpdate: @escaping (Double) -> Void
    ) {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!

        // Heart Rate Query — anchored so we only get new samples
        let hrQuery = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: nil,
            anchor: heartRateAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.heartRateAnchor = newAnchor
            self?.processHeartRateSamples(samples, handler: onHeartRateUpdate)
        }
        hrQuery.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            self?.heartRateAnchor = newAnchor
            self?.processHeartRateSamples(samples, handler: onHeartRateUpdate)
        }

        healthStore.execute(hrQuery)
        self.heartRateQuery = hrQuery

        // HRV Query — anchored so we only get new samples
        let hrvQuery = HKAnchoredObjectQuery(
            type: hrvType,
            predicate: nil,
            anchor: hrvAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.hrvAnchor = newAnchor
            self?.processHRVSamples(samples, handler: onHRVUpdate)
        }
        hrvQuery.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            self?.hrvAnchor = newAnchor
            self?.processHRVSamples(samples, handler: onHRVUpdate)
        }

        healthStore.execute(hrvQuery)
        self.hrvQuery = hrvQuery

        // Observer query for heart rate — wakes app in background
        let hrObserver = HKObserverQuery(
            type: heartRateType,
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            if let error = error {
                print("Heart rate observer query error: \(error)")
                completionHandler()
                return
            }
            self?.backgroundDeliveryQueue.async {
                self?.refreshHeartRateData(onHeartRateUpdate)
                completionHandler()
            }
        }
        healthStore.execute(hrObserver)
        self.heartRateObserverQuery = hrObserver

        // Observer query for HRV — wakes app in background
        let hrvObserver = HKObserverQuery(
            type: hrvType,
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            if let error = error {
                print("HRV observer query error: \(error)")
                completionHandler()
                return
            }
            self?.backgroundDeliveryQueue.async {
                self?.refreshHRVData(onHRVUpdate)
                completionHandler()
            }
        }
        healthStore.execute(hrvObserver)
        self.hrvObserverQuery = hrvObserver
    }

    // MARK: - Background Data Refresh
    private func refreshHeartRateData(_ handler: (Double) -> Void) {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: nil,
            anchor: heartRateAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.heartRateAnchor = newAnchor
            self?.processHeartRateSamples(samples, handler: handler)
        }
        healthStore.execute(query)
    }

    private func refreshHRVData(_ handler: (Double) -> Void) {
        let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let query = HKAnchoredObjectQuery(
            type: hrvType,
            predicate: nil,
            anchor: hrvAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.hrvAnchor = newAnchor
            self?.processHRVSamples(samples, handler: handler)
        }
        healthStore.execute(query)
    }

    private func processHeartRateSamples(_ samples: [HKSample]?, handler: (Double) -> Void) {
        guard let quantitySamples = samples as? [HKQuantitySample],
              let mostRecent = quantitySamples.last else { return }

        let heartRate = mostRecent.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        DispatchQueue.main.async {
            self.latestHeartRate = heartRate
            handler(heartRate)
        }
    }

    private func processHRVSamples(_ samples: [HKSample]?, handler: (Double) -> Void) {
        guard let quantitySamples = samples as? [HKQuantitySample],
              let mostRecent = quantitySamples.last else { return }

        let hrv = mostRecent.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
        DispatchQueue.main.async {
            self.latestHRV = hrv
            handler(hrv)
        }
    }

    // MARK: - Sleep Query

    /// Queries total sleep hours for a given date range.
    /// Returns sleep duration in hours via completion handler.
    func queryTotalSleep(from startDate: Date, to endDate: Date, completion: @escaping (Float?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(nil)
            return
        }

        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, error in
            guard error == nil,
                  let categorySamples = samples as? [HKCategorySample] else {
                completion(nil)
                return
            }

            // Sum all asleep values (asleepUnspecified, asleepCore, asleepDeep, asleepREM)
            let totalSeconds = categorySamples.reduce(0.0) { total, sample in
                total + sample.endDate.timeIntervalSince(sample.startDate)
            }
            let hours = Float(totalSeconds / 3600.0)

            DispatchQueue.main.async {
                completion(hours)
            }
        }

        healthStore.execute(query)
    }

    /// Convenience wrapper with async/await for queryTotalSleep.
    func queryTotalSleep(from startDate: Date, to endDate: Date) async -> Float? {
        await withCheckedContinuation { continuation in
            queryTotalSleep(from: startDate, to: endDate) { hours in
                continuation.resume(returning: hours)
            }
        }
    }

    /// Queries total sleep hours for a specific night (start of night to start of next day).
    func querySleepForNight(_ date: Date, completion: @escaping (Float?) -> Void) {
        let calendar = Calendar.current
        let startOfNight = calendar.startOfDay(for: date)
        guard let endOfNight = calendar.date(byAdding: .day, value: 1, to: startOfNight) else {
            completion(nil)
            return
        }
        queryTotalSleep(from: startOfNight, to: endOfNight, completion: completion)
    }

    /// Convenience wrapper with async/await for querySleepForNight.
    func querySleepForNight(_ date: Date) async -> Float? {
        await withCheckedContinuation { continuation in
            querySleepForNight(date) { hours in
                continuation.resume(returning: hours)
            }
        }
    }

    func stopMonitoring() {
        if let query = heartRateQuery {
            healthStore.stop(query)
        }
        if let query = hrvQuery {
            healthStore.stop(query)
        }
        if let query = heartRateObserverQuery {
            healthStore.stop(query)
        }
        if let query = hrvObserverQuery {
            healthStore.stop(query)
        }
        heartRateQuery = nil
        hrvQuery = nil
        heartRateObserverQuery = nil
        hrvObserverQuery = nil
    }
}
