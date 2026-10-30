import SwiftUI
import SwiftData

/// サマリ画面右上の「＋」メニューから起動する登録モーダル種別
private enum SummaryQuickAddType: String, Identifiable {
    case meal
    case healthCheck
    case clinicExpense
    case pharmacyExpense

    var id: String { rawValue }
}

/// 「サマリ」画面（摂取/消費/ネットカロリー、服薬記録・サプリメント記録、主要バイタル）
public struct SummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Meal.timestamp, order: .forward) private var allMeals: [Meal]
    @Query private var profiles: [HealthProfile]
    @Query private var dailyLogs: [DailyHealthLog]
    @Query(sort: \MedicationItem.orderIndex) private var medications: [MedicationItem]

    @StateObject private var healthKit = HealthKitManager.shared
    @State private var activeQuickAddModal: SummaryQuickAddType? = nil

    public var onOpenProfileMedicationSettings: (() -> Void)?

    public init(onOpenProfileMedicationSettings: (() -> Void)? = nil) {
        self.onOpenProfileMedicationSettings = onOpenProfileMedicationSettings
    }

    private var profile: HealthProfile? {
        profiles.first
    }

    /// 本日の食事データ
    private var todaysMeals: [Meal] {
        let calendar = Calendar.current
        return allMeals.filter { calendar.isDateInToday($0.timestamp) }
    }

    private var intakeCalories: Double { todaysMeals.reduce(0) { $0 + $1.calories } }
    private var proteinGrams: Double { todaysMeals.reduce(0) { $0 + $1.protein } }
    private var fatGrams: Double { todaysMeals.reduce(0) { $0 + $1.fat } }
    private var carbsGrams: Double { todaysMeals.reduce(0) { $0 + $1.carbs } }

    private var burnedCalories: Double { healthKit.vitals.totalEnergyBurned }
    private var netCalories: Double { intakeCalories - burnedCalories }

    private var medicationOnlyItems: [MedicationItem] {
        medications.filter { $0.kind == .medication }
    }

    private var supplementOnlyItems: [MedicationItem] {
        medications.filter { $0.kind == .supplement }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. カロリーダッシュボードカード
                    calorieDashboardCard

                    // 2. PFCバランスカード
                    pfcCard

                    // 3. 服薬記録カード（毎日 00:00 自動リセット・タイミング一括＆個別チェック）
                    intakeTrackerCard(
                        title: "服薬記録",
                        iconName: "pills",
                        accentColor: .orange,
                        items: medicationOnlyItems,
                        emptyGuide: "マイカルテの「服薬・サプリメント管理」から処方薬や常備薬を登録すると、ここでタイミング別・薬別に摂取記録を管理できます。"
                    )

                    // 4. サプリメント記録カード（毎日 00:00 自動リセット・タイミング一括＆個別チェック）
                    intakeTrackerCard(
                        title: "サプリメント記録",
                        iconName: "sparkles",
                        accentColor: AppTheme.emerald,
                        items: supplementOnlyItems,
                        emptyGuide: "マイカルテの「服薬・サプリメント管理」からサプリメントを登録すると、ここでタイミング別・サプリ別に摂取記録を管理できます。"
                    )

                    // 5. 主要バイタルセクション（Apple HealthKit）
                    vitalsSection

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AdBottomBannerBar()
            }
            .navigationTitle("今日のサマリ")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: { activeQuickAddModal = .meal }) {
                            Label("食事", systemImage: "fork.knife")
                        }
                        Button(action: { activeQuickAddModal = .healthCheck }) {
                            Label("検査結果", systemImage: "waveform.path.ecg.rectangle.fill")
                        }
                        Button(action: { activeQuickAddModal = .clinicExpense }) {
                            Label("診療明細", systemImage: "stethoscope")
                        }
                        Button(action: { activeQuickAddModal = .pharmacyExpense }) {
                            Label("調剤明細", systemImage: "pills.fill")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(AppTheme.emerald)
                    }
                }
            }
            .sheet(item: $activeQuickAddModal) { modalType in
                switch modalType {
                case .meal:
                    AddMealView()
                case .healthCheck:
                    HealthCheckEditorSheet(recordToEdit: nil)
                case .clinicExpense:
                    MedicalExpenseEditorSheet(
                        recordToEdit: nil,
                        initialCategory: .clinic,
                        customTitle: "診療明細の記録"
                    )
                case .pharmacyExpense:
                    MedicalExpenseEditorSheet(
                        recordToEdit: nil,
                        initialCategory: .pharmacy,
                        customTitle: "調剤明細の記録"
                    )
                }
            }
            .onAppear {
                checkMedicationDailyResets()
                refreshData()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    checkMedicationDailyResets()
                    refreshData()
                }
            }
            .onChange(of: allMeals.count) { _, _ in
                syncToWidget()
            }
            .refreshable {
                await healthKit.fetchTodayVitals()
                syncToWidget()
            }
        }
    }

    // MARK: - 1. カロリーダッシュボード
    private var calorieDashboardCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("カロリーバランス")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            // 摂取・消費・ネットの3分割グリッド
            HStack(alignment: .top, spacing: 12) {
                // 摂取カロリー
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppTheme.calorieIntake)
                        Text("摂取")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(Int(intakeCalories))")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(AppTheme.calorieIntake)
                            .preventTruncation()
                        Text("kcal")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 44)

                // 消費カロリー（下に小さく「安静時＋運動」を表記）
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppTheme.calorieBurn)
                        Text("消費")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(Int(burnedCalories))")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(AppTheme.calorieBurn)
                            .preventTruncation()
                        Text("kcal")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Text("安静時＋運動")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 44)

                // ネットカロリー
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "plusminus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.blue)
                        Text("ネット")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(Int(netCalories))")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.primary)
                            .preventTruncation()
                        Text("kcal")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .appCard()
    }

    // MARK: - 2. PFCバランスカード
    private var pfcCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本日のPFCバランス")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.secondary)

            PFCBalanceView(
                protein: proteinGrams,
                fat: fatGrams,
                carbs: carbsGrams
            )
        }
        .padding(16)
        .appCard()
    }

    // MARK: - 3 & 4. 服薬記録・サプリメント記録カード（個人用アプリUI準拠 ＋ 個別摂取管理）
    @ViewBuilder
    private func intakeTrackerCard(
        title: String,
        iconName: String,
        accentColor: Color,
        items: [MedicationItem],
        emptyGuide: String
    ) -> some View {
        let activeTimings = DoseTiming.allCases.filter { timing in
            items.contains { $0.hasTiming(timing) }
        }
        let activeTimingNames = activeTimings.map(\.rawValue).joined(separator: "・")

        VStack(alignment: .leading, spacing: 14) {
            // ヘッダー部分
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(accentColor)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.primary)

                        Text("毎日 00:00 自動リセット")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color(.tertiarySystemGroupedBackground)))
                    }

                    if let onOpenProfileMedicationSettings {
                        Button(action: onOpenProfileMedicationSettings) {
                            HStack(spacing: 4) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 11, weight: .bold))
                                Text("マイカルテでタイミング設定")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    if !activeTimings.isEmpty {
                        Text("対象タイミング（\(activeTimingNames)）のボタンを押して一括記録、または下の各項目をタップして個別に記録できます")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
            }

            if items.isEmpty || activeTimings.isEmpty {
                Text(emptyGuide)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // 5つのタイミングボタン（起床 / 朝 / 昼 / 夜 / 就寝前）
                HStack(spacing: 6) {
                    ForEach(DoseTiming.allCases) { timing in
                        let scheduled = items.filter { $0.hasTiming(timing) }
                        let totalCount = scheduled.count
                        let takenCount = scheduled.filter { $0.isTakenToday(for: timing) }.count
                        let isEnabled = totalCount > 0
                        let isAllTaken = isEnabled && takenCount == totalCount
                        let isPartial = isEnabled && takenCount > 0 && takenCount < totalCount

                        Button(action: {
                            guard isEnabled else { return }
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            let shouldMarkTaken = !isAllTaken
                            for item in scheduled {
                                item.setTakenToday(shouldMarkTaken, for: timing)
                            }
                            syncTodayMedicationStampToDailyLog()
                            try? modelContext.save()
                        }) {
                            VStack(spacing: 3) {
                                HStack(spacing: 2) {
                                    if isAllTaken {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .black))
                                    }
                                    Text(timing.rawValue)
                                        .font(.system(size: 12, weight: .bold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                                .foregroundColor(
                                    !isEnabled ? Color.secondary.opacity(0.45) :
                                    (isAllTaken ? .white : .primary)
                                )

                                if isEnabled {
                                    Text(isPartial ? "\(takenCount)/\(totalCount)種" : "\(totalCount)種")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(isAllTaken ? .white.opacity(0.92) : accentColor)
                                } else {
                                    Text(" ")
                                        .font(.system(size: 10))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        !isEnabled ? Color(.tertiarySystemGroupedBackground) :
                                        (isAllTaken ? accentColor : (isPartial ? accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground)))
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        !isEnabled ? Color.clear : accentColor.opacity(isAllTaken ? 1.0 : 0.65),
                                        lineWidth: isEnabled ? 1.5 : 0
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEnabled)
                    }
                }

                // タイミング別の登録内容 ＆ 1種類ごとの個別摂取チェック一覧
                VStack(spacing: 8) {
                    ForEach(activeTimings) { timing in
                        let scheduled = items.filter { $0.hasTiming(timing) }
                        let allTaken = !scheduled.isEmpty && scheduled.allSatisfy { $0.isTakenToday(for: timing) }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                Text("[\(timing.rawValue)]")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(allTaken ? accentColor : .secondary)
                                    .frame(minWidth: 38, alignment: .leading)
                                    .padding(.top, 3)

                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(scheduled) { med in
                                        let taken = med.isTakenToday(for: timing)
                                        Button(action: {
                                            let generator = UIImpactFeedbackGenerator(style: .light)
                                            generator.impactOccurred()
                                            med.toggleIntakeToday(for: timing)
                                            syncTodayMedicationStampToDailyLog()
                                            try? modelContext.save()
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: taken ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 15, weight: .bold))
                                                    .foregroundColor(taken ? accentColor : .secondary.opacity(0.45))

                                                Text(med.cleanName)
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(taken ? .primary : .primary.opacity(0.85))
                                                    .multilineTextAlignment(.leading)

                                                Spacer(minLength: 4)

                                                let doseText = med.formattedDosage
                                                if !doseText.isEmpty {
                                                    Text(doseText)
                                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                                        .foregroundColor(taken ? accentColor : .secondary)
                                                        .padding(.horizontal, 7)
                                                        .padding(.vertical, 2)
                                                        .background(
                                                            Capsule()
                                                                .fill(taken ? accentColor.opacity(0.16) : Color(.systemBackground))
                                                        )
                                                }
                                            }
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(allTaken ? accentColor.opacity(0.10) : Color(.tertiarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(allTaken ? accentColor.opacity(0.45) : Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding(16)
        .appCard()
    }

    // MARK: - 5. 主要バイタルセクション
    private var vitalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "heart.text.square.fill")
                        .foregroundColor(.pink)
                    Text("ヘルスケア・バイタル")
                        .font(.system(size: 15, weight: .bold))
                }
                Spacer()

                if !healthKit.isAuthorized {
                    Button(action: {
                        Task { _ = await healthKit.requestAuthorization() }
                    }) {
                        Text("連携する")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppTheme.emerald)
                    }
                }
            }

            // 2×2 バイタルグリッド
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCard(
                    title: "歩数",
                    value: "\(Int(healthKit.vitals.stepCount))",
                    unit: "歩",
                    icon: "figure.walk",
                    iconColor: .green
                )

                MetricCard(
                    title: "最新心拍",
                    value: healthKit.vitals.latestHeartRate != nil ? "\(Int(healthKit.vitals.latestHeartRate!))" : "--",
                    unit: "bpm",
                    icon: "heart.fill",
                    iconColor: .red
                )

                MetricCard(
                    title: "睡眠時間",
                    value: String(format: "%.1f", healthKit.vitals.sleepHours),
                    unit: "時間",
                    icon: "bed.double.fill",
                    iconColor: .indigo
                )

                MetricCard(
                    title: "安静時代謝",
                    value: "\(Int(healthKit.vitals.basalEnergyBurned))",
                    unit: "kcal",
                    icon: "bolt.heart.fill",
                    iconColor: .orange
                )
            }
        }
    }

    // MARK: - Helpers & Data Sync
    private func checkMedicationDailyResets() {
        for med in medications {
            med.resetIfNewDay()
        }
        syncTodayMedicationStampToDailyLog()
        try? modelContext.save()
    }

    /// カレンダーの薬スタンプ表示用：本日の登録済み服薬・サプリメントがすべて摂取完了しているかを DailyHealthLog に記録
    private func syncTodayMedicationStampToDailyLog() {
        let activeItems = medications.filter { !$0.selectedTimings.isEmpty }
        let allCompletedToday = !activeItems.isEmpty && activeItems.allSatisfy { med in
            med.selectedTimings.allSatisfy { timing in
                med.isTakenToday(for: timing)
            }
        }

        let todayKey = DailyHealthLog.makeDateKey(for: Date())
        if let existing = dailyLogs.first(where: { $0.dateKey == todayKey }) {
            existing.isMedicationCompleted = allCompletedToday
            existing.updatedAt = Date()
        } else if allCompletedToday {
            let log = DailyHealthLog(
                dateKey: todayKey,
                isMedicationCompleted: true,
                weightKg: profile?.weightKg,
                bodyFatPercentage: profile?.bodyFatPercentage
            )
            modelContext.insert(log)
        }
    }

    private func refreshData() {
        Task {
            if healthKit.isAvailable {
                await healthKit.ensureBodyMetricsAuthorizationAndFetch()
                syncHealthKitBodyMetricsToProfileIfNewer()
            }
            syncToWidget()
        }
    }

    /// 起動直後やフォアグラウンド復帰時に、ヘルスケア側の新しい体重・体脂肪率があればマイカルテ＆日次ログへ自動反映
    private func syncHealthKitBodyMetricsToProfileIfNewer() {
        guard let targetProfile = profile else { return }
        let manualDate = targetProfile.manualBodyMetricsUpdatedAt
        var didUpdate = false

        if let hkW = healthKit.vitals.latestWeightKg, hkW > 0 {
            let hkDate = healthKit.vitals.latestWeightDate ?? Date()
            if manualDate == nil || hkDate >= manualDate! {
                let rounded = (hkW * 10).rounded() / 10.0
                if abs(targetProfile.weightKg - rounded) > 0.05 {
                    targetProfile.weightKg = rounded
                    didUpdate = true
                }
            }
        }

        if let hkBF = healthKit.vitals.latestBodyFatPercentage, hkBF > 0 {
            let hkDate = healthKit.vitals.latestBodyFatDate ?? Date()
            if manualDate == nil || hkDate >= manualDate! {
                let rounded = (hkBF * 10).rounded() / 10.0
                if targetProfile.bodyFatPercentage == nil || abs((targetProfile.bodyFatPercentage ?? 0) - rounded) > 0.05 {
                    targetProfile.bodyFatPercentage = rounded
                    didUpdate = true
                }
            }
        }

        if didUpdate {
            let todayKey = DailyHealthLog.makeDateKey(for: Date())
            if let existing = dailyLogs.first(where: { $0.dateKey == todayKey }) {
                existing.weightKg = targetProfile.weightKg
                if let bf = targetProfile.bodyFatPercentage, bf > 0 {
                    existing.bodyFatPercentage = bf
                }
                existing.updatedAt = Date()
            } else {
                let log = DailyHealthLog(
                    dateKey: todayKey,
                    isMedicationCompleted: false,
                    weightKg: targetProfile.weightKg,
                    bodyFatPercentage: targetProfile.bodyFatPercentage
                )
                modelContext.insert(log)
            }
            try? modelContext.save()
        }
    }

    private func syncToWidget() {
        let latestMeal = allMeals.filter { $0.timestamp <= Date() }.last ?? todaysMeals.last
        WidgetDataManager.shared.updateWidgetData(
            intakeCalories: intakeCalories,
            burnedCalories: burnedCalories,
            protein: proteinGrams,
            fat: fatGrams,
            carbs: carbsGrams,
            lastMealDate: latestMeal?.timestamp
        )
    }
}
