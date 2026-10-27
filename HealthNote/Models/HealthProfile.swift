import Foundation
import SwiftData

/// 活動レベル
public enum ActivityLevel: String, CaseIterable, Codable, Identifiable {
    case sedentary = "座り仕事中心（運動少なめ）"
    case light = "軽い運動（週1〜2回程度）"
    case moderate = "中程度の運動（週3〜5回）"
    case active = "活発（ハードな運動・立ち仕事中心）"

    public var id: String { rawValue }
}

/// マイカルテ（身体プロファイル・健康状態・栄養目標）
/// SwiftData + CloudKit 同期準拠
@Model
public final class HealthProfile {
    public var id: UUID = UUID()
    public var nickname: String = "ユーザー"
    public var birthDate: Date? = nil
    public var genderRaw: String = "未設定"
    public var heightCm: Double = 170.0
    public var weightKg: Double = 65.0
    public var targetWeightKg: Double = 62.0
    public var activityLevelRaw: String = ActivityLevel.moderate.rawValue

    // 目標栄養素
    public var targetCalories: Double = 2000.0
    public var targetProtein: Double = 75.0
    public var targetFat: Double = 55.0
    public var targetCarbs: Double = 250.0

    // 簡易問診票・健康留意事項（AIアドバイザーの個別化に活用）
    public var medicalHistory: String = ""      // 既往歴・持病
    public var allergies: String = ""           // アレルギー
    public var dietaryRestrictions: String = "" // 食事制限・嗜好（減塩、低糖質等）
    public var healthCheckMemo: String = ""     // 直近の健診気になる項目

    public var updatedAt: Date = Date()
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        nickname: String = "ユーザー",
        birthDate: Date? = nil,
        genderRaw: String = "未設定",
        heightCm: Double = 170.0,
        weightKg: Double = 65.0,
        targetWeightKg: Double = 62.0,
        activityLevelRaw: String = ActivityLevel.moderate.rawValue,
        targetCalories: Double = 2000.0,
        targetProtein: Double = 75.0,
        targetFat: Double = 55.0,
        targetCarbs: Double = 250.0,
        medicalHistory: String = "",
        allergies: String = "",
        dietaryRestrictions: String = "",
        healthCheckMemo: String = ""
    ) {
        self.id = id
        self.nickname = nickname
        self.birthDate = birthDate
        self.genderRaw = genderRaw
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.targetWeightKg = targetWeightKg
        self.activityLevelRaw = activityLevelRaw
        self.targetCalories = targetCalories
        self.targetProtein = targetProtein
        self.targetFat = targetFat
        self.targetCarbs = targetCarbs
        self.medicalHistory = medicalHistory
        self.allergies = allergies
        self.dietaryRestrictions = dietaryRestrictions
        self.healthCheckMemo = healthCheckMemo
        self.updatedAt = Date()
        self.createdAt = Date()
    }

    // MARK: - Computed Properties
    public var activityLevel: ActivityLevel {
        get { ActivityLevel(rawValue: activityLevelRaw) ?? .moderate }
        set { activityLevelRaw = newValue.rawValue }
    }

    /// 年齢（生年月日からの算出）
    public var age: Int? {
        guard let birthDate = birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }

    /// BMI（体重kg / (身長m)^2）
    public var bmi: Double {
        guard heightCm > 0 else { return 0 }
        let heightM = heightCm / 100.0
        return weightKg / (heightM * heightM)
    }

    /// BMIの判定テキスト
    public var bmiCategory: String {
        switch bmi {
        case ..<18.5: return "低体重"
        case 18.5..<25.0: return "普通体重"
        case 25.0..<30.0: return "肥満 (1度)"
        default: return "肥満 (2度以上)"
        }
    }

    /// AIアドバイザー向けの要約プロンプトテキスト生成（個人情報を含まない安全な健康サマリ）
    public var aiContextSummary: String {
        var items: [String] = []
        if let age = age { items.append("年齢: \(age)歳") }
        if genderRaw != "未設定" { items.append("性別: \(genderRaw)") }
        items.append("身長: \(String(format: "%.1f", heightCm))cm")
        items.append("体重: \(String(format: "%.1f", weightKg))kg (BMI: \(String(format: "%.1f", bmi)))")
        items.append("目標カロリー: \(Int(targetCalories))kcal (P:\(Int(targetProtein))g, F:\(Int(targetFat))g, C:\(Int(targetCarbs))g)")
        if !dietaryRestrictions.isEmpty { items.append("食事制限/要望: \(dietaryRestrictions)") }
        if !allergies.isEmpty { items.append("アレルギー: \(allergies)") }
        if !medicalHistory.isEmpty { items.append("健康上の留意点: \(medicalHistory)") }
        return items.joined(separator: ", ")
    }
}
