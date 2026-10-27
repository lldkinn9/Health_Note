import Foundation
import SwiftData

/// 1日の食事総括・AIアドバイザー評価キャッシュ
/// SwiftData + CloudKit 同期準拠
@Model
public final class DailyAdvice {
    public var id: UUID = UUID()
    public var dateKey: String = "" // "yyyy-MM-dd"
    public var adviceText: String = ""
    public var score: Int = 80 // 1-100のバランススコア
    public var goodPoints: String = ""
    public var improvementPoints: String = ""
    public var generatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        dateKey: String,
        adviceText: String,
        score: Int = 80,
        goodPoints: String = "",
        improvementPoints: String = "",
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.dateKey = dateKey
        self.adviceText = adviceText
        self.score = score
        self.goodPoints = goodPoints
        self.improvementPoints = improvementPoints
        self.generatedAt = generatedAt
    }

    /// 今日の日付キーを生成するヘルパー
    public static func makeDateKey(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
