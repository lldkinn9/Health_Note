import SwiftUI
import SwiftData
import PhotosUI

/// 食事登録モーダル（Gemini写真解析・手動入力・HealthKit保存）
public struct AddMealView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var mealType: MealType = .lunch
    @State private var name: String = ""
    @State private var calories: Double = 0
    @State private var protein: Double = 0
    @State private var fat: Double = 0
    @State private var carbs: Double = 0
    @State private var memo: String = ""
    @State private var timestamp: Date = Date()

    // 写真選択・解析
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var isAnalyzing: Bool = false
    @State private var analysisAdvice: String? = nil
    @State private var errorMessage: String? = nil

    // 食品辞書・過去履歴ピッカー
    @State private var showingFoodDictionary: Bool = false

    public init(defaultMealType: MealType = .lunch) {
        _mealType = State(initialValue: defaultMealType)
    }

    public var body: some View {
        NavigationStack {
            Form {
                // 0. 食品辞書・過去の履歴からかんたん自動入力（APIキー不要・主役機能）
                Section(
                    header: Text("かんたん自動入力（食品辞書・履歴）"),
                    footer: Text("定番メニュー約70品目の栄養成分辞書（複数組み合わせ・分量調整対応）や、過去に記録した食事履歴からワンタップで自動入力できます。")
                ) {
                    Button(action: {
                        showingFoodDictionary = true
                    }) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(AppTheme.emerald.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "book.pages.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(AppTheme.emerald)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("📖 食品辞書・過去の記録から選ぶ")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.primary)
                                Text("白米・鶏むね・定食・コンビニ・プロテイン等")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // 1. 写真の添付・AI自動解析（任意オプション）
                Section(header: Text("写真の添付・AI自動解析（任意）")) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let selectedImageData, let uiImage = UIImage(data: selectedImageData) {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                Button(action: {
                                    self.selectedImageData = nil
                                    self.selectedPhotoItem = nil
                                    self.analysisAdvice = nil
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(.white)
                                        .shadow(radius: 3)
                                }
                                .padding(8)
                            }
                        }

                        HStack {
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                Label(selectedImageData == nil ? "食事の写真を選択" : "写真を変更", systemImage: "camera.fill")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.emerald)

                            Spacer()

                            if selectedImageData != nil && GeminiService.shared.getApiKey() != nil {
                                Button(action: {
                                    analyzeSelectedImage()
                                }) {
                                    if isAnalyzing {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Label("AI自動解析", systemImage: "sparkles")
                                            .font(.system(size: 14, weight: .bold))
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.indigo)
                                .disabled(isAnalyzing)
                            }
                        }

                        if let analysisAdvice {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.indigo)
                                Text(analysisAdvice)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color.indigo.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else if selectedImageData != nil && GeminiService.shared.getApiKey() == nil {
                            Text("※APIキーをお持ちの方は「設定」で登録すると、写真からカロリーやPFCを自動解析できます。未登録のままでも下部で手動入力して記録可能です。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 2. 食事基本情報
                Section(header: Text("食事情報")) {
                    Picker("食事区分", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Label(type.rawValue, systemImage: type.iconName).tag(type)
                        }
                    }

                    DatePicker("日時", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])

                    TextField("料理名・メニュー名", text: $name)
                }

                // 3. 栄養素（カロリー & PFC）
                Section(header: Text("栄養素（推定・入力）")) {
                    HStack {
                        Text("カロリー")
                        Spacer()
                        TextField("0", value: $calories, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundColor(AppTheme.calorieIntake)
                            .frame(width: 80)
                        Text("kcal").foregroundColor(.secondary)
                    }

                    HStack {
                        Text("タンパク質 (P)")
                            .foregroundColor(AppTheme.proteinColor)
                        Spacer()
                        TextField("0", value: $protein, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("g").foregroundColor(.secondary)
                    }

                    HStack {
                        Text("脂質 (F)")
                            .foregroundColor(AppTheme.fatColor)
                        Spacer()
                        TextField("0", value: $fat, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("g").foregroundColor(.secondary)
                    }

                    HStack {
                        Text("炭水化物 (C)")
                            .foregroundColor(AppTheme.carbsColor)
                        Spacer()
                        TextField("0", value: $carbs, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("g").foregroundColor(.secondary)
                    }

                    // PFCグラム数からカロリーを自動計算する補助ボタン
                    if protein > 0 || fat > 0 || carbs > 0 {
                        Button(action: {
                            let calc = (protein * 4.0) + (fat * 9.0) + (carbs * 4.0)
                            calories = calc.rounded()
                        }) {
                            HStack {
                                Image(systemName: "function")
                                Text("P・F・Cからカロリーを自動計算（\(Int((protein * 4 + fat * 9 + carbs * 4).rounded())) kcal）")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(AppTheme.emerald)
                        }
                    }
                }

                // 4. メモ
                Section(header: Text("メモ")) {
                    TextField("食事メモ（任意）", text: $memo)
                }
            }
            .navigationTitle("食事の記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveMeal()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isAnalyzing)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        self.selectedImageData = data
                        // APIキー登録時のみ自動解析を実行
                        if GeminiService.shared.getApiKey() != nil {
                            analyzeSelectedImage()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingFoodDictionary) {
                FoodDictionaryPickerView { selectedName, selectedCal, selectedP, selectedF, selectedC in
                    self.name = selectedName
                    self.calories = selectedCal
                    self.protein = selectedP
                    self.fat = selectedF
                    self.carbs = selectedC
                }
            }
            .alert("エラー", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Gemini 写真解析処理
    private func analyzeSelectedImage() {
        guard let data = selectedImageData else { return }
        isAnalyzing = true
        errorMessage = nil

        Task {
            do {
                let result = try await GeminiService.shared.analyzeMealPhoto(imageData: data)
                await MainActor.run {
                    self.name = result.name
                    self.calories = result.calories
                    self.protein = result.protein
                    self.fat = result.fat
                    self.carbs = result.carbs
                    self.analysisAdvice = result.advice
                    self.isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isAnalyzing = false
                }
            }
        }
    }

    // MARK: - 食事レコードの保存 & HealthKit連携
    private func saveMeal() {
        let meal = Meal(
            timestamp: timestamp,
            mealType: mealType,
            name: name.trimmingCharacters(in: .whitespaces),
            calories: calories,
            protein: protein,
            fat: fat,
            carbs: carbs,
            imageData: selectedImageData,
            memo: memo
        )

        modelContext.insert(meal)
        try? modelContext.save()

        // ウィジェットへ即時同期
        syncWidgetAfterSave()

        // HealthKitへの書き込みタスク
        Task {
            let success = await HealthKitManager.shared.saveMealToHealthKit(meal: meal)
            if success {
                await MainActor.run {
                    meal.healthKitSynced = true
                    try? modelContext.save()
                }
            }
        }

        dismiss()
    }

    private func syncWidgetAfterSave() {
        let descriptor = FetchDescriptor<Meal>(sortBy: [SortDescriptor(\Meal.timestamp, order: .forward)])
        guard let fetched = try? modelContext.fetch(descriptor) else { return }
        let calendar = Calendar.current
        let todayList = fetched.filter { calendar.isDateInToday($0.timestamp) }

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
