import SwiftUI
import SwiftData

/// 「サマリ」画面（摂取/消費/ネットカロリー、服薬・サプリトグル、主要バイタル）
public struct SummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meal.timestamp, order: .forward) private var allMeals: [Meal]
    @Query private var profiles: [HealthProfile]
    @Query(sort: \MedicationItem.orderIndex) private var medications: [MedicationItem]

    @StateObject private var healthKit = HealthKitManager.shared
    @State private var showingAddMealModal: Bool = false

    public init() {}

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

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. カロリーダッシュボードカード
                    calorieDashboardCard

                    // 2. PFCバランスカード
                    pfcCard

                    // 3. 服薬・サプリメントチェック（毎日00:00自動リセット）
                    medicationCheckSection

                    // 4. 主要バイタルセクション（Apple HealthKit）
                    vitalsSection

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("今日のサマリ")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingAddMealModal = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(AppTheme.emerald)
                    }
                }
            }
            .sheet(isPresented: $showingAddMealModal) {
                AddMealView()
            }
            .onAppear {
                checkMedicationDailyResets()
                refreshData()
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
                if let target = profile?.targetCalories {
                    Text("目標: \(Int(target)) kcal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            // 摂取・消費・ネットの3分割グリッド
            HStack(spacing: 12) {
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

                Divider().frame(height: 35)

                // 消費カロリー
                VStack(alignment: .leading, spacing: 4) {
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 35)

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
                carbs: carbsGrams,
                targetProtein: profile?.targetProtein,
                targetFat: profile?.targetFat,
                targetCarbs: profile?.targetCarbs
            )
        }
        .padding(16)
        .appCard()
    }

    // MARK: - 3. 服薬・サプリメントチェック
    private var medicationCheckSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "pills.fill")
                        .foregroundColor(.purple)
                    Text("本日の服薬・サプリ")
                        .font(.system(size: 15, weight: .bold))
                }
                Spacer()
                Text("毎日00:00自動リセット")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if medications.isEmpty {
                Text("マイカルテ画面から服薬やサプリを登録すると、ここに日々のチェックリストが表示されます。")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(medications) { med in
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            med.toggleCompletion()
                            try? modelContext.save()
                        }) {
                            HStack {
                                Image(systemName: med.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundColor(med.isCompleted ? AppTheme.emerald : .secondary.opacity(0.5))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(med.name)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(med.isCompleted ? .secondary : .primary)
                                        .strikethrough(med.isCompleted, color: .secondary)

                                    HStack(spacing: 4) {
                                        Text(med.timingRaw)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.purple)
                                        if !med.dosage.isEmpty {
                                            Text("(\(med.dosage))")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }

                                Spacer()

                                if med.isCompleted {
                                    Text("完了")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(AppTheme.emerald)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        if med.id != medications.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(16)
        .appCard()
    }

    // MARK: - 4. 主要バイタルセクション
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
                        Task { await healthKit.requestAuthorization() }
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
        try? modelContext.save()
    }

    private func refreshData() {
        Task {
            if healthKit.isAvailable {
                await healthKit.fetchTodayVitals()
            }
            syncToWidget()
        }
    }

    private func syncToWidget() {
        let lastMeal = todaysMeals.last
        WidgetDataManager.shared.updateWidgetData(
            intakeCalories: intakeCalories,
            burnedCalories: burnedCalories,
            protein: proteinGrams,
            fat: fatGrams,
            carbs: carbsGrams,
            lastMealDate: lastMeal?.timestamp
        )
    }
}
