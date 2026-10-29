import Foundation
import Combine
import SwiftData
import UIKit

public enum GeminiError: LocalizedError {
    case missingApiKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case allModelsFailed(lastError: String)
    case parsingFailed
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "本機能はAPIキーをお持ちの場合に、設定画面でキーを設定することで使用できる任意の機能です。"
        case .invalidResponse:
            return "Gemini APIからの応答が不正です。通信状態を確認してください。"
        case .apiError(let code, let message):
            return "Gemini APIエラー (\(code)): \(message)"
        case .allModelsFailed(let lastError):
            return "すべての利用可能モデルでリクエストが失敗しました。しばらく待ってから再試行してください。（詳細: \(lastError)）"
        case .parsingFailed:
            return "解析結果のパースに失敗しました。"
        case .emptyResult:
            return "解析結果が得られませんでした。"
        }
    }
}

// MARK: - Analysis & Diagnostic Result DTOs
public struct MealAnalysisResult: Codable {
    public let name: String
    public let calories: Double
    public let protein: Double
    public let fat: Double
    public let carbs: Double
    public let advice: String

    public init(name: String, calories: Double, protein: Double, fat: Double, carbs: Double, advice: String) {
        self.name = name
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.advice = advice
    }
}

public struct DailyEvaluationResult: Codable {
    public let score: Int
    public let summary: String
    public let goodPoints: String
    public let improvementPoints: String

    public init(score: Int, summary: String, goodPoints: String, improvementPoints: String) {
        self.score = score
        self.summary = summary
        self.goodPoints = goodPoints
        self.improvementPoints = improvementPoints
    }
}

/// モデル診断・疎通テスト結果
public struct GeminiDiagnosticResult {
    public let isSuccess: Bool
    public let activeModel: String
    public let availableModels: [String]
    public let message: String
}

/// 任意の追加検査項目DTO
public struct ExtraLabItemDTO: Codable {
    public let name: String?
    public let value: String?
    public let unit: String?
    public let reference: String?
}

/// 健診・検査結果シートAI読取結果DTO（個人識別情報を除外した全検査項目）
public struct HealthCheckAnalysisResult: Codable {
    public let examDate: String?          // YYYY-MM-DD
    public let facilityName: String?
    // 身体・視力・血圧・脈拍
    public let heightCm: Double?
    public let weightKg: Double?
    public let bodyFatPercent: Double?
    public let waistCm: Double?
    public let visionRight: Double?
    public let visionLeft: Double?
    public let systolicBP: Int?
    public let diastolicBP: Int?
    public let pulseRate: Int?
    // 血算・貧血
    public let wbc: Int?
    public let rbc: Double?
    public let hemoglobin: Double?
    public let hematocrit: Double?
    public let platelets: Double?
    // 脂質
    public let totalCholesterol: Int?
    public let ldlCholesterol: Int?
    public let hdlCholesterol: Int?
    public let nonHdlCholesterol: Int?
    public let triglycerides: Int?
    // 肝機能・蛋白・膵
    public let ast: Int?
    public let alt: Int?
    public let gammaGTP: Int?
    public let alp: Int?
    public let ldh: Int?
    public let totalBilirubin: Double?
    public let totalProtein: Double?
    public let albumin: Double?
    public let amylase: Int?
    // 糖代謝・尿酸
    public let fastingGlucose: Int?
    public let hba1c: Double?
    public let uricAcid: Double?
    // 腎機能・電解質・炎症・鉄
    public let bun: Double?
    public let creatinine: Double?
    public let egfr: Double?
    public let crp: Double?
    public let sodium: Double?
    public let potassium: Double?
    public let chloride: Double?
    public let serumIron: Int?
    // 尿・所見
    public let urineProtein: String?
    public let urineGlucose: String?
    public let urineOccultBlood: String?
    public let hearingFinding: String?
    public let ecgFinding: String?
    public let chestXrayFinding: String?
    // 標準フィールド以外のすべての血液・尿・特殊検査項目
    public let extraItems: [ExtraLabItemDTO]?
    public let memo: String?
}

/// 医療費領収書・診療明細書・調剤明細書AI読取結果DTO（個人識別情報を除外した支払・明細情報）
public struct MedicalExpenseAnalysisResult: Codable {
    public let paymentDate: String?      // YYYY-MM-DD（診療日・調剤日・領収日）
    public let facilityName: String?
    public let category: String?
    public let amountYen: Int?
    public let statementDetails: String? // 診療明細・処方/調剤明細の具体的内容
    public let memo: String?
}

/// Google Gemini API連携サービス
/// - 特定世代モデルのハードコード禁止・環境変数＆最新公式エイリアス動的解決
/// - メイン ➔ サブ ➔ models.list 動的選定による多重自動フェールオーバー（404 / 429 / 500 / 503 自動切替）
/// - AQ... 形式を含む最新APIキー仕様の安全なサニタイズ＆ヘッダー送信対応
public final class GeminiService {
    public static let shared = GeminiService()

    /// models.list から動的に取得した有効モデルのキャッシュ
    private var cachedDynamicModels: [String] = []
    /// 直近で 200 OK 疎通に成功した優先モデルキャッシュ
    private var lastVerifiedModel: String? = nil

    private init() {}

    // MARK: - 1. モデル選定 ＆ 環境変数による動的解決

    /// メインモデル（環境変数 GEMINI_MODEL || Google公式最新自動アップデートエイリアス）
    public func resolveMainModel() -> String {
        if let envModel = ProcessInfo.processInfo.environment["GEMINI_MODEL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envModel.isEmpty {
            return sanitizeModelName(envModel)
        }
        return "gemini-flash-lite-latest"
    }

    /// サブバックアップモデル（環境変数 GEMINI_BACKUP_MODEL || Google公式最新Flashエイリアス）
    public func resolveBackupModel() -> String {
        if let envBackup = ProcessInfo.processInfo.environment["GEMINI_BACKUP_MODEL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envBackup.isEmpty {
            return sanitizeModelName(envBackup)
        }
        return "gemini-flash-latest"
    }

    /// 優先モデル候補チェーンを構築（メイン ➔ サブ ➔ キャッシュ済み動的モデル）
    public func buildInitialCandidateChain() -> [String] {
        var chain: [String] = []
        if let verified = lastVerifiedModel {
            chain.append(verified)
        }
        let main = resolveMainModel()
        if !chain.contains(main) { chain.append(main) }

        let backup = resolveBackupModel()
        if !chain.contains(backup) { chain.append(backup) }

        for dynamicModel in cachedDynamicModels {
            if !chain.contains(dynamicModel) {
                chain.append(dynamicModel)
            }
        }
        return chain
    }

    private func sanitizeModelName(_ raw: String) -> String {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("models/") {
            clean = String(clean.dropFirst("models/".count))
        }
        return clean
    }

    // MARK: - 2. 最新 API キー仕様 (AQ... / AIza... 形式) の安全な取得・サニタイズ

    /// KeychainからAPIキーを取得し、空白・改行・引用符・制御文字を安全に除去して返す
    public func getApiKey() -> String? {
        guard let rawKey = KeychainManager.shared.load(key: KeychainManager.geminiApiKeyIdentifier) else {
            return nil
        }
        let sanitized = sanitizeApiKey(rawKey)
        return sanitized.isEmpty ? nil : sanitized
    }

    /// AQ... 形式やコピペ時の不可視文字・クォートを含むキー文字列を安全に正規化
    public func sanitizeApiKey(_ rawKey: String) -> String {
        var clean = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        // 制御文字やゼロ幅スペース等を除去し、印字可能ASCII文字のみ保持
        clean = clean.unicodeScalars.filter { scalar in
            scalar.isASCII && scalar.value >= 0x21 && scalar.value <= 0x7E
        }.map { String($0) }.joined()
        return clean
    }

    // MARK: - 3. 利用可能モデル一覧の動的チェック (models.list エンドポイント)

    /// `https://generativelanguage.googleapis.com/v1beta/models` から現在そのAPIキーで `generateContent` 可能なモデル一覧を動的取得
    public func fetchAvailableModels(apiKey: String? = nil) async throws -> [String] {
        guard let key = (apiKey != nil ? sanitizeApiKey(apiKey!) : getApiKey()), !key.isEmpty else {
            throw GeminiError.missingApiKey
        }

        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")
        components?.queryItems = [URLQueryItem(name: "key", value: key)]
        guard let url = components?.url else {
            throw GeminiError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = extractApiErrorMessage(from: data, statusCode: httpResponse.statusCode)
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorMsg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw GeminiError.parsingFailed
        }

        var validModels: [String] = []
        for modelDict in models {
            guard let rawName = modelDict["name"] as? String else { continue }
            let methods = modelDict["supportedGenerationMethods"] as? [String] ?? []
            guard methods.contains("generateContent") else { continue }

            let name = sanitizeModelName(rawName)
            let lower = name.lowercased()

            // テキスト/マルチモーダル生成に適さない特殊用途モデル（embedding, imagen, veo, tts, audio, aqa, bisheng等）を除外
            let excludedKeywords = ["embedding", "imagen", "veo", "aqa", "tts", "audio", "learnlm", "robotics", "thinking"]
            if excludedKeywords.contains(where: { lower.contains($0) }) {
                continue
            }
            if lower.hasPrefix("gemini-") {
                validModels.append(name)
            }
        }

        // 優先度ソート: flash-lite系 ➔ flash系 ➔ pro系 の順で優先配置
        let sorted = validModels.sorted { a, b in
            let scoreA = Self.modelPriorityScore(a)
            let scoreB = Self.modelPriorityScore(b)
            if scoreA != scoreB { return scoreA < scoreB }
            return a > b
        }

        if !sorted.isEmpty {
            self.cachedDynamicModels = sorted
        }
        return sorted
    }

    private static func modelPriorityScore(_ name: String) -> Int {
        let lower = name.lowercased()
        if lower.contains("flash-lite-latest") { return 0 }
        if lower.contains("flash-lite") { return 1 }
        if lower.contains("flash-latest") { return 2 }
        if lower.contains("flash") { return 3 }
        if lower.contains("pro-latest") { return 4 }
        if lower.contains("pro") { return 5 }
        return 6
    }

    /// 設定画面用：APIキーの疎通テスト＆利用可能モデル診断
    public func diagnoseModels(overrideApiKey: String? = nil) async -> GeminiDiagnosticResult {
        let resolvedKey: String?
        if let override = overrideApiKey, !sanitizeApiKey(override).isEmpty {
            resolvedKey = sanitizeApiKey(override)
        } else {
            resolvedKey = getApiKey()
        }

        guard let apiKey = resolvedKey else {
            return GeminiDiagnosticResult(
                isSuccess: false,
                activeModel: "-",
                availableModels: [],
                message: "本機能はAPIキーをお持ちの場合に、設定画面でキーを設定することで使用できる任意の機能です。"
            )
        }

        do {
            // 1. models.list エンドポイントから利用可能モデル一覧を動的取得
            let available = try await fetchAvailableModels(apiKey: apiKey)

            // 2. 多重フェールオーバーチェーンで実疎通（200 OK）を確認
            let testBody: [String: Any] = [
                "contents": [
                    ["parts": [["text": "Respond with OK"]]]
                ],
                "generationConfig": [
                    "maxOutputTokens": 8
                ]
            ]

            let (_, activeModel) = try await executeWithFailover(apiKey: apiKey, requestBody: testBody)

            return GeminiDiagnosticResult(
                isSuccess: true,
                activeModel: activeModel,
                availableModels: available,
                message: "疎通成功 (200 OK)・有効モデル \(available.count) 件を確認しました。"
            )
        } catch {
            return GeminiDiagnosticResult(
                isSuccess: false,
                activeModel: "-",
                availableModels: [],
                message: "疎通テストに失敗しました: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - 4. 多重モデル自動フォールバック（フェールオーバー）実行エンジン

    /// 優先モデルチェーン（メイン ➔ サブ ➔ models.list動的選定）を順番に試行し、
    /// HTTP 404 / 429 (RESOURCE_EXHAUSTED) / 500 / 503 発生時は裏で自動的に次モデルへ切り替えて成功結果を返す
    private func executeWithFailover(
        apiKey: String,
        requestBody: [String: Any]
    ) async throws -> (Data, String) {
        var candidates = buildInitialCandidateChain()
        var triedModels = Set<String>()
        var didFetchDynamicList = false
        var lastErrorDescription = "不明なエラー"

        var index = 0
        while index < candidates.count {
            let model = candidates[index]
            index += 1

            if triedModels.contains(model) { continue }
            triedModels.insert(model)

            do {
                let responseData = try await sendGenerateContentRequest(
                    model: model,
                    apiKey: apiKey,
                    body: requestBody
                )
                // 成功したモデルをキャッシュ
                self.lastVerifiedModel = model
                return (responseData, model)
            } catch let GeminiError.apiError(statusCode, message) {
                lastErrorDescription = "[\(model)] HTTP \(statusCode): \(message)"

                // フェールオーバー対象エラーの判定（404: 廃止/未存在, 429: クォータ上限, 500/503: サーバー過負荷, 400: 対象モデル非対応）
                let shouldFailover = (statusCode == 404)
                    || (statusCode == 429)
                    || (statusCode == 500)
                    || (statusCode == 503)
                    || message.uppercased().contains("RESOURCE_EXHAUSTED")
                    || message.uppercased().contains("NOT_FOUND")
                    || message.uppercased().contains("UNAVAILABLE")

                if shouldFailover {
                    if self.lastVerifiedModel == model {
                        self.lastVerifiedModel = nil
                    }
                    // まだ models.list を動的取得していない場合は、予備モデル一覧を即時取得してチェーン末尾に追加
                    if !didFetchDynamicList {
                        didFetchDynamicList = true
                        if let dynamicList = try? await fetchAvailableModels(apiKey: apiKey) {
                            for dynModel in dynamicList where !triedModels.contains(dynModel) && !candidates.contains(dynModel) {
                                candidates.append(dynModel)
                            }
                        }
                    }
                    // エラーを呼び出し側に返さず、即座に次のモデルへ自動フォールバック
                    continue
                } else {
                    // 認証エラー（401 / 403 API_KEY_INVALID 等）はモデルを変えても失敗するため即座に通知
                    throw GeminiError.apiError(statusCode: statusCode, message: message)
                }
            } catch {
                lastErrorDescription = error.localizedDescription
                continue
            }
        }

        throw GeminiError.allModelsFailed(lastError: lastErrorDescription)
    }

    // MARK: - 5. 食事写真のマルチモーダル解析
    public func analyzeMealPhoto(imageData: Data) async throws -> MealAnalysisResult {
        guard let apiKey = getApiKey() else {
            throw GeminiError.missingApiKey
        }

        let optimizedData = optimizeImageData(imageData)
        let base64String = optimizedData.base64EncodedString()

        let prompt = """
        あなたは熟練した管理栄養士です。添付された食事の写真を視覚的に詳細に分析し、以下のJSON形式でのみ出力してください。

        【厳格な法的遵守事項（医師法・薬機法・App Store Guideline 1.4/5.1.3）】
        - 医療行為、診断、治療、疾病の予防を目的とした表現は一切行わないでください。
        - 特定の食材や栄養素について、医薬品的な効能効果（例: 「血圧を下げる」「血糖値を治す」「がんを防ぐ」等）を断定する表現を厳禁とします。
        - あくまで日常の健康維持・栄養バランス向上のための「一般的な推定参考値」および「食生活のワンポイントヒント」として出力してください。

        出力スキーマ（JSONのみ、Markdownのバッククォート不要）:
        {
          "name": "料理名（例: 鶏胸肉とブロッコリーの定食）",
          "calories": 620.0,
          "protein": 38.5,
          "fat": 12.0,
          "carbs": 75.0,
          "advice": "高タンパクでバランスの良い組み合わせです。緑黄色野菜も豊富に含まれています。"
        }
        """

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64String
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "response_mime_type": "application/json"
            ]
        ]

        let (responseData, _) = try await executeWithFailover(apiKey: apiKey, requestBody: requestBody)
        let jsonText = try extractText(from: responseData)

        guard let cleanData = cleanJsonString(jsonText).data(using: .utf8) else {
            throw GeminiError.parsingFailed
        }

        return try JSONDecoder().decode(MealAnalysisResult.self, from: cleanData)
    }

    // MARK: - 6. AIアドバイザーチャット
    public func chatWithAdvisor(
        messages: [AdvisorChatMessage],
        profile: HealthProfile?,
        todaysMeals: [Meal],
        latestHealthCheck: HealthCheckRecord? = nil,
        medications: [MedicationItem] = []
    ) async throws -> String {
        guard let apiKey = getApiKey() else {
            throw GeminiError.missingApiKey
        }

        var systemInstruction = """
        あなたはユーザー専属の親切でポジティブなパーソナルヘルスケア・栄養生活アドバイザーです。

        【最重要：医師法・薬機法・医療免責の厳格遵守義務】
        1. 【医師法第17条（医業の独占）の遵守】:
           - あなたは医師や医療従事者ではありません。病気の診断、治療法・処方の指示、病気の治癒に関する判断は一切行ってはなりません。
           - 「〜の病気です」「〜の疾患の疑いがあります」といった診断的表現、および「この薬を飲んでください」「薬を増減・中止してください」等の投薬指示は絶対禁止です。
        2. 【医薬品医療機器等法（薬機法）の遵守】:
           - 特定の食品・サプリメント・食材に対し、医薬品的な効能効果（例: 「高血圧が治る」「血糖値が下がる」「脂肪を溶かす」「病気を予防する」等）を断定・標榜してはなりません。
           - 栄養成分の一般的な知見（例: 「ビタミンCは抗酸化作用が知られています」「筋肉の維持にはタンパク質の摂取が推奨されます」等）として言及してください。
           - 登録されている服薬・サプリメント情報は、栄養素の重複把握や一般的な食品との食べ合わせ上の留意点（例: 一般論としての食品との相性への配慮と、主治医・薬剤師への確認促し）の参考としてのみ活用してください。
        3. 【セーフティガードレール】:
           - ユーザーが激しい痛み、持病の悪化、体調不良、妊娠・服薬中の懸念や飲み合わせの疑問を訴えた場合は、いかなる場合でも「必ず主治医や薬剤師、専門医療機関にご相談ください」と案内してください。
        4. 【回答スタイル】:
           - 日常生活における健康的な食事の選び方や運動習慣づくりを応援する、温かく親切な日本語で回答してください。
        """

        if let profile = profile {
            systemInstruction += "\n\n【ユーザーのカルテ参考情報】\n\(profile.aiContextSummary)"
        }

        let validMedications = medications.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !validMedications.isEmpty {
            let prescriptionLines = validMedications
                .filter { $0.kind == .medication }
                .map { item -> String in
                    let timingsText = item.selectedTimings.map { timing in
                        let status = item.isTakenToday(for: timing) ? "済" : "未"
                        return "\(timing.rawValue)(\(status))"
                    }.joined(separator: "・")
                    return "- [処方薬・市販薬] \(item.cleanName) / 1回量: \(item.formattedDosage) / タイミング(本日状況): \(timingsText)"
                }

            let supplementLines = validMedications
                .filter { $0.kind == .supplement }
                .map { item -> String in
                    let timingsText = item.selectedTimings.map { timing in
                        let status = item.isTakenToday(for: timing) ? "済" : "未"
                        return "\(timing.rawValue)(\(status))"
                    }.joined(separator: "・")
                    return "- [サプリメント] \(item.cleanName) / 1回量: \(item.formattedDosage) / タイミング(本日状況): \(timingsText)"
                }

            let allMedLines = (prescriptionLines + supplementLines).joined(separator: "\n")
            if !allMedLines.isEmpty {
                systemInstruction += "\n\n【登録中の服薬・サプリメント状況（投薬指示や中止指示は厳禁。栄養重複や一般的な食生活上の配慮の参考としてのみ参照）】\n\(allMedLines)"
            }
        }

        if let hc = latestHealthCheck {
            let labSummary = hc.aiLabSummary
            if !labSummary.isEmpty {
                systemInstruction += "\n\n【直近の健康診断記録（診断行為は行わず、一般的な食生活バランスの参考としてのみ参照）】\n\(labSummary)"
            }
        }

        if !todaysMeals.isEmpty {
            let mealList = todaysMeals.map { meal in
                "- \(meal.mealType.rawValue): \(meal.name) (\(Int(meal.calories))kcal, P:\(Int(meal.protein))g, F:\(Int(meal.fat))g, C:\(Int(meal.carbs))g)"
            }.joined(separator: "\n")
            systemInstruction += "\n\n【本日のこれまでの食事記録】\n\(mealList)"
        }

        var contents: [[String: Any]] = []
        let recentMessages = messages.suffix(10)
        for msg in recentMessages {
            let role = msg.isUser ? "user" : "model"
            contents.append([
                "role": role,
                "parts": [["text": msg.content]]
            ])
        }

        let requestBody: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemInstruction]]
            ],
            "contents": contents,
            "generationConfig": [
                "temperature": 0.7
            ]
        ]

        let (responseData, _) = try await executeWithFailover(apiKey: apiKey, requestBody: requestBody)
        return try extractText(from: responseData)
    }

    // MARK: - 7. 本日の食事総括・栄養バランス評価
    public func generateDailyEvaluation(meals: [Meal], profile: HealthProfile?) async throws -> DailyEvaluationResult {
        guard let apiKey = getApiKey() else {
            throw GeminiError.missingApiKey
        }

        let totalCal = meals.reduce(0) { $0 + $1.calories }
        let totalP = meals.reduce(0) { $0 + $1.protein }
        let totalF = meals.reduce(0) { $0 + $1.fat }
        let totalC = meals.reduce(0) { $0 + $1.carbs }

        let mealDetails = meals.map { "- \($0.mealType.rawValue): \($0.name) (\(Int($0.calories))kcal)" }.joined(separator: "\n")

        var profileContext = "一般的な成人"
        if let p = profile {
            profileContext = p.aiContextSummary
        }

        let prompt = """
        以下の本日の食事記録を分析し、1日の食事総括と栄養バランス評価をJSONのみで出力してください。

        【厳格な遵守事項（医師法・薬機法遵守）】
        - 医療行為、疾病の治療や診断、医薬品的な効能の標榜は一切行わないでください。
        - 固定の目標値は設けず、一般的な栄養学上のPFCバランス（タンパク質・脂質・炭水化物の比率や食事の組み合わせ）の観点から、日常の健康的な食習慣づくりの講評として出力してください。

        【身体プロフィール参考】: \(profileContext)
        【本日合計】: カロリー \(Int(totalCal))kcal, P: \(Int(totalP))g, F: \(Int(totalF))g, C: \(Int(totalC))g
        【食事内訳】:
        \(mealDetails)

        出力スキーマ（JSONのみ、Markdownバッククォート不要）:
        {
          "score": 85,
          "summary": "1日を通してタンパク質がしっかり確保され、バランスの良い食生活が実践できています。",
          "goodPoints": "昼食で良質なタンパク質を補給できており、栄養バランスが整っています。",
          "improvementPoints": "夕食の炭水化物が少し控えめだったため、明日の朝食に食物繊維豊富な主食をプラスするとさらに良いバランスになります。"
        }
        """

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [["text": prompt]]
                ]
            ],
            "generationConfig": [
                "temperature": 0.3,
                "response_mime_type": "application/json"
            ]
        ]

        let (responseData, _) = try await executeWithFailover(apiKey: apiKey, requestBody: requestBody)
        let jsonText = try extractText(from: responseData)

        guard let cleanData = cleanJsonString(jsonText).data(using: .utf8) else {
            throw GeminiError.parsingFailed
        }

        return try JSONDecoder().decode(DailyEvaluationResult.self, from: cleanData)
    }

    // MARK: - 8. 健康診断結果シートの画像AI自動読取（OCR補助・個人情報破棄・診断行為禁止）
    public func analyzeHealthCheckPhoto(imageData: Data) async throws -> HealthCheckAnalysisResult {
        guard let apiKey = getApiKey() else {
            throw GeminiError.missingApiKey
        }

        let optimizedData = optimizeImageData(imageData)
        let base64String = optimizedData.base64EncodedString()

        let prompt = """
        添付された健康診断・人間ドック・病院の血液検査/尿検査の結果表画像から、印字されているすべての検査数値・所見を読み取って以下のJSON形式のみで出力してください。

        【厳格なプライバシー保護・法令遵守ルール】
        - 受診者の氏名、住所、生年月日、保険者番号、被保険者記号・番号などの個人識別情報（PII）は絶対に抽出・出力しないでください。
        - 病気の診断や医学的判定コメントの作成は一切行わず、紙面に印字されている客観的な検査数値・定性結果のみを抽出してください。
        - 画像内に存在しない項目は推測せず必ず `null` にしてください。
        - 標準キーに含まれない検査項目（例: MCV, MCH, MCHC, フェリチン, TSH, FT3, FT4, CK/CPK, Ca, P, Mg, IgE, 腫瘍マーカー, 眼底, 便潜血 等）が紙面にある場合は、漏れなくすべて `extraItems` 配列に `{"name": "項目名", "value": "測定値", "unit": "単位", "reference": "記載基準値"}` として格納してください。
        - 白血球数(`wbc`)は `/μL` 単位の整数に揃えてください（例: 紙面が `52` (×10²/μL) や `5.2` (×10³/μL) の場合は `5200` に換算、すでに `5200` ならそのまま）。赤血球数(`rbc`)は `万/μL`（例: `465`）、血小板数(`platelets`)は `万/μL`（例: `24.5`）に揃えてください。
        - 和暦（令和6年=2024、令和7年=2025、令和8年=2026等）の受診日は西暦 `YYYY-MM-DD` 形式に変換してください。

        出力スキーマ（JSONのみ、Markdownのバッククォート不要）:
        {
          "examDate": "2026-05-15",
          "facilityName": "〇〇クリニック",
          "heightCm": 170.5,
          "weightKg": 64.2,
          "bodyFatPercent": 18.5,
          "waistCm": 78.0,
          "visionRight": 1.2,
          "visionLeft": 1.0,
          "systolicBP": 118,
          "diastolicBP": 74,
          "pulseRate": 68,
          "wbc": 5400,
          "rbc": 472.0,
          "hemoglobin": 14.6,
          "hematocrit": 43.8,
          "platelets": 23.5,
          "totalCholesterol": 192,
          "ldlCholesterol": 112,
          "hdlCholesterol": 62,
          "nonHdlCholesterol": 130,
          "triglycerides": 95,
          "ast": 21,
          "alt": 19,
          "gammaGTP": 28,
          "alp": 68,
          "ldh": 175,
          "totalBilirubin": 0.7,
          "totalProtein": 7.2,
          "albumin": 4.5,
          "amylase": 74,
          "fastingGlucose": 92,
          "hba1c": 5.4,
          "uricAcid": 5.8,
          "bun": 13.5,
          "creatinine": 0.82,
          "egfr": 78.5,
          "crp": 0.05,
          "sodium": 141.0,
          "potassium": 4.1,
          "chloride": 103.0,
          "serumIron": 98,
          "urineProtein": "(-)",
          "urineGlucose": "(-)",
          "urineOccultBlood": "(-)",
          "hearingFinding": "所見なし",
          "ecgFinding": "異常なし",
          "chestXrayFinding": "異常なし",
          "extraItems": [
            {"name": "フェリチン", "value": "85.2", "unit": "ng/mL", "reference": "30〜300"}
          ],
          "memo": null
        }
        """

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64String
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "response_mime_type": "application/json"
            ]
        ]

        let (responseData, _) = try await executeWithFailover(apiKey: apiKey, requestBody: requestBody)
        let jsonText = try extractText(from: responseData)

        guard let cleanData = cleanJsonString(jsonText).data(using: .utf8) else {
            throw GeminiError.parsingFailed
        }

        return try JSONDecoder().decode(HealthCheckAnalysisResult.self, from: cleanData)
    }

    // MARK: - 9. 医療費領収書・診療明細書・調剤明細書の画像AI自動読取（OCR補助・個人情報破棄）
    public func analyzeMedicalReceiptPhoto(imageData: Data) async throws -> MedicalExpenseAnalysisResult {
        guard let apiKey = getApiKey() else {
            throw GeminiError.missingApiKey
        }

        let optimizedData = optimizeImageData(imageData)
        let base64String = optimizedData.base64EncodedString()

        let prompt = """
        添付された病院・クリニック・歯科・調剤薬局の「領収書」「診療明細書」「調剤明細書（処方明細書・薬剤情報提供書）」またはレシート画像から、受診・調剤記録に必要な項目を読み取って以下のJSON形式のみで出力してください。

        【厳格なプライバシー保護・抽出ルール】
        - 患者氏名、住所、カルテ番号、保険証記号・番号などの個人識別情報（PII）は絶対に抽出・出力しないでください。
        - `paymentDate` には、書類に記載されている「診療日」「受診日」「調剤日」「処方日」「領収日」「発行日」のいずれかの日付を必ず西暦 `YYYY-MM-DD` 形式に変換して出力してください（例: 令和6年=2024、令和7年=2025、令和8年=2026、`R8.10.29` や `8年10月29日` は `"2026-10-29"`）。日付が全く記載されていない場合のみ `null` にしてください。
        - `amountYen` には、実際に窓口やレジで支払った「自己負担合計金額（領収金額・請求金額・負担額の税込整数円）」を入れてください（保険点数そのものではなく円単位の支払額。公費負担等で0円と記載されている場合は `0`、金額欄が存在しない明細書単体の場合は `null`）。
        - `category` は以下のいずれか最も近い1つを選んでください:
          "診療・通院", "処方薬・薬局", "歯科", "健診・人間ドック", "市販薬（対象医薬品）", "通院交通費", "その他医療費"
          （※調剤明細書・薬局領収書・処方薬の明細であれば `"処方薬・薬局"`、医科の診療明細書・病院領収書であれば `"診療・通院"` を選択）
        - `statementDetails` には、書類に印字されている「診療明細」または「処方・調剤明細」の具体的な項目・内訳を、見やすい箇条書き（改行 `\n` 区切り）で抽出してください：
          ・診療明細書・領収書の場合：算定されている診療区分・検査名・処置名・画像診断・投薬・点数や項目別の金額など（例: `"・初・再診料（再診料・外来管理加算）\n・検査（血液学的検査・生化学的検査I）\n・投薬（処方箋料）"`）
          ・調剤明細書・薬剤情報・薬局領収書の場合：調剤された薬品名・規格・用法用量・日数や調剤技術料・薬学管理料など（例: `"・チラーヂンS錠100μg 1回1錠 1日1回起床時（28日分）\n・調剤技術料 / 薬学管理料"`）
        - `memo` には診療科名（例: `"内科"`、`"皮膚科"`）などの短い補足があれば記載し、なければ `null` にしてください。

        出力スキーマ（JSONのみ、Markdownのバッククォート不要）:
        {
          "paymentDate": "2026-10-20",
          "facilityName": "〇〇クリニック",
          "category": "診療・通院",
          "amountYen": 2480,
          "statementDetails": "・初・再診料（再診料）\n・医学管理等\n・血液検査 / 尿検査\n・処方箋料",
          "memo": "内科受診"
        }
        """

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64String
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "response_mime_type": "application/json"
            ]
        ]

        let (responseData, _) = try await executeWithFailover(apiKey: apiKey, requestBody: requestBody)
        let jsonText = try extractText(from: responseData)

        guard let cleanData = cleanJsonString(jsonText).data(using: .utf8) else {
            throw GeminiError.parsingFailed
        }

        return try JSONDecoder().decode(MedicalExpenseAnalysisResult.self, from: cleanData)
    }

    // MARK: - Private HTTP & Parsing Helpers
    private func sendGenerateContentRequest(
        model: String,
        apiKey: String,
        body: [String: Any]
    ) async throws -> Data {
        let cleanModel = sanitizeModelName(model)
        guard let encodedModel = cleanModel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw GeminiError.invalidResponse
        }

        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent")
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = components?.url else {
            throw GeminiError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // AQ... 形式を含む最新APIキー仕様に確実に対応するよう HTTP ヘッダーにもセット
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = extractApiErrorMessage(from: data, statusCode: httpResponse.statusCode)
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorMsg)
        }

        return data
    }

    private func extractApiErrorMessage(from data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = json["error"] as? [String: Any] {
            let status = err["status"] as? String ?? ""
            let msg = err["message"] as? String ?? ""
            if !status.isEmpty {
                return "\(status) - \(msg)"
            }
            if !msg.isEmpty {
                return msg
            }
        }
        return String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
    }

    private func extractText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiError.emptyResult
        }
        return text
    }

    private func cleanJsonString(_ input: String) -> String {
        var clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```json") {
            clean = String(clean.dropFirst(7))
        } else if clean.hasPrefix("```") {
            clean = String(clean.dropFirst(3))
        }
        if clean.hasSuffix("```") {
            clean = String(clean.dropLast(3))
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func optimizeImageData(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let maxDimension: CGFloat = 1024
        let size = image.size

        if size.width <= maxDimension && size.height <= maxDimension {
            return image.jpegData(compressionQuality: 0.8) ?? data
        }

        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resizedImage.jpegData(compressionQuality: 0.8) ?? data
    }
}

// MARK: - 食事登録・編集・削除時のAI栄養評価 自動更新コーディネーター
@MainActor
public final class DailyEvaluationCoordinator: ObservableObject {
    public static let shared = DailyEvaluationCoordinator()

    @Published public private(set) var evaluatingDateKeys: Set<String> = []
    @Published public var errorMessageByDateKey: [String: String] = [:]

    private var activeTasks: [String: Task<Void, Never>] = [:]

    private init() {}

    public func isEvaluating(dateKey: String) -> Bool {
        evaluatingDateKeys.contains(dateKey)
    }

    public func errorMessage(for dateKey: String) -> String? {
        errorMessageByDateKey[dateKey]
    }

    /// 指定した日付の食事データをもとに「本日のAI食事総括・栄養評価」を裏側で自動更新する
    public func refreshEvaluation(
        for date: Date,
        context: ModelContext,
        showMissingKeyError: Bool = false
    ) {
        let dateKey = DailyAdvice.makeDateKey(for: date)

        // 同一日付の進行中リクエストがあればキャンセルし、最新の食事内容で再評価
        activeTasks[dateKey]?.cancel()

        let mealDescriptor = FetchDescriptor<Meal>(sortBy: [SortDescriptor(\Meal.timestamp, order: .forward)])
        let allMeals = (try? context.fetch(mealDescriptor)) ?? []
        let calendar = Calendar.current
        let targetMeals = allMeals.filter { calendar.isDate($0.timestamp, inSameDayAs: date) }

        let adviceDescriptor = FetchDescriptor<DailyAdvice>()
        let allAdvices = (try? context.fetch(adviceDescriptor)) ?? []
        let existingAdvice = allAdvices.first(where: { $0.dateKey == dateKey })

        // 該当日の食事が0件になった場合は古い評価キャッシュをクリア
        guard !targetMeals.isEmpty else {
            if let existingAdvice {
                context.delete(existingAdvice)
                try? context.save()
            }
            evaluatingDateKeys.remove(dateKey)
            errorMessageByDateKey[dateKey] = nil
            activeTasks[dateKey] = nil
            return
        }

        // APIキー未設定時は自動更新時は静かにスキップ（手動ボタン押下時のみ案内を表示）
        guard GeminiService.shared.getApiKey() != nil else {
            evaluatingDateKeys.remove(dateKey)
            if showMissingKeyError {
                errorMessageByDateKey[dateKey] = GeminiError.missingApiKey.localizedDescription
            }
            return
        }

        let profileDescriptor = FetchDescriptor<HealthProfile>()
        let profile = (try? context.fetch(profileDescriptor))?.first

        evaluatingDateKeys.insert(dateKey)
        errorMessageByDateKey[dateKey] = nil

        let task = Task { @MainActor [weak self] in
            do {
                let result = try await GeminiService.shared.generateDailyEvaluation(
                    meals: targetMeals,
                    profile: profile
                )
                guard !Task.isCancelled else { return }

                let refreshedAdvices = (try? context.fetch(FetchDescriptor<DailyAdvice>())) ?? []
                if let current = refreshedAdvices.first(where: { $0.dateKey == dateKey }) {
                    current.score = result.score
                    current.adviceText = result.summary
                    current.goodPoints = result.goodPoints
                    current.improvementPoints = result.improvementPoints
                    current.generatedAt = Date()
                } else {
                    let newAdvice = DailyAdvice(
                        dateKey: dateKey,
                        adviceText: result.summary,
                        score: result.score,
                        goodPoints: result.goodPoints,
                        improvementPoints: result.improvementPoints
                    )
                    context.insert(newAdvice)
                }
                try? context.save()

                self?.evaluatingDateKeys.remove(dateKey)
                self?.activeTasks[dateKey] = nil
            } catch {
                guard !Task.isCancelled else { return }
                if !(error is CancellationError) {
                    self?.errorMessageByDateKey[dateKey] = error.localizedDescription
                }
                self?.evaluatingDateKeys.remove(dateKey)
                self?.activeTasks[dateKey] = nil
            }
        }

        activeTasks[dateKey] = task
    }
}
