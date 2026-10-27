import Foundation
import SwiftData

/// 服薬・サプリメントアイテム（毎日00:00自動リセット対応）
/// SwiftData + CloudKit 同期準拠
@Model
public final class MedicationItem {
    public var id: UUID = UUID()
    public var name: String = ""
    public var timingRaw: String = "朝" // 朝, 昼, 夕, 就寝前, 随時
    public var dosage: String = ""    // 例: 1錠, 2カプセル
    public var isCompleted: Bool = false
    public var lastCompletedDate: Date? = nil
    public var orderIndex: Int = 0
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        name: String,
        timingRaw: String = "朝",
        dosage: String = "",
        isCompleted: Bool = false,
        lastCompletedDate: Date? = nil,
        orderIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.timingRaw = timingRaw
        self.dosage = dosage
        self.isCompleted = isCompleted
        self.lastCompletedDate = lastCompletedDate
        self.orderIndex = orderIndex
        self.createdAt = Date()
    }

    /// 00:00 自動リセットチェック
    /// 本日以外に完了されたチェックであれば、自動で未完了にリセットする
    public func resetIfNewDay() {
        guard let lastDate = lastCompletedDate else {
            isCompleted = false
            return
        }

        let calendar = Calendar.current
        if !calendar.isDateInToday(lastDate) {
            isCompleted = false
        }
    }

    /// チェック状態の切り替え
    public func toggleCompletion() {
        isCompleted.toggle()
        if isCompleted {
            lastCompletedDate = Date()
        }
    }
}
