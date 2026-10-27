import Foundation
import UIKit

public enum GeminiError: LocalizedError {
    case missingApiKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parsingFailed
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Google Gemini APIキーが設定されていません。「設定」画面からAPIキーを登録してください。"
        case .invalidResponse:
            return "Gemini APIからの応答が不正です。通信状態を確認してください。"
        case .apiError(let code, let message):
            return "Gemini APIエラー (\(code)): \(message)"
        case .parsingFailed:
            return "解析結果のパースに失敗しました。"
        case .emptyResult:
            return "解析結果が得られませんでした。"
        }
    }
}

// MARK: - Analysis Result DTOs
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

/// Google Gemini API連携サービス（BYOK方式、特定バージョン非固定・最新エイリアス動的解決）
public final class GeminiService {
    public static let shared = GeminiService()

    private init() {}

    /// モデル名の動的解決（環境変数 > ユーザー設定 > 最新エイリアス "gemini-flash"）
    public func resolveModel() -> String {
        // 1. 環境変数からの取得
        if let envModel = ProcessInfo.processInfo.environment["GEMINI_MODEL"], !envModel.isEmpty {
            return envModel
        }
        // 2. ユーザー設定（Keychain）からの取得
        if let userModel = KeychainManager.shared.load(key: KeychainManager.geminiModelIdentifier), !userModel.isEmpty {
            return userModel
        }
        // 3. Google 公式最新エイリアス / ライトモデル（特定バージョン番号をハードコードしない）
        return "gemini-flash-lite"
    }

    /// 現在設定されているAPIキーを取得（Keychainから解決）
    public func getApiKey() -> String? {
        if let key = KeychainManager.shared.load(key: KeychainManager.geminiApiKeyIdentifier), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    // MARK: - 1. 食事写真のマルチモーダル解析
    public func analyzeMealPhoto(imageData: Data) async throws -> MealAnalysisResult {
        guard let apiKey = getApiKey() else {
            throw GeminiError.missingApiKey
        }

        let model = resolveModel()
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidResponse
        }

        // 画像リサイズ圧縮（最大1024pxに縮小して転送量を最適化）
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

        let responseData = try await sendRequest(url: url, body: requestBody)
        let jsonText = try extractText(from: responseData)

        guard let cleanData = cleanJsonString(jsonText).data(using: .utf8) else {
            throw GeminiError.parsingFailed
        }

        return try JSONDecoder().decode(MealAnalysisResult.self, from: cleanData)
    }

    // MARK: - 2. AIアドバイザーチャット
    public func chatWithAdvisor(
        messages: [AdvisorChatMessage],
        profile: HealthProfile?,
        todaysMeals: [Meal]
    ) async throws -> String {
        guard let apiKey = getApiKey() else {
            throw GeminiError.missingApiKey
        }

        let model = resolveModel()
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidResponse
        }

        // プロンプト構築（医師法・薬機法・App Store医療免責を厳格に指示）
        var systemInstruction = """
        あなたはユーザー専属の親切でポジティブなパーソナルヘルスケア・栄養生活アドバイザーです。

        【最重要：医師法・薬機法・医療免責の厳格遵守義務】
        1. 【医師法第17条（医業の独占）の遵守】:
           - あなたは医師や医療従事者ではありません。病気の診断、治療法・処方の指示、病気の治癒に関する判断は一切行ってはなりません。
           - 「〜の病気です」「〜の疾患の疑いがあります」といった診断的表現、および「この薬を飲んでください」「薬を中止してください」等の投薬指示は絶対禁止です。
        2. 【医薬品医療機器等法（薬機法）の遵守】:
           - 特定の食品・サプリメント・食材に対し、医薬品的な効能効果（例: 「高血圧が治る」「血糖値が下がる」「脂肪を溶かす」「病気を予防する」等）を断定・標榜してはなりません。
           - 栄養成分の一般的な知見（例: 「ビタミンCは抗酸化作用が知られています」「筋肉の維持にはタンパク質の摂取が推奨されます」等）として言及してください。
        3. 【セーフティガードレール】:
           - ユーザーが激しい痛み、持病の悪化、体調不良、妊娠・服薬中の懸念を訴えた場合は、いかなる場合でも「直ちに医師や専門医療機関にご相談ください」と受診勧奨を行ってください。
        4. 【回答スタイル】:
           - 日常生活における健康的な食事の選び方や運動習慣づくりを応援する、温かく親切な日本語で回答してください。
        """

        if let profile = profile {
            systemInstruction += "\n\n【ユーザーのカルテ参考情報】\n\(profile.aiContextSummary)"
        }

        if !todaysMeals.isEmpty {
            let mealList = todaysMeals.map { meal in
                "- \(meal.mealType.rawValue): \(meal.name) (\(Int(meal.calories))kcal, P:\(Int(meal.protein))g, F:\(Int(meal.fat))g, C:\(Int(meal.carbs))g)"
            }.joined(separator: "\n")
            systemInstruction += "\n\n【本日のこれまでの食事記録】\n\(mealList)"
        }

        var contents: [[String: Any]] = []

        // 過去のチャット履歴（直近10件）
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

        let responseData = try await sendRequest(url: url, body: requestBody)
        return try extractText(from: responseData)
    }

    // MARK: - 3. 本日の食事総括・栄養バランス評価
    public func generateDailyEvaluation(meals: [Meal], profile: HealthProfile?) async throws -> DailyEvaluationResult {
        guard let apiKey = getApiKey() else {
            throw GeminiError.missingApiKey
        }

        let model = resolveModel()
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidResponse
        }

        let totalCal = meals.reduce(0) { $0 + $1.calories }
        let totalP = meals.reduce(0) { $0 + $1.protein }
        let totalF = meals.reduce(0) { $0 + $1.fat }
        let totalC = meals.reduce(0) { $0 + $1.carbs }

        let mealDetails = meals.map { "- \($0.mealType.rawValue): \($0.name) (\(Int($0.calories))kcal)" }.joined(separator: "\n")

        var targetText = "目標カロリー: 2000kcal"
        if let p = profile {
            targetText = "目標カロリー: \(Int(p.targetCalories))kcal (P:\(Int(p.targetProtein))g, F:\(Int(p.targetFat))g, C:\(Int(p.targetCarbs))g)"
        }

        let prompt = """
        以下の本日の食事記録を分析し、1日の食事総括と栄養バランス評価をJSONのみで出力してください。

        【厳格な遵守事項（医師法・薬機法遵守）】
        - 医療行為、疾病の治療や診断、医薬品的な効能の標榜は一切行わないでください。
        - 毎日の健康的な食習慣づくりのための、栄養学的な観点からの一般的なバランス講評として出力してください。

        【目標値】: \(targetText)
        【本日合計】: カロリー \(Int(totalCal))kcal, P: \(Int(totalP))g, F: \(Int(totalF))g, C: \(Int(totalC))g
        【食事内訳】:
        \(mealDetails)

        出力スキーマ（JSONのみ、Markdownバッククォート不要）:
        {
          "score": 85,
          "summary": "1日を通してタンパク質がしっかり確保され、バランスの良い食生活が実践できています。",
          "goodPoints": "昼食で良質なタンパク質を補給できており、目標達成に向けて順調です。",
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

        let responseData = try await sendRequest(url: url, body: requestBody)
        let jsonText = try extractText(from: responseData)

        guard let cleanData = cleanJsonString(jsonText).data(using: .utf8) else {
            throw GeminiError.parsingFailed
        }

        return try JSONDecoder().decode(DailyEvaluationResult.self, from: cleanData)
    }

    // MARK: - Private Helpers
    private func sendRequest(url: URL, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown HTTP \(httpResponse.statusCode)"
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorMsg)
        }

        return data
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
