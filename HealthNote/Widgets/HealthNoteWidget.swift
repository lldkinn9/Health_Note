import WidgetKit
import SwiftUI

// MARK: - Widget Timeline Entry
public struct HealthNoteEntry: TimelineEntry {
    public let date: Date
    public let summary: WidgetSummaryData

    public init(date: Date, summary: WidgetSummaryData) {
        self.date = date
        self.summary = summary
    }
}

// MARK: - Widget Provider
public struct HealthNoteTimelineProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> HealthNoteEntry {
        HealthNoteEntry(
            date: Date(),
            summary: WidgetSummaryData(
                intakeCalories: 1450,
                burnedCalories: 1820,
                proteinGrams: 68,
                fatGrams: 42,
                carbsGrams: 180,
                lastMealTimeAgo: "2 hr, 52 min 前"
            )
        )
    }

    public func getSnapshot(in context: Context, completion: @escaping (HealthNoteEntry) -> Void) {
        let data = WidgetDataManager.shared.loadWidgetData()
        let entry = HealthNoteEntry(date: Date(), summary: data)
        completion(entry)
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<HealthNoteEntry>) -> Void) {
        let data = WidgetDataManager.shared.loadWidgetData()
        let entry = HealthNoteEntry(date: Date(), summary: data)

        // 15分ごとにタイムライン更新
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget View (systemMedium 横長)
public struct HealthNoteWidgetEntryView: View {
    public var entry: HealthNoteEntry

    public init(entry: HealthNoteEntry) {
        self.entry = entry
    }

    public var body: some View {
        HStack(spacing: 12) {
            // 左側カラム（広め）
            leftColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            // 縦の境界線
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 4)

            // 右側カラム（幅115ptにコンパクト化）
            rightColumn
                .frame(width: 115)
        }
        .padding(14)
        .containerBackground(for: .widget) {
            ZStack {
                AppTheme.deepNavy // #0F172A
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppTheme.cardBorderSubtle, lineWidth: 1)
            }
        }
    }

    // MARK: - 左側カラム
    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 1. ブランド
            HStack(spacing: 4) {
                Text("🔥")
                    .font(.system(size: 13))
                Text("Health Note")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }

            Spacer()

            // 2. 摂取カロリー ｜ 消費カロリー（4桁対応、フォント18pt rounded、文字切れ防止）
            HStack(spacing: 8) {
                // 摂取
                VStack(alignment: .leading, spacing: 1) {
                    Text("摂取")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.orange.opacity(0.9))
                    HStack(alignment: .lastTextBaseline, spacing: 1) {
                        Text("\(Int(entry.summary.intakeCalories))")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("cal")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Text("|")
                    .foregroundColor(Color.white.opacity(0.2))
                    .font(.system(size: 16, weight: .light))

                // 消費
                VStack(alignment: .leading, spacing: 1) {
                    Text("消費")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.green.opacity(0.9))
                    HStack(alignment: .lastTextBaseline, spacing: 1) {
                        Text("\(Int(entry.summary.burnedCalories))")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("cal")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }

            Spacer()

            // 3. 下部: 前回食事からの経過時間（相対時間表示）
            HStack(spacing: 4) {
                Text("⏳")
                    .font(.system(size: 10))
                Text(entry.summary.lastMealTimeAgo)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    // MARK: - 右側カラム（幅115pt）
    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. PFCバランス（グラム数 ＆ 3色プログレスバー）
            VStack(alignment: .leading, spacing: 4) {
                // 3色プログレスバー
                let total = max(1.0, entry.summary.proteinGrams + entry.summary.fatGrams + entry.summary.carbsGrams)
                let pRatio = CGFloat(entry.summary.proteinGrams / total)
                let fRatio = CGFloat(entry.summary.fatGrams / total)
                let cRatio = CGFloat(entry.summary.carbsGrams / total)

                GeometryReader { geo in
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppTheme.proteinColor)
                            .frame(width: max(3, geo.size.width * pRatio))

                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppTheme.fatColor)
                            .frame(width: max(3, geo.size.width * fRatio))

                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppTheme.carbsColor)
                            .frame(width: max(3, geo.size.width * cRatio))
                    }
                }
                .frame(height: 5)
                .clipShape(Capsule())

                // P, F, C グラム数表示
                HStack(spacing: 4) {
                    pfcBadge(label: "P", grams: entry.summary.proteinGrams, color: AppTheme.proteinColor)
                    pfcBadge(label: "F", grams: entry.summary.fatGrams, color: AppTheme.fatColor)
                    pfcBadge(label: "C", grams: entry.summary.carbsGrams, color: AppTheme.carbsColor)
                }
            }

            Spacer()

            // 2. ＋ 食事登録ボタン（タップでアプリ内食事登録モーダル直行ディープリンク）
            Link(destination: URL(string: "healthnote://add-meal")!) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("食事登録")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(AppTheme.actionGradient)
                .clipShape(Capsule())
                .shadow(color: Color.purple.opacity(0.4), radius: 4, x: 0, y: 2)
            }
        }
    }

    @ViewBuilder
    private func pfcBadge(label: String, grams: Double, color: Color) -> some View {
        HStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(color)
            Text("\(Int(grams))")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Widget Definition (Widget Extension Entry Point)
@main
public struct HealthNoteWidget: Widget {
    public let kind: String = "HealthNoteWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HealthNoteTimelineProvider()) { entry in
            HealthNoteWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Health Note サマリ")
        .description("本日のカロリー・PFCバランスと経過時間をリアルタイム確認。")
        .supportedFamilies([.systemMedium])
    }
}
