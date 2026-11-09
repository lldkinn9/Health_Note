import SwiftUI
import SwiftData

/// 「アドバイザー」画面（単一AIアドバイザーとの1対1チャット、医療免責常時明記）
public struct AdvisorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AdvisorChatMessage.timestamp, order: .forward) private var messages: [AdvisorChatMessage]
    @Query private var profiles: [HealthProfile]
    @Query(sort: \Meal.timestamp, order: .forward) private var allMeals: [Meal]
    @Query(sort: \HealthCheckRecord.examDate, order: .reverse) private var healthChecks: [HealthCheckRecord]
    @Query(sort: \MedicationItem.orderIndex) private var medications: [MedicationItem]

    @State private var inputText: String = ""
    @State private var isSending: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showingAIConsentSheet: Bool = false
    @State private var pendingMessageAfterConsent: String? = nil
    @AppStorage(GeminiService.aiConsentUserDefaultsKey) private var hasConsentedToThirdPartyAI: Bool = false

    private var profile: HealthProfile? {
        profiles.first
    }

    private var todaysMeals: [Meal] {
        let calendar = Calendar.current
        return allMeals.filter { calendar.isDateInToday($0.timestamp) }
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. App Store Guideline 1.4/5.1.3 準拠の医療免責常時バナー
                disclaimerBanner

                // 2. メッセージ一覧
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            // 初回ウェルカムメッセージ（履歴が空の場合）
                            if messages.isEmpty {
                                welcomeCard
                            }

                            ForEach(messages) { msg in
                                chatBubble(for: msg)
                                    .id(msg.id)
                            }

                            if isSending {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("AIアドバイザーが回答を作成中...")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("loading_indicator")
                            }

                            Spacer().frame(height: 10)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: messages.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: isSending) { _, sending in
                        if sending {
                            withAnimation {
                                proxy.scrollTo("loading_indicator", anchor: .bottom)
                            }
                        }
                    }
                }

                // 3. クイック相談チップ
                quickSuggestionsView

                // 4. チャット入力エリア
                inputBar

                // 5. 下部常時固定バナー広告（案C）
                AdBottomBannerBar()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea(edges: .bottom))
            .navigationTitle("AIアドバイザー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: {
                            pendingMessageAfterConsent = nil
                            showingAIConsentSheet = true
                        }) {
                            Label("AIデータ送信内容・許可設定を確認", systemImage: "hand.raised.shield")
                        }
                        Button(role: .destructive, action: { clearHistory() }) {
                            Label("会話履歴をクリア", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showingAIConsentSheet) {
                ThirdPartyAIConsentSheet(
                    onAllow: {
                        if let pending = pendingMessageAfterConsent {
                            pendingMessageAfterConsent = nil
                            executeSendMessage(trimmed: pending)
                        }
                    },
                    onCancel: {
                        pendingMessageAfterConsent = nil
                    }
                )
            }
        }
    }

    // MARK: - 1. 医療免責・データ送信先開示バナー（医師法第17条・薬機法・Guideline 1.4/5.1.2(i)/5.1.3 準拠）
    private var disclaimerBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 12))
                    .padding(.top, 1)
                Text("【医師法・薬機法に基づく免責】AIアドバイザーは医師・医療機関ではありません。病気の診断・治療や医薬品的な効能効果の助言は行わず、日々の食習慣改善の参考情報をお届けします。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Image(systemName: hasConsentedToThirdPartyAI ? "checkmark.shield.fill" : "hand.raised.fill")
                    .foregroundColor(hasConsentedToThirdPartyAI ? AppTheme.emerald : .indigo)
                    .font(.system(size: 11))
                Text("送信先: Google LLC (Google Gemini API) ｜ 送信データ: 相談文・食事記録・カルテ/服薬・健診数値サマリ（氏名等除外）")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button(action: {
                    pendingMessageAfterConsent = nil
                    showingAIConsentSheet = true
                }) {
                    Text(hasConsentedToThirdPartyAI ? "詳細" : "許可設定")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.emerald)
                        .underline()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - 初回ウェルカムカード（キー未設定時も安心の任意ガイダンス）
    private var welcomeCard: some View {
        let hasApiKey = GeminiService.shared.getApiKey() != nil

        return VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.emeraldLight)
                    .frame(width: 50, height: 50)
                Image(systemName: "sparkles")
                    .font(.system(size: 24))
                    .foregroundColor(AppTheme.emerald)
            }

            Text("専属AIアドバイザー（任意機能）")
                .font(.system(size: 16, weight: .bold))

            if hasApiKey {
                Text("マイカルテの身体・生活習慣データ、服薬/サプリメント名、直近の健診検査数値サマリ（氏名・医療機関名等は除外）、本日の食事記録および相談メッセージを Google LLC（Google Gemini API）へ暗号化送信し、あなたに合った食生活のヒントをアドバイスします。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                if !hasConsentedToThirdPartyAI {
                    Button(action: {
                        pendingMessageAfterConsent = nil
                        showingAIConsentSheet = true
                    }) {
                        Label("送信データ・送信先を確認してデータ送信を許可する", systemImage: "hand.raised.shield.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(AppTheme.emerald)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 4)
                }
            } else {
                Text("本機能は、Gemini APIキーをお持ちの方向けのオプショナル拡張機能です。\nキーをお持ちでない場合でも、他のすべての食事記録、カロリー計算、PFCバランス分析は完全無料で100%ご利用いただけます。\n\nご利用時は「設定」画面からキーを登録のうえ、Google LLC（Google Gemini API）へのデータ送信（相談文・食事記録・カルテ・健診数値サマリ）に事前同意いただくことで有効化されます。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .padding(20)
        .appCard()
        .padding(.top, 10)
    }

    // MARK: - 吹き出し
    @ViewBuilder
    private func chatBubble(for message: AdvisorChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isUser {
                Spacer(minLength: 40)
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppTheme.emerald)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ZStack {
                    Circle()
                        .fill(AppTheme.emerald.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.emerald)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(message.content)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)

                    if message.isError {
                        Text("通信状況または設定をご確認ください。")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                }

                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - 3. クイック相談チップ
    private var quickSuggestionsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickChip(text: "今日の食事バランスを教えて")
                quickChip(text: "タンパク質を増やすには何を食べればいい？")
                quickChip(text: "夜遅くに食べても良い低カロリー間食は？")
                quickChip(text: "減塩を無理なく続けるコツは？")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func quickChip(text: String) -> some View {
        Button(action: {
            inputText = text
            sendMessage()
        }) {
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: - 4. チャット入力エリア
    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                TextField("AIアドバイザーに相談（食事・運動等）...", text: $inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                Button(action: { sendMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isSending ? .secondary.opacity(0.4) : AppTheme.emerald)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
        }
    }

    // MARK: - チャット送信処理（Guideline 5.1.2(i) 事前許可確認付き）
    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // APIキー設定済みだが第三者AIへのデータ送信にまだ同意していない場合は、送信前に必ず明示的許可モーダルを表示
        if GeminiService.shared.getApiKey() != nil && !hasConsentedToThirdPartyAI {
            inputText = ""
            pendingMessageAfterConsent = trimmed
            showingAIConsentSheet = true
            return
        }

        inputText = ""
        executeSendMessage(trimmed: trimmed)
    }

    private func executeSendMessage(trimmed: String) {
        let userMsg = AdvisorChatMessage(role: .user, content: trimmed)
        modelContext.insert(userMsg)
        try? modelContext.save()

        isSending = true

        Task {
            do {
                let reply = try await GeminiService.shared.chatWithAdvisor(
                    messages: messages + [userMsg],
                    profile: profile,
                    todaysMeals: todaysMeals,
                    latestHealthCheck: healthChecks.first,
                    medications: medications
                )

                await MainActor.run {
                    let aiMsg = AdvisorChatMessage(role: .assistant, content: reply)
                    modelContext.insert(aiMsg)
                    try? modelContext.save()
                    isSending = false
                }
            } catch GeminiError.missingApiKey {
                await MainActor.run {
                    let infoMsg = AdvisorChatMessage(
                        role: .assistant,
                        content: "本機能はAPIキーをお持ちの場合に、設定画面でキーを設定することで使用できる任意の機能です。",
                        isError: false
                    )
                    modelContext.insert(infoMsg)
                    try? modelContext.save()
                    isSending = false
                }
            } catch GeminiError.consentRequired {
                await MainActor.run {
                    isSending = false
                    showingAIConsentSheet = true
                }
            } catch {
                await MainActor.run {
                    let errorMsg = AdvisorChatMessage(
                        role: .assistant,
                        content: "申し訳ありません。回答の生成に失敗しました: \(error.localizedDescription)",
                        isError: true
                    )
                    modelContext.insert(errorMsg)
                    try? modelContext.save()
                    isSending = false
                }
            }
        }
    }

    private func clearHistory() {
        for msg in messages {
            modelContext.delete(msg)
        }
        try? modelContext.save()
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastId = messages.last?.id {
            withAnimation {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}
