import Foundation
import HealthKit
import SwiftUI

/// 本日のバイタル＆最新体組成データDTO
public struct DailyVitalData {
    public var stepCount: Double = 0
    public var activeEnergyBurned: Double = 0 // kcal
    public var basalEnergyBurned: Double = 0  // kcal
    public var latestHeartRate: Double? = nil // bpm
    public var sleepHours: Double = 0         // hours

    // マイカルテ連携用の最新体組成データ（HealthKit）
    public var latestWeightKg: Double? = nil
    public var latestWeightDate: Date? = nil
    public var latestBodyFatPercentage: Double? = nil
    public var latestBodyFatDate: Date? = nil

    public var totalEnergyBurned: Double {
        activeEnergyBurned + basalEnergyBurned
    }

    public init(
        stepCount: Double = 0,
        activeEnergyBurned: Double = 0,
        basalEnergyBurned: Double = 0,
        latestHeartRate: Double? = nil,
        sleepHours: Double = 0,
        latestWeightKg: Double? = nil,
        latestWeightDate: Date? = nil,
        latestBodyFatPercentage: Double? = nil,
        latestBodyFatDate: Date? = nil
    ) {
        self.stepCount = stepCount
        self.activeEnergyBurned = activeEnergyBurned
        self.basalEnergyBurned = basalEnergyBurned
        self.latestHeartRate = latestHeartRate
        self.sleepHours = sleepHours
        self.latestWeightKg = latestWeightKg
        self.latestWeightDate = latestWeightDate
        self.latestBodyFatPercentage = latestBodyFatPercentage
        self.latestBodyFatDate = latestBodyFatDate
    }
}

/// Apple HealthKit 統合マネージャー
@MainActor
public final class HealthKitManager: ObservableObject {
    public static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    private let bodyMetricsAuthKey = "hkRequestedBodyMetricsAuth_v2"

    @Published public var isAuthorized: Bool = false
    @Published public var vitals: DailyVitalData = DailyVitalData()
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    private init() {}

    /// HealthKitが利用可能な端末かチェック（iPad等ではfalseの場合がある）
    public var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - 権限リクエスト（体重・体脂肪率を含む全対象項目）
    public func requestAuthorization() async -> Bool {
        guard isAvailable else {
            errorMessage = "この端末ではAppleヘルスケアが利用できません。"
            return false
        }

        // 読み取り許可リクエスト型（歩数・カロリー・心拍・睡眠 ＋ 体重・体脂肪率）
        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!
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
            UserDefaults.standard.set(true, forKey: bodyMetricsAuthKey)
            isAuthorized = true
            await fetchTodayVitals()
            return true
        } catch {
            isAuthorized = false
            errorMessage = "ヘルスケア連携の認可に失敗しました: \(error.localizedDescription)"
            return false
        }
    }

    /// 既存ユーザーがアップデート後に初めて開いた際にも体重・体脂肪率の読み取り許可シートを確実に表示する
    public func ensureBodyMetricsAuthorizationAndFetch() async {
        guard isAvailable else { return }
        if !UserDefaults.standard.bool(forKey: bodyMetricsAuthKey) {
            _ = await requestAuthorization()
        } else {
            await fetchTodayVitals()
        }
    }

    // MARK: - 本日のバイタル ＆ 最新体重・体脂肪率の読み込み
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
        async let latestWeight = fetchLatestQuantitySample(for: .bodyMass, unit: .gramUnit(with: .kilo))
        async let latestBodyFat = fetchLatestQuantitySample(for: .bodyFatPercentage, unit: .percent())

        let stepVal = await steps
        let activeVal = await activeCal
        let basalVal = await basalCal
        let hrVal = await heartRate
        let sleepVal = await sleep
        let weightSample = await latestWeight
        let bodyFatSample = await latestBodyFat

        // HealthKitのbodyFatPercentageは標準で 0.0〜1.0（例: 0.185 = 18.5%）で格納されるため % 単位へ正規化
        var normalizedBodyFat: Double? = nil
        if let rawBF = bodyFatSample?.value, rawBF > 0 {
            normalizedBodyFat = rawBF <= 1.0 ? (rawBF * 100.0) : rawBF
        }

        var validWeight: Double? = nil
        if let rawW = weightSample?.value, rawW > 0 {
            validWeight = rawW
        }

        if stepVal > 0 || activeVal > 0 || basalVal > 0 || validWeight != nil || normalizedBodyFat != nil {
            isAuthorized = true
        }

        self.vitals = DailyVitalData(
            stepCount: stepVal,
            activeEnergyBurned: activeVal,
            basalEnergyBurned: basalVal,
            latestHeartRate: hrVal,
            sleepHours: sleepVal,
            latestWeightKg: validWeight,
            latestWeightDate: weightSample?.date,
            latestBodyFatPercentage: normalizedBodyFat,
            latestBodyFatDate: bodyFatSample?.date
        )
    }

    // MARK: - カレンダー選択日用：任意の日付の歩数・消費カロリー・体重・体脂肪率を取得
    public struct DayHealthKitMetrics {
        public var stepCount: Double = 0
        public var burnedCalories: Double = 0
        public var weightKg: Double? = nil
        public var bodyFatPercentage: Double? = nil

        public init(
            stepCount: Double = 0,
            burnedCalories: Double = 0,
            weightKg: Double? = nil,
            bodyFatPercentage: Double? = nil
        ) {
            self.stepCount = stepCount
            self.burnedCalories = burnedCalories
            self.weightKg = weightKg
            self.bodyFatPercentage = bodyFatPercentage
        }
    }

    public func fetchDayMetrics(for date: Date) async -> DayHealthKitMetrics {
        guard isAvailable else { return DayHealthKitMetrics() }

        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay = min(Date(), cal.date(byAdding: .day, value: 1, to: startOfDay) ?? date)

        guard endOfDay > startOfDay else { return DayHealthKitMetrics() }

        async let steps = fetchSumQuantity(for: .stepCount, unit: .count(), start: startOfDay, end: endOfDay)
        async let activeCal = fetchSumQuantity(for: .activeEnergyBurned, unit: .kilocalorie(), start: startOfDay, end: endOfDay)
        async let basalCal = fetchSumQuantity(for: .basalEnergyBurned, unit: .kilocalorie(), start: startOfDay, end: endOfDay)
        async let dayWeight = fetchLatestQuantityInRange(for: .bodyMass, unit: .gramUnit(with: .kilo), start: startOfDay, end: endOfDay)
        async let dayBodyFat = fetchLatestQuantityInRange(for: .bodyFatPercentage, unit: .percent(), start: startOfDay, end: endOfDay)

        let stepVal = await steps
        let burnedVal = (await activeCal) + (await basalCal)
        let wVal = await dayWeight
        let bfRaw = await dayBodyFat

        var normalizedBF: Double? = nil
        if let bfRaw, bfRaw > 0 {
            normalizedBF = bfRaw <= 1.0 ? (bfRaw * 100.0) : bfRaw
        }

        return DayHealthKitMetrics(
            stepCount: stepVal,
            burnedCalories: burnedVal,
            weightKg: (wVal != nil && wVal! > 0) ? wVal : nil,
            bodyFatPercentage: normalizedBF
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

    private func fetchLatestQuantityInRange(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let val = sample.quantity.doubleValue(for: unit)
                continuation.resume(returning: val)
            }
            healthStore.execute(query)
        }
    }

    private func fetchLatestQuantitySample(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async -> (value: Double, date: Date)? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let val = sample.quantity.doubleValue(for: unit)
                continuation.resume(returning: (val, sample.endDate))
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
