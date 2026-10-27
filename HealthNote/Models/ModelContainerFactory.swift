import Foundation
import SwiftData

/// SwiftData の ModelContainer 初期化・管理ファクトリ
public enum ModelContainerFactory {
    public static let schema = Schema([
        Meal.self,
        HealthProfile.self,
        MedicationItem.self,
        AdvisorChatMessage.self,
        DailyAdvice.self
    ])

    /// アプリ本番用コンテナ生成（CloudKit Private Database連携対応）
    @MainActor
    public static func createLiveContainer(enableCloudKit: Bool = true) -> ModelContainer {
        let modelConfiguration: ModelConfiguration

        if enableCloudKit {
            // CloudKit Private Database 自動同期設定
            modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
        } else {
            modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
        }

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            ensureInitialData(context: container.mainContext)
            return container
        } catch {
            fatalError("Failed to create live ModelContainer: \(error)")
        }
    }

    /// Xcode Previews & テスト用インメモリコンテナ生成
    @MainActor
    public static func createPreviewContainer() -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            insertSampleData(context: container.mainContext)
            return container
        } catch {
            fatalError("Failed to create preview ModelContainer: \(error)")
        }
    }

    /// 初回起動時のデフォルトプロフィール・サンプル初期化
    @MainActor
    public static func ensureInitialData(context: ModelContext) {
        let descriptor = FetchDescriptor<HealthProfile>()
        do {
            let count = try context.fetchCount(descriptor)
            if count == 0 {
                let defaultProfile = HealthProfile(
                    nickname: "あなた",
                    heightCm: 170.0,
                    weightKg: 65.0,
                    targetWeightKg: 62.0,
                    targetCalories: 2000.0,
                    targetProtein: 75.0,
                    targetFat: 55.0,
                    targetCarbs: 250.0
                )
                context.insert(defaultProfile)

                // デフォルトのサプリ・服薬サンプル
                let sampleMed = MedicationItem(name: "マルチビタミン", timingRaw: "朝", dosage: "1粒")
                context.insert(sampleMed)

                try? context.save()
            }
        } catch {
            print("Failed to fetch initial HealthProfile: \(error)")
        }
    }

    /// プレビュー用モックデータの投入
    @MainActor
    private static func insertSampleData(context: ModelContext) {
        let profile = HealthProfile(
            nickname: "山田 太郎",
            genderRaw: "男性",
            heightCm: 175.0,
            weightKg: 68.0,
            targetWeightKg: 64.0,
            targetCalories: 2100.0,
            targetProtein: 80.0,
            targetFat: 55.0,
            targetCarbs: 260.0,
            dietaryRestrictions: "減塩を心がけている"
        )
        context.insert(profile)

        let meal1 = Meal(
            timestamp: Calendar.current.date(byAdding: .hour, value: -6, to: Date()) ?? Date(),
            mealType: .breakfast,
            name: "全粒粉トースト・目玉焼き・サラダ",
            calories: 450,
            protein: 22,
            fat: 16,
            carbs: 52,
            memo: "オリーブオイル少々"
        )
        let meal2 = Meal(
            timestamp: Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date(),
            mealType: .lunch,
            name: "鶏胸肉のグリルと玄米定食",
            calories: 680,
            protein: 48,
            fat: 14,
            carbs: 85,
            memo: "味噌汁付き"
        )
        context.insert(meal1)
        context.insert(meal2)

        let med1 = MedicationItem(name: "ビタミンD", timingRaw: "朝", dosage: "1粒", isCompleted: true, lastCompletedDate: Date())
        let med2 = MedicationItem(name: "整腸剤", timingRaw: "夕", dosage: "2錠", isCompleted: false)
        context.insert(med1)
        context.insert(med2)

        let chat1 = AdvisorChatMessage(role: .assistant, content: "こんにちは！今日の昼食は高タンパクで素晴らしい栄養バランスですね。水分補給も忘れずに行いましょう。")
        context.insert(chat1)

        try? context.save()
    }
}
