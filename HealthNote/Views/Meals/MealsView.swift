import SwiftUI
import SwiftData

/// 「食事」画面（食事ログ一覧、AI食事登録、最下部AIアドバイザー評価ブロック）
public struct MealsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meal.timestamp, order: .forward) private var allMeals: [Meal]
    @Query private var profiles: [HealthProfile]
    @Query private var adviceList: [DailyAdvice]

    @State private var selectedDate: Date = Date()
    @State private var showingAddMeal: Bool = false
    @State private var defaultMealTypeToAdd: MealType = .lunch
    @State private var isGeneratingAdvice: Bool = false
    @State private var adviceErrorMessage: String? = nil

    public init() {}

    private var profile: HealthProfile? {
        profiles.first
    }

    /// 選択された日付の食事ログ
    private var todaysMeals: [Meal] {
        let calendar = Calendar.current
        return allMeals.filter { calendar.isDate($0.timestamp, inSameDayAs: selectedDate) }
    }

    /// 選択日の日付キー
    private var selectedDateKey: String {
        DailyAdvice.makeDateKey(for: selectedDate)
    }

    /// 本日のAIアドバイスキャッシュ
    private var todaysAdvice: DailyAdvice? {
        adviceList.first { $0.dateKey == selectedDateKey }
    }

    // 本日の合計値
    private var totalCalories: Double { todaysMeals.reduce(0) { $0 + $1.calories } }
    private var totalProtein: Double { todaysMeals.reduce(0) { $0 + $1.protein } }
    private var totalFat: Double { todaysMeals.reduce(0) { $0 + $1.fat } }
    private var totalCarbs: Double { todaysMeals.reduce(0) { $0 + $1.carbs } }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. 日付セレクター
                    dateSelectorHeader

                    // 2. 本日の合計カロリー & PFC進捗
                    dailyNutritionHeader

                    // 3. 食事記録リスト
                    mealListSection

                    // 4. 新規登録ボタン（インディゴ〜パープルグラデーション）
                    addMealActionButton

                    // 5. 【最下部】AIアドバイザー評価ブロック
                    aiDailyEvaluationBlock

                    // 6. カード埋め込み型バナー広告（案A）
                    AdBannerCardView(placementName: "meals_bottom")

                    Spacer().frame(height: 30)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("食事ログ")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAddMeal) {
                AddMealView(defaultMealType: defaultMealTypeToAdd)
            }
        }
    }

    // MARK: - 1. 日付セレクター
    private var dateSelectorHeader: some View {
        HStack {
            Button(action: { changeDate(by: -1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(8)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundColor(AppTheme.emerald)
                Text(formatDate(selectedDate))
                    .font(.system(size: 15, weight: .bold))
            }

            Spacer()

            Button(action: { changeDate(by: 1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .appCard()
    }

    // MARK: - 2. 本日の合計カロリー & PFC
    private var dailyNutritionHeader: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("摂取カロリー合計")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(Int(totalCalories))")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(AppTheme.calorieIntake)
                            .preventTruncation()

                        if let target = profile?.targetCalories {
                            Text("/ \(Int(target)) kcal")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                        } else {
                            Text("kcal")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
            }

            Divider()

            // PFCバランス
            PFCBalanceView(
                protein: totalProtein,
                fat: totalFat,
                carbs: totalCarbs,
                targetProtein: profile?.targetProtein,
                targetFat: profile?.targetFat,
                targetCarbs: profile?.targetCarbs
            )
        }
        .padding(16)
        .appCard()
    }

    // MARK: - 3. 食事記録リスト
    private var mealListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本日の記録（\(todaysMeals.count)件）")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.secondary)

            if todaysMeals.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "fork.knife.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("まだこの日の食事が記録されていません")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .appCard()
            } else {
                ForEach(todaysMeals) { meal in
                    mealRow(meal: meal)
                }
            }
        }
    }

    @ViewBuilder
    private func mealRow(meal: Meal) -> some View {
        HStack(spacing: 12) {
            // 写真サムネイルまたは食事アイコン
            if let imageData = meal.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(meal.mealType.themeColor.opacity(0.12))
                        .frame(width: 60, height: 60)

                    Image(systemName: meal.mealType.iconName)
                        .font(.system(size: 24))
                        .foregroundColor(meal.mealType.themeColor)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(meal.mealType.rawValue)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(meal.mealType.themeColor.opacity(0.15)))
                        .foregroundColor(meal.mealType.themeColor)

                    Text(formatTime(meal.timestamp))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Spacer()

                    if meal.healthKitSynced {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.pink)
                    }
                }

                Text(meal.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // カロリー & PFC
                HStack(spacing: 8) {
                    Text("\(Int(meal.calories)) kcal")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.calorieIntake)

                    Text("P:\(Int(meal.protein))g F:\(Int(meal.fat))g C:\(Int(meal.carbs))g")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 削除ボタン
            Button(role: .destructive, action: {
                modelContext.delete(meal)
                try? modelContext.save()
                syncWidgetAfterDelete()
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(12)
        .appCard()
    }

    // MARK: - 4. 新規登録ボタン
    private var addMealActionButton: some View {
        Button(action: {
            defaultMealTypeToAdd = guessMealType()
            showingAddMeal = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "camera.badge.ellipsis")
                    .font(.system(size: 16, weight: .bold))
                Text("食事を記録する（写真AI解析 / 手動）")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.actionGradient)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
            .shadow(color: Color.purple.opacity(0.25), radius: 8, x: 0, y: 4)
        }
    }

    // MARK: - 5. 【最下部】AIアドバイザー評価ブロック
    private var aiDailyEvaluationBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.indigo)
                    Text("本日のAI食事総括・栄養評価")
                        .font(.system(size: 16, weight: .bold))
                }

                Spacer()

                if isGeneratingAdvice {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button(action: { generateAdvice() }) {
                        Label(todaysAdvice == nil ? "評価を生成" : "再評価", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.indigo)
                    }
                    .disabled(todaysMeals.isEmpty)
                }
            }

            if let advice = todaysAdvice {
                VStack(alignment: .leading, spacing: 12) {
                    // スコアバッジ
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(Color.indigo.opacity(0.15), lineWidth: 5)
                                .frame(width: 54, height: 54)
                            Circle()
                                .trim(from: 0, to: CGFloat(advice.score) / 100.0)
                                .stroke(AppTheme.emerald, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 54, height: 54)

                            Text("\(advice.score)")
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundColor(.primary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("栄養バランススコア")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(advice.score >= 80 ? "大変優れたバランスです！" : "あと少しで目標達成です")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AppTheme.emerald)
                        }
                    }

                    // 総括テキスト
                    Text(advice.adviceText)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineSpacing(3)

                    if !advice.goodPoints.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "hand.thumbsup.fill")
                                .foregroundColor(AppTheme.emerald)
                                .font(.system(size: 12))
                            Text(advice.goodPoints)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

                    if !advice.improvementPoints.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                            Text(advice.improvementPoints)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    let hasApiKey = GeminiService.shared.getApiKey() != nil
                    if hasApiKey {
                        Text(todaysMeals.isEmpty ? "食事を記録すると、AIが1日の栄養バランスを総合評価します。" : "右上の「評価を生成」ボタンを押すと、AIが本日の食事を総括講評します。")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    } else {
                        Text("【任意オプション】\n食事を記録するとPFCバランスとカロリーが集計されます。\nGemini APIキーをお持ちの方は「設定」で登録すると、AIによる総合栄養講評も受けられます。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
            }

            if let adviceErrorMessage {
                Text(adviceErrorMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            // 医療免責表記（医師法・薬機法準拠）
            Text("※本アドバイスは医師法・薬機法に基づき、病気の診断・治療や医薬品的な効能効果を標榜するものではなく、日常の健康的な食習慣改善のための参考指標です。")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding(16)
        .appCard()
    }

    // MARK: - AIアドバイス生成
    private func generateAdvice() {
        guard !todaysMeals.isEmpty else { return }
        isGeneratingAdvice = true
        adviceErrorMessage = nil

        Task {
            do {
                let result = try await GeminiService.shared.generateDailyEvaluation(meals: todaysMeals, profile: profile)
                await MainActor.run {
                    if let existing = todaysAdvice {
                        existing.score = result.score
                        existing.adviceText = result.summary
                        existing.goodPoints = result.goodPoints
                        existing.improvementPoints = result.improvementPoints
                        existing.generatedAt = Date()
                    } else {
                        let newAdvice = DailyAdvice(
                            dateKey: selectedDateKey,
                            adviceText: result.summary,
                            score: result.score,
                            goodPoints: result.goodPoints,
                            improvementPoints: result.improvementPoints
                        )
                        modelContext.insert(newAdvice)
                    }
                    try? modelContext.save()
                    isGeneratingAdvice = false
                }
            } catch {
                await MainActor.run {
                    self.adviceErrorMessage = error.localizedDescription
                    self.isGeneratingAdvice = false
                }
            }
        }
    }

    // MARK: - Helpers
    private func changeDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            selectedDate = newDate
        }
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今日"
        } else if calendar.isDateInYesterday(date) {
            return "昨日"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 (E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter.string(from: date)
    }

    private func guessMealType() -> MealType {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snack
        }
    }

    private func syncWidgetAfterDelete() {
        let calendar = Calendar.current
        let todayList = allMeals.filter { calendar.isDateInToday($0.timestamp) }
        let intake = todayList.reduce(0) { $0 + $1.calories }
        let p = todayList.reduce(0) { $0 + $1.protein }
        let f = todayList.reduce(0) { $0 + $1.fat }
        let c = todayList.reduce(0) { $0 + $1.carbs }
        let burned = HealthKitManager.shared.vitals.totalEnergyBurned

        WidgetDataManager.shared.updateWidgetData(
            intakeCalories: intake,
            burnedCalories: burned,
            protein: p,
            fat: f,
            carbs: c,
            lastMealDate: todayList.last?.timestamp
        )
    }
}
