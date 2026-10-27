import Foundation
import SwiftData
import SwiftUI

/// 食事の分類タイプ
public enum MealType: String, CaseIterable, Codable, Identifiable {
    case breakfast = "朝食"
    case lunch = "昼食"
    case dinner = "夕食"
    case snack = "間食"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .breakfast: return "sun.rise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "cup.and.saucer.fill"
        }
    }

    public var themeColor: Color {
        switch self {
        case .breakfast: return .orange
        case .lunch: return .yellow
        case .dinner: return .indigo
        case .snack: return .pink
        }
    }
}

/// 食事レコード（SwiftData + CloudKit 同期準拠）
/// CloudKit制約: 全フィールドに初期値があるかオプショナルであること、@Attribute(.unique)は非使用
@Model
public final class Meal {
    public var id: UUID = UUID()
    public var timestamp: Date = Date()
    public var mealTypeRaw: String = MealType.lunch.rawValue
    public var name: String = ""
    public var calories: Double = 0.0
    public var protein: Double = 0.0
    public var fat: Double = 0.0
    public var carbs: Double = 0.0
    public var memo: String = ""

    /// 食事写真（大容量バイナリは外部ストレージ化してCloudKit・メモリ効率を最大化）
    @Attribute(.externalStorage)
    public var imageData: Data? = nil

    /// HealthKit同期フラグ
    public var healthKitSynced: Bool = false

    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    // MARK: - Initializer
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        mealType: MealType = .lunch,
        name: String,
        calories: Double,
        protein: Double = 0.0,
        fat: Double = 0.0,
        carbs: Double = 0.0,
        imageData: Data? = nil,
        memo: String = "",
        healthKitSynced: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mealTypeRaw = mealType.rawValue
        self.name = name
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.imageData = imageData
        self.memo = memo
        self.healthKitSynced = healthKitSynced
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Computed Properties
    public var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .lunch }
        set { mealTypeRaw = newValue.rawValue }
    }

    /// PFC合計グラム数
    public var totalPFCGrams: Double {
        protein + fat + carbs
    }

    /// タンパク質比率 (0.0 ~ 1.0)
    public var proteinRatio: Double {
        guard totalPFCGrams > 0 else { return 0 }
        return protein / totalPFCGrams
    }

    /// 脂質比率 (0.0 ~ 1.0)
    public var fatRatio: Double {
        guard totalPFCGrams > 0 else { return 0 }
        return fat / totalPFCGrams
    }

    /// 炭水化物比率 (0.0 ~ 1.0)
    public var carbsRatio: Double {
        guard totalPFCGrams > 0 else { return 0 }
        return carbs / totalPFCGrams
    }

    /// ウィジェットやサマリ表示用：経過時間の日本語表記（例: "2 hr, 52 min 前"）
    public var timeAgoDisplay: String {
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
}
