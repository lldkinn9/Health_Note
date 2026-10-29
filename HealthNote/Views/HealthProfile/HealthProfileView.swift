import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// マイカルテ内の3つのサブタブ
public enum ProfileSubTab: String, CaseIterable, Identifiable {
    case basic = "基本カルテ"
    case healthCheck = "健診・検査結果"
    case medicalExpense = "医療費ノート"

    public var id: String { rawValue }
}

/// 「マイカルテ」画面（基本カルテ / 健診・検査結果 / 医療費ノート）
public struct HealthProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [HealthProfile]
    @Query(sort: \MedicationItem.orderIndex) private var medications: [MedicationItem]
    @Query(sort: \HealthCheckRecord.examDate, order: .reverse) private var healthChecks: [HealthCheckRecord]
    @Query(sort: \MedicalExpenseRecord.paymentDate, order: .reverse) private var medicalExpenses: [MedicalExpenseRecord]

    @State private var selectedSubTab: ProfileSubTab = .basic

    // 基本カルテ編集ステート（目標設定なし）
    @State private var nickname: String = ""
    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var hasBirthDate: Bool = false
    @State private var genderRaw: String = "未設定"
    @State private var heightCm: Double = 170.0
    @State private var weightKg: Double = 65.0
    @State private var activityLevel: ActivityLevel = .moderate

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

    // 健診・検査結果 ＆ 医療費モーダル制御
    @State private var showingAddHealthCheck: Bool = false
    @State private var editingHealthCheck: HealthCheckRecord? = nil
    @State private var showingAddMedicalExpense: Bool = false
    @State private var editingMedicalExpense: MedicalExpenseRecord? = nil
    @State private var selectedExpenseYear: Int = Calendar.current.component(.year, from: Date())

    // 変更検知フラグ（基本カルテ用）
    @State private var hasChanges: Bool = false
    @State private var isLoaded: Bool = false

    public init() {}

    private var activeProfile: HealthProfile? {
        profiles.first
    }

    private var isFloatingSaveVisible: Bool {
        selectedSubTab == .basic && hasChanges
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // 上部セグメント切替バー（基本カルテ / 健診・検査結果 / 医療費ノート）
                    Picker("表示モード", selection: $selectedSubTab) {
                        ForEach(ProfileSubTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .overlay(Divider(), alignment: .bottom)

                    ScrollView {
                        VStack(spacing: 20) {
                            switch selectedSubTab {
                            case .basic:
                                basicProfileContent
                            case .healthCheck:
                                healthCheckContent
                            case .medicalExpense:
                                medicalExpenseContent
                            }

                            Spacer().frame(height: isFloatingSaveVisible ? 84 : 28)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
                .background(Color(.systemGroupedBackground).ignoresSafeArea())

                // 基本カルテ編集時のみ出現する下部フローティング保存バー
                FloatingSaveBar(
                    isVisible: isFloatingSaveVisible,
                    onSave: { saveChanges() },
                    onDiscard: { loadInitialData() }
                )
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // 未保存の変更バー（FloatingSaveBar）表示中は干渉を防ぐためバナーを自動的に隠す
                AdBottomBannerBar(isTemporarilyHidden: isFloatingSaveVisible)
            }
            .navigationTitle("マイカルテ")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAddMedication) {
                addMedicationSheet
            }
            .sheet(isPresented: $showingAddHealthCheck) {
                HealthCheckEditorSheet(recordToEdit: nil)
            }
            .sheet(item: $editingHealthCheck) { record in
                HealthCheckEditorSheet(recordToEdit: record)
            }
            .sheet(isPresented: $showingAddMedicalExpense) {
                MedicalExpenseEditorSheet(recordToEdit: nil)
            }
            .sheet(item: $editingMedicalExpense) { record in
                MedicalExpenseEditorSheet(recordToEdit: record)
            }
            .onAppear {
                if !isLoaded {
                    loadInitialData()
                }
            }
            .onChange(of: profiles.first?.id) { _, _ in
                if !hasChanges {
                    loadInitialData()
                }
            }
        }
    }

    // =========================================================================
    // MARK: - タブ1：基本カルテ コンテンツ（目標設定なし）
    // =========================================================================
    @ViewBuilder
    private var basicProfileContent: some View {
        summaryCard
        basicInfoSection
        medicalSurveySection
        medicationSection
    }

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

                Text("身長 \(String(format: "%.1f", heightCm)) cm ・ 体重 \(String(format: "%.1f", weightKg)) kg")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
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
                        .onChange(of: nickname) { _, _ in markChanged() }
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
                    .onChange(of: genderRaw) { _, _ in markChanged() }
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
                        .onChange(of: heightCm) { _, _ in markChanged() }
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
                        .onChange(of: weightKg) { _, _ in markChanged() }
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
                    .onChange(of: activityLevel) { _, _ in markChanged() }
                }

                Divider()

                // App Store Guideline 1.4.1 準拠：BMI判定基準の公的出典明記
                VStack(alignment: .leading, spacing: 4) {
                    Text("※BMI計算式（体重kg ÷ [身長m]²、普通体重: 18.5〜25.0未満）の区分表示は、厚生労働省および日本肥満学会の一般的な統計指標に基づいています（医療上の診断ではありません）。")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)

                    Link(destination: URL(string: "https://www.e-healthnet.mhlw.go.jp/information/dictionary/metabolic/ym-002.html")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("出典：厚生労働省 e-ヘルスネット「BMIの算出と判定基準」")
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
                surveyField(title: "健康メモ・気になること", placeholder: "例: 最近少し疲れやすい", text: $healthCheckMemo)
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
                .onChange(of: text.wrappedValue) { _, _ in markChanged() }
        }
    }

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

    // =========================================================================
    // MARK: - タブ2：健診・検査結果 コンテンツ（手入力 ＋ 任意AI写真読取 ＋ 前回比較）
    // =========================================================================
    @ViewBuilder
    private var healthCheckContent: some View {
        // 新規登録ボタン
        Button(action: { showingAddHealthCheck = true }) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("健診・検査結果を記録する（手入力 / 写真AI）")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.actionGradient)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
            .shadow(color: Color.purple.opacity(0.25), radius: 8, x: 0, y: 4)
        }

        if let latest = healthChecks.first {
            let previous = healthChecks.count >= 2 ? healthChecks[1] : nil
            latestHealthCheckDashboard(latest: latest, previous: previous)

            // 健診・検査履歴リスト
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "記録済みの健診・検査履歴（\(healthChecks.count)回）", icon: "clock.arrow.circlepath", color: .indigo)

                ForEach(healthChecks) { record in
                    Button(action: { editingHealthCheck = record }) {
                        HStack(spacing: 12) {
                            if let data = record.sheetImageData, let img = UIImage(data: data) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(AppTheme.emerald.opacity(0.12))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.system(size: 20))
                                        .foregroundColor(AppTheme.emerald)
                                }
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(formatJapaneseDate(record.examDate))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.primary)

                                if !record.facilityName.isEmpty {
                                    Text(record.facilityName)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }

                                let summary = record.aiLabSummary
                                if !summary.isEmpty {
                                    Text(summary)
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .appCard()
                    }
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 42))
                    .foregroundColor(.secondary.opacity(0.45))
                Text("健診・検査結果の記録がまだありません")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                Text("定期健康診断・人間ドック・病院での血液検査や尿検査の結果を記録しておくと、前回との比較や推移をひと目で振り返ることができます。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .appCard()
        }

        // Guideline 1.4.1 & 医師法第17条準拠：参考基準の公的出典と医療免責
        VStack(alignment: .leading, spacing: 6) {
            Text("【参考基準値の出典および医療免責（Guideline 1.4.1）】\n画面内に記載されている一般的な基準値目安は、厚生労働省「標準的な健診・保健指導プログラム」および日本人間ドック・予防医療学会が公開する一般的な統計基準値です。本機能は検査結果の個人記録（備忘録）であり、疾病の診断や医学的判定を行うものではありません。気になる数値がある場合は必ず医師・医療機関にご相談ください。")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineSpacing(2)

            Link(destination: URL(string: "https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000194155.html")!) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                    Text("出典1：厚生労働省「標準的な健診・保健指導プログラム」")
                        .underline()
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.emerald)
            }

            Link(destination: URL(string: "https://www.ningen-dock.jp/public/method/")!) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                    Text("出典2：日本人間ドック・予防医療学会「判定区分基準表」")
                        .underline()
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.emerald)
            }
        }
        .padding(14)
        .appCard()
    }

    @ViewBuilder
    private func latestHealthCheckDashboard(latest: HealthCheckRecord, previous: HealthCheckRecord?) -> some View {
        let tiles = buildDisplayTiles(latest: latest, previous: previous)

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("最新の健診・検査サマリ")
                        .font(.system(size: 16, weight: .bold))
                    Text("\(formatJapaneseDate(latest.examDate))\(latest.facilityName.isEmpty ? "" : " ・ \(latest.facilityName)")")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { editingHealthCheck = latest }) {
                    Label("詳細・編集", systemImage: "pencil")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.emerald)
                }
            }

            if !tiles.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(tiles) { tile in
                        labTile(
                            title: tile.title,
                            valueText: tile.valueText,
                            unit: tile.unit,
                            refNote: tile.refNote,
                            diffText: tile.diffText
                        )
                    }
                }
            }

            // 尿・心電図・X線・聴力などの定性所見表示
            let findings = buildQualitativeSummary(latest: latest)
            if !findings.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("定性検査・所見項目")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(findings, id: \.0) { label, val in
                            HStack {
                                Text(label)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(val)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemGroupedBackground).opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            if !latest.memo.isEmpty {
                Divider()
                Text("メモ: \(latest.memo)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .appCard()
    }

    private struct LabTileDisplay: Identifiable {
        let id = UUID()
        let title: String
        let valueText: String
        let unit: String
        let refNote: String
        let diffText: String?
    }

    private func buildDisplayTiles(latest: HealthCheckRecord, previous: HealthCheckRecord?) -> [LabTileDisplay] {
        var list: [LabTileDisplay] = []

        // 身体・血圧・脈拍・視力
        if let w = latest.weightKg {
            let sub = latest.waistCm != nil ? "腹囲: \(String(format: "%.1f", latest.waistCm!))cm" : (latest.bodyFatPercent != nil ? "体脂肪: \(String(format: "%.1f", latest.bodyFatPercent!))%" : "身体計測")
            list.append(.init(title: "体重", valueText: String(format: "%.1f", w), unit: "kg", refNote: sub, diffText: previous?.weightKg.map { formatDoubleDiff(w - $0) }))
        }
        if let bf = latest.bodyFatPercent, latest.weightKg == nil {
            list.append(.init(title: "体脂肪率", valueText: String(format: "%.1f", bf), unit: "%", refNote: "身体計測", diffText: previous?.bodyFatPercent.map { formatDoubleDiff(bf - $0) }))
        }
        if latest.visionRight != nil || latest.visionLeft != nil {
            let vr = latest.visionRight.map { String(format: "%.1f", $0) } ?? "-"
            let vl = latest.visionLeft.map { String(format: "%.1f", $0) } ?? "-"
            list.append(.init(title: "視力 (右 / 左)", valueText: "\(vr) / \(vl)", unit: "", refNote: "視力検査", diffText: nil))
        }
        if let sys = latest.systolicBP, let dia = latest.diastolicBP {
            list.append(.init(title: "血圧 (最高/最低)", valueText: "\(sys)/\(dia)", unit: "mmHg", refNote: "基準目安: <130/<85", diffText: previous?.systolicBP.map { formatIntDiff(sys - $0) }))
        }
        if let pulse = latest.pulseRate {
            list.append(.init(title: "脈拍数", valueText: "\(pulse)", unit: "bpm", refNote: "基準目安: 60〜100", diffText: previous?.pulseRate.map { formatIntDiff(pulse - $0) }))
        }

        // 血算・貧血
        if let wbc = latest.wbc {
            list.append(.init(title: "白血球数 (WBC)", valueText: "\(wbc)", unit: "/μL", refNote: "基準目安: 3100〜8400", diffText: previous?.wbc.map { formatIntDiff(wbc - $0) }))
        }
        if let rbc = latest.rbc {
            list.append(.init(title: "赤血球数 (RBC)", valueText: String(format: "%.0f", rbc), unit: "万/μL", refNote: "基準目安: 380〜550", diffText: previous?.rbc.map { formatDoubleDiff(rbc - $0) }))
        }
        if let hb = latest.hemoglobin {
            list.append(.init(title: "ヘモグロビン (Hb)", valueText: String(format: "%.1f", hb), unit: "g/dL", refNote: "基準目安: 12.1〜17.0", diffText: previous?.hemoglobin.map { formatDoubleDiff(hb - $0) }))
        }
        if let ht = latest.hematocrit {
            list.append(.init(title: "ヘマトクリット (Ht)", valueText: String(format: "%.1f", ht), unit: "%", refNote: "基準目安: 36〜50", diffText: previous?.hematocrit.map { formatDoubleDiff(ht - $0) }))
        }
        if let plt = latest.platelets {
            list.append(.init(title: "血小板数 (PLT)", valueText: String(format: "%.1f", plt), unit: "万/μL", refNote: "基準目安: 14.0〜34.0", diffText: previous?.platelets.map { formatDoubleDiff(plt - $0) }))
        }

        // 脂質
        if let tc = latest.totalCholesterol {
            list.append(.init(title: "総コレステロール", valueText: "\(tc)", unit: "mg/dL", refNote: "基準目安: 140〜199", diffText: previous?.totalCholesterol.map { formatIntDiff(tc - $0) }))
        }
        if let ldl = latest.ldlCholesterol {
            list.append(.init(title: "LDLコレステロール", valueText: "\(ldl)", unit: "mg/dL", refNote: "基準目安: 60〜119", diffText: previous?.ldlCholesterol.map { formatIntDiff(ldl - $0) }))
        }
        if let hdl = latest.hdlCholesterol {
            list.append(.init(title: "HDLコレステロール", valueText: "\(hdl)", unit: "mg/dL", refNote: "基準目安: 40以上", diffText: previous?.hdlCholesterol.map { formatIntDiff(hdl - $0) }))
        }
        if let nonHdl = latest.nonHdlCholesterol {
            list.append(.init(title: "Non-HDLコレステロール", valueText: "\(nonHdl)", unit: "mg/dL", refNote: "基準目安: 90〜149", diffText: previous?.nonHdlCholesterol.map { formatIntDiff(nonHdl - $0) }))
        }
        if let tg = latest.triglycerides {
            list.append(.init(title: "中性脂肪 (TG)", valueText: "\(tg)", unit: "mg/dL", refNote: "基準目安: 30〜149", diffText: previous?.triglycerides.map { formatIntDiff(tg - $0) }))
        }

        // 肝機能・蛋白・膵
        if let ast = latest.ast {
            list.append(.init(title: "AST (GOT)", valueText: "\(ast)", unit: "U/L", refNote: "基準目安: 30以下", diffText: previous?.ast.map { formatIntDiff(ast - $0) }))
        }
        if let alt = latest.alt {
            list.append(.init(title: "ALT (GPT)", valueText: "\(alt)", unit: "U/L", refNote: "基準目安: 30以下", diffText: previous?.alt.map { formatIntDiff(alt - $0) }))
        }
        if let ggtp = latest.gammaGTP {
            list.append(.init(title: "γ-GTP", valueText: "\(ggtp)", unit: "U/L", refNote: "基準目安: 50以下", diffText: previous?.gammaGTP.map { formatIntDiff(ggtp - $0) }))
        }
        if let alp = latest.alp {
            list.append(.init(title: "ALP", valueText: "\(alp)", unit: "U/L", refNote: "基準目安: 38〜113", diffText: previous?.alp.map { formatIntDiff(alp - $0) }))
        }
        if let ldh = latest.ldh {
            list.append(.init(title: "LDH (LD)", valueText: "\(ldh)", unit: "U/L", refNote: "基準目安: 124〜222", diffText: previous?.ldh.map { formatIntDiff(ldh - $0) }))
        }
        if let tbil = latest.totalBilirubin {
            list.append(.init(title: "総ビリルビン", valueText: String(format: "%.1f", tbil), unit: "mg/dL", refNote: "基準目安: 0.4〜1.5", diffText: previous?.totalBilirubin.map { formatDoubleDiff(tbil - $0) }))
        }
        if let tp = latest.totalProtein {
            list.append(.init(title: "総蛋白 (TP)", valueText: String(format: "%.1f", tp), unit: "g/dL", refNote: "基準目安: 6.6〜8.1", diffText: previous?.totalProtein.map { formatDoubleDiff(tp - $0) }))
        }
        if let alb = latest.albumin {
            list.append(.init(title: "アルブミン (Alb)", valueText: String(format: "%.1f", alb), unit: "g/dL", refNote: "基準目安: 4.1〜5.1", diffText: previous?.albumin.map { formatDoubleDiff(alb - $0) }))
        }
        if let amy = latest.amylase {
            list.append(.init(title: "アミラーゼ", valueText: "\(amy)", unit: "U/L", refNote: "基準目安: 44〜132", diffText: previous?.amylase.map { formatIntDiff(amy - $0) }))
        }

        // 糖代謝・尿酸
        if let fbg = latest.fastingGlucose {
            list.append(.init(title: "血糖 (空腹時)", valueText: "\(fbg)", unit: "mg/dL", refNote: "基準目安: 99以下", diffText: previous?.fastingGlucose.map { formatIntDiff(fbg - $0) }))
        }
        if let a1c = latest.hba1c {
            list.append(.init(title: "HbA1c", valueText: String(format: "%.1f", a1c), unit: "%", refNote: "基準目安: 5.5以下", diffText: previous?.hba1c.map { formatDoubleDiff(a1c - $0) }))
        }
        if let ua = latest.uricAcid {
            list.append(.init(title: "尿酸値 (UA)", valueText: String(format: "%.1f", ua), unit: "mg/dL", refNote: "基準目安: 2.1〜7.0", diffText: previous?.uricAcid.map { formatDoubleDiff(ua - $0) }))
        }

        // 腎機能・電解質・炎症・鉄
        if let bun = latest.bun {
            list.append(.init(title: "尿素窒素 (BUN)", valueText: String(format: "%.1f", bun), unit: "mg/dL", refNote: "基準目安: 8.0〜20.0", diffText: previous?.bun.map { formatDoubleDiff(bun - $0) }))
        }
        if let cr = latest.creatinine {
            list.append(.init(title: "クレアチニン (Cr)", valueText: String(format: "%.2f", cr), unit: "mg/dL", refNote: "基準目安: 1.00以下", diffText: previous?.creatinine.map { formatDoubleDiff(cr - $0) }))
        }
        if let egfr = latest.egfr {
            list.append(.init(title: "eGFR (腎機能)", valueText: String(format: "%.1f", egfr), unit: "mL/min", refNote: "基準目安: 60.0以上", diffText: previous?.egfr.map { formatDoubleDiff(egfr - $0) }))
        }
        if let crp = latest.crp {
            list.append(.init(title: "CRP定量", valueText: String(format: "%.2f", crp), unit: "mg/dL", refNote: "基準目安: 0.30以下", diffText: previous?.crp.map { formatDoubleDiff(crp - $0) }))
        }
        if let na = latest.sodium {
            list.append(.init(title: "ナトリウム (Na)", valueText: String(format: "%.0f", na), unit: "mEq/L", refNote: "基準目安: 138〜145", diffText: nil))
        }
        if let k = latest.potassium {
            list.append(.init(title: "カリウム (K)", valueText: String(format: "%.1f", k), unit: "mEq/L", refNote: "基準目安: 3.6〜4.8", diffText: nil))
        }
        if let cl = latest.chloride {
            list.append(.init(title: "クロール (Cl)", valueText: String(format: "%.0f", cl), unit: "mEq/L", refNote: "基準目安: 101〜108", diffText: nil))
        }
        if let fe = latest.serumIron {
            list.append(.init(title: "血清鉄 (Fe)", valueText: "\(fe)", unit: "μg/dL", refNote: "基準目安: 40〜188", diffText: previous?.serumIron.map { formatIntDiff(fe - $0) }))
        }

        // カスタム・追加検査項目
        for extra in latest.extraItems where !extra.name.isEmpty && !extra.value.isEmpty {
            list.append(.init(
                title: extra.name,
                valueText: extra.value,
                unit: extra.unit,
                refNote: extra.reference.isEmpty ? "追加検査項目" : "基準: \(extra.reference)",
                diffText: nil
            ))
        }

        return list
    }

    private func buildQualitativeSummary(latest: HealthCheckRecord) -> [(String, String)] {
        var res: [(String, String)] = []
        if !latest.urineProtein.isEmpty { res.append(("尿蛋白", latest.urineProtein)) }
        if !latest.urineGlucose.isEmpty { res.append(("尿糖", latest.urineGlucose)) }
        if !latest.urineOccultBlood.isEmpty { res.append(("尿潜血", latest.urineOccultBlood)) }
        if !latest.hearingFinding.isEmpty { res.append(("聴力", latest.hearingFinding)) }
        if !latest.ecgFinding.isEmpty { res.append(("心電図", latest.ecgFinding)) }
        if !latest.chestXrayFinding.isEmpty { res.append(("胸部X線", latest.chestXrayFinding)) }
        return res
    }

    @ViewBuilder
    private func labTile(title: String, valueText: String, unit: String, refNote: String, diffText: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(valueText)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text(refNote)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                if let diff = diffText {
                    Text("前回比 \(diff)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.indigo)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground).opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // =========================================================================
    // MARK: - タブ3：医療費ノート コンテンツ（年間集計・医療費控除目安・領収書AI読取）
    // =========================================================================
    private var yearFilteredExpenses: [MedicalExpenseRecord] {
        let cal = Calendar.current
        return medicalExpenses.filter { cal.component(.year, from: $0.paymentDate) == selectedExpenseYear }
    }

    private var annualTotalYen: Int {
        yearFilteredExpenses.reduce(0) { $0 + $1.amountYen }
    }

    private var currentMonthTotalYen: Int {
        let cal = Calendar.current
        let now = Date()
        return medicalExpenses
            .filter { cal.isDate($0.paymentDate, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amountYen }
    }

    @ViewBuilder
    private var medicalExpenseContent: some View {
        // 年セレクター
        HStack {
            Button(action: { selectedExpenseYear -= 1 }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(6)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundColor(AppTheme.emerald)
                Text("\(selectedExpenseYear)年（1月〜12月）の医療費")
                    .font(.system(size: 15, weight: .bold))
            }
            Spacer()
            Button(action: { selectedExpenseYear += 1 }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .appCard()

        // 年間医療費サマリ ＆ 医療費控除（10万円ライン）進捗カード
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(selectedExpenseYear)年 自己負担額 合計")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)

                    Text("¥\(annualTotalYen.formatted())")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.emerald)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("今月の支払計")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("¥\(currentMonthTotalYen.formatted())")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("年間 \(yearFilteredExpenses.count) 件")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            // 医療費控除（年間10万円目安）プログレスバー
            let threshold = 100_000
            let progress = min(1.0, Double(annualTotalYen) / Double(threshold))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("確定申告・医療費控除の目安（年間10万円）")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    if annualTotalYen >= threshold {
                        Text("控除対象目安額: ¥\((annualTotalYen - threshold).formatted())")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppTheme.emerald)
                    } else {
                        Text("あと ¥\((threshold - annualTotalYen).formatted())")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 8)
                        Capsule()
                            .fill(AppTheme.emeraldGradient)
                            .frame(width: max(6, geo.size.width * progress), height: 8)
                    }
                }
                .frame(height: 8)
            }

            // カテゴリ別小計チップ
            if !yearFilteredExpenses.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MedicalExpenseCategory.allCases) { cat in
                            let sum = yearFilteredExpenses.filter { $0.category == cat }.reduce(0) { $0 + $1.amountYen }
                            if sum > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: cat.iconName)
                                        .font(.system(size: 10))
                                    Text("\(cat.rawValue): ¥\(sum.formatted())")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                }
                                .foregroundColor(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(.tertiarySystemGroupedBackground))
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .appCard()

        // 新規登録ボタン
        Button(action: { showingAddMedicalExpense = true }) {
            HStack(spacing: 8) {
                Image(systemName: "doc.viewfinder.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("医療費・領収書を記録する（手入力 / 写真AI）")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.actionGradient)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
            .shadow(color: Color.purple.opacity(0.25), radius: 8, x: 0, y: 4)
        }

        // 明細リスト
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "\(selectedExpenseYear)年の医療費明細", icon: "list.bullet.rectangle.portrait.fill", color: .teal)

            if yearFilteredExpenses.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "yensign.circle")
                        .font(.system(size: 38))
                        .foregroundColor(.secondary.opacity(0.45))
                    Text("\(selectedExpenseYear)年の医療費記録はまだありません")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
                .appCard()
            } else {
                ForEach(yearFilteredExpenses) { item in
                    Button(action: { editingMedicalExpense = item }) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(AppTheme.emerald.opacity(0.12))
                                    .frame(width: 44, height: 44)
                                Image(systemName: item.category.iconName)
                                    .font(.system(size: 18))
                                    .foregroundColor(AppTheme.emerald)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(item.facilityName.isEmpty ? item.category.rawValue : item.facilityName)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    if item.receiptImageData != nil {
                                        Image(systemName: "paperclip")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                }

                                HStack(spacing: 6) {
                                    Text(formatShortDate(item.paymentDate))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Text(item.category.rawValue)
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color(.tertiarySystemGroupedBackground))
                                        .clipShape(Capsule())
                                        .foregroundColor(.secondary)
                                    Text(item.familyMember)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.indigo)
                                }
                            }

                            Spacer()

                            Text("¥\(item.amountYen.formatted())")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        .padding(14)
                        .appCard()
                    }
                }
            }
        }

        // 公的制度参考リンク（国税庁 医療費控除）
        VStack(alignment: .leading, spacing: 4) {
            Text("※医療費控除（原則として年間10万円、または総所得金額等の5%を超える自己負担医療費が対象）の正確な要件や確定申告手続きについては、国税庁の公式案内をご確認ください。")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineSpacing(2)

            Link(destination: URL(string: "https://www.nta.go.jp/taxes/shiraberu/taxanswer/shotoku/1120.htm")!) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                    Text("参考：国税庁「No.1120 医療費を支払ったとき（医療費控除）」")
                        .underline()
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.emerald)
            }
        }
        .padding(14)
        .appCard()
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

    // MARK: - Helpers
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

    private func formatJapaneseDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }

    private func formatShortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d(E)"
        return f.string(from: date)
    }

    private func formatIntDiff(_ diff: Int) -> String {
        if diff == 0 { return "±0" }
        return diff > 0 ? "+\(diff)" : "\(diff)"
    }

    private func formatDoubleDiff(_ diff: Double) -> String {
        if abs(diff) < 0.05 { return "±0.0" }
        return diff > 0 ? String(format: "+%.1f", diff) : String(format: "%.1f", diff)
    }

    // MARK: - Data Management & Change Tracking
    private var hasActualChanges: Bool {
        guard isLoaded else { return false }
        guard let p = activeProfile else {
            return !nickname.isEmpty && nickname != "あなた"
        }
        return nickname != p.nickname
            || genderRaw != p.genderRaw
            || abs(heightCm - p.heightCm) > 0.01
            || abs(weightKg - p.weightKg) > 0.01
            || activityLevel != p.activityLevel
            || medicalHistory != p.medicalHistory
            || allergies != p.allergies
            || dietaryRestrictions != p.dietaryRestrictions
            || healthCheckMemo != p.healthCheckMemo
    }

    private func markChanged() {
        guard isLoaded else { return }
        let changed = hasActualChanges
        if hasChanges != changed {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                hasChanges = changed
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func loadInitialData() {
        isLoaded = false
        if let p = activeProfile {
            nickname = p.nickname
            genderRaw = p.genderRaw
            heightCm = p.heightCm
            weightKg = p.weightKg
            activityLevel = p.activityLevel
            medicalHistory = p.medicalHistory
            allergies = p.allergies
            dietaryRestrictions = p.dietaryRestrictions
            healthCheckMemo = p.healthCheckMemo
            if let bDate = p.birthDate {
                birthDate = bDate
                hasBirthDate = true
            }
        }
        hasChanges = false
        dismissKeyboard()
        DispatchQueue.main.async {
            self.isLoaded = true
            self.hasChanges = false
        }
    }

    private func saveChanges() {
        let profileToSave = activeProfile ?? HealthProfile()
        profileToSave.nickname = nickname
        profileToSave.genderRaw = genderRaw
        profileToSave.heightCm = heightCm
        profileToSave.weightKg = weightKg
        profileToSave.activityLevel = activityLevel
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
        dismissKeyboard()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            hasChanges = false
        }
    }
}

// =============================================================================
// MARK: - 健診・検査結果 登録・編集モーダル（全8系統＋自由検査項目追加＋写真AI自動読取）
// =============================================================================
private struct HealthCheckEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let recordToEdit: HealthCheckRecord?

    @State private var examDate: Date = Date()
    @State private var facilityName: String = ""

    // 1. 身体・視力・血圧・脈拍
    @State private var heightStr: String = ""
    @State private var weightStr: String = ""
    @State private var bodyFatStr: String = ""
    @State private var waistStr: String = ""
    @State private var visionRightStr: String = ""
    @State private var visionLeftStr: String = ""
    @State private var sysBPStr: String = ""
    @State private var diaBPStr: String = ""
    @State private var pulseStr: String = ""

    // 2. 血算・貧血（CBC）
    @State private var wbcStr: String = ""
    @State private var rbcStr: String = ""
    @State private var hbStr: String = ""
    @State private var htStr: String = ""
    @State private var pltStr: String = ""

    // 3. 脂質
    @State private var tcStr: String = ""
    @State private var ldlStr: String = ""
    @State private var hdlStr: String = ""
    @State private var nonHdlStr: String = ""
    @State private var tgStr: String = ""

    // 4. 肝機能・胆道・膵・蛋白
    @State private var astStr: String = ""
    @State private var altStr: String = ""
    @State private var ggtpStr: String = ""
    @State private var alpStr: String = ""
    @State private var ldhStr: String = ""
    @State private var tbilStr: String = ""
    @State private var tpStr: String = ""
    @State private var albStr: String = ""
    @State private var amyStr: String = ""

    // 5. 糖代謝・尿酸
    @State private var fbgStr: String = ""
    @State private var hba1cStr: String = ""
    @State private var uaStr: String = ""

    // 6. 腎機能・電解質・炎症・鉄
    @State private var bunStr: String = ""
    @State private var crStr: String = ""
    @State private var egfrStr: String = ""
    @State private var crpStr: String = ""
    @State private var naStr: String = ""
    @State private var kStr: String = ""
    @State private var clStr: String = ""
    @State private var feStr: String = ""

    // 7. 尿検査・生理検査所見
    @State private var urineProtein: String = ""
    @State private var urineGlucose: String = ""
    @State private var urineOccult: String = ""
    @State private var hearingFinding: String = ""
    @State private var ecgFinding: String = ""
    @State private var chestXrayFinding: String = ""

    // 8. 自由追加カスタム検査項目（特殊血液検査・ホルモン・腫瘍マーカー等すべて対応）
    @State private var extraItems: [ExtraLabItem] = []

    @State private var memo: String = ""

    // 写真・AI読取
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var imageData: Data? = nil
    @State private var showingCamera: Bool = false
    @State private var isAnalyzing: Bool = false
    @State private var alertMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                // 1. 写真控え ＆ 任意AI自動読取セクション
                Section(
                    header: Text("結果表の写真添付・AI自動読取（任意）"),
                    footer: Text("※AI読取はAPIキー設定時のみ使用できる任意の補助機能です（手入力のみでもすべての項目を記録できます）。病院の採血結果など標準項目以外の数値も自動的に「その他の検査項目」へ追加されます。")
                ) {
                    if let imageData, let uiImg = UIImage(data: imageData) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: uiImg)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Button(action: {
                                self.imageData = nil
                                self.photoItem = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                                    .shadow(radius: 3)
                            }
                            .padding(8)
                        }
                    }

                    HStack(spacing: 10) {
                        Button(action: {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                showingCamera = true
                            } else {
                                alertMessage = "この端末ではカメラが利用できないため、「アルバムから選択」をご利用ください。"
                            }
                        }) {
                            Label("カメラで撮影", systemImage: "camera.fill")
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.emerald)

                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("アルバムから選択", systemImage: "photo.on.rectangle")
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.emerald)
                    }

                    if imageData != nil {
                        if GeminiService.shared.getApiKey() != nil {
                            Button(action: { analyzeSheetImage() }) {
                                HStack {
                                    Spacer()
                                    if isAnalyzing {
                                        ProgressView().tint(.white)
                                        Text("すべての検査数値を読み取り中...")
                                            .font(.system(size: 13, weight: .bold))
                                    } else {
                                        Label("写真から検査数値をAI自動入力", systemImage: "sparkles")
                                            .font(.system(size: 14, weight: .bold))
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.indigo)
                            .disabled(isAnalyzing)
                        } else {
                            Text("本機能（AI自動読取）はAPIキーをお持ちの場合に、設定画面でキーを設定することで使用できる任意の機能です。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 2. 受診基本情報
                Section(header: Text("検査日・医療機関")) {
                    DatePicker("検査・受診日", selection: $examDate, displayedComponents: [.date])
                    TextField("健診機関・病院・クリニック名（任意）", text: $facilityName)
                }

                // 3. 身体計測・視力・血圧・脈拍
                Section(header: Text("1. 身体計測・視力・血圧・脈拍（わかる項目のみでOK）")) {
                    numRow("身長", text: $heightStr, unit: "cm", placeholder: "170.0", decimal: true)
                    numRow("体重", text: $weightStr, unit: "kg", placeholder: "65.0", decimal: true)
                    numRow("体脂肪率", text: $bodyFatStr, unit: "%", placeholder: "18.5", decimal: true)
                    numRow("腹囲", text: $waistStr, unit: "cm", placeholder: "78.0", decimal: true)
                    numRow("視力（右）", text: $visionRightStr, unit: "", placeholder: "1.2", decimal: true)
                    numRow("視力（左）", text: $visionLeftStr, unit: "", placeholder: "1.0", decimal: true)
                    numRow("最高血圧 (収縮期)", text: $sysBPStr, unit: "mmHg", placeholder: "120", decimal: false)
                    numRow("最低血圧 (拡張期)", text: $diaBPStr, unit: "mmHg", placeholder: "75", decimal: false)
                    numRow("脈拍数", text: $pulseStr, unit: "拍/分", placeholder: "68", decimal: false)
                }

                // 4. 血算・貧血検査
                Section(header: Text("2. 血液一般・貧血（CBC）")) {
                    numRow("白血球数 (WBC)", text: $wbcStr, unit: "/μL", placeholder: "5400", decimal: false)
                    numRow("赤血球数 (RBC)", text: $rbcStr, unit: "万/μL", placeholder: "470", decimal: true)
                    numRow("血色素量 / Hb", text: $hbStr, unit: "g/dL", placeholder: "14.5", decimal: true)
                    numRow("ヘマトクリット (Ht)", text: $htStr, unit: "%", placeholder: "43.5", decimal: true)
                    numRow("血小板数 (PLT)", text: $pltStr, unit: "万/μL", placeholder: "23.5", decimal: true)
                }

                // 5. 脂質検査
                Section(header: Text("3. 血中脂質（コレステロール・中性脂肪）")) {
                    numRow("総コレステロール", text: $tcStr, unit: "mg/dL", placeholder: "190", decimal: false)
                    numRow("LDLコレステロール", text: $ldlStr, unit: "mg/dL", placeholder: "110", decimal: false)
                    numRow("HDLコレステロール", text: $hdlStr, unit: "mg/dL", placeholder: "60", decimal: false)
                    numRow("Non-HDLコレステロール", text: $nonHdlStr, unit: "mg/dL", placeholder: "130", decimal: false)
                    numRow("中性脂肪 (TG)", text: $tgStr, unit: "mg/dL", placeholder: "95", decimal: false)
                }

                // 6. 肝機能・胆道・膵・蛋白
                Section(header: Text("4. 肝機能・胆道・膵・血清蛋白")) {
                    numRow("AST (GOT)", text: $astStr, unit: "U/L", placeholder: "22", decimal: false)
                    numRow("ALT (GPT)", text: $altStr, unit: "U/L", placeholder: "20", decimal: false)
                    numRow("γ-GTP", text: $ggtpStr, unit: "U/L", placeholder: "30", decimal: false)
                    numRow("ALP", text: $alpStr, unit: "U/L", placeholder: "70", decimal: false)
                    numRow("LDH (LD)", text: $ldhStr, unit: "U/L", placeholder: "175", decimal: false)
                    numRow("総ビリルビン (T-Bil)", text: $tbilStr, unit: "mg/dL", placeholder: "0.7", decimal: true)
                    numRow("総蛋白 (TP)", text: $tpStr, unit: "g/dL", placeholder: "7.2", decimal: true)
                    numRow("アルブミン (Alb)", text: $albStr, unit: "g/dL", placeholder: "4.5", decimal: true)
                    numRow("アミラーゼ (AMY)", text: $amyStr, unit: "U/L", placeholder: "75", decimal: false)
                }

                // 7. 糖代謝・尿酸
                Section(header: Text("5. 糖代謝・痛風（尿酸）")) {
                    numRow("血糖 (空腹時・随時)", text: $fbgStr, unit: "mg/dL", placeholder: "92", decimal: false)
                    numRow("HbA1c", text: $hba1cStr, unit: "%", placeholder: "5.4", decimal: true)
                    numRow("尿酸値 (UA)", text: $uaStr, unit: "mg/dL", placeholder: "5.8", decimal: true)
                }

                // 8. 腎機能・電解質・炎症・鉄代謝
                Section(header: Text("6. 腎機能・電解質・炎症・鉄代謝")) {
                    numRow("尿素窒素 (BUN / UN)", text: $bunStr, unit: "mg/dL", placeholder: "13.5", decimal: true)
                    numRow("クレアチニン (Cr)", text: $crStr, unit: "mg/dL", placeholder: "0.80", decimal: true)
                    numRow("eGFR", text: $egfrStr, unit: "mL/min", placeholder: "80.0", decimal: true)
                    numRow("CRP定量 (炎症反応)", text: $crpStr, unit: "mg/dL", placeholder: "0.05", decimal: true)
                    numRow("ナトリウム (Na)", text: $naStr, unit: "mEq/L", placeholder: "141", decimal: true)
                    numRow("カリウム (K)", text: $kStr, unit: "mEq/L", placeholder: "4.1", decimal: true)
                    numRow("クロール (Cl)", text: $clStr, unit: "mEq/L", placeholder: "103", decimal: true)
                    numRow("血清鉄 (Fe)", text: $feStr, unit: "μg/dL", placeholder: "95", decimal: false)
                }

                // 9. 尿検査・心電図・胸部X線等の所見
                Section(header: Text("7. 尿検査・生理検査・画像所見")) {
                    textRow("尿蛋白", text: $urineProtein, placeholder: "例: (-), (±), (+)")
                    textRow("尿糖", text: $urineGlucose, placeholder: "例: (-), (±), (+)")
                    textRow("尿潜血", text: $urineOccult, placeholder: "例: (-), (±), (+)")
                    textRow("聴力検査", text: $hearingFinding, placeholder: "例: 所見なし")
                    textRow("心電図", text: $ecgFinding, placeholder: "例: 異常なし")
                    textRow("胸部X線", text: $chestXrayFinding, placeholder: "例: 異常なし")
                }

                // 10. その他の検査項目（無制限カスタム追加）
                Section(
                    header: Text("8. その他の検査項目（自由追加）"),
                    footer: Text("甲状腺（TSH/FT4）、フェリチン、CK(CPK)、腫瘍マーカー、アレルギー検査など、病院独自のあらゆる検査項目を自由に追加できます。")
                ) {
                    ForEach($extraItems) { $item in
                        VStack(spacing: 8) {
                            HStack {
                                TextField("項目名（例: フェリチン, TSH）", text: $item.name)
                                    .font(.system(size: 14, weight: .bold))
                                Spacer()
                                Button(role: .destructive, action: {
                                    extraItems.removeAll { $0.id == item.id }
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            HStack(spacing: 8) {
                                TextField("測定値", text: $item.value)
                                    .keyboardType(.numbersAndPunctuation)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .textFieldStyle(.roundedBorder)
                                TextField("単位 (ng/mL等)", text: $item.unit)
                                    .font(.system(size: 12))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                TextField("基準値メモ", text: $item.reference)
                                    .font(.system(size: 12))
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button(action: {
                        extraItems.append(ExtraLabItem())
                    }) {
                        Label("任意の検査項目を追加する", systemImage: "plus.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.emerald)
                    }
                }

                // 11. メモ・削除
                Section(header: Text("メモ・医師コメント控え")) {
                    TextField("医師からのアドバイス控えなど（任意）", text: $memo, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let existing = recordToEdit {
                    Section {
                        Button(role: .destructive, action: {
                            modelContext.delete(existing)
                            try? modelContext.save()
                            dismiss()
                        }) {
                            HStack {
                                Spacer()
                                Label("この健診・検査記録を削除", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(recordToEdit == nil ? "健診・検査結果の記録" : "健診・検査結果の編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveRecord() }
                        .disabled(isAnalyzing)
                }
            }
            .onAppear { populateIfEditing() }
            .onChange(of: photoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        self.imageData = data
                        if GeminiService.shared.getApiKey() != nil {
                            analyzeSheetImage()
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                ProfileCameraPicker { img in
                    if let data = img.jpegData(compressionQuality: 0.85) {
                        self.imageData = data
                        if GeminiService.shared.getApiKey() != nil {
                            analyzeSheetImage()
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .alert("お知らせ", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func numRow(_ label: String, text: Binding<String>, unit: String, placeholder: String, decimal: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .frame(width: 86)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 48, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func textRow(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            TextField(placeholder, text: text)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14))
        }
    }

    private func populateIfEditing() {
        guard let r = recordToEdit else { return }
        examDate = r.examDate
        facilityName = r.facilityName
        heightStr = r.heightCm.map { String(format: "%.1f", $0) } ?? ""
        weightStr = r.weightKg.map { String(format: "%.1f", $0) } ?? ""
        bodyFatStr = r.bodyFatPercent.map { String(format: "%.1f", $0) } ?? ""
        waistStr = r.waistCm.map { String(format: "%.1f", $0) } ?? ""
        visionRightStr = r.visionRight.map { String(format: "%.1f", $0) } ?? ""
        visionLeftStr = r.visionLeft.map { String(format: "%.1f", $0) } ?? ""
        sysBPStr = r.systolicBP.map(String.init) ?? ""
        diaBPStr = r.diastolicBP.map(String.init) ?? ""
        pulseStr = r.pulseRate.map(String.init) ?? ""

        wbcStr = r.wbc.map(String.init) ?? ""
        rbcStr = r.rbc.map { String(format: "%.0f", $0) } ?? ""
        hbStr = r.hemoglobin.map { String(format: "%.1f", $0) } ?? ""
        htStr = r.hematocrit.map { String(format: "%.1f", $0) } ?? ""
        pltStr = r.platelets.map { String(format: "%.1f", $0) } ?? ""

        tcStr = r.totalCholesterol.map(String.init) ?? ""
        ldlStr = r.ldlCholesterol.map(String.init) ?? ""
        hdlStr = r.hdlCholesterol.map(String.init) ?? ""
        nonHdlStr = r.nonHdlCholesterol.map(String.init) ?? ""
        tgStr = r.triglycerides.map(String.init) ?? ""

        astStr = r.ast.map(String.init) ?? ""
        altStr = r.alt.map(String.init) ?? ""
        ggtpStr = r.gammaGTP.map(String.init) ?? ""
        alpStr = r.alp.map(String.init) ?? ""
        ldhStr = r.ldh.map(String.init) ?? ""
        tbilStr = r.totalBilirubin.map { String(format: "%.1f", $0) } ?? ""
        tpStr = r.totalProtein.map { String(format: "%.1f", $0) } ?? ""
        albStr = r.albumin.map { String(format: "%.1f", $0) } ?? ""
        amyStr = r.amylase.map(String.init) ?? ""

        fbgStr = r.fastingGlucose.map(String.init) ?? ""
        hba1cStr = r.hba1c.map { String(format: "%.1f", $0) } ?? ""
        uaStr = r.uricAcid.map { String(format: "%.1f", $0) } ?? ""

        bunStr = r.bun.map { String(format: "%.1f", $0) } ?? ""
        crStr = r.creatinine.map { String(format: "%.2f", $0) } ?? ""
        egfrStr = r.egfr.map { String(format: "%.1f", $0) } ?? ""
        crpStr = r.crp.map { String(format: "%.2f", $0) } ?? ""
        naStr = r.sodium.map { String(format: "%.0f", $0) } ?? ""
        kStr = r.potassium.map { String(format: "%.1f", $0) } ?? ""
        clStr = r.chloride.map { String(format: "%.0f", $0) } ?? ""
        feStr = r.serumIron.map(String.init) ?? ""

        urineProtein = r.urineProtein
        urineGlucose = r.urineGlucose
        urineOccult = r.urineOccultBlood
        hearingFinding = r.hearingFinding
        ecgFinding = r.ecgFinding
        chestXrayFinding = r.chestXrayFinding

        extraItems = r.extraItems
        memo = r.memo
        imageData = r.sheetImageData
    }

    private func analyzeSheetImage() {
        guard let data = imageData else { return }
        isAnalyzing = true
        Task {
            do {
                let res = try await GeminiService.shared.analyzeHealthCheckPhoto(imageData: data)
                await MainActor.run {
                    if let dStr = res.examDate, let parsedDate = parseISODate(dStr) { examDate = parsedDate }
                    if let fac = res.facilityName, !fac.isEmpty { facilityName = fac }

                    if let v = res.heightCm { heightStr = String(format: "%.1f", v) }
                    if let v = res.weightKg { weightStr = String(format: "%.1f", v) }
                    if let v = res.bodyFatPercent { bodyFatStr = String(format: "%.1f", v) }
                    if let v = res.waistCm { waistStr = String(format: "%.1f", v) }
                    if let v = res.visionRight { visionRightStr = String(format: "%.1f", v) }
                    if let v = res.visionLeft { visionLeftStr = String(format: "%.1f", v) }
                    if let v = res.systolicBP { sysBPStr = "\(v)" }
                    if let v = res.diastolicBP { diaBPStr = "\(v)" }
                    if let v = res.pulseRate { pulseStr = "\(v)" }

                    if let v = res.wbc { wbcStr = "\(v)" }
                    if let v = res.rbc { rbcStr = String(format: "%.0f", v) }
                    if let v = res.hemoglobin { hbStr = String(format: "%.1f", v) }
                    if let v = res.hematocrit { htStr = String(format: "%.1f", v) }
                    if let v = res.platelets { pltStr = String(format: "%.1f", v) }

                    if let v = res.totalCholesterol { tcStr = "\(v)" }
                    if let v = res.ldlCholesterol { ldlStr = "\(v)" }
                    if let v = res.hdlCholesterol { hdlStr = "\(v)" }
                    if let v = res.nonHdlCholesterol { nonHdlStr = "\(v)" }
                    if let v = res.triglycerides { tgStr = "\(v)" }

                    if let v = res.ast { astStr = "\(v)" }
                    if let v = res.alt { altStr = "\(v)" }
                    if let v = res.gammaGTP { ggtpStr = "\(v)" }
                    if let v = res.alp { alpStr = "\(v)" }
                    if let v = res.ldh { ldhStr = "\(v)" }
                    if let v = res.totalBilirubin { tbilStr = String(format: "%.1f", v) }
                    if let v = res.totalProtein { tpStr = String(format: "%.1f", v) }
                    if let v = res.albumin { albStr = String(format: "%.1f", v) }
                    if let v = res.amylase { amyStr = "\(v)" }

                    if let v = res.fastingGlucose { fbgStr = "\(v)" }
                    if let v = res.hba1c { hba1cStr = String(format: "%.1f", v) }
                    if let v = res.uricAcid { uaStr = String(format: "%.1f", v) }

                    if let v = res.bun { bunStr = String(format: "%.1f", v) }
                    if let v = res.creatinine { crStr = String(format: "%.2f", v) }
                    if let v = res.egfr { egfrStr = String(format: "%.1f", v) }
                    if let v = res.crp { crpStr = String(format: "%.2f", v) }
                    if let v = res.sodium { naStr = String(format: "%.0f", v) }
                    if let v = res.potassium { kStr = String(format: "%.1f", v) }
                    if let v = res.chloride { clStr = String(format: "%.0f", v) }
                    if let v = res.serumIron { feStr = "\(v)" }

                    if let s = res.urineProtein, !s.isEmpty { urineProtein = s }
                    if let s = res.urineGlucose, !s.isEmpty { urineGlucose = s }
                    if let s = res.urineOccultBlood, !s.isEmpty { urineOccult = s }
                    if let s = res.hearingFinding, !s.isEmpty { hearingFinding = s }
                    if let s = res.ecgFinding, !s.isEmpty { ecgFinding = s }
                    if let s = res.chestXrayFinding, !s.isEmpty { chestXrayFinding = s }

                    if let extras = res.extraItems {
                        for dto in extras {
                            let n = (dto.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            let val = (dto.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !n.isEmpty && !val.isEmpty else { continue }
                            if let idx = extraItems.firstIndex(where: { $0.name == n }) {
                                extraItems[idx].value = val
                                if let u = dto.unit { extraItems[idx].unit = u }
                                if let r = dto.reference { extraItems[idx].reference = r }
                            } else {
                                extraItems.append(ExtraLabItem(
                                    name: n,
                                    value: val,
                                    unit: dto.unit ?? "",
                                    reference: dto.reference ?? ""
                                ))
                            }
                        }
                    }

                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                    isAnalyzing = false
                }
            }
        }
    }

    private func saveRecord() {
        let target = recordToEdit ?? HealthCheckRecord()
        target.examDate = examDate
        target.facilityName = facilityName.trimmingCharacters(in: .whitespacesAndNewlines)

        target.heightCm = Double(heightStr)
        target.weightKg = Double(weightStr)
        target.bodyFatPercent = Double(bodyFatStr)
        target.waistCm = Double(waistStr)
        target.visionRight = Double(visionRightStr)
        target.visionLeft = Double(visionLeftStr)
        target.systolicBP = Int(sysBPStr)
        target.diastolicBP = Int(diaBPStr)
        target.pulseRate = Int(pulseStr)

        target.wbc = Int(wbcStr)
        target.rbc = Double(rbcStr)
        target.hemoglobin = Double(hbStr)
        target.hematocrit = Double(htStr)
        target.platelets = Double(pltStr)

        target.totalCholesterol = Int(tcStr)
        target.ldlCholesterol = Int(ldlStr)
        target.hdlCholesterol = Int(hdlStr)
        target.nonHdlCholesterol = Int(nonHdlStr)
        target.triglycerides = Int(tgStr)

        target.ast = Int(astStr)
        target.alt = Int(altStr)
        target.gammaGTP = Int(ggtpStr)
        target.alp = Int(alpStr)
        target.ldh = Int(ldhStr)
        target.totalBilirubin = Double(tbilStr)
        target.totalProtein = Double(tpStr)
        target.albumin = Double(albStr)
        target.amylase = Int(amyStr)

        target.fastingGlucose = Int(fbgStr)
        target.hba1c = Double(hba1cStr)
        target.uricAcid = Double(uaStr)

        target.bun = Double(bunStr)
        target.creatinine = Double(crStr)
        target.egfr = Double(egfrStr)
        target.crp = Double(crpStr)
        target.sodium = Double(naStr)
        target.potassium = Double(kStr)
        target.chloride = Double(clStr)
        target.serumIron = Int(feStr)

        target.urineProtein = urineProtein.trimmingCharacters(in: .whitespacesAndNewlines)
        target.urineGlucose = urineGlucose.trimmingCharacters(in: .whitespacesAndNewlines)
        target.urineOccultBlood = urineOccult.trimmingCharacters(in: .whitespacesAndNewlines)
        target.hearingFinding = hearingFinding.trimmingCharacters(in: .whitespacesAndNewlines)
        target.ecgFinding = ecgFinding.trimmingCharacters(in: .whitespacesAndNewlines)
        target.chestXrayFinding = chestXrayFinding.trimmingCharacters(in: .whitespacesAndNewlines)

        target.extraItems = extraItems.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty &&
            !$0.value.trimmingCharacters(in: .whitespaces).isEmpty
        }

        target.memo = memo
        target.sheetImageData = imageData

        if recordToEdit == nil {
            modelContext.insert(target)
        }
        try? modelContext.save()
        dismiss()
    }
}

// =============================================================================
// MARK: - 医療費ノート 登録・編集モーダル（手入力 ＋ 領収書カメラ/写真 AI読取）
// =============================================================================
private struct MedicalExpenseEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let recordToEdit: MedicalExpenseRecord?

    @State private var paymentDate: Date = Date()
    @State private var facilityName: String = ""
    @State private var category: MedicalExpenseCategory = .clinic
    @State private var amountStr: String = ""
    @State private var familyMember: String = "本人"
    @State private var memo: String = ""

    @State private var photoItem: PhotosPickerItem? = nil
    @State private var receiptData: Data? = nil
    @State private var showingCamera: Bool = false
    @State private var isAnalyzing: Bool = false
    @State private var alertMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                // 1. 領収書写真 ＆ 任意AI自動読取
                Section(
                    header: Text("領収書・明細書の写真添付・AI読取（任意）"),
                    footer: Text("※AI読取はAPIキー設定時のみ使用できる任意の補助機能です。未設定でも下部から手入力で簡単に記録できます。")
                ) {
                    if let receiptData, let uiImg = UIImage(data: receiptData) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: uiImg)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Button(action: {
                                self.receiptData = nil
                                self.photoItem = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                                    .shadow(radius: 3)
                            }
                            .padding(8)
                        }
                    }

                    HStack(spacing: 10) {
                        Button(action: {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                showingCamera = true
                            } else {
                                alertMessage = "この端末ではカメラが利用できないため、「アルバムから選択」をご利用ください。"
                            }
                        }) {
                            Label("領収書を撮影", systemImage: "camera.fill")
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.emerald)

                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("アルバムから選択", systemImage: "photo.on.rectangle")
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.emerald)
                    }

                    if receiptData != nil {
                        if GeminiService.shared.getApiKey() != nil {
                            Button(action: { analyzeReceipt() }) {
                                HStack {
                                    Spacer()
                                    if isAnalyzing {
                                        ProgressView().tint(.white)
                                        Text("領収書を読み取り中...")
                                            .font(.system(size: 13, weight: .bold))
                                    } else {
                                        Label("領収書から金額・病院名をAI自動入力", systemImage: "sparkles")
                                            .font(.system(size: 14, weight: .bold))
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.indigo)
                            .disabled(isAnalyzing)
                        } else {
                            Text("本機能（AI自動読取）はAPIキーをお持ちの場合に、設定画面でキーを設定することで使用できる任意の機能です。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 2. 支払内容
                Section(header: Text("支払情報")) {
                    DatePicker("受診・支払日", selection: $paymentDate, displayedComponents: [.date])

                    TextField("病院・クリニック・薬局名", text: $facilityName)

                    Picker("区分", selection: $category) {
                        ForEach(MedicalExpenseCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.iconName).tag(cat)
                        }
                    }

                    HStack {
                        Text("自己負担支払額")
                            .font(.system(size: 15, weight: .bold))
                        Spacer()
                        Text("¥")
                            .foregroundColor(.secondary)
                        TextField("0", text: $amountStr)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(AppTheme.emerald)
                            .frame(width: 110)
                    }

                    Picker("対象者（医療費控除用）", selection: $familyMember) {
                        Text("本人").tag("本人")
                        Text("配偶者・家族").tag("家族")
                    }
                }

                Section(header: Text("メモ")) {
                    TextField("診療科・処方内容・通院経路など（任意）", text: $memo)
                }

                if let existing = recordToEdit {
                    Section {
                        Button(role: .destructive, action: {
                            modelContext.delete(existing)
                            try? modelContext.save()
                            dismiss()
                        }) {
                            HStack {
                                Spacer()
                                Label("この医療費記録を削除", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(recordToEdit == nil ? "医療費の記録" : "医療費の編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveExpense() }
                        .disabled((Int(amountStr) ?? 0) <= 0 || isAnalyzing)
                }
            }
            .onAppear { populateIfEditing() }
            .onChange(of: photoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        self.receiptData = data
                        if GeminiService.shared.getApiKey() != nil {
                            analyzeReceipt()
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                ProfileCameraPicker { img in
                    if let data = img.jpegData(compressionQuality: 0.85) {
                        self.receiptData = data
                        if GeminiService.shared.getApiKey() != nil {
                            analyzeReceipt()
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .alert("お知らせ", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func populateIfEditing() {
        guard let r = recordToEdit else { return }
        paymentDate = r.paymentDate
        facilityName = r.facilityName
        category = r.category
        amountStr = r.amountYen > 0 ? "\(r.amountYen)" : ""
        familyMember = r.familyMember
        memo = r.memo
        receiptData = r.receiptImageData
    }

    private func analyzeReceipt() {
        guard let data = receiptData else { return }
        isAnalyzing = true
        Task {
            do {
                let res = try await GeminiService.shared.analyzeMedicalReceiptPhoto(imageData: data)
                await MainActor.run {
                    if let dStr = res.paymentDate, let parsed = parseISODate(dStr) { paymentDate = parsed }
                    if let fac = res.facilityName, !fac.isEmpty { facilityName = fac }
                    if let catStr = res.category, let matched = MedicalExpenseCategory(rawValue: catStr) {
                        category = matched
                    }
                    if let amt = res.amountYen, amt > 0 { amountStr = "\(amt)" }
                    if let m = res.memo, !m.isEmpty, memo.isEmpty { memo = m }
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                    isAnalyzing = false
                }
            }
        }
    }

    private func saveExpense() {
        let cleanDigits = amountStr.filter { $0.isNumber }
        guard let yen = Int(cleanDigits), yen > 0 else { return }

        let target = recordToEdit ?? MedicalExpenseRecord()
        target.paymentDate = paymentDate
        target.facilityName = facilityName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.category = category
        target.amountYen = yen
        target.familyMember = familyMember
        target.memo = memo
        target.receiptImageData = receiptData

        if recordToEdit == nil {
            modelContext.insert(target)
        }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - 日付パース ＆ カメラピッカー共通ヘルパー
private func parseISODate(_ raw: String) -> Date? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    if let d = f.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return d
    }
    f.dateFormat = "yyyy/MM/dd"
    return f.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines))
}

private struct ProfileCameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ProfileCameraPicker
        init(parent: ProfileCameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.onCaptured(img)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
