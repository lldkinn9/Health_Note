import SwiftUI
import SwiftData
import UIKit

public enum AppTab: Int, CaseIterable, Identifiable {
    case summary = 0
    case meals = 1
    case profile = 2
    case calendar = 3
    case advisor = 4
    case settings = 5

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .summary: return "サマリ"
        case .meals: return "食事"
        case .profile: return "マイカルテ"
        case .calendar: return "カレンダー"
        case .advisor: return "アドバイザー"
        case .settings: return "設定"
        }
    }

    public var iconName: String {
        switch self {
        case .summary: return "house.fill"
        case .meals: return "fork.knife"
        case .profile: return "heart.text.square.fill"
        case .calendar: return "calendar"
        case .advisor: return "sparkles"
        case .settings: return "gearshape.fill"
        }
    }
}

public extension Notification.Name {
    static let openProfileMedicationSection = Notification.Name("openProfileMedicationSection")
}

/// メインタブ画面（6タブ一列表示：サマリ / 食事 / マイカルテ / カレンダー / アドバイザー / 設定）
/// ※標準TabViewでは6タブ時にiOSが自動で「その他(...)」へ折りたたんでしまうため、6タブすべてを一列で快適に表示するフローティングタブバーを採用
public struct MainTabView: View {
    @State private var selectedTab: AppTab = .summary
    @State private var showingQuickAddMealSheet: Bool = false
    @State private var isKeyboardVisible: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .summary:
                    SummaryView(
                        onOpenProfileMedicationSettings: {
                            selectedTab = .profile
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                NotificationCenter.default.post(name: .openProfileMedicationSection, object: nil)
                            }
                        }
                    )
                case .meals:
                    MealsView()
                case .profile:
                    HealthProfileView()
                case .calendar:
                    CalendarView()
                case .advisor:
                    AdvisorView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !isKeyboardVisible {
                sixItemTabBar
            }
        }
        .sheet(isPresented: $showingQuickAddMealSheet) {
            AddMealView()
        }
        .onOpenURL { url in
            handleDeepLink(url: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .task {
            await AdMobManager.shared.requestATTAndStartAds()
        }
    }

    // MARK: - 6アイテム横一列フローティングカプセルタブバー
    private var sixItemTabBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.35)

            HStack(spacing: 2) {
                ForEach(AppTab.allCases) { tab in
                    let isSelected = (selectedTab == tab)
                    Button(action: {
                        guard selectedTab != tab else { return }
                        let gen = UISelectionFeedbackGenerator()
                        gen.selectionChanged()
                        selectedTab = tab
                    }) {
                        VStack(spacing: 3) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 17, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? AppTheme.emerald : .primary.opacity(0.68))
                                .frame(height: 20)

                            Text(tab.title)
                                .font(.system(size: 9.5, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? AppTheme.emerald : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(isSelected ? AppTheme.emerald.opacity(0.14) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
        .background(.ultraThinMaterial)
    }

    /// ウィジェットや通知からのディープリンク処理（例: healthnote://add-meal）
    private func handleDeepLink(url: URL) {
        guard url.scheme == "healthnote" else { return }

        switch url.host {
        case "add-meal":
            selectedTab = .meals
            showingQuickAddMealSheet = true
        case "calendar":
            selectedTab = .calendar
        case "advisor":
            selectedTab = .advisor
        case "profile":
            selectedTab = .profile
        default:
            selectedTab = .summary
        }
    }
}

// =============================================================================
// MARK: - 「カレンダー」画面（月間スタンプカレンダー ＋ 選択日の詳細情報表示）
// =============================================================================
public struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meal.timestamp, order: .forward) private var allMeals: [Meal]
    @Query private var profiles: [HealthProfile]
    @Query private var dailyLogs: [DailyHealthLog]
    @Query(sort: \MedicationItem.orderIndex) private var medications: [MedicationItem]
    @Query(sort: \MedicalExpenseRecord.paymentDate, order: .reverse) private var medicalExpenses: [MedicalExpenseRecord]
    @Query(sort: \HealthCheckRecord.examDate, order: .reverse) private var healthChecks: [HealthCheckRecord]

    @StateObject private var healthKit = HealthKitManager.shared

    @State private var displayedMonthDate: Date = Date()
    @State private var selectedDate: Date = Date()
    @State private var selectedDayHKMetrics: HealthKitManager.DayHealthKitMetrics = .init()
    @State private var isLoadingDayMetrics: Bool = false

    // 受診明細・検査結果のタップ確認用モーダル
    @State private var editingExpense: MedicalExpenseRecord? = nil
    @State private var editingHealthCheck: HealthCheckRecord? = nil

    private let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    public init() {}

    private var profile: HealthProfile? {
        profiles.first
    }

    public var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 18) {
                        // 1. 月切替バー ＆ スタンプ凡例
                        monthHeaderBar

                        // 2. 月間カレンダーカード（薬スタンプ・聴診器スタンプのみをシンプル表示）
                        monthlyCalendarGrid(scrollProxy: scrollProxy)

                        // 3. タップした日の詳細情報パネル
                        selectedDayDetailCard
                            .id("selected_day_detail_card")

                        Spacer().frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AdBottomBannerBar()
            }
            .navigationTitle("カレンダー")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingExpense) { item in
                MedicalExpenseEditorSheet(recordToEdit: item)
            }
            .sheet(item: $editingHealthCheck) { item in
                HealthCheckEditorSheet(recordToEdit: item)
            }
            .onAppear {
                loadHealthKitForSelectedDate(selectedDate)
            }
            .onChange(of: selectedDate) { _, newDate in
                loadHealthKitForSelectedDate(newDate)
            }
        }
    }

    // MARK: - 1. 月セレクター ＆ スタンプ凡例
    private var monthHeaderBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: { shiftMonth(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                        .overlay(Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 1))
                }

                Text(formatMonthTitle(displayedMonthDate))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.18), lineWidth: 1))

                Button(action: { shiftMonth(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                        .overlay(Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 1))
                }

                Spacer()

                if !Calendar.current.isDate(displayedMonthDate, equalTo: Date(), toGranularity: .month) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            displayedMonthDate = Date()
                            selectedDate = Date()
                        }
                    }) {
                        Text("今月")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppTheme.emerald)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(AppTheme.emerald.opacity(0.12)))
                    }
                }
            }

            // スタンプ凡例
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    pillStampBadge(size: 18)
                    Text("服薬・サプリ摂取完了")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 5) {
                    stethoscopeStampBadge(size: 18)
                    Text("診療・受診・検査記録")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
    }

    // MARK: - 2. 月間カレンダーグリッド（個人用アプリUI準拠：薬マーク＋下に聴診器マーク、数値非表示）
    private func monthlyCalendarGrid(scrollProxy: ScrollViewProxy) -> some View {
        let days = generateCalendarDays(for: displayedMonthDate)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

        return VStack(spacing: 12) {
            // 曜日ヘッダー
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { idx in
                    Text(weekdays[idx])
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(
                            idx == 0 ? .red :
                            (idx == 6 ? .blue : .secondary)
                        )
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)

            Divider().opacity(0.5)

            // 日付セルグリッド
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, dateOpt in
                    if let dayDate = dateOpt {
                        dayCell(for: dayDate, scrollProxy: scrollProxy)
                    } else {
                        Color.clear
                            .frame(height: 62)
                    }
                }
            }
        }
        .padding(14)
        .appCard()
    }

    @ViewBuilder
    private func dayCell(for date: Date, scrollProxy: ScrollViewProxy) -> some View {
        let cal = Calendar.current
        let dayNum = cal.component(.day, from: date)
        let weekday = cal.component(.weekday, from: date) // 1: 日, 7: 土
        let isToday = cal.isDateInToday(date)
        let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
        let hasMedStamp = isMedicationCompleted(on: date)
        let hasClinicStamp = hasMedicalVisitRecord(on: date)

        Button(action: {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDate = date
            }
        }) {
            HStack(alignment: .top, spacing: 0) {
                // 左上：日付番号（当日はエメラルド丸バッジ）
                ZStack {
                    if isToday {
                        Circle()
                            .fill(AppTheme.emerald)
                            .frame(width: 22, height: 22)
                    }
                    Text("\(dayNum)")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundColor(
                            isToday ? .white :
                            (weekday == 1 ? .red : (weekday == 7 ? .blue : .primary))
                        )
                }
                .frame(width: 22, height: 22)

                Spacer(minLength: 1)

                // 右側スタンプ枠：上段＝薬マーク、その下＝聴診器マーク
                VStack(spacing: 4) {
                    if hasMedStamp {
                        pillStampBadge(size: 20)
                    } else {
                        Color.clear.frame(width: 20, height: 20)
                    }

                    if hasClinicStamp {
                        stethoscopeStampBadge(size: 20)
                    } else {
                        Color.clear.frame(width: 20, height: 20)
                    }
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(isSelected ? AppTheme.emerald.opacity(0.08) : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(
                        isSelected ? AppTheme.emerald : Color.secondary.opacity(0.16),
                        lineWidth: isSelected ? 2.0 : 1.0
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// 薬マークのスタンプ（個人用アプリ風のイエロー/アンバーピルバッジ）
    private func pillStampBadge(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.36)
                .fill(Color.orange.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.36)
                        .stroke(Color.orange.opacity(0.55), lineWidth: 1)
                )
            Image(systemName: "pills.fill")
                .font(.system(size: size * 0.52, weight: .bold))
                .foregroundColor(.orange)
        }
        .frame(width: size, height: size)
    }

    /// 聴診器マークのスタンプ（薬マークの下に表示される受診・診療スタンプ）
    private func stethoscopeStampBadge(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.36)
                .fill(Color.cyan.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.36)
                        .stroke(Color.cyan.opacity(0.55), lineWidth: 1)
                )
            Image(systemName: "stethoscope")
                .font(.system(size: size * 0.52, weight: .bold))
                .foregroundColor(.teal)
        }
        .frame(width: size, height: size)
    }

    // MARK: - 3. 選択日の詳細情報パネル（体重・体脂肪率・歩数・食事内容・摂取カロリー・消費カロリー・受診内容）
    private var selectedDayDetailCard: some View {
        let dayMeals = meals(on: selectedDate)
        let intakeCal = dayMeals.reduce(0.0) { $0 + $1.calories }
        let burnedCal = resolvedBurnedCalories(on: selectedDate)
        let stepsCount = resolvedStepCount(on: selectedDate)
        let dayWeight = resolvedWeight(on: selectedDate)
        let dayBodyFat = resolvedBodyFat(on: selectedDate)
        let dayExpenses = expenses(on: selectedDate)
        let dayChecks = checks(on: selectedDate)
        let medDone = isMedicationCompleted(on: selectedDate)

        return VStack(alignment: .leading, spacing: 16) {
            // 日付タイトル ＆ スタンプバッジ
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.emerald)

                Text("\(formatFullJapaneseDate(selectedDate)) の記録")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                if isLoadingDayMetrics {
                    ProgressView()
                        .scaleEffect(0.75)
                }

                if medDone {
                    HStack(spacing: 3) {
                        Image(systemName: "pills.fill")
                            .font(.system(size: 10))
                        Text("服薬完了")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.14)))
                }
            }

            // A. 体組成・歩数・カロリーサマリ（体重 / 体脂肪率 / 歩数 / 摂取カロリー / 消費カロリー）
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    compactStatTile(
                        title: "体重",
                        value: dayWeight != nil ? String(format: "%.1f", dayWeight!) : "--",
                        unit: "kg",
                        icon: "scalemass.fill",
                        color: .blue
                    )

                    compactStatTile(
                        title: "体脂肪率",
                        value: dayBodyFat != nil ? String(format: "%.1f", dayBodyFat!) : "--",
                        unit: "%",
                        icon: "percent",
                        color: .purple
                    )

                    compactStatTile(
                        title: "歩数",
                        value: stepsCount > 0 ? Int(stepsCount).formatted() : "0",
                        unit: "歩",
                        icon: "figure.walk",
                        color: .green
                    )
                }

                HStack(spacing: 8) {
                    compactStatTile(
                        title: "摂取カロリー",
                        value: Int(intakeCal).formatted(),
                        unit: "kcal",
                        icon: "fork.knife",
                        color: AppTheme.calorieIntake
                    )

                    compactStatTile(
                        title: "消費カロリー（安静時＋運動）",
                        value: Int(burnedCal).formatted(),
                        unit: "kcal",
                        icon: "flame.fill",
                        color: AppTheme.calorieBurn
                    )
                }
            }

            Divider()

            // B. 食事内容
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppTheme.calorieIntake)
                    Text("食事内容（\(dayMeals.count)件）")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                }

                if dayMeals.isEmpty {
                    Text("この日の食事記録はありません")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    VStack(spacing: 8) {
                        ForEach(dayMeals) { meal in
                            HStack(spacing: 10) {
                                if let imgData = meal.imageData, let uiImg = UIImage(data: imgData) {
                                    Image(uiImage: uiImg)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 42, height: 42)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(AppTheme.calorieIntake.opacity(0.12))
                                            .frame(width: 42, height: 42)
                                        Image(systemName: meal.mealType.iconName)
                                            .font(.system(size: 16))
                                            .foregroundColor(AppTheme.calorieIntake)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(meal.mealType.rawValue)
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(AppTheme.emerald)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(AppTheme.emerald.opacity(0.12)))

                                        Text(formatTime(meal.timestamp))
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }

                                    Text(meal.name)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.primary)
                                        .lineLimit(2)

                                    Text("P:\(Int(meal.protein))g  F:\(Int(meal.fat))g  C:\(Int(meal.carbs))g")
                                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text("\(Int(meal.calories)) kcal")
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                                    .foregroundColor(AppTheme.calorieIntake)
                            }
                            .padding(10)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }

            Divider()

            // C. 受診内容（診療明細・調剤明細・健診/検査結果）
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.teal)
                    Text("受診・診療・検査内容（\(dayExpenses.count + dayChecks.count)件）")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                }

                if dayExpenses.isEmpty && dayChecks.isEmpty {
                    Text("この日の受診・診療記録はありません")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    VStack(spacing: 8) {
                        // 診療明細・調剤明細など医療費レコード
                        ForEach(dayExpenses) { exp in
                            Button(action: { editingExpense = exp }) {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.cyan.opacity(0.14))
                                            .frame(width: 40, height: 40)
                                        Image(systemName: exp.category.iconName)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.teal)
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(exp.category.rawValue)
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.teal)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(Capsule().fill(Color.cyan.opacity(0.14)))

                                            Text(exp.familyMember)
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.indigo)
                                        }

                                        Text(exp.facilityName.isEmpty ? exp.category.rawValue : exp.facilityName)
                                            .font(.system(size: 13.5, weight: .bold))
                                            .foregroundColor(.primary)
                                            .multilineTextAlignment(.leading)

                                        if !exp.memo.isEmpty {
                                            Text(exp.memo)
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("¥\(exp.amountYen.formatted())")
                                            .font(.system(size: 14, weight: .black, design: .rounded))
                                            .foregroundColor(.primary)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(10)
                                .background(Color(.tertiarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }

                        // 健診・検査結果レコード
                        ForEach(dayChecks) { check in
                            Button(action: { editingHealthCheck = check }) {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(AppTheme.emerald.opacity(0.14))
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "waveform.path.ecg.rectangle.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(AppTheme.emerald)
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("健診・検査結果")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(AppTheme.emerald)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(AppTheme.emerald.opacity(0.14)))

                                        Text(check.facilityName.isEmpty ? "健診・血液検査記録" : check.facilityName)
                                            .font(.system(size: 13.5, weight: .bold))
                                            .foregroundColor(.primary)

                                        let labSummary = check.aiLabSummary
                                        if !labSummary.isEmpty {
                                            Text(labSummary)
                                                .font(.system(size: 11, design: .rounded))
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                        } else if !check.memo.isEmpty {
                                            Text(check.memo)
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.secondary)
                                }
                                .padding(10)
                                .background(Color(.tertiarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
        .appCard()
    }

    @ViewBuilder
    private func compactStatTile(title: String, value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Data Resolution Helpers

    /// その日の服薬/サプリメントがすべて完了しているか（当日はリアルタイム判定、過去日は DailyHealthLog を参照）
    private func isMedicationCompleted(on date: Date) -> Bool {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let activeItems = medications.filter { !$0.selectedTimings.isEmpty }
            if !activeItems.isEmpty {
                return activeItems.allSatisfy { med in
                    med.selectedTimings.allSatisfy { timing in
                        med.isTakenToday(for: timing)
                    }
                }
            }
        }
        let key = DailyHealthLog.makeDateKey(for: date)
        return dailyLogs.first(where: { $0.dateKey == key })?.isMedicationCompleted ?? false
    }

    /// その日に診療・受診・調剤・検査結果のいずれかの記録があるか
    private func hasMedicalVisitRecord(on date: Date) -> Bool {
        let cal = Calendar.current
        let hasExp = medicalExpenses.contains { cal.isDate($0.paymentDate, inSameDayAs: date) }
        if hasExp { return true }
        return healthChecks.contains { cal.isDate($0.examDate, inSameDayAs: date) }
    }

    private func meals(on date: Date) -> [Meal] {
        let cal = Calendar.current
        return allMeals.filter { cal.isDate($0.timestamp, inSameDayAs: date) }
    }

    private func expenses(on date: Date) -> [MedicalExpenseRecord] {
        let cal = Calendar.current
        return medicalExpenses.filter { cal.isDate($0.paymentDate, inSameDayAs: date) }
    }

    private func checks(on date: Date) -> [HealthCheckRecord] {
        let cal = Calendar.current
        return healthChecks.filter { cal.isDate($0.examDate, inSameDayAs: date) }
    }

    private func resolvedWeight(on date: Date) -> Double? {
        if let hkW = selectedDayHKMetrics.weightKg, hkW > 0 { return hkW }
        if let checkW = checks(on: date).first?.weightKg, checkW > 0 { return checkW }
        let key = DailyHealthLog.makeDateKey(for: date)
        if let logW = dailyLogs.first(where: { $0.dateKey == key })?.weightKg, logW > 0 { return logW }
        if Calendar.current.isDateInToday(date), let profW = profile?.weightKg, profW > 0 { return profW }
        return nil
    }

    private func resolvedBodyFat(on date: Date) -> Double? {
        if let hkBF = selectedDayHKMetrics.bodyFatPercentage, hkBF > 0 { return hkBF }
        if let checkBF = checks(on: date).first?.bodyFatPercent, checkBF > 0 { return checkBF }
        let key = DailyHealthLog.makeDateKey(for: date)
        if let logBF = dailyLogs.first(where: { $0.dateKey == key })?.bodyFatPercentage, logBF > 0 { return logBF }
        if Calendar.current.isDateInToday(date), let profBF = profile?.bodyFatPercentage, profBF > 0 { return profBF }
        return nil
    }

    private func resolvedStepCount(on date: Date) -> Double {
        if selectedDayHKMetrics.stepCount > 0 { return selectedDayHKMetrics.stepCount }
        if Calendar.current.isDateInToday(date) { return healthKit.vitals.stepCount }
        return 0
    }

    private func resolvedBurnedCalories(on date: Date) -> Double {
        if selectedDayHKMetrics.burnedCalories > 0 { return selectedDayHKMetrics.burnedCalories }
        if Calendar.current.isDateInToday(date) { return healthKit.vitals.totalEnergyBurned }
        return 0
    }

    private func loadHealthKitForSelectedDate(_ date: Date) {
        selectedDayHKMetrics = .init()
        guard healthKit.isAvailable else { return }
        isLoadingDayMetrics = true
        Task {
            let fetched = await healthKit.fetchDayMetrics(for: date)
            await MainActor.run {
                if Calendar.current.isDate(date, inSameDayAs: self.selectedDate) {
                    self.selectedDayHKMetrics = fetched
                    self.isLoadingDayMetrics = false
                }
            }
        }
    }

    // MARK: - Calendar Date Generation & Formatting
    private func shiftMonth(by months: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: months, to: displayedMonthDate) {
            withAnimation(.easeInOut(duration: 0.2)) {
                displayedMonthDate = next
            }
        }
    }

    private func generateCalendarDays(for monthDate: Date) -> [Date?] {
        let cal = Calendar.current
        guard let monthInterval = cal.dateInterval(of: .month, for: monthDate),
              let daysRange = cal.range(of: .day, in: .month, for: monthDate) else {
            return []
        }

        let firstDayOfMonth = monthInterval.start
        let firstWeekday = cal.component(.weekday, from: firstDayOfMonth) // 1 = 日曜 ... 7 = 土曜
        let leadingEmptyCount = firstWeekday - 1

        var result: [Date?] = Array(repeating: nil, count: leadingEmptyCount)
        for day in daysRange {
            if let d = cal.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                result.append(d)
            }
        }

        let remainder = result.count % 7
        if remainder != 0 {
            result.append(contentsOf: Array(repeating: nil, count: 7 - remainder))
        }
        return result
    }

    private func formatMonthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年 M月"
        return f.string(from: date)
    }

    private func formatFullJapaneseDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日(E)"
        return f.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "H:mm"
        return f.string(from: date)
    }
}
