import SwiftUI
import SwiftData

/// 食品辞書（複数選択・分量調整・検索）＆ 過去の食事履歴からワンタップ再利用シート
public struct FoodDictionaryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Meal.timestamp, order: .reverse) private var pastMeals: [Meal]

    public enum PickerMode: String, CaseIterable {
        case dictionary = "📖 食品辞書から選ぶ"
        case history = "🕒 過去の記録から再利用"
    }

    @State private var mode: PickerMode = .dictionary
    @State private var searchText: String = ""
    @State private var selectedCategory: FoodCategory = .all
    @State private var selectedEntries: [SelectedFoodEntry] = []

    /// 選択完了コールバック: (料理名, カロリー, P, F, C)
    public let onApplySelection: (String, Double, Double, Double, Double) -> Void

    public init(onApplySelection: @escaping (String, Double, Double, Double, Double) -> Void) {
        self.onApplySelection = onApplySelection
    }

    // MARK: - フィルタリングされた辞書アイテム
    private var filteredItems: [FoodDictionaryItem] {
        FoodDictionaryCatalog.allItems.filter { item in
            let matchesCategory = (selectedCategory == .all) || (item.category == selectedCategory)
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return matchesCategory
            }
            let query = trimmed.lowercased()
            let matchesSearch = item.name.lowercased().contains(query)
                || item.keywords.lowercased().contains(query)
                || item.unitDescription.lowercased().contains(query)
            return matchesCategory && matchesSearch
        }
    }

    // MARK: - 重複排除された過去の食事履歴
    private var uniquePastMeals: [Meal] {
        var seen = Set<String>()
        var result: [Meal] = []
        for meal in pastMeals {
            let key = "\(meal.name)_\(Int(meal.calories))"
            if !seen.contains(key) && !meal.name.isEmpty {
                seen.insert(key)
                result.append(meal)
            }
            if result.count >= 50 { break }
        }
        return result
    }

    // MARK: - 選択中アイテムの合算値
    private var totalCalories: Double {
        selectedEntries.reduce(0) { $0 + $1.adjustedCalories }
    }
    private var totalProtein: Double {
        ((selectedEntries.reduce(0) { $0 + $1.adjustedProtein }) * 10).rounded() / 10
    }
    private var totalFat: Double {
        ((selectedEntries.reduce(0) { $0 + $1.adjustedFat }) * 10).rounded() / 10
    }
    private var totalCarbs: Double {
        ((selectedEntries.reduce(0) { $0 + $1.adjustedCarbs }) * 10).rounded() / 10
    }
    private var combinedName: String {
        selectedEntries.map { $0.displayNameWithPortion }.joined(separator: "・")
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // 1. モード切替（食品辞書 / 過去の履歴）
                    Picker("モード", selection: $mode) {
                        ForEach(PickerMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(Color(.secondarySystemGroupedBackground))

                    if mode == .dictionary {
                        dictionaryContentView
                    } else {
                        historyContentView
                    }
                }
                .background(Color(.systemGroupedBackground).ignoresSafeArea())

                // 下部フローティング合算バー（辞書モードで1品以上選択時）
                if mode == .dictionary && !selectedEntries.isEmpty {
                    bottomSelectionSummaryBar
                }
            }
            .navigationTitle("かんたん栄養入力")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                if mode == .dictionary && !selectedEntries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("クリア") {
                            withAnimation { selectedEntries.removeAll() }
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }

    // MARK: - 📖 食品辞書コンテンツ
    private var dictionaryContentView: some View {
        VStack(spacing: 0) {
            // 検索バー
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("食品名・メニュー名で検索（例: 白米、鶏むね、納豆）", text: $searchText)
                    .font(.system(size: 14))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .background(Color(.secondarySystemGroupedBackground))

            // カテゴリ横スクロールチップ
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FoodCategory.allCases) { category in
                        let isSelected = (selectedCategory == category)
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedCategory = category
                            }
                        }) {
                            Text(category.rawValue)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(isSelected ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? AppTheme.emerald : Color(.systemBackground))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .background(Color(.secondarySystemGroupedBackground))

            Divider()

            // 食品リスト
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filteredItems) { item in
                        foodItemRow(item: item)
                    }

                    // 下部フローティングバー用の余白
                    Spacer().frame(height: selectedEntries.isEmpty ? 24 : 150)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
    }

    @ViewBuilder
    private func foodItemRow(item: FoodDictionaryItem) -> some View {
        let entryIndex = selectedEntries.firstIndex(where: { $0.item.id == item.id })
        let isSelected = (entryIndex != nil)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)

                        Text(item.unitDescription)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(Capsule())
                    }

                    // カロリー & PFC
                    HStack(spacing: 10) {
                        Text("\(Int(item.calories)) kcal")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(AppTheme.calorieIntake)

                        HStack(spacing: 6) {
                            Text("P:\(String(format: "%.1f", item.protein))g")
                                .foregroundColor(AppTheme.proteinColor)
                            Text("F:\(String(format: "%.1f", item.fat))g")
                                .foregroundColor(AppTheme.fatColor)
                            Text("C:\(String(format: "%.1f", item.carbs))g")
                                .foregroundColor(AppTheme.carbsColor)
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                }

                Spacer()

                // 追加 / 解除ボタン
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    toggleItem(item)
                }) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(isSelected ? AppTheme.emerald : .indigo)
                }
            }

            // 選択中は分量（0.5人前 / 1人前 / 1.5人前 / 2人前）調整チップを表示
            if let idx = entryIndex {
                Divider()
                HStack(spacing: 6) {
                    Text("分量:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { mult in
                        let active = (selectedEntries[idx].multiplier == mult)
                        Button(action: {
                            selectedEntries[idx].multiplier = mult
                        }) {
                            Text(mult == 0.5 ? "0.5倍(半分)" : "\(String(format: mult == floor(mult) ? "%.0f" : "%.1f", mult))人前")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(active ? .white : .primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(active ? AppTheme.emerald : Color(.tertiarySystemGroupedBackground))
                                )
                        }
                    }

                    Spacer()

                    Text("計 \(Int(selectedEntries[idx].adjustedCalories))kcal")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.emerald)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? AppTheme.emerald : Color.clear, lineWidth: 1.5)
                )
        )
    }

    // MARK: - 🕒 過去の記録から再利用コンテンツ
    private var historyContentView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if uniquePastMeals.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("過去の食事記録がまだありません。\n一度記録した食事はここからワンタップで再利用できます。")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
                } else {
                    ForEach(uniquePastMeals) { meal in
                        Button(action: {
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                            onApplySelection(meal.name, meal.calories, meal.protein, meal.fat, meal.carbs)
                            dismiss()
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meal.name)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

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

                                HStack(spacing: 4) {
                                    Text("反映")
                                        .font(.system(size: 12, weight: .bold))
                                    Image(systemName: "checkmark.circle.fill")
                                }
                                .foregroundColor(AppTheme.emerald)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.emerald.opacity(0.12))
                                .clipShape(Capsule())
                            }
                            .padding(14)
                            .appCard()
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - 下部フローティング合算バー
    private var bottomSelectionSummaryBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("選択中（\(selectedEntries.count)品）: \(combinedName)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                Text("\(Int(totalCalories)) kcal")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.calorieIntake)
            }

            HStack(spacing: 12) {
                Text("合計 P: \(String(format: "%.1f", totalProtein))g")
                    .foregroundColor(AppTheme.proteinColor)
                Text("F: \(String(format: "%.1f", totalFat))g")
                    .foregroundColor(AppTheme.fatColor)
                Text("C: \(String(format: "%.1f", totalCarbs))g")
                    .foregroundColor(AppTheme.carbsColor)
                Spacer()
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))

            Button(action: {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                onApplySelection(combinedName, totalCalories, totalProtein, totalFat, totalCarbs)
                dismiss()
            }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("この内容を入力欄に反映する（\(selectedEntries.count)品）")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.emeraldGradient)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.15), radius: 14, x: 0, y: -4)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func toggleItem(_ item: FoodDictionaryItem) {
        if let idx = selectedEntries.firstIndex(where: { $0.item.id == item.id }) {
            withAnimation {
                selectedEntries.remove(at: idx)
            }
        } else {
            withAnimation {
                selectedEntries.append(SelectedFoodEntry(item: item, multiplier: 1.0))
            }
        }
    }
}
