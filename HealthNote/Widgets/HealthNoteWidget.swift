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
                intakeCalories: 580,
                burnedCalories: 1219,
                proteinGrams: 45,
                fatGrams: 42,
                carbsGrams: 4,
                lastMealTimeAgo: "5 hr, 38 min 前",
                lastMealDate: Calendar.current.date(byAdding: .minute, value: -338, to: Date())
            )
        )
    }

    public func getSnapshot(in context: Context, completion: @escaping (HealthNoteEntry) -> Void) {
        let saved = WidgetDataManager.shared.loadWidgetData()
        // ウィジェットギャラリーでのプレビュー時に完全空データの場合は見やすいサンプルを表示
        if context.isPreview && saved.intakeCalories == 0 && saved.burnedCalories == 0 && saved.lastMealDate == nil {
            completion(placeholder(in: context))
            return
        }
        completion(HealthNoteEntry(date: Date(), summary: saved))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<HealthNoteEntry>) -> Void) {
        let data = WidgetDataManager.shared.loadWidgetData()
        let entry = HealthNoteEntry(date: Date(), summary: data)

        // 15分ごとにタイムライン更新（経過時間は style: .relative により毎分自動カウントアップ）
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget View (systemMedium 横長 — 個人用アプリUI準拠)
public struct HealthNoteWidgetEntryView: View {
    public var entry: HealthNoteEntry

    public init(entry: HealthNoteEntry) {
        self.entry = entry
    }

    private let widgetBg = Color(red: 0.13, green: 0.15, blue: 0.21)      // #212636 ダークスレートネイビー
    private let cyanAccent = Color(red: 0.02, green: 0.71, blue: 0.83)    // #06B6D4 シアン
    private let orangeAccent = Color(red: 0.98, green: 0.45, blue: 0.09)  // #F97316 オレンジ
    private let greenAccent = Color(red: 0.06, green: 0.73, blue: 0.51)   // #10B981 エメラルド
    private let yellowAccent = Color(red: 0.92, green: 0.70, blue: 0.03)  // #EAB308 イエロー

    public var body: some View {
        HStack(spacing: 12) {
            // 左側カラム（ブランド・摂取/消費カロリー・前回食事からの経過時間）
            leftColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            // 中央の縦区切り線
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1)
                .padding(.vertical, 2)

            // 右側カラム（PFCバランス グラム＆3色バー・＋食事登録ボタン）
            rightColumn
                .frame(width: 124)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .containerBackground(for: .widget) {
            ZStack {
                widgetBg
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
    }

    // MARK: - 左側カラム
    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. ブランドヘッダー
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(orangeAccent)
                Text("Health Note")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Spacer(minLength: 6)

            // 2. 摂取カロリー ｜ 消費カロリー（カンマ区切り・大型フォント）
            HStack(alignment: .center, spacing: 10) {
                // 摂取
                VStack(alignment: .leading, spacing: 2) {
                    Text("摂取")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(orangeAccent)

                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(Int(entry.summary.intakeCalories).formatted())
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("kcal")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1, height: 32)

                // 消費
                VStack(alignment: .leading, spacing: 2) {
                    Text("消費")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(greenAccent)

                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(Int(entry.summary.burnedCalories).formatted())
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("kcal")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }

            Spacer(minLength: 6)

            // 3. 前回食事からの経過時間（iOS標準 .relative タイマーでリアルタイム更新）
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(cyanAccent)

                Text("前回食事から")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .layoutPriority(1)

                if let lastDate = entry.summary.lastMealDate, lastDate <= Date() {
                    Text(lastDate, style: .relative)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(cyanAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 0)

                    Text("前")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(cyanAccent.opacity(0.85))
                } else {
                    Text(entry.summary.lastMealTimeAgo)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(cyanAccent)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - 右側カラム（PFCバランス ＆ 食事登録ボタン）
    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PFCバランス")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
                .padding(.bottom, 5)

            // P / F / C ラベルとグラム数（2段組）
            HStack(spacing: 6) {
                pfcMetricColumn(label: "P", grams: entry.summary.proteinGrams, color: cyanAccent)
                pfcMetricColumn(label: "F", grams: entry.summary.fatGrams, color: yellowAccent)
                pfcMetricColumn(label: "C", grams: entry.summary.carbsGrams, color: greenAccent)
            }
            .padding(.bottom, 6)

            // 3色プログレスバー（グラム数の下に配置）
            pfcBar

            Spacer(minLength: 8)

            // ＋ 食事登録ボタン（タップでアプリ内食事登録モーダル直行）
            Link(destination: URL(string: "healthnote://add-meal")!) {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("食事登録")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.43, green: 0.31, blue: 0.96),
                            Color(red: 0.72, green: 0.25, blue: 0.95)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 11))
            }
        }
    }

    @ViewBuilder
    private func pfcMetricColumn(label: String, grams: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text("\(Int(grams))g")
                .font(.system(size: 12.5, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pfcBar: some View {
        let p = max(0, entry.summary.proteinGrams)
        let f = max(0, entry.summary.fatGrams)
        let c = max(0, entry.summary.carbsGrams)
        let sum = p + f + c
        let pRatio: CGFloat = sum > 0 ? CGFloat(p / sum) : 0.34
        let fRatio: CGFloat = sum > 0 ? CGFloat(f / sum) : 0.33
        let cRatio: CGFloat = sum > 0 ? CGFloat(c / sum) : 0.33

        return GeometryReader { geo in
            let availableWidth = max(12, geo.size.width - 6)
            HStack(spacing: 3) {
                Capsule()
                    .fill(cyanAccent)
                    .frame(width: max(4, availableWidth * pRatio))

                Capsule()
                    .fill(yellowAccent)
                    .frame(width: max(4, availableWidth * fRatio))

                Capsule()
                    .fill(greenAccent)
                    .frame(width: max(4, availableWidth * cRatio))
            }
        }
        .frame(height: 5)
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
        .description("摂取・消費カロリー、前回食事からの経過時間、PFCバランスをホーム画面に表示します。")
        .supportedFamilies([.systemMedium])
    }
}
