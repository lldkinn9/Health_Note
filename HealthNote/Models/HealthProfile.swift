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

/// マイカルテ（身体プロファイル・健康状態）
/// SwiftData + CloudKit 同期準拠（既存DB互換のため内部カラムは維持しつつ目標設定は不使用）
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

    // 旧スキーマ互換用カラム（UI・AI評価では目標値を使用しない）
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

    /// AIアドバイザー向けの要約プロンプトテキスト生成（個人情報および目標値を含まない安全な健康サマリ）
    public var aiContextSummary: String {
        var items: [String] = []
        if let age = age { items.append("年齢: \(age)歳") }
        if genderRaw != "未設定" { items.append("性別: \(genderRaw)") }
        items.append("身長: \(String(format: "%.1f", heightCm))cm")
        items.append("体重: \(String(format: "%.1f", weightKg))kg (BMI: \(String(format: "%.1f", bmi)))")
        items.append("日常活動レベル: \(activityLevel.rawValue)")
        if !dietaryRestrictions.isEmpty { items.append("食事制限/要望: \(dietaryRestrictions)") }
        if !allergies.isEmpty { items.append("アレルギー: \(allergies)") }
        if !medicalHistory.isEmpty { items.append("健康上の留意点: \(medicalHistory)") }
        return items.joined(separator: ", ")
    }
}

/// 病院の血液検査・特殊検査など任意の検査項目を無制限に保持する構造体
public struct ExtraLabItem: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var name: String      // 例: "TSH", "フェリチン", "CK(CPK)", "PSA"
    public var value: String     // 例: "1.85", "45.2", "(-)"
    public var unit: String      // 例: "μIU/mL", "ng/mL", "U/L"
    public var reference: String // 例: "0.50〜5.00"（任意）

    public init(id: UUID = UUID(), name: String = "", value: String = "", unit: String = "", reference: String = "") {
        self.id = id
        self.name = name
        self.value = value
        self.unit = unit
        self.reference = reference
    }
}

// MARK: - 健診・検査結果モデル（定期健診・人間ドック・病院採血フル対応・CloudKit準拠）
@Model
public final class HealthCheckRecord: Identifiable {
    public var id: UUID = UUID()
    public var examDate: Date = Date()
    public var facilityName: String = ""

    // 1. 身体計測・視力・血圧・脈拍
    public var heightCm: Double? = nil
    public var weightKg: Double? = nil
    public var bodyFatPercent: Double? = nil  // 体脂肪率 (%)
    public var waistCm: Double? = nil         // 腹囲 (cm)
    public var visionRight: Double? = nil     // 視力（右）
    public var visionLeft: Double? = nil      // 視力（左）
    public var systolicBP: Int? = nil         // 最高血圧 (mmHg)
    public var diastolicBP: Int? = nil        // 最低血圧 (mmHg)
    public var pulseRate: Int? = nil          // 脈拍数 (拍/分)

    // 2. 血算・貧血検査（CBC）
    public var wbc: Int? = nil                // 白血球数 (/μL)
    public var rbc: Double? = nil             // 赤血球数 (万/μL)
    public var hemoglobin: Double? = nil      // 血色素量 / Hb (g/dL)
    public var hematocrit: Double? = nil      // ヘマトクリット / Ht (%)
    public var platelets: Double? = nil       // 血小板数 / PLT (万/μL)

    // 3. 脂質検査
    public var totalCholesterol: Int? = nil   // 総コレステロール (mg/dL)
    public var ldlCholesterol: Int? = nil     // LDLコレステロール (mg/dL)
    public var hdlCholesterol: Int? = nil     // HDLコレステロール (mg/dL)
    public var nonHdlCholesterol: Int? = nil  // Non-HDLコレステロール (mg/dL)
    public var triglycerides: Int? = nil      // 中性脂肪 TG (mg/dL)

    // 4. 肝機能・胆道・蛋白検査
    public var ast: Int? = nil                // AST / GOT (U/L)
    public var alt: Int? = nil                // ALT / GPT (U/L)
    public var gammaGTP: Int? = nil           // γ-GTP (U/L)
    public var alp: Int? = nil                // ALP (U/L)
    public var ldh: Int? = nil                // LDH / LD (U/L)
    public var totalBilirubin: Double? = nil  // 総ビリルビン / T-Bil (mg/dL)
    public var totalProtein: Double? = nil    // 総蛋白 / TP (g/dL)
    public var albumin: Double? = nil         // アルブミン / Alb (g/dL)
    public var amylase: Int? = nil            // アミラーゼ / AMY (U/L)

    // 5. 糖代謝・尿酸
    public var fastingGlucose: Int? = nil     // 血糖 / 空腹時血糖 (mg/dL)
    public var hba1c: Double? = nil           // HbA1c (%)
    public var uricAcid: Double? = nil        // 尿酸値 / UA (mg/dL)

    // 6. 腎機能・電解質・炎症・鉄代謝
    public var bun: Double? = nil             // 尿素窒素 / BUN / UN (mg/dL)
    public var creatinine: Double? = nil      // クレアチニン / Cr (mg/dL)
    public var egfr: Double? = nil            // eGFR (mL/min/1.73m²)
    public var crp: Double? = nil             // CRP定量 (mg/dL)
    public var sodium: Double? = nil          // Na ナトリウム (mEq/L)
    public var potassium: Double? = nil       // K カリウム (mEq/L)
    public var chloride: Double? = nil        // Cl クロール (mEq/L)
    public var serumIron: Int? = nil          // Fe 血清鉄 (μg/dL)

    // 7. 尿検査・心電図・胸部X線等の定性・所見
    public var urineProtein: String = ""      // 尿蛋白 (- / ± / + 等)
    public var urineGlucose: String = ""      // 尿糖 (- / ± / + 等)
    public var urineOccultBlood: String = ""  // 尿潜血 (- / ± / + 等)
    public var hearingFinding: String = ""    // 聴力所見 (異常なし等)
    public var ecgFinding: String = ""        // 心電図所見
    public var chestXrayFinding: String = ""  // 胸部X線所見

    // 8. 任意の追加検査項目（病院独自の血液検査項目等をJSONで無制限保存）
    public var extraItemsJSON: String = ""

    public var memo: String = ""

    @Attribute(.externalStorage)
    public var sheetImageData: Data? = nil

    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        examDate: Date = Date(),
        facilityName: String = "",
        memo: String = "",
        sheetImageData: Data? = nil
    ) {
        self.id = id
        self.examDate = examDate
        self.facilityName = facilityName
        self.memo = memo
        self.sheetImageData = sheetImageData
        self.createdAt = Date()
    }

    /// 自由追加検査項目のデコード・エンコードアクセサ
    public var extraItems: [ExtraLabItem] {
        get {
            guard !extraItemsJSON.isEmpty,
                  let data = extraItemsJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([ExtraLabItem].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let jsonStr = String(data: data, encoding: .utf8) {
                extraItemsJSON = jsonStr
            } else {
                extraItemsJSON = ""
            }
        }
    }

    /// 個人識別情報を含まない検査数値のみのAIコンテキスト要約
    public var aiLabSummary: String {
        var parts: [String] = []
        if let sys = systolicBP, let dia = diastolicBP { parts.append("血圧:\(sys)/\(dia)mmHg") }
        if let hb = hemoglobin { parts.append("Hb:\(String(format: "%.1f", hb))g/dL") }
        if let tc = totalCholesterol { parts.append("総Cho:\(tc)mg/dL") }
        if let ldl = ldlCholesterol { parts.append("LDL:\(ldl)mg/dL") }
        if let hdl = hdlCholesterol { parts.append("HDL:\(hdl)mg/dL") }
        if let tg = triglycerides { parts.append("中性脂肪:\(tg)mg/dL") }
        if let ast = ast, let alt = alt { parts.append("AST/ALT:\(ast)/\(alt)U/L") }
        if let ggtp = gammaGTP { parts.append("γ-GTP:\(ggtp)U/L") }
        if let fbg = fastingGlucose { parts.append("血糖:\(fbg)mg/dL") }
        if let a1c = hba1c { parts.append("HbA1c:\(String(format: "%.1f", a1c))%") }
        if let ua = uricAcid { parts.append("尿酸:\(String(format: "%.1f", ua))mg/dL") }
        if let cr = creatinine { parts.append("Cr:\(String(format: "%.2f", cr))mg/dL") }
        if let egfr = egfr { parts.append("eGFR:\(String(format: "%.1f", egfr))") }
        for ex in extraItems where !ex.name.isEmpty && !ex.value.isEmpty {
            parts.append("\(ex.name):\(ex.value)\(ex.unit)")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - 医療費区分
public enum MedicalExpenseCategory: String, CaseIterable, Codable, Identifiable {
    case clinic = "診療・通院"
    case pharmacy = "処方薬・薬局"
    case dental = "歯科"
    case checkup = "健診・人間ドック"
    case otc = "市販薬（対象医薬品）"
    case transport = "通院交通費"
    case other = "その他医療費"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .clinic: return "stethoscope"
        case .pharmacy: return "pills.fill"
        case .dental: return "mouth.fill"
        case .checkup: return "waveform.path.ecg.rectangle.fill"
        case .otc: return "cross.vial.fill"
        case .transport: return "tram.fill"
        case .other: return "doc.text.fill"
        }
    }
}

// MARK: - 医療費記録モデル（CloudKit 準拠：全項目デフォルト値またはOptional）
@Model
public final class MedicalExpenseRecord: Identifiable {
    public var id: UUID = UUID()
    public var paymentDate: Date = Date()
    public var facilityName: String = ""
    public var categoryRaw: String = MedicalExpenseCategory.clinic.rawValue
    public var amountYen: Int = 0
    public var familyMember: String = "本人"
    public var memo: String = ""

    @Attribute(.externalStorage)
    public var receiptImageData: Data? = nil

    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        paymentDate: Date = Date(),
        facilityName: String = "",
        category: MedicalExpenseCategory = .clinic,
        amountYen: Int = 0,
        familyMember: String = "本人",
        memo: String = "",
        receiptImageData: Data? = nil
    ) {
        self.id = id
        self.paymentDate = paymentDate
        self.facilityName = facilityName
        self.categoryRaw = category.rawValue
        self.amountYen = amountYen
        self.familyMember = familyMember
        self.memo = memo
        self.receiptImageData = receiptImageData
        self.createdAt = Date()
    }

    public var category: MedicalExpenseCategory {
        get { MedicalExpenseCategory(rawValue: categoryRaw) ?? .clinic }
        set { categoryRaw = newValue.rawValue }
    }
}
