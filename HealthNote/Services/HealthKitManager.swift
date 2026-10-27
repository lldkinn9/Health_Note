import Foundation
import HealthKit
import SwiftUI

/// 本日のバイタルデータDTO
public struct DailyVitalData {
    public var stepCount: Double = 0
    public var activeEnergyBurned: Double = 0 // kcal
    public var basalEnergyBurned: Double = 0  // kcal
    public var latestHeartRate: Double? = nil // bpm
    public var sleepHours: Double = 0         // hours

    public var totalEnergyBurned: Double {
        activeEnergyBurned + basalEnergyBurned
    }

    public init(
        stepCount: Double = 0,
        activeEnergyBurned: Double = 0,
        basalEnergyBurned: Double = 0,
        latestHeartRate: Double? = nil,
        sleepHours: Double = 0
    ) {
        self.stepCount = stepCount
        self.activeEnergyBurned = activeEnergyBurned
        self.basalEnergyBurned = basalEnergyBurned
        self.latestHeartRate = latestHeartRate
        self.sleepHours = sleepHours
    }
}

/// Apple HealthKit 統合マネージャー
@MainActor
public final class HealthKitManager: ObservableObject {
    public static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    @Published public var isAuthorized: Bool = false
    @Published public var vitals: DailyVitalData = DailyVitalData()
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    private init() {}

    /// HealthKitが利用可能な端末かチェック（iPad等ではfalseの場合がある）
    public var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - 権限リクエスト
    public func requestAuthorization() async -> Bool {
        guard isAvailable else {
            errorMessage = "この端末ではAppleヘルスケアが利用できません。"
            return false
        }

        // 読み取り許可リクエスト型
        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        // 書き込み許可リクエスト型（食事データ）
        let shareTypes: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!
        ]

        do {
            try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
            isAuthorized = true
            await fetchTodayVitals()
            return true
        } catch {
            isAuthorized = false
            errorMessage = "ヘルスケア連携の認可に失敗しました: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - 本日のバイタル読み込み
    public func fetchTodayVitals() async {
        guard isAvailable else { return }
        isLoading = true
        defer { isLoading = false }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        async let steps = fetchSumQuantity(for: .stepCount, unit: .count(), start: startOfDay, end: now)
        async let activeCal = fetchSumQuantity(for: .activeEnergyBurned, unit: .kilocalorie(), start: startOfDay, end: now)
        async let basalCal = fetchSumQuantity(for: .basalEnergyBurned, unit: .kilocalorie(), start: startOfDay, end: now)
        async let heartRate = fetchLatestHeartRate(start: startOfDay, end: now)
        async let sleep = fetchSleepHours(start: Calendar.current.date(byAdding: .day, value: -1, to: startOfDay)!, end: now)

        let stepVal = await steps
        let activeVal = await activeCal
        let basalVal = await basalCal
        let hrVal = await heartRate
        let sleepVal = await sleep

        self.vitals = DailyVitalData(
            stepCount: stepVal,
            activeEnergyBurned: activeVal,
            basalEnergyBurned: basalVal,
            latestHeartRate: hrVal,
            sleepHours: sleepVal
        )
    }

    // MARK: - 食事データのHealthKit書き込み
    public func saveMealToHealthKit(meal: Meal) async -> Bool {
        guard isAvailable else { return false }

        var samples: [HKQuantitySample] = []
        let date = meal.timestamp

        // カロリー
        if meal.calories > 0, let calType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
            let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: meal.calories)
            samples.append(HKQuantitySample(type: calType, quantity: quantity, start: date, end: date))
        }

        // タンパク質
        if meal.protein > 0, let pType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein) {
            let quantity = HKQuantity(unit: .gram(), doubleValue: meal.protein)
            samples.append(HKQuantitySample(type: pType, quantity: quantity, start: date, end: date))
        }

        // 脂質
        if meal.fat > 0, let fType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal) {
            let quantity = HKQuantity(unit: .gram(), doubleValue: meal.fat)
            samples.append(HKQuantitySample(type: fType, quantity: quantity, start: date, end: date))
        }

        // 炭水化物
        if meal.carbs > 0, let cType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) {
            let quantity = HKQuantity(unit: .gram(), doubleValue: meal.carbs)
            samples.append(HKQuantitySample(type: cType, quantity: quantity, start: date, end: date))
        }

        guard !samples.isEmpty else { return true }

        return await withCheckedContinuation { continuation in
            healthStore.save(samples) { success, error in
                if success {
                    continuation.resume(returning: true)
                } else {
                    print("HealthKit save failed: \(String(describing: error))")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Private Query Helpers
    private func fetchSumQuantity(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let value = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func fetchLatestHeartRate(start: Date, end: Date) async -> Double? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let hr = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: hr)
            }
            healthStore.execute(query)
        }
    }

    private func fetchSleepHours(start: Date, end: Date) async -> Double {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let sleepSamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: 0)
                    return
                }

                // asleep または asleepCore, asleepDeep, asleepREM の睡眠時間を合算
                var totalSeconds: TimeInterval = 0
                for sample in sleepSamples {
                    if #available(iOS 16.0, *) {
                        if sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                            sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                            sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                            sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue {
                            totalSeconds += sample.endDate.timeIntervalSince(sample.startDate)
                        }
                    } else {
                        if sample.value == HKCategoryValueSleepAnalysis.asleep.rawValue {
                            totalSeconds += sample.endDate.timeIntervalSince(sample.startDate)
                        }
                    }
                }
                continuation.resume(returning: totalSeconds / 3600.0)
            }
            healthStore.execute(query)
        }
    }
}
