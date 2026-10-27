import Foundation
import WidgetKit

/// ウィジェット共有データDTO
public struct WidgetSummaryData: Codable {
    public var intakeCalories: Double
    public var burnedCalories: Double
    public var proteinGrams: Double
    public var fatGrams: Double
    public var carbsGrams: Double
    public var lastMealTimeAgo: String
    public var lastMealDate: Date?
    public var updatedAt: Date

    public init(
        intakeCalories: Double = 0,
        burnedCalories: Double = 0,
        proteinGrams: Double = 0,
        fatGrams: Double = 0,
        carbsGrams: Double = 0,
        lastMealTimeAgo: String = "未記録",
        lastMealDate: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.intakeCalories = intakeCalories
        self.burnedCalories = burnedCalories
        self.proteinGrams = proteinGrams
        self.fatGrams = fatGrams
        self.carbsGrams = carbsGrams
        self.lastMealTimeAgo = lastMealTimeAgo
        self.lastMealDate = lastMealDate
        self.updatedAt = updatedAt
    }
}

/// ウィジェット（WidgetKit）と本体アプリ間のデータ同期マネージャー
public final class WidgetDataManager {
    public static let shared = WidgetDataManager()

    /// App Group 識別子（XcodeプロジェクトのCapabilitiesと一致させる）
    public static let appGroupIdentifier = "group.com.lldkinn9.Health-Note"
    private static let storageKey = "widget_summary_data_key"

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: WidgetDataManager.appGroupIdentifier) ?? UserDefaults.standard
    }

    private init() {}

    /// ウィジェット用データの保存とタイムラインの即時リロード
    public func updateWidgetData(
        intakeCalories: Double,
        burnedCalories: Double,
        protein: Double,
        fat: Double,
        carbs: Double,
        lastMealDate: Date?
    ) {
        let timeAgo = Self.formatTimeAgo(from: lastMealDate)
        let data = WidgetSummaryData(
            intakeCalories: intakeCalories,
            burnedCalories: burnedCalories,
            proteinGrams: protein,
            fatGrams: fat,
            carbsGrams: carbs,
            lastMealTimeAgo: timeAgo,
            lastMealDate: lastMealDate,
            updatedAt: Date()
        )

        if let encoded = try? JSONEncoder().encode(data) {
            sharedDefaults?.set(encoded, forKey: WidgetDataManager.storageKey)
        }

        // WidgetKitのタイムラインを更新
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 経過時間のフォーマット（例: "2 hr, 52 min 前"）
    public static func formatTimeAgo(from timestamp: Date?) -> String {
        guard let timestamp = timestamp else { return "未記録" }
        let diff = Date().timeIntervalSince(timestamp)
        guard diff > 0 else { return "たった今" }
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60

        if hours > 24 {
            let days = hours / 24
            return "\(days)日前"
        } else if hours > 0 {
            return "\(hours) hr, \(minutes) min 前"
        } else {
            return "\(max(1, minutes)) min 前"
        }
    }

    /// ウィジェット側から保存データを読み出すヘルパー（経過時間を現在時刻基準で再計算）
    public func loadWidgetData() -> WidgetSummaryData {
        guard let data = sharedDefaults?.data(forKey: WidgetDataManager.storageKey),
              var decoded = try? JSONDecoder().decode(WidgetSummaryData.self, from: data) else {
            return WidgetSummaryData()
        }
        if let lastDate = decoded.lastMealDate {
            decoded.lastMealTimeAgo = Self.formatTimeAgo(from: lastDate)
        }
        return decoded
    }
}
