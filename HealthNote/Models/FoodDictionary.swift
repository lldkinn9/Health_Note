import Foundation

/// 食品辞書のカテゴリ分類
public enum FoodCategory: String, CaseIterable, Identifiable {
    case all = "すべて"
    case staple = "🍚 主食・パン・麺"
    case protein = "🍗 肉・魚・卵・大豆"
    case setMeal = "🏪 定食・外食・コンビニ"
    case vegetable = "🥦 野菜・副菜・汁物"
    case snack = "🥛 乳製品・プロテイン・間食"
    case drink = "☕ 飲料・オイル・調味料"

    public var id: String { rawValue }
}

/// 食品辞書アイテム（文部科学省「日本食品標準成分表」等の一般的な1人前・標準目安値）
public struct FoodDictionaryItem: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let unitDescription: String
    public let category: FoodCategory
    public let calories: Double
    public let protein: Double
    public let fat: Double
    public let carbs: Double
    public let keywords: String

    public init(
        id: String,
        name: String,
        unitDescription: String,
        category: FoodCategory,
        calories: Double,
        protein: Double,
        fat: Double,
        carbs: Double,
        keywords: String = ""
    ) {
        self.id = id
        self.name = name
        self.unitDescription = unitDescription
        self.category = category
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.keywords = keywords
    }
}

/// 選択された食品アイテムと分量倍率
public struct SelectedFoodEntry: Identifiable {
    public let item: FoodDictionaryItem
    public var multiplier: Double // 0.5, 1.0, 1.5, 2.0 など

    public var id: String { item.id }

    public var adjustedCalories: Double { (item.calories * multiplier).rounded() }
    public var adjustedProtein: Double { ((item.protein * multiplier) * 10).rounded() / 10 }
    public var adjustedFat: Double { ((item.fat * multiplier) * 10).rounded() / 10 }
    public var adjustedCarbs: Double { ((item.carbs * multiplier) * 10).rounded() / 10 }

    public var displayNameWithPortion: String {
        if multiplier == 1.0 {
            return item.name
        } else if multiplier == 0.5 {
            return "\(item.name)(半分)"
        } else {
            return "\(item.name)(\(String(format: "%.1f", multiplier))倍)"
        }
    }
}

/// 標準搭載の食品・メニュー栄養成分カタログ
public enum FoodDictionaryCatalog {
    public static let allItems: [FoodDictionaryItem] = [
        // MARK: - 🍚 主食・パン・麺
        FoodDictionaryItem(id: "rice_normal", name: "白米ご飯", unitDescription: "茶碗1杯 (150g)", category: .staple, calories: 234, protein: 3.8, fat: 0.5, carbs: 55.7, keywords: "ごはん ライス こめ"),
        FoodDictionaryItem(id: "rice_small", name: "白米ご飯（小盛）", unitDescription: "小茶碗1杯 (100g)", category: .staple, calories: 156, protein: 2.5, fat: 0.3, carbs: 37.1, keywords: "ごはん ライス こめ 少なめ"),
        FoodDictionaryItem(id: "rice_large", name: "白米ご飯（大盛）", unitDescription: "丼1杯 (220g)", category: .staple, calories: 343, protein: 5.5, fat: 0.7, carbs: 81.6, keywords: "ごはん ライス こめ おおもり"),
        FoodDictionaryItem(id: "brown_rice", name: "玄米ご飯", unitDescription: "茶碗1杯 (150g)", category: .staple, calories: 228, protein: 4.2, fat: 1.5, carbs: 53.4, keywords: "げんまい 雑穀米"),
        FoodDictionaryItem(id: "oatmeal", name: "オートミール", unitDescription: "1食分 (30g)", category: .staple, calories: 105, protein: 4.1, fat: 1.7, carbs: 20.7, keywords: "シリアル 朝食"),
        FoodDictionaryItem(id: "onigiri_salmon", name: "おにぎり（鮭）", unitDescription: "1個", category: .staple, calories: 180, protein: 4.9, fat: 1.5, carbs: 37.2, keywords: "おむすび コンビニ しゃけ"),
        FoodDictionaryItem(id: "onigiri_tuna", name: "おにぎり（ツナマヨ）", unitDescription: "1個", category: .staple, calories: 228, protein: 4.8, fat: 6.2, carbs: 38.5, keywords: "おむすび コンビニ"),
        FoodDictionaryItem(id: "onigiri_ume", name: "おにぎり（梅・昆布）", unitDescription: "1個", category: .staple, calories: 170, protein: 3.2, fat: 0.5, carbs: 38.0, keywords: "おむすび コンビニ うめ"),
        FoodDictionaryItem(id: "toast_6", name: "食パン（6枚切）", unitDescription: "1枚 (60g)", category: .staple, calories: 149, protein: 5.3, fat: 2.5, carbs: 28.0, keywords: "トースト ぱん"),
        FoodDictionaryItem(id: "whole_wheat_bread", name: "全粒粉パン", unitDescription: "1枚", category: .staple, calories: 140, protein: 5.8, fat: 2.2, carbs: 25.4, keywords: "ライ麦パン トースト"),
        FoodDictionaryItem(id: "roll_bread", name: "バターロール", unitDescription: "2個 (60g)", category: .staple, calories: 186, protein: 5.6, fat: 5.4, carbs: 29.2, keywords: "ロールパン"),
        FoodDictionaryItem(id: "udon", name: "かけうどん", unitDescription: "1人前", category: .staple, calories: 310, protein: 8.5, fat: 1.2, carbs: 64.5, keywords: "麺 めん"),
        FoodDictionaryItem(id: "soba", name: "かけそば・ざるそば", unitDescription: "1人前", category: .staple, calories: 320, protein: 12.0, fat: 2.0, carbs: 63.0, keywords: "蕎麦 麺 めん"),
        FoodDictionaryItem(id: "pasta_plain", name: "茹でパスタ（麺のみ）", unitDescription: "1人前 (250g)", category: .staple, calories: 373, protein: 13.0, fat: 2.3, carbs: 72.0, keywords: "スパゲッティ 麺"),
        FoodDictionaryItem(id: "mochi", name: "切り餅", unitDescription: "1個 (50g)", category: .staple, calories: 112, protein: 2.0, fat: 0.3, carbs: 25.4, keywords: "もち お餅"),

        // MARK: - 🍗 肉・魚・卵・大豆
        FoodDictionaryItem(id: "chicken_breast", name: "鶏むね肉（皮なし・茹で/焼き）", unitDescription: "100g", category: .protein, calories: 113, protein: 23.3, fat: 1.9, carbs: 0.0, keywords: "とりむね チキン 高タンパク"),
        FoodDictionaryItem(id: "salad_chicken", name: "サラダチキン", unitDescription: "1パック (110g)", category: .protein, calories: 115, protein: 24.5, fat: 1.2, carbs: 1.0, keywords: "コンビニ とりむね"),
        FoodDictionaryItem(id: "chicken_sasami", name: "鶏ささみ", unitDescription: "2本 (100g)", category: .protein, calories: 109, protein: 23.9, fat: 0.8, carbs: 0.0, keywords: "ササミ 高タンパク"),
        FoodDictionaryItem(id: "chicken_thigh", name: "鶏もも肉（皮つき・焼き）", unitDescription: "100g", category: .protein, calories: 204, protein: 16.6, fat: 14.2, carbs: 0.0, keywords: "とりもも チキン"),
        FoodDictionaryItem(id: "pork_loin", name: "豚ロース肉（ソテー）", unitDescription: "100g", category: .protein, calories: 248, protein: 19.3, fat: 19.2, carbs: 0.2, keywords: "ぶた 豚肉"),
        FoodDictionaryItem(id: "beef_lean", name: "牛赤身肉（もも・ステーキ）", unitDescription: "100g", category: .protein, calories: 182, protein: 21.2, fat: 10.7, carbs: 0.6, keywords: "ぎゅう 牛肉 ローストビーフ"),
        FoodDictionaryItem(id: "salmon_grilled", name: "焼き鮭（塩鮭）", unitDescription: "1切れ (80g)", category: .protein, calories: 138, protein: 18.0, fat: 6.8, carbs: 0.1, keywords: "魚 しゃけ サーモン"),
        FoodDictionaryItem(id: "mackerel_grilled", name: "サバの塩焼き", unitDescription: "1切れ (100g)", category: .protein, calories: 247, protein: 20.6, fat: 16.8, carbs: 0.3, keywords: "魚 鯖 さば 青魚"),
        FoodDictionaryItem(id: "tuna_sashimi", name: "マグロ赤身（刺身）", unitDescription: "5〜6切れ (80g)", category: .protein, calories: 92, protein: 21.1, fat: 1.1, carbs: 0.1, keywords: "魚 まぐろ お刺身"),
        FoodDictionaryItem(id: "tuna_can_water", name: "ツナ缶（水煮・ノンオイル）", unitDescription: "1缶 (70g)", category: .protein, calories: 50, protein: 11.2, fat: 0.5, carbs: 0.1, keywords: "シーチキン 魚"),
        FoodDictionaryItem(id: "egg_boiled", name: "卵（ゆで卵・生卵・目玉焼き）", unitDescription: "1個 (55g)", category: .protein, calories: 83, protein: 6.8, fat: 5.7, carbs: 0.2, keywords: "たまご 玉子"),
        FoodDictionaryItem(id: "natto", name: "納豆", unitDescription: "1パック (45g)", category: .protein, calories: 90, protein: 7.4, fat: 4.5, carbs: 5.4, keywords: "なっとう 大豆 発酵食品"),
        FoodDictionaryItem(id: "tofu_momen", name: "木綿豆腐（冷奴・湯豆腐）", unitDescription: "半丁 (150g)", category: .protein, calories: 110, protein: 10.5, fat: 7.4, carbs: 2.3, keywords: "とうふ 大豆"),
        FoodDictionaryItem(id: "tofu_kinu", name: "絹ごし豆腐", unitDescription: "半丁 (150g)", category: .protein, calories: 84, protein: 7.9, fat: 5.3, carbs: 3.0, keywords: "とうふ 大豆"),
        FoodDictionaryItem(id: "atsuage", name: "厚揚げ（焼き）", unitDescription: "1/2枚 (100g)", category: .protein, calories: 143, protein: 10.7, fat: 11.3, carbs: 0.9, keywords: "あつあげ 大豆"),

        // MARK: - 🏪 定食・外食・コンビニ
        FoodDictionaryItem(id: "karaage_3", name: "鶏の唐揚げ", unitDescription: "3個 (約100g)", category: .setMeal, calories: 290, protein: 16.5, fat: 21.0, carbs: 8.5, keywords: "からあげ 揚げ物"),
        FoodDictionaryItem(id: "shogayaki", name: "豚の生姜焼き（おかず単品）", unitDescription: "1人前", category: .setMeal, calories: 350, protein: 21.0, fat: 24.0, carbs: 10.5, keywords: "しょうがやき 定食"),
        FoodDictionaryItem(id: "hamburg", name: "ハンバーグ（ソース付）", unitDescription: "1個 (150g)", category: .setMeal, calories: 380, protein: 20.5, fat: 26.0, carbs: 14.5, keywords: "洋食 おかず"),
        FoodDictionaryItem(id: "set_grilled_fish", name: "焼き魚定食（ご飯・味噌汁・小鉢付）", unitDescription: "1人前", category: .setMeal, calories: 580, protein: 31.0, fat: 15.0, carbs: 74.0, keywords: "和食 ランチ 外食"),
        FoodDictionaryItem(id: "set_sashimi", name: "お刺身定食（ご飯・味噌汁・小鉢付）", unitDescription: "1人前", category: .setMeal, calories: 550, protein: 33.0, fat: 10.0, carbs: 76.0, keywords: "和食 ランチ 外食"),
        FoodDictionaryItem(id: "gyudon_nami", name: "牛丼（並盛）", unitDescription: "1杯", category: .setMeal, calories: 635, protein: 20.0, fat: 20.4, carbs: 89.6, keywords: "外食 丼 どんぶり"),
        FoodDictionaryItem(id: "oyakodon", name: "親子丼", unitDescription: "1杯", category: .setMeal, calories: 620, protein: 28.5, fat: 14.0, carbs: 90.0, keywords: "外食 丼 どんぶり 鶏肉 卵"),
        FoodDictionaryItem(id: "curry_rice", name: "カレーライス", unitDescription: "1皿", category: .setMeal, calories: 730, protein: 16.5, fat: 23.0, carbs: 108.0, keywords: "外食 ランチ"),
        FoodDictionaryItem(id: "pasta_meat", name: "ミートソースパスタ", unitDescription: "1人前", category: .setMeal, calories: 610, protein: 23.0, fat: 16.0, carbs: 88.0, keywords: "スパゲッティ イタリアン"),
        FoodDictionaryItem(id: "pasta_pepe", name: "ペペロンチーノ", unitDescription: "1人前", category: .setMeal, calories: 520, protein: 14.5, fat: 17.0, carbs: 74.0, keywords: "スパゲッティ イタリアン"),
        FoodDictionaryItem(id: "ramen_shoyu", name: "醤油ラーメン", unitDescription: "1杯", category: .setMeal, calories: 470, protein: 21.0, fat: 10.0, carbs: 72.0, keywords: "中華そば 麺 外食"),
        FoodDictionaryItem(id: "sandwich_mix", name: "ミックスサンドイッチ", unitDescription: "1パック", category: .setMeal, calories: 320, protein: 11.5, fat: 15.0, carbs: 34.0, keywords: "コンビニ パン 朝食"),
        FoodDictionaryItem(id: "bento_makunouchi", name: "幕の内弁当", unitDescription: "1個", category: .setMeal, calories: 680, protein: 24.0, fat: 20.0, carbs: 98.0, keywords: "コンビニ 弁当"),
        FoodDictionaryItem(id: "gyoza_6", name: "焼き餃子", unitDescription: "6個 (1人前)", category: .setMeal, calories: 290, protein: 10.5, fat: 14.5, carbs: 28.0, keywords: "ぎょうざ 中華"),

        // MARK: - 🥦 野菜・副菜・汁物
        FoodDictionaryItem(id: "green_salad", name: "グリーンサラダ（野菜のみ）", unitDescription: "1皿", category: .vegetable, calories: 25, protein: 1.2, fat: 0.2, carbs: 5.0, keywords: "レタス キャベツ 野菜"),
        FoodDictionaryItem(id: "broccoli", name: "茹でブロッコリー", unitDescription: "小房5〜6個 (80g)", category: .vegetable, calories: 28, protein: 3.4, fat: 0.3, carbs: 4.2, keywords: "緑黄色野菜 筋トレ"),
        FoodDictionaryItem(id: "tomato", name: "トマト", unitDescription: "中1個 (150g)", category: .vegetable, calories: 30, protein: 1.1, fat: 0.2, carbs: 7.1, keywords: "野菜 リコピン"),
        FoodDictionaryItem(id: "avocado_half", name: "アボカド", unitDescription: "1/2個 (70g)", category: .vegetable, calories: 123, protein: 1.5, fat: 12.3, carbs: 5.5, keywords: "良質な脂質 サラダ"),
        FoodDictionaryItem(id: "spinach_ohitashi", name: "ほうれん草のお浸し", unitDescription: "1小鉢 (80g)", category: .vegetable, calories: 20, protein: 2.2, fat: 0.3, carbs: 3.1, keywords: "副菜 鉄分 緑黄色野菜"),
        FoodDictionaryItem(id: "kinpira", name: "きんぴらごぼう", unitDescription: "1小鉢 (60g)", category: .vegetable, calories: 75, protein: 1.4, fat: 3.2, carbs: 11.0, keywords: "副菜 食物繊維 和食"),
        FoodDictionaryItem(id: "hijiki", name: "ひじきの煮物", unitDescription: "1小鉢 (60g)", category: .vegetable, calories: 62, protein: 2.8, fat: 2.5, carbs: 7.5, keywords: "副菜 海藻 ミネラル"),
        FoodDictionaryItem(id: "edamame", name: "枝豆", unitDescription: "1小鉢 (さや付100g)", category: .vegetable, calories: 67, protein: 5.9, fat: 3.1, carbs: 4.4, keywords: "えだまめ おつまみ 豆"),
        FoodDictionaryItem(id: "kimchi", name: "白菜キムチ", unitDescription: "1小鉢 (50g)", category: .vegetable, calories: 23, protein: 1.3, fat: 0.4, carbs: 4.1, keywords: "発酵食品 漬物"),
        FoodDictionaryItem(id: "miso_soup", name: "豆腐とわかめの味噌汁", unitDescription: "1杯", category: .vegetable, calories: 42, protein: 3.2, fat: 1.5, carbs: 4.5, keywords: "みそしる スープ 和食"),
        FoodDictionaryItem(id: "tonjiru", name: "豚汁（具だくさん）", unitDescription: "1杯", category: .vegetable, calories: 145, protein: 8.5, fat: 7.5, carbs: 11.0, keywords: "とんじる 味噌汁 スープ"),
        FoodDictionaryItem(id: "corn_soup", name: "コーンスープ", unitDescription: "1杯", category: .vegetable, calories: 110, protein: 2.8, fat: 4.5, carbs: 14.5, keywords: "ポタージュ スープ"),

        // MARK: - 🥛 乳製品・プロテイン・間食
        FoodDictionaryItem(id: "whey_protein", name: "ホエイプロテイン（水割り）", unitDescription: "1杯 (粉末30g)", category: .snack, calories: 117, protein: 21.5, fat: 1.5, carbs: 4.2, keywords: "サプリ タンパク質 筋トレ"),
        FoodDictionaryItem(id: "soy_protein", name: "ソイプロテイン（水割り）", unitDescription: "1杯 (粉末25g)", category: .snack, calories: 95, protein: 18.0, fat: 1.0, carbs: 2.5, keywords: "大豆 プロテイン タンパク質"),
        FoodDictionaryItem(id: "protein_bar", name: "プロテインバー", unitDescription: "1本", category: .snack, calories: 185, protein: 15.0, fat: 8.5, carbs: 12.0, keywords: "コンビニ 間食 おやつ"),
        FoodDictionaryItem(id: "greek_yogurt", name: "ギリシャヨーグルト（プレーン/無糖）", unitDescription: "1個 (100g)", category: .snack, calories: 59, protein: 10.0, fat: 0.2, carbs: 4.2, keywords: "オイコス パルテノ 乳製品"),
        FoodDictionaryItem(id: "plain_yogurt", name: "プレーンヨーグルト（無糖）", unitDescription: "1食 (100g)", category: .snack, calories: 56, protein: 3.6, fat: 3.0, carbs: 4.9, keywords: "発酵食品 乳酸菌"),
        FoodDictionaryItem(id: "milk", name: "牛乳", unitDescription: "コップ1杯 (200ml)", category: .snack, calories: 126, protein: 6.8, fat: 7.8, carbs: 9.9, keywords: "ミルク カルシウム"),
        FoodDictionaryItem(id: "soymilk", name: "無調整豆乳", unitDescription: "コップ1杯 (200ml)", category: .snack, calories: 86, protein: 7.4, fat: 4.2, carbs: 5.8, keywords: "とうにゅう 大豆"),
        FoodDictionaryItem(id: "cheese_piece", name: "プロセスチーズ（6Pチーズ等）", unitDescription: "1個 (18g)", category: .snack, calories: 57, protein: 3.9, fat: 4.7, carbs: 0.2, keywords: "乳製品 間食 おつまみ"),
        FoodDictionaryItem(id: "banana", name: "バナナ", unitDescription: "1本 (可食部100g)", category: .snack, calories: 93, protein: 1.1, fat: 0.2, carbs: 22.5, keywords: "果物 フルーツ 朝食"),
        FoodDictionaryItem(id: "apple_half", name: "りんご", unitDescription: "1/2個 (125g)", category: .snack, calories: 66, protein: 0.3, fat: 0.3, carbs: 18.3, keywords: "果物 フルーツ"),
        FoodDictionaryItem(id: "kiwi", name: "キウイフルーツ", unitDescription: "1個 (85g)", category: .snack, calories: 43, protein: 0.8, fat: 0.2, carbs: 11.4, keywords: "果物 ビタミンC"),
        FoodDictionaryItem(id: "mixed_nuts", name: "素焼きミックスナッツ", unitDescription: "1つかみ (25g)", category: .snack, calories: 155, protein: 4.5, fat: 13.8, carbs: 4.2, keywords: "アーモンド くるみ 間食"),
        FoodDictionaryItem(id: "high_cacao_choco", name: "高カカオチョコレート (72%)", unitDescription: "3枚 (15g)", category: .snack, calories: 84, protein: 1.5, fat: 6.0, carbs: 6.6, keywords: "お菓子 おやつ ポリフェノール"),
        FoodDictionaryItem(id: "daifuku", name: "豆大福・和菓子", unitDescription: "1個 (80g)", category: .snack, calories: 185, protein: 4.2, fat: 0.6, carbs: 41.2, keywords: "あんこ 低脂質 間食"),

        // MARK: - ☕ 飲料・オイル・調味料
        FoodDictionaryItem(id: "olive_oil", name: "オリーブオイル・サラダ油", unitDescription: "大さじ1 (12g)", category: .drink, calories: 107, protein: 0.0, fat: 12.0, carbs: 0.0, keywords: "油 脂質 調理油"),
        FoodDictionaryItem(id: "mayonnaise", name: "マヨネーズ", unitDescription: "大さじ1 (12g)", category: .drink, calories: 80, protein: 0.2, fat: 9.0, carbs: 0.2, keywords: "調味料"),
        FoodDictionaryItem(id: "dressing_sesame", name: "ごまドレッシング", unitDescription: "大さじ1 (15g)", category: .drink, calories: 58, protein: 0.5, fat: 5.2, carbs: 2.3, keywords: "サラダ 調味料"),
        FoodDictionaryItem(id: "cafe_latte", name: "カフェラテ（無糖）", unitDescription: "1杯 (240ml)", category: .drink, calories: 95, protein: 5.0, fat: 5.2, carbs: 7.2, keywords: "コーヒー 飲み物"),
        FoodDictionaryItem(id: "black_coffee", name: "ブラックコーヒー・緑茶", unitDescription: "1杯", category: .drink, calories: 4, protein: 0.2, fat: 0.0, carbs: 0.7, keywords: "お茶 飲み物")
    ]
}
