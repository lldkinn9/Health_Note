import Foundation
import SwiftData

/// 服薬（処方薬・市販薬）かサプリメントかの区分
public enum MedicationKind: String, CaseIterable, Codable, Identifiable {
    case medication = "medication"   // 服薬（薬）
    case supplement = "supplement"   // サプリメント

    public var id: String { rawValue }
}

/// 飲むタイミング（起床 / 朝 / 昼 / 夜 / 就寝前）— 複数同時選択対応
public enum DoseTiming: String, CaseIterable, Codable, Identifiable {
    case wakeUp = "起床"
    case morning = "朝"
    case noon = "昼"
    case night = "夜"
    case bedtime = "就寝前"

    public var id: String { rawValue }
}

/// 容量の単位（錠 / 袋 / 包）
public enum DosageUnitOption: String, CaseIterable, Codable, Identifiable {
    case tablet = "錠"
    case bag = "袋"
    case packet = "包"

    public var id: String { rawValue }
}

/// 服薬・サプリメント管理モデル（毎日00:00自動リセット・タイミング別＆アイテム別の詳細摂取記録対応）
/// SwiftData + CloudKit 同期準拠（既存スキーマからの自動移行対応）
@Model
public final class MedicationItem: Identifiable {
    public var id: UUID = UUID()
    public var name: String = ""

    /// "medication"（薬） または "supplement"（サプリ）
    public var itemTypeRaw: String = MedicationKind.medication.rawValue

    /// 処方日（服薬カード用）
    public var prescribedDate: Date? = nil

    /// 複数選択されたタイミングのカンマ区切り（例: "朝,夜"）
    public var timingsCSV: String = ""

    /// 旧バージョン互換用タイミング文字列
    public var timingRaw: String = "朝"

    /// 1回あたりの容量数値（例: "1", "2", "0.5"）
    public var dosageAmount: String = "1"

    /// 容量の単位（"錠" / "袋" / "包"）
    public var dosageUnit: String = DosageUnitOption.tablet.rawValue

    /// 旧バージョン互換用表示文字列（例: "1錠"）
    public var dosage: String = "1錠"

    /// 本日摂取済みのタイミング（カンマ区切り、例: "起床" / "朝,夜"）
    public var completedTimingsTodayCSV: String = ""

    public var isCompleted: Bool = false
    public var lastCompletedDate: Date? = nil
    public var orderIndex: Int = 0
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        name: String = "",
        kind: MedicationKind = .medication,
        prescribedDate: Date? = nil,
        timings: [DoseTiming] = [.morning],
        dosageAmount: String = "1",
        dosageUnit: String = DosageUnitOption.tablet.rawValue,
        isCompleted: Bool = false,
        lastCompletedDate: Date? = nil,
        orderIndex: Int = 0
    ) {
        self.id = id
        self.name = Self.sanitizeName(name)
        self.itemTypeRaw = kind.rawValue
        self.prescribedDate = prescribedDate ?? (kind == .medication ? Date() : nil)

        let ordered = DoseTiming.allCases.filter { timings.contains($0) }
        let finalTimings = ordered.isEmpty ? [DoseTiming.morning] : ordered
        self.timingsCSV = finalTimings.map(\.rawValue).joined(separator: ",")
        self.timingRaw = finalTimings.map(\.rawValue).joined(separator: "・")

        let cleanAmount = dosageAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        self.dosageAmount = cleanAmount.isEmpty ? "1" : cleanAmount
        self.dosageUnit = dosageUnit.isEmpty ? DosageUnitOption.tablet.rawValue : dosageUnit
        self.dosage = "\(self.dosageAmount)\(self.dosageUnit)"

        self.isCompleted = isCompleted
        self.lastCompletedDate = lastCompletedDate
        if isCompleted {
            self.completedTimingsTodayCSV = self.timingsCSV
        }
        self.orderIndex = orderIndex
        self.createdAt = Date()
    }

    // MARK: - Computed Helpers

    public static func sanitizeName(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "<br>", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "<br >", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "", options: .caseInsensitive)
    }

    public var cleanName: String {
        let s = Self.sanitizeName(name).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? (kind == .medication ? "名称未入力の薬" : "名称未入力のサプリ") : s
    }

    public var kind: MedicationKind {
        get { MedicationKind(rawValue: itemTypeRaw) ?? .medication }
        set { itemTypeRaw = newValue.rawValue }
    }

    /// 選択されている飲むタイミング一覧（起床→朝→昼→夜→就寝前 の順）
    public var selectedTimings: [DoseTiming] {
        get {
            if !timingsCSV.trimmingCharacters(in: .whitespaces).isEmpty {
                let parts = Set(timingsCSV.split(separator: ",").map { String($0) })
                let mapped = DoseTiming.allCases.filter { parts.contains($0.rawValue) }
                if !mapped.isEmpty { return mapped }
            }
            // 旧データ（timingRaw）からのフォールバック変換
            switch timingRaw {
            case "起床": return [.wakeUp]
            case "朝": return [.morning]
            case "昼": return [.noon]
            case "夕", "夜": return [.night]
            case "就寝前": return [.bedtime]
            default: return [.morning]
            }
        }
        set {
            let ordered = DoseTiming.allCases.filter { newValue.contains($0) }
            timingsCSV = ordered.map(\.rawValue).joined(separator: ",")
            timingRaw = ordered.map(\.rawValue).joined(separator: "・")
            syncLegacyCompletionFlag()
        }
    }

    /// 1回あたりのフォーマット済み容量テキスト（例: "1錠", "2包", "1袋"）
    public var formattedDosage: String {
        let amt = dosageAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        if !amt.isEmpty {
            let unit = dosageUnit.isEmpty ? DosageUnitOption.tablet.rawValue : dosageUnit
            return "\(amt)\(unit)"
        }
        return dosage
    }

    public func updateDosage(amount: String, unit: String) {
        dosageAmount = amount
        dosageUnit = unit
        let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        dosage = trimmed.isEmpty ? "" : "\(trimmed)\(unit)"
    }

    public func hasTiming(_ timing: DoseTiming) -> Bool {
        selectedTimings.contains(timing)
    }

    public func toggleTimingSelection(_ timing: DoseTiming) {
        var current = selectedTimings
        if let idx = current.firstIndex(of: timing) {
            current.remove(at: idx)
        } else {
            current.append(timing)
        }
        let ordered = DoseTiming.allCases.filter { current.contains($0) }
        timingsCSV = ordered.map(\.rawValue).joined(separator: ",")
        timingRaw = ordered.map(\.rawValue).joined(separator: "・")
        syncLegacyCompletionFlag()
    }

    // MARK: - 毎日 00:00 自動リセット ＆ タイミング別摂取ステータス管理

    /// 本日（00:00〜23:59）に指定タイミング分を摂取済みかどうかを判定
    public func isTakenToday(for timing: DoseTiming) -> Bool {
        guard let lastDate = lastCompletedDate, Calendar.current.isDateInToday(lastDate) else {
            return false
        }
        if !completedTimingsTodayCSV.isEmpty {
            let parts = Set(completedTimingsTodayCSV.split(separator: ",").map { String($0) })
            return parts.contains(timing.rawValue)
        }
        // 旧データ移行直後の当日チェック互換
        return isCompleted && hasTiming(timing)
    }

    /// 指定タイミングの摂取状態を明示的にセット
    public func setTakenToday(_ taken: Bool, for timing: DoseTiming) {
        resetIfNewDay()
        var currentSet: Set<String> = {
            guard let lastDate = lastCompletedDate, Calendar.current.isDateInToday(lastDate) else {
                return []
            }
            if !completedTimingsTodayCSV.isEmpty {
                return Set(completedTimingsTodayCSV.split(separator: ",").map { String($0) })
            }
            if isCompleted {
                return Set(selectedTimings.map(\.rawValue))
            }
            return []
        }()

        if taken {
            currentSet.insert(timing.rawValue)
        } else {
            currentSet.remove(timing.rawValue)
        }

        let ordered = DoseTiming.allCases.map(\.rawValue).filter { currentSet.contains($0) }
        completedTimingsTodayCSV = ordered.joined(separator: ",")
        lastCompletedDate = ordered.isEmpty ? nil : Date()
        syncLegacyCompletionFlag()
    }

    /// 指定タイミングの摂取状態を反転（個別アイテムタップ用）
    public func toggleIntakeToday(for timing: DoseTiming) {
        let next = !isTakenToday(for: timing)
        setTakenToday(next, for: timing)
    }

    /// 00:00 自動リセットチェック
    public func resetIfNewDay() {
        guard let lastDate = lastCompletedDate else {
            isCompleted = false
            completedTimingsTodayCSV = ""
            return
        }
        if !Calendar.current.isDateInToday(lastDate) {
            isCompleted = false
            completedTimingsTodayCSV = ""
            lastCompletedDate = nil
        }
    }

    private func syncLegacyCompletionFlag() {
        let active = selectedTimings
        guard !active.isEmpty,
              let lastDate = lastCompletedDate,
              Calendar.current.isDateInToday(lastDate) else {
            isCompleted = false
            return
        }
        let takenSet = Set(completedTimingsTodayCSV.split(separator: ",").map { String($0) })
        isCompleted = active.allSatisfy { takenSet.contains($0.rawValue) }
    }
}
