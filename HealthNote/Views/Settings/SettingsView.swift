import SwiftUI
import SwiftData

/// 「設定」画面（Gemini BYOK設定、完全データ初期化、医療免責・プライバシーポリシー）
public struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allMeals: [Meal]
    @Query private var allProfiles: [HealthProfile]
    @Query private var allMedications: [MedicationItem]
    @Query private var allMessages: [AdvisorChatMessage]
    @Query private var allAdvices: [DailyAdvice]

    @State private var apiKeyInput: String = ""
    @State private var modelInput: String = ""
    @State private var isKeySecure: Bool = true
    @State private var saveSuccessAlert: Bool = false

    // 全データ初期化の確認アラート
    @State private var showingResetConfirmationAlert: Bool = false
    @State private var showingFinalResetAlert: Bool = false

    // 規約・免責シート
    @State private var showingPrivacySheet: Bool = false
    @State private var showingMedicalDisclaimerSheet: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // 1. Google Gemini AI設定 (任意・上級者向けオプショナル機能)
                Section(header: Text("AI拡張機能設定（任意オプション）"), footer: aiFooterView) {
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

                    HStack {
                        Text("使用モデル")
                        Spacer()
                        TextField("gemini-flash-lite", text: $modelInput)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
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
                }

                // 2. Apple HealthKit 連携状態
                Section(header: Text("Apple ヘルスケア連携")) {
                    HStack {
                        Label("ヘルスケア同期", systemImage: "heart.fill")
                            .foregroundColor(.pink)
                        Spacer()
                        Text(HealthKitManager.shared.isAuthorized ? "接続済み" : "未接続")
                            .foregroundColor(HealthKitManager.shared.isAuthorized ? .green : .secondary)
                    }

                    if !HealthKitManager.shared.isAuthorized {
                        Button(action: {
                            Task { await HealthKitManager.shared.requestAuthorization() }
                        }) {
                            Text("ヘルスケアのアクセス権限をリクエスト")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.emerald)
                        }
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
                        Text("1.0.0 (Build 1)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("同期方式")
                        Spacer()
                        Text("Apple CloudKit (開発者負担0円)")
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
                Text("食事ログ、マイカルテ、服薬管理、チャット履歴を含むすべてのデータが削除されます。この操作は取り消せません。")
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
        }
    }

    // MARK: - AIフッター説明（Guideline 3.1.1 準拠：外部リンク完全排除・任意機能の徹底）
    private var aiFooterView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("【上級者向け任意機能】\n本アプリはAPIキーが未登録の場合でも、すべての食事記録、カロリー計算、PFCバランス分析、HealthKitバイタル同期、服薬管理が完全無料・制限なしでご利用いただけます。\n\nGoogle Gemini APIキーをお持ちの場合、キーを登録することで写真からの食事自動解析やAI相談などの追加サポート機能を活用できます。入力されたキーは端末のセキュア領域（Keychain）にのみ厳重に暗号化保存されます。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineSpacing(3)
        }
    }

    // MARK: - AI設定のロード＆セーブ
    private func loadAiSettings() {
        apiKeyInput = KeychainManager.shared.load(key: KeychainManager.geminiApiKeyIdentifier) ?? ""
        modelInput = KeychainManager.shared.load(key: KeychainManager.geminiModelIdentifier) ?? "gemini-flash-lite"
    }

    private func saveAiSettings() {
        let cleanKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = modelInput.trimmingCharacters(in: .whitespacesAndNewlines)

        KeychainManager.shared.save(key: KeychainManager.geminiApiKeyIdentifier, value: cleanKey)
        KeychainManager.shared.save(key: KeychainManager.geminiModelIdentifier, value: cleanModel.isEmpty ? "gemini-flash-lite" : cleanModel)

        saveSuccessAlert = true
    }

    // MARK: - 全データ初期化（退会・アカウント削除相当）
    private func performCompleteReset() {
        for item in allMeals { modelContext.delete(item) }
        for item in allProfiles { modelContext.delete(item) }
        for item in allMedications { modelContext.delete(item) }
        for item in allMessages { modelContext.delete(item) }
        for item in allAdvices { modelContext.delete(item) }

        try? modelContext.save()

        // KeychainのAPIキーも削除
        KeychainManager.shared.delete(key: KeychainManager.geminiApiKeyIdentifier)
        KeychainManager.shared.delete(key: KeychainManager.geminiModelIdentifier)
        apiKeyInput = ""
        modelInput = "gemini-flash-lite"

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
                    本アプリ（My Trainer / ヘルスノート）は、利用者の一般的な生活習慣の改善、健康維持および栄養管理をサポートすることを目的としたセルフケア・ツールであり、医療機器または医療提供サービスではありません。

                    1. 【医師法第17条（医業の禁止）に基づく免責】:
                    本アプリ内のAIアドバイザー、食事解析結果、およびその他のすべてのコンテンツは、医師、管理栄養士その他の医療専門家による医学的判断・診断・処方・指示の代替となるものではありません。病気の診断、治療法・処方の決定、治癒の判断は一切行いません。

                    2. 【医薬品医療機器等法（薬機法）に基づく表記】:
                    本アプリで提示される栄養素や食材、サプリメント等に関する情報は、公的な栄養データに基づく一般的な知見であり、特定の疾病の治療・予防や医薬品的な効能効果を保証・標榜するものではありません。

                    3. 【医療機関の受診勧奨】:
                    体調に異変や痛みを感じた場合、既存の疾患・持病をお持ちの場合、妊娠中または服薬中の方は、自己判断を行わず、必ず主治医や専門医療機関に直接ご相談ください。

                    4. 【自己責任による健康管理】:
                    本アプリで提示される栄養目標や推定値は一般的な成人向けの参考指標です。ご自身の体調に合わせて無理のない範囲でご活用ください。
                    """)
                    .font(.system(size: 13))
                    .lineSpacing(5)

                    Divider()
                        .padding(.vertical, 4)

                    // App Store Guideline 1.4.1 準拠：栄養基準・BMI算出根拠の公的出典および参照リンク
                    VStack(alignment: .leading, spacing: 10) {
                        Text("5. 【栄養指標・BMI計算式の公的出典（Guideline 1.4.1 準拠）】")
                            .font(.system(size: 14, weight: .bold))

                        Text("本アプリにおけるBMI計算式（体重kg ÷ [身長m]²、普通体重 18.5〜25.0未満）およびPFC栄養バランス・摂取カロリー目標の参考指標は、以下の公的機関が公開する一般的な健康・栄養統計基準に基づいています。")
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
                    }
                }
                .padding(20)
            }
            .navigationTitle("医療免責事項")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - プライバシーポリシーシート（サーバーレス設計 ＆ 第三者AI規約開示）
    private var privacyPolicyView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("プライバシーポリシー")
                        .font(.system(size: 18, weight: .bold))

                    Text("""
                    本アプリは、開発者インフラコスト0円・完全サーバーレスの設計思想を採用しており、利用者の個人情報とプライバシーを最大限に尊重します。

                    1. 開発者サーバーの不使用（Guideline 5.1.1 準拠）:
                    開発者側で管理・運用する外部データベースやWebサーバーは一切存在しません。お客様の食事記録、身体データ、チャット履歴が開発者のサーバーに収集・送信されることはありません。

                    2. データ保存と同期（Apple CloudKit）:
                    記録されたすべてのデータは、お客様自身の端末内およびお客様個人のiCloud（CloudKit Private Database）にのみ暗号化保存・端末間同期されます。開発者を含め第三者がこれらを閲覧することは不可能です。

                    3. 第三者AIサービス（Google Gemini API）の利用と規約:
                    お客様が任意で設定したGoogle Gemini APIキーは、端末のセキュア領域（iOS Keychain）に暗号化保存されます。
                    AI解析および相談機能を利用する際、解析対象のデータは端末からGoogleのAPIエンドポイントへ直接HTTPS暗号化通信で送信されます。
                    ※Google AI Studioの無料APIキー（Free Tier）をご利用の場合、Googleの利用規約（Gemini API Additional Terms）に基づき、送信されたプロンプトや画像がGoogleのAIモデル改善・学習に利用される場合があります。学習利用を希望されない場合は、Google Cloudの有料従量課金プロジェクトで発行されたキーをご利用いただくか、AI機能を使用せず手動記録機能をご利用ください。

                    4. ヘルスケアデータ（Apple HealthKit）:
                    Apple HealthKitから取得したバイタル情報は、アプリ内のダッシュボード表示にのみ使用され、外部への提供や広告等の目的で利用されることは一切ありません。
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
