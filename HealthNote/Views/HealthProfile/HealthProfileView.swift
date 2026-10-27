import SwiftUI
import SwiftData

/// 「マイカルテ」画面（プロフィール、問診票、健診、栄養目標、下部フローティング保存バーUX）
public struct HealthProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [HealthProfile]
    @Query(sort: \MedicationItem.orderIndex) private var medications: [MedicationItem]

    // 編集ステート（HealthProfileのプロパティをバインド）
    @State private var nickname: String = ""
    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var hasBirthDate: Bool = false
    @State private var genderRaw: String = "未設定"
    @State private var heightCm: Double = 170.0
    @State private var weightKg: Double = 65.0
    @State private var targetWeightKg: Double = 62.0
    @State private var activityLevel: ActivityLevel = .moderate

    // 栄養目標
    @State private var targetCalories: Double = 2000.0
    @State private var targetProtein: Double = 75.0
    @State private var targetFat: Double = 55.0
    @State private var targetCarbs: Double = 250.0

    // 簡易問診票
    @State private var medicalHistory: String = ""
    @State private var allergies: String = ""
    @State private var dietaryRestrictions: String = ""
    @State private var healthCheckMemo: String = ""

    // 服薬追加用シート
    @State private var showingAddMedication: Bool = false
    @State private var newMedName: String = ""
    @State private var newMedTiming: String = "朝"
    @State private var newMedDosage: String = "1錠"

    // 変更検知フラグ
    @State private var hasChanges: Bool = false
    @State private var isLoaded: Bool = false

    public init() {}

    private var activeProfile: HealthProfile? {
        profiles.first
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 20) {
                        // 1. BMI＆プロファイルサマリーカード
                        summaryCard

                        // 2. 基本情報セクション
                        basicInfoSection

                        // 3. 栄養目標セクション
                        nutritionTargetsSection

                        // 4. 簡易問診票・健康状態セクション
                        medicalSurveySection

                        // 5. 服薬・サプリメント管理セクション
                        medicationSection

                        // フローティングバー用のボトム余白
                        Spacer().frame(height: 80)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(Color(.systemGroupedBackground).ignoresSafeArea())

                // 3. 最上部の保存ボタンは置かず、下部フローティング保存バー（編集時のみ出現）
                FloatingSaveBar(
                    isVisible: hasChanges,
                    onSave: {
                        saveChanges()
                    },
                    onDiscard: {
                        loadInitialData()
                    }
                )
            }
            .navigationTitle("マイカルテ")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingAddMedication) {
                addMedicationSheet
            }
            .onAppear {
                if !isLoaded {
                    loadInitialData()
                }
            }
        }
    }

    // MARK: - 1. BMI＆プロファイルサマリカード
    private var summaryCard: some View {
        let currentBmi = heightCm > 0 ? (weightKg / ((heightCm / 100.0) * (heightCm / 100.0))) : 0.0
        let bmiCategory: String = {
            switch currentBmi {
            case ..<18.5: return "低体重"
            case 18.5..<25.0: return "普通体重"
            case 25.0..<30.0: return "肥満 (1度)"
            default: return "肥満 (2度以上)"
            }
        }()

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(nickname.isEmpty ? "あなた" : nickname)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)

                Text("目標まであと \(String(format: "%.1f", max(0, weightKg - targetWeightKg))) kg")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.emerald)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("BMI")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f", currentBmi))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(.primary)
                }

                Text(bmiCategory)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(currentBmi >= 18.5 && currentBmi < 25.0 ? AppTheme.emerald : .orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill((currentBmi >= 18.5 && currentBmi < 25.0 ? AppTheme.emerald : Color.orange).opacity(0.12))
                    )
            }
        }
        .padding(16)
        .appCard()
    }

    // MARK: - 2. 基本情報セクション
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "基本プロフィール", icon: "person.text.rectangle.fill", color: .blue)

            VStack(spacing: 12) {
                HStack {
                    Text("ニックネーム")
                        .foregroundColor(.secondary)
                    Spacer()
                    TextField("ニックネーム", text: $nickname)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: nickname) { _ in markChanged() }
                }

                Divider()

                HStack {
                    Text("性別")
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("性別", selection: $genderRaw) {
                        Text("未設定").tag("未設定")
                        Text("男性").tag("男性")
                        Text("女性").tag("女性")
                        Text("その他").tag("その他")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: genderRaw) { _ in markChanged() }
                }

                Divider()

                HStack {
                    Text("身長")
                        .foregroundColor(.secondary)
                    Spacer()
                    TextField("170.0", value: $heightCm, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onChange(of: heightCm) { _ in markChanged() }
                    Text("cm").foregroundColor(.secondary)
                }

                Divider()

                HStack {
                    Text("現在の体重")
                        .foregroundColor(.secondary)
                    Spacer()
                    TextField("65.0", value: $weightKg, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onChange(of: weightKg) { _ in markChanged() }
                    Text("kg").foregroundColor(.secondary)
                }

                Divider()

                HStack {
                    Text("目標体重")
                        .foregroundColor(.secondary)
                    Spacer()
                    TextField("62.0", value: $targetWeightKg, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onChange(of: targetWeightKg) { _ in markChanged() }
                    Text("kg").foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("日常の活動レベル")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Picker("活動レベル", selection: $activityLevel) {
                        ForEach(ActivityLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: activityLevel) { _ in markChanged() }
                }
            }
            .padding(16)
            .appCard()
        }
    }

    // MARK: - 3. 栄養目標セクション
    private var nutritionTargetsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "1日の栄養目標（PFCバランス）", icon: "flame.fill", color: .orange)

            VStack(spacing: 14) {
                HStack {
                    Text("目標カロリー")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    TextField("2000", value: $targetCalories, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.calorieIntake)
                        .frame(width: 90)
                        .onChange(of: targetCalories) { _ in markChanged() }
                    Text("kcal").foregroundColor(.secondary)
                }

                Divider()

                // PFC入力グリッド
                HStack(spacing: 12) {
                    pfcInputField(label: "P (タンパク質)", value: $targetProtein, color: AppTheme.proteinColor)
                    pfcInputField(label: "F (脂質)", value: $targetFat, color: AppTheme.fatColor)
                    pfcInputField(label: "C (炭水化物)", value: $targetCarbs, color: AppTheme.carbsColor)
                }

                // リアルタイムPFC比率プレビュー
                PFCBalanceView(
                    protein: targetProtein,
                    fat: targetFat,
                    carbs: targetCarbs,
                    compact: true
                )

                Divider()

                // App Store Guideline 1.4.1 準拠：BMI・PFC基準の公的出典明記
                VStack(alignment: .leading, spacing: 4) {
                    Text("※BMI判定基準（普通体重: 18.5〜25.0未満）およびPFC栄養目標の参考値は、日本肥満学会および厚生労働省「日本人の食事摂取基準」の一般的な統計指標に基づいています（医療上の診断ではありません）。")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)

                    Link(destination: URL(string: "https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/kenkou_iryou/kenkou/eiyou/syokuji_kijyun.html")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("出典：厚生労働省「日本人の食事摂取基準」を確認")
                                .underline()
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.emerald)
                    }
                }
            }
            .padding(16)
            .appCard()
        }
    }

    @ViewBuilder
    private func pfcInputField(label: String, value: Binding<Double>, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            HStack(spacing: 2) {
                TextField("0", value: value, format: .number)
                    .keyboardType(.numberPad)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .onChange(of: value.wrappedValue) { _ in markChanged() }
                Text("g")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 4. 簡易問診票セクション
    private var medicalSurveySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "簡易問診票・健康上の留意事項", icon: "cross.case.fill", color: .pink)

            VStack(spacing: 12) {
                surveyField(title: "既往歴・持病（高血圧・糖尿病など）", placeholder: "特になし", text: $medicalHistory)
                Divider()
                surveyField(title: "食物アレルギー", placeholder: "例: 甲殻類、卵", text: $allergies)
                Divider()
                surveyField(title: "食事の制限・ご要望", placeholder: "例: 減塩、低糖質を意識したい", text: $dietaryRestrictions)
                Divider()
                surveyField(title: "健康診断メモ・気になる数値", placeholder: "例: 中性脂肪がやや高めだった", text: $healthCheckMemo)
            }
            .padding(16)
            .appCard()
        }
    }

    @ViewBuilder
    private func surveyField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(1...3)
                .font(.system(size: 14))
                .onChange(of: text.wrappedValue) { _ in markChanged() }
        }
    }

    // MARK: - 5. 服薬・サプリメント管理セクション
    private var medicationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionHeader(title: "服薬・サプリメント管理", icon: "pills.fill", color: .purple)
                Spacer()
                Button(action: { showingAddMedication = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.emerald)
                }
            }

            VStack(spacing: 8) {
                if medications.isEmpty {
                    Text("登録されたサプリメントや服薬はありません。\n右上の「＋」から追加できます。")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(medications) { med in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(med.name)
                                    .font(.system(size: 14, weight: .bold))
                                HStack(spacing: 6) {
                                    Text(med.timingRaw)
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.purple.opacity(0.12)))
                                        .foregroundColor(.purple)

                                    if !med.dosage.isEmpty {
                                        Text(med.dosage)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            Spacer()

                            Button(role: .destructive, action: {
                                modelContext.delete(med)
                                try? modelContext.save()
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 13))
                                    .foregroundColor(.red.opacity(0.7))
                            }
                        }
                        .padding(.vertical, 4)
                        if med.id != medications.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(16)
            .appCard()
        }
    }

    // MARK: - 服薬追加シート
    private var addMedicationSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("アイテム情報")) {
                    TextField("名称（例: マルチビタミン、血圧薬）", text: $newMedName)
                    Picker("飲むタイミング", selection: $newMedTiming) {
                        Text("朝").tag("朝")
                        Text("昼").tag("昼")
                        Text("夕").tag("夕")
                        Text("就寝前").tag("就寝前")
                        Text("随時").tag("随時")
                    }
                    TextField("用量・目安（例: 1粒、2錠）", text: $newMedDosage)
                }
            }
            .navigationTitle("服薬・サプリの追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        showingAddMedication = false
                        newMedName = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        guard !newMedName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        let newMed = MedicationItem(
                            name: newMedName.trimmingCharacters(in: .whitespaces),
                            timingRaw: newMedTiming,
                            dosage: newMedDosage,
                            orderIndex: medications.count
                        )
                        modelContext.insert(newMed)
                        try? modelContext.save()
                        showingAddMedication = false
                        newMedName = ""
                    }
                    .disabled(newMedName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Section Header Helper
    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
        }
    }

    // MARK: - Data Management & Change Tracking
    private func markChanged() {
        guard isLoaded else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            hasChanges = true
        }
    }

    private func loadInitialData() {
        if let p = activeProfile {
            nickname = p.nickname
            genderRaw = p.genderRaw
            heightCm = p.heightCm
            weightKg = p.weightKg
            targetWeightKg = p.targetWeightKg
            activityLevel = p.activityLevel
            targetCalories = p.targetCalories
            targetProtein = p.targetProtein
            targetFat = p.targetFat
            targetCarbs = p.targetCarbs
            medicalHistory = p.medicalHistory
            allergies = p.allergies
            dietaryRestrictions = p.dietaryRestrictions
            healthCheckMemo = p.healthCheckMemo
            if let bDate = p.birthDate {
                birthDate = bDate
                hasBirthDate = true
            }
        }
        isLoaded = true
        withAnimation {
            hasChanges = false
        }
    }

    private func saveChanges() {
        let profileToSave = activeProfile ?? HealthProfile()
        profileToSave.nickname = nickname
        profileToSave.genderRaw = genderRaw
        profileToSave.heightCm = heightCm
        profileToSave.weightKg = weightKg
        profileToSave.targetWeightKg = targetWeightKg
        profileToSave.activityLevel = activityLevel
        profileToSave.targetCalories = targetCalories
        profileToSave.targetProtein = targetProtein
        profileToSave.targetFat = targetFat
        profileToSave.targetCarbs = targetCarbs
        profileToSave.medicalHistory = medicalHistory
        profileToSave.allergies = allergies
        profileToSave.dietaryRestrictions = dietaryRestrictions
        profileToSave.healthCheckMemo = healthCheckMemo
        profileToSave.birthDate = hasBirthDate ? birthDate : nil
        profileToSave.updatedAt = Date()

        if activeProfile == nil {
            modelContext.insert(profileToSave)
        }

        try? modelContext.save()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            hasChanges = false
        }
    }
}
