import SwiftUI
import SwiftData

/// 「設定」画面（Gemini BYOK設定、完全データ初期化、医療免責・プライバシーポリシー）
public struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allMeals: [Meal]
    @Query private var allProfiles: [HealthProfile]
    @Query private var allHealthChecks: [HealthCheckRecord]
    @Query private var allMedicalExpenses: [MedicalExpenseRecord]
    @Query private var allDailyLogs: [DailyHealthLog]
    @Query private var allMedications: [MedicationItem]
    @Query private var allMessages: [AdvisorChatMessage]
    @Query private var allAdvices: [DailyAdvice]

    @State private var apiKeyInput: String = ""
    @State private var isKeySecure: Bool = true
    @State private var saveSuccessAlert: Bool = false
    @State private var isTestingDiagnostic: Bool = false
    @State private var diagnosticResult: GeminiDiagnosticResult? = nil

    // 全データ初期化の確認アラート
    @State private var showingResetConfirmationAlert: Bool = false
    @State private var showingFinalResetAlert: Bool = false

    // 規約・免責・第三者AIデータ送信同意シート
    @State private var showingPrivacySheet: Bool = false
    @State private var showingMedicalDisclaimerSheet: Bool = false
    @State private var showingProUpgradeSheet: Bool = false
    @State private var showingAIConsentSheet: Bool = false
    @State private var pendingActionAfterConsent: (() -> Void)? = nil
    @AppStorage(GeminiService.aiConsentUserDefaultsKey) private var hasConsentedToThirdPartyAI: Bool = false

    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @ObservedObject private var healthKit = HealthKitManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // 0. Proプラン（500円買い切り・広告完全非表示）
                Section(
                    header: Text("プラン・広告設定"),
                    footer: Text("Proプランは500円（税込）の1回買い切りです。月額課金は一切発生せず、購入後はすべての画面の下部バナー広告が永久に非表示になります。")
                ) {
                    HStack {
                        Label(
                            purchaseManager.isProUnlocked ? "Health Note Pro（広告非表示）" : "現在のプラン：無料プラン",
                            systemImage: purchaseManager.isProUnlocked ? "crown.fill" : "sparkles"
                        )
                        .foregroundColor(purchaseManager.isProUnlocked ? AppTheme.emerald : .primary)
                        .font(.system(size: 14, weight: .bold))

                        Spacer()

                        if purchaseManager.isProUnlocked {
                            Text("適用中")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppTheme.emerald)
                                .clipShape(Capsule())
                        }
                    }

                    if !purchaseManager.isProUnlocked {
                        Button(action: {
                            showingProUpgradeSheet = true
                        }) {
                            HStack {
                                Image(systemName: "crown.fill")
                                    .foregroundColor(.yellow)
                                Text("Proプランへアップグレード（\(purchaseManager.displayPrice) 買い切り）")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(AppTheme.actionGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))

                        Button(action: {
                            Task { await purchaseManager.restorePurchases() }
                        }) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("購入を復元する（機種変更・再インストール時）")
                                    .font(.system(size: 13))
                            }
                            .foregroundColor(AppTheme.emerald)
                        }
                        .disabled(purchaseManager.isLoading)
                    } else {
                        #if DEBUG
                        Button(role: .destructive, action: {
                            purchaseManager.debugResetProStatus()
                        }) {
                            Text("【デバッグ用】無料プラン（広告あり）の表示に戻す")
                                .font(.system(size: 12))
                        }
                        #endif
                    }

                    if let status = purchaseManager.statusMessage {
                        Text(status)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppTheme.emerald)
                    }
                    if let error = purchaseManager.errorMessage {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                }

                // 1. Google Gemini AI設定 (任意・上級者向けオプショナル機能 & Guideline 5.1.2(i) 明示的同意)
                Section(header: Text("AI拡張機能設定（任意オプション）"), footer: aiFooterView) {
                    // Guideline 5.1.1(i) & 5.1.2(i): 送信データ・送信先（Google LLC）の明示および事前許可ステータス
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: hasConsentedToThirdPartyAI ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                .foregroundColor(hasConsentedToThirdPartyAI ? AppTheme.emerald : .orange)
                            Text("第三者AI（Google Gemini API）へのデータ送信許可")
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                            Text(hasConsentedToThirdPartyAI ? "許可済み" : "未許可")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(hasConsentedToThirdPartyAI ? AppTheme.emerald : Color.orange)
                                .clipShape(Capsule())
                        }

                        Text("送信先: Google LLC（Google Gemini API）\n送信データ: 相談文、食事記録・食事写真、マイカルテ（年齢・性別・身長・体重・生活習慣・アレルギー・既往歴メモ・服薬/サプリ名）、健診の検査数値サマリ、健診結果表・医療費領収書画像（氏名・保険証番号等の個人識別情報は除外）")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)

                        HStack(spacing: 12) {
                            Button(action: {
                                pendingActionAfterConsent = nil
                                showingAIConsentSheet = true
                            }) {
                                Label(
                                    hasConsentedToThirdPartyAI ? "送信データの詳細・同意内容を確認" : "送信内容を確認してデータ送信を許可する",
                                    systemImage: "hand.raised.fill"
                                )
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(AppTheme.emerald)
                            }
                            .buttonStyle(.plain)

                            if hasConsentedToThirdPartyAI {
                                Spacer()
                                Button(role: .destructive, action: {
                                    hasConsentedToThirdPartyAI = false
                                }) {
                                    Text("許可を取り消す")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        if isKeySecure {
                            SecureField("Gemini APIキー（任意）", text: $apiKeyInput)
                        } else {
                            TextField("Gemini APIキー（任意）", text: $apiKeyInput)
                        }

                        Button(action: { isKeySecure.toggle() }) {
                            Image(systemName: isKeySecure ? "eye" : "eye.slash")
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: { saveAiSettings() }) {
                        HStack {
                            Spacer()
                            Text("APIキー設定を保存")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppTheme.emerald)
                            Spacer()
                        }
                    }

                    if !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: { runModelDiagnostic() }) {
                            HStack(spacing: 6) {
                                Spacer()
                                if isTestingDiagnostic {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("models.list 疎通診断中...")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                } else {
                                    Image(systemName: "checkmark.shield")
                                    Text("疎通テスト・利用可能モデル診断")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                Spacer()
                            }
                            .foregroundColor(.indigo)
                        }
                        .disabled(isTestingDiagnostic)
                    }

                    if let diag = diagnosticResult {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: diag.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(diag.isSuccess ? AppTheme.emerald : .red)
                                Text(diag.message)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(diag.isSuccess ? AppTheme.emerald : .red)
                            }
                            if diag.isSuccess {
                                Text("疎通確認モデル: \(diag.activeModel)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // 2. Apple HealthKit 連携状態
                Section(header: Text("Apple ヘルスケア連携")) {
                    HStack {
                        Label("ヘルスケア同期", systemImage: "heart.fill")
                            .foregroundColor(.pink)
                        Spacer()
                        Text(healthKit.isAuthorized ? "接続済み" : "未接続")
                            .foregroundColor(healthKit.isAuthorized ? .green : .secondary)
                    }

                    Button(action: {
                        Task { _ = await healthKit.requestAuthorization() }
                    }) {
                        Text(healthKit.isAuthorized ? "ヘルスケアの最新データを今すぐ再同期" : "ヘルスケアのアクセス権限をリクエスト")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.emerald)
                    }
                }

                // 3. 審査必須：全データ初期化（退会・アカウント削除相当）
                Section(header: Text("データ管理（審査基準 5.1.1 準拠）"), footer: Text("本アプリは外部サーバーを持たないため、端末内およびユーザー本人のiCloud Private Databaseにのみデータが保存されます。下記を実行するとすべての個人データが完全に抹消されます。")) {
                    Button(role: .destructive, action: {
                        showingResetConfirmationAlert = true
                    }) {
                        Label("全データを完全に初期化・削除", systemImage: "trash.fill")
                            .foregroundColor(.red)
                    }
                }

                // 4. 法的情報・App Storeガイドライン遵守
                Section(header: Text("法的情報・免責事項")) {
                    Button(action: { showingMedicalDisclaimerSheet = true }) {
                        HStack {
                            Text("医療免責事項（Guideline 1.4 & 5.1.3）")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: { showingPrivacySheet = true }) {
                        HStack {
                            Text("プライバシーポリシー（サーバーレス設計）")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 5. アプリ情報
                Section(header: Text("アプリ情報")) {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("設定")
            .onAppear {
                loadAiSettings()
            }
            .alert("設定を保存しました", isPresented: $saveSuccessAlert) {
                Button("OK", role: .cancel) {}
            }
            .alert("全データを削除しますか？", isPresented: $showingResetConfirmationAlert) {
                Button("キャンセル", role: .cancel) {}
                Button("削除する", role: .destructive) {
                    showingFinalResetAlert = true
                }
            } message: {
                Text("食事ログ、マイカルテ、健診・検査結果、医療費ノート、服薬管理、チャット履歴を含むすべてのデータが削除されます。この操作は取り消せません。")
            }
            .alert("最終確認：本当に初期化しますか？", isPresented: $showingFinalResetAlert) {
                Button("キャンセル", role: .cancel) {}
                Button("完全に初期化", role: .destructive) {
                    performCompleteReset()
                }
            } message: {
                Text("すべてのローカルおよびiCloud同期データが完全に消去されます。")
            }
            .sheet(isPresented: $showingMedicalDisclaimerSheet) {
                medicalDisclaimerView
            }
            .sheet(isPresented: $showingPrivacySheet) {
                privacyPolicyView
            }
            .sheet(isPresented: $showingProUpgradeSheet) {
                ProUpgradeSheetView()
            }
            .sheet(isPresented: $showingAIConsentSheet) {
                ThirdPartyAIConsentSheet(
                    onAllow: {
                        let action = pendingActionAfterConsent
                        pendingActionAfterConsent = nil
                        action?()
                    },
                    onCancel: {
                        pendingActionAfterConsent = nil
                    }
                )
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AdBottomBannerBar()
            }
        }
    }

    // MARK: - AIフッター説明（Guideline 3.1.1 & 5.1.2(i) 準拠：外部リンク完全排除・任意機能と送信先の明示）
    private var aiFooterView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("【上級者向け任意機能・データ送信に関する説明（Guideline 5.1.1(i) & 5.1.2(i)）】\n本アプリはAPIキーが未登録の場合でも、すべての食事記録、カロリー計算、PFCバランス分析、HealthKitバイタル同期、健診結果・医療費ノート管理、服薬管理、月間カレンダーが完全無料・制限なしでご利用いただけます。\n\nGoogle Gemini APIキーをお持ちの場合、キーを登録し「データ送信を許可」に同意いただくことで、食事写真の自動栄養解析、本日のAI食事総括評価、健診結果・医療費領収書/明細書の画像読取補助、AIアドバイザー相談を活用できます。AI機能実行時、対象データはお客様の端末から送信先である Google LLC（Google Gemini API: generativelanguage.googleapis.com）へ直接HTTPS暗号化通信で送信されます。お客様の事前の明示的な許可なしにデータが外部へ送信されることは一切ありません。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineSpacing(3)
        }
    }

    // MARK: - AI設定のロード＆セーブ
    private func loadAiSettings() {
        apiKeyInput = KeychainManager.shared.load(key: KeychainManager.geminiApiKeyIdentifier) ?? ""
    }

    private func saveAiSettings() {
        let cleanKey = GeminiService.shared.sanitizeApiKey(apiKeyInput)
        apiKeyInput = cleanKey
        KeychainManager.shared.save(key: KeychainManager.geminiApiKeyIdentifier, value: cleanKey)
        diagnosticResult = nil

        if !cleanKey.isEmpty && !hasConsentedToThirdPartyAI {
            pendingActionAfterConsent = {
                saveSuccessAlert = true
            }
            showingAIConsentSheet = true
        } else {
            saveSuccessAlert = true
        }
    }

    private func runModelDiagnostic() {
        let cleanKey = GeminiService.shared.sanitizeApiKey(apiKeyInput)
        apiKeyInput = cleanKey
        KeychainManager.shared.save(key: KeychainManager.geminiApiKeyIdentifier, value: cleanKey)

        if !hasConsentedToThirdPartyAI {
            pendingActionAfterConsent = {
                executeModelDiagnostic(cleanKey: cleanKey)
            }
            showingAIConsentSheet = true
        } else {
            executeModelDiagnostic(cleanKey: cleanKey)
        }
    }

    private func executeModelDiagnostic(cleanKey: String) {
        isTestingDiagnostic = true
        diagnosticResult = nil

        Task {
            let result = await GeminiService.shared.diagnoseModels(overrideApiKey: cleanKey)
            await MainActor.run {
                self.diagnosticResult = result
                self.isTestingDiagnostic = false
            }
        }
    }

    // MARK: - 全データ初期化（退会・アカウント削除相当）
    private func performCompleteReset() {
        for item in allMeals { modelContext.delete(item) }
        for item in allProfiles { modelContext.delete(item) }
        for item in allHealthChecks { modelContext.delete(item) }
        for item in allMedicalExpenses { modelContext.delete(item) }
        for item in allDailyLogs { modelContext.delete(item) }
        for item in allMedications { modelContext.delete(item) }
        for item in allMessages { modelContext.delete(item) }
        for item in allAdvices { modelContext.delete(item) }

        try? modelContext.save()

        // KeychainのAPIキーおよびAIデータ送信同意フラグも初期化
        KeychainManager.shared.delete(key: KeychainManager.geminiApiKeyIdentifier)
        KeychainManager.shared.delete(key: KeychainManager.geminiModelIdentifier)
        hasConsentedToThirdPartyAI = false
        apiKeyInput = ""

        // 初期プロファイルの再投入
        ModelContainerFactory.ensureInitialData(context: modelContext)

        // ウィジェット表示データもリセット
        WidgetDataManager.shared.updateWidgetData(
            intakeCalories: 0,
            burnedCalories: 0,
            protein: 0,
            fat: 0,
            carbs: 0,
            lastMealDate: nil
        )
    }

    // MARK: - 医療免責事項（医師法・薬機法・App Store Guideline 1.4 & 5.1.3 準拠）
    private var medicalDisclaimerView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("医療免責事項および法令遵守方針")
                        .font(.system(size: 18, weight: .bold))

                    Text("""
                    本アプリ（Health Note / ヘルスノート）は、利用者の一般的な生活習慣の改善、健康維持および栄養管理をサポートすることを目的としたセルフケア・ツールであり、医療機器または医療提供サービスではありません。

                    1. 【医師法第17条（医業の禁止）に基づく免責】:
                    本アプリ内のAIアドバイザー、食事解析結果、およびその他のすべてのコンテンツは、医師、管理栄養士その他の医療専門家による医学的判断・診断・処方・指示の代替となるものではありません。病気の診断、治療法・処方の決定、治癒の判断は一切行いません。

                    2. 【医薬品医療機器等法（薬機法）に基づく表記】:
                    本アプリで提示される栄養素や食材、サプリメント等に関する情報は、公的な栄養データに基づく一般的な知見であり、特定の疾病の治療・予防や医薬品的な効能効果を保証・標榜するものではありません。

                    3. 【医療機関の受診勧奨】:
                    体調に異変や痛みを感じた場合、既存の疾患・持病をお持ちの場合、妊娠中または服薬中の方は、自己判断を行わず、必ず主治医や専門医療機関に直接ご相談ください。

                    4. 【自己責任による健康管理】:
                    本アプリで提示される栄養指標や推定値は一般的な成人向けの参考情報です。ご自身の体調に合わせて無理のない範囲でご活用ください。
                    """)
                    .font(.system(size: 13))
                    .lineSpacing(5)

                    Divider()
                        .padding(.vertical, 4)

                    // App Store Guideline 1.4.1 準拠：栄養基準・BMI・健診・医療費控除の公的出典および参照リンク
                    VStack(alignment: .leading, spacing: 10) {
                        Text("5. 【栄養指標・BMI・健診基準・医療費控除の公的出典（Guideline 1.4.1 準拠）】")
                            .font(.system(size: 14, weight: .bold))

                        Text("本アプリにおけるBMI計算式（体重kg ÷ [身長m]²、普通体重 18.5〜25.0未満）、PFC栄養バランス・摂取カロリーの参考指標、健康診断項目の一般的な基準範囲、および医療費控除の集計目安は、以下の公的機関が公開する統計基準・案内情報に基づいています。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineSpacing(4)

                        Link(destination: URL(string: "https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/kenkou_iryou/kenkou/eiyou/syokuji_kijyun.html")!) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                Text("厚生労働省「日本人の食事摂取基準」")
                                    .underline()
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.emerald)
                        }

                        Link(destination: URL(string: "https://www.e-healthnet.mhlw.go.jp/information/dictionary/metabolic/ym-002.html")!) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                Text("厚生労働省 健康情報サイト「BMI（体格指数）の算出と判定基準」")
                                    .underline()
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.emerald)
                        }

                        Link(destination: URL(string: "https://www.mext.go.jp/a_menu/syokuhinseibun/index.htm")!) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                Text("文部科学省「日本食品標準成分表」")
                                    .underline()
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.emerald)
                        }

                        Link(destination: URL(string: "https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/0000194155.html")!) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                Text("厚生労働省「標準的な健診・保健指導プログラム」")
                                    .underline()
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.emerald)
                        }

                        Link(destination: URL(string: "https://www.nta.go.jp/taxes/shiraberu/taxanswer/shotoku/1120.htm")!) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                Text("国税庁 タックスアンサー「No.1120 医療費を支払ったとき（医療費控除）」")
                                    .underline()
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.emerald)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("医療免責事項")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - プライバシーポリシーシート（Guideline 5.1.1(i) & 5.1.2(i) 完全準拠）
    private var privacyPolicyView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("プライバシーポリシー（Guideline 5.1.1(i) & 5.1.2(i) 準拠）")
                        .font(.system(size: 18, weight: .bold))

                    Text("""
                    本アプリ（Health Note / ヘルスノート）は、開発者サーバーを一切持たない完全サーバーレス設計を採用しており、利用者の個人情報とプライバシーを最大限に保護します。

                    1. 収集・取り扱うデータと収集方法（What Data the App Collects & How It Is Collected）:
                    • ユーザーによる手動入力データ：食事記録（料理名・カロリー・PFC）、身体・生活習慣プロフィール（年齢・性別・身長・体重・体脂肪率・活動レベル・睡眠時間・飲酒/喫煙/妊娠状況・アレルギー・既往歴メモ）、服薬・サプリメント名、健康診断の検査数値、医療費記録、AIアドバイザー相談メッセージ。
                    • カメラ・写真ライブラリからの選択画像（任意）：食事写真、健康診断結果表の画像、医療費領収書・明細書の画像（お客様が自ら撮影または選択した場合のみ取得）。
                    • Apple HealthKit データ（任意・明示的許可時のみ）：歩数、消費エネルギー、心拍数、睡眠時間、体重、体脂肪率の読み取り、および食事の摂取エネルギー・PFC栄養素の書き込み。
                    • 広告配信に関する技術データ（Google AdMob SDK）：デバイス識別子（ATT許可時のみIDFA）、おおよその位置情報、広告表示・操作データ、クラッシュ・パフォーマンス診断データ。

                    2. データの保存先とすべての利用目的（Storage & All Uses of Data）:
                    • すべての健康・食事・健診・医療費記録は、お客様ご自身のiOS端末内およびお客様個人のiCloud（Apple CloudKit Private Database）にのみ暗号化保存され、日々の健康・栄養・医療費管理およびアプリ内表示の目的にのみ使用されます。開発者のサーバーへ収集・送信・保存されることは一切ありません。
                    • お客様は「設定 ＞ 全データを完全に初期化・削除」から、いつでもすべてのデータを完全に消去できます。

                    3. 第三者AIサービスへのデータ送信・送信先・事前同意（Data Sharing with Third-Party AI - Guideline 5.1.2(i)）:
                    • 初期状態（デフォルト）では、いかなるデータも第三者AIサービスへ送信されません。
                    • お客様が任意でご自身の Google Gemini APIキーを設定し、かつアプリ内の「第三者AIへのデータ送信に関する許可確認（同意画面）」にて明示的に許可（同意）した後にAI機能を実行した場合に限り、以下のデータがお客様の端末から直接 Google LLC（Google Gemini API: generativelanguage.googleapis.com）へ暗号化通信（HTTPS/TLS）で送信されます：
                      (a) 食事写真解析・本日のAI食事総括：選択した食事画像、本日の食事記録（料理名・カロリー・PFC）、および個人識別情報を含まない身体・生活習慣プロフィール要約。
                      (b) 健診結果表・医療費領収書/明細書の画像AI読取補助：お客様が選択した書類画像（氏名・住所・生年月日・保険証記号番号等の個人識別情報は抽出・保存しないよう厳格に制御）。
                      (c) AIアドバイザー相談：入力した相談メッセージ、本日の食事記録、身体・生活習慣プロフィール要約、登録中の服薬・サプリメント名、および直近の健康診断の検査数値サマリ（氏名・医療機関名・生年月日・保険証番号等の個人識別情報は一切含まれません）。
                    • 利用目的：お客様が要求したAI栄養推定、書類の自動入力補助（OCR）、および一般的な食生活アドバイスの生成目的にのみ使用されます。

                    4. 第三者による同等以上のデータ保護の確認（Same or Equal Protection by Third Parties - Guideline 5.1.1(i) & 5.1.2(i)）:
                    • 本アプリがデータを共有・送信する第三者（Google LLC：Google Gemini API および Google AdMob、ならびに Apple Inc.：iCloud / CloudKit）は、すべて業界標準の暗号化通信（HTTPS/TLS）および厳格なデータ保護規約・セキュリティ基準を遵守しており、本プライバシーポリシーに記載された基準および Apple App Store Review Guidelines が求める水準と同等以上のデータ保護（Same or Equal Protection）を提供していることを確認しています。
                    • Google AI Studioの無料枠（Free Tier）APIキーをご利用の場合、Googleの利用規約に基づき送信データがGoogleのモデル改善に利用される場合があります。学習利用を希望されない場合は、Google Cloudの有料従量課金プロジェクトのAPIキーをご利用いただくか、AIデータ送信の許可をオフにして手動記録機能をご利用ください。

                    5. Apple HealthKit データの厳格保護（Guideline 5.1.3 準拠）:
                    • Apple HealthKit から取得した歩数・消費カロリー・心拍数・睡眠時間等のバイタルデータが第三者AI（Google Gemini API）や広告事業者へ送信されることは一切ありません。また、HealthKitデータやアプリ内の健康記録を広告・マーケティング・データマイニング目的で使用・売却・共有することは一切ありません。
                    """)
                    .font(.system(size: 13))
                    .lineSpacing(5)
                }
                .padding(20)
            }
            .navigationTitle("プライバシーポリシー")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// =============================================================================
// MARK: - Guideline 5.1.1(i) & 5.1.2(i) 準拠：第三者AI（Google Gemini API）データ送信の明示的許可（同意）モーダル
// =============================================================================
public struct ThirdPartyAIConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(GeminiService.aiConsentUserDefaultsKey) private var hasConsentedToThirdPartyAI: Bool = false

    public var onAllow: (() -> Void)? = nil
    public var onCancel: (() -> Void)? = nil

    public init(onAllow: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.onAllow = onAllow
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // ヘッダー
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.emerald.opacity(0.15))
                                .frame(width: 48, height: 48)
                            Image(systemName: "hand.raised.shield.fill")
                                .font(.system(size: 24))
                                .foregroundColor(AppTheme.emerald)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("第三者AIへのデータ送信の許可確認")
                                .font(.system(size: 17, weight: .bold))
                            Text("Permission to Share Data with Third-Party AI")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.bottom, 2)

                    Text("任意のAI機能（AIアドバイザー相談・食事写真解析・本日のAI食事総括・健診結果/医療費明細の画像AI読取）を使用する前に、以下の「送信先」「送信されるデータ」「利用目的と保護水準」をご確認のうえ、データ送信を許可するか選択してください。")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineSpacing(3)

                    // 1. データの送信先 (Who the Data Is Sent To)
                    consentCard(
                        icon: "building.2.crop.circle.fill",
                        color: .indigo,
                        title: "1. データの送信先 (Who Data Is Sent To)",
                        bodyText: """
                        • 送信先事業者：Google LLC（Google Gemini API / generativelanguage.googleapis.com）
                        • 開発者サーバーは一切経由せず、お客様が設定したAPIキーを用いて、お客様のiOS端末から Google LLC のサーバーへ直接 HTTPS/TLS 暗号化通信で送信されます。
                        """
                    )

                    // 2. 送信されるデータの内容 (What Data Will Be Sent)
                    consentCard(
                        icon: "doc.text.magnifyingglass",
                        color: AppTheme.emerald,
                        title: "2. 送信されるデータの内容 (What Data Will Be Sent)",
                        bodyText: """
                        お客様が各AI機能を実行した際に限り、以下の該当データが Google LLC（Google Gemini API）へ送信されます：
                        • 【AIアドバイザー相談・AI食事総括】：入力した相談メッセージ、本日の食事記録（料理名・カロリー・PFC）、マイカルテの身体・生活習慣データ（年齢・性別・身長・体重/BMI・体脂肪率・活動レベル・睡眠時間・飲酒/喫煙/妊娠状況・食事制限・アレルギー・既往歴メモ）、登録中の服薬・サプリメント名、および直近の健康診断結果の検査数値サマリ（血圧・コレステロール・肝機能・血糖・HbA1c等の数値のみ）。
                        • 【写真AI自動読取（食事・健診結果表・医療費領収書/明細書）】：お客様が撮影またはアルバムから選択した対象画像データ。
                        • 【個人識別情報（PII）およびHealthKitバイタルの除外】：受診者氏名、住所、生年月日、医療機関名（チャット送信時）、保険証記号・番号などの個人識別情報は除外・破棄されます。また、Apple HealthKitの歩数・心拍数・消費カロリー・睡眠データがAIへ送信されることはありません。
                        """
                    )

                    // 3. 利用目的と第三者の保護水準 (Purpose & Same or Equal Protection)
                    consentCard(
                        icon: "lock.shield.fill",
                        color: .teal,
                        title: "3. 利用目的と保護水準 (Purpose & Equal Protection)",
                        bodyText: """
                        • 利用目的：お客様が要求した栄養推定、健診・医療費の入力補助（OCR）、および一般的な食生活アドバイスの生成目的にのみ使用されます。広告配信やトラッキングには一切使用されません。
                        • 同等以上の保護（Same or Equal Protection）：送信先である Google LLC（Google Gemini API）は、暗号化通信および利用規約・データ保護基準に基づき、本アプリのプライバシーポリシーと同等以上の保護措置（Same or Equal Protection）を提供します。
                        • いつでも「設定 ＞ AI拡張機能設定 ＞ 許可を取り消す」から同意を撤回でき、同意しない場合でも手動記録や食品辞書などの全コア機能を無料でご利用いただけます。
                        """
                    )

                    // 4. 明示的な許可・拒否ボタン
                    VStack(spacing: 10) {
                        Button(action: {
                            hasConsentedToThirdPartyAI = true
                            dismiss()
                            onAllow?()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.shield.fill")
                                Text("上記内容を確認し、Google Gemini APIへのデータ送信を許可する (Allow)")
                                    .font(.system(size: 14, weight: .bold))
                                    .multilineTextAlignment(.center)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 12)
                            .background(AppTheme.emerald)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button(role: .cancel, action: {
                            dismiss()
                            onCancel?()
                        }) {
                            Text("許可しない（データを送信せずキャンセル / Do Not Allow）")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("データ送信の事前許可")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                        onCancel?()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func consentCard(icon: String, color: Color, title: String, bodyText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
            }
            Text(bodyText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
