# My Trainer（ヘルスノート） - iOSネイティブ食事・健康管理アプリ

完全無料運用・開発者インフラコスト永久0円（サーバーレス）でApp Storeに公開する、SwiftUI + SwiftData + Apple CloudKit + HealthKit + Gemini AI（BYOK）アプリです。

---

## 📁 ディレクトリ構成

```
HealthNote/
├── App/
│   └── HealthNoteApp.swift           # アプリのエントリーポイント
├── DesignSystem/
│   ├── Theme.swift                   # エメラルドグリーン、PFCカラー、文字切れ防止Modifier
│   └── Components/
│       ├── PFCBalanceView.swift      # 3色プログレスバー ＆ グラム数表示
│       ├── MetricCard.swift          # 太字丸ゴシック数値カード
│       └── FloatingSaveBar.swift     # 下部フローティング保存バー（パルス点滅UX）
├── Models/
│   ├── Meal.swift                    # 食事ログ（@Attribute(.externalStorage)画像保存）
│   ├── HealthProfile.swift           # マイカルテ（身体・問診票・目標PFC）
│   ├── MedicationItem.swift          # 服薬・サプリ（0:00自動リセットロジック）
│   ├── AdvisorChatMessage.swift      # AIアドバイザーチャット履歴
│   ├── DailyAdvice.swift             # 本日の食事総括AI評価キャッシュ
│   └── ModelContainerFactory.swift   # CloudKit同期 & プレビューコンテナ
├── Services/
│   ├── KeychainManager.swift         # APIキーのセキュア保管（Keychain）
│   ├── GeminiService.swift           # BYOK・動的モデル解決・食事写真解析・チャット
│   ├── HealthKitManager.swift        # 歩数・消費カロリー・心拍・睡眠の読取 & 食事書込
│   └── WidgetDataManager.swift       # WidgetKit間データ共有（App Group）
├── Views/
│   ├── MainTabView.swift             # 5タブ構成 & ディープリンクハンドラー
│   ├── Summary/
│   │   └── SummaryView.swift         # カロリーバランス、服薬トグル、バイタル
│   ├── Meals/
│   │   ├── MealsView.swift           # 食事一覧、最下部AI評価ブロック
│   │   └── AddMealView.swift         # 写真AI自動解析モーダル
│   ├── HealthProfile/
│   │   └── HealthProfileView.swift   # マイカルテ（下部フローティング保存バーUX）
│   ├── Advisor/
│   │   └── AdvisorView.swift         # 単一AIアドバイザーチャット（医療免責常時明記）
│   └── Settings/
│       └── SettingsView.swift        # Geminiキー設定、完全データ初期化、法的免責
├── Widgets/
│   ├── HealthNoteWidget.swift        # systemMedium 横長ウィジェット完全配置 (@main)
│   ├── HealthNoteWidget.entitlements # ウィジェット用 App Group 権限設定
│   └── Widget-Info.plist             # ウィジェット用 Info.plist
└── Resources/
    ├── Info.plist                    # 本体権限説明文・UILaunchScreen・URL Scheme
    ├── HealthNote.entitlements       # 本体用 CloudKit / HealthKit / App Group 権限
    ├── PrivacyInfo.xcprivacy         # iOS 17+ 審査必須プライバシーマニフェスト (CA92.1 / 1C8F.1)
    └── APP_REVIEW_NOTES.md           # App Store Connect 審査提出用メモ（英文・テストキー）
docs/
├── index.html                        # GitHub Pages用 公式サポートページ (Support URL)
└── privacy.html                      # GitHub Pages用 プライバシーポリシー＆医療免責 (Privacy URL)
project.yml                           # XcodeGen 自動プロジェクト生成定義ファイル
.gitignore                            # Xcode / macOS / Windows 不要ファイル除外設定
```

---

## 🔄 Windows（Antigravity）⇄ GitHub ⇄ MacBook（Xcode）連携フロー

Windows側でコードを作成・修正してGitHubへPushし、MacBook側でPullしてXcodeでビルド・実機テストを行う手順です。

### 1. Windows側（初回Git初期化 ＆ GitHubへのPush）
```powershell
git init
git add .
git commit -m "Initial release preparation for My Trainer (HealthNote)"
git branch -M main
git remote add origin https://github.com/lldkinn9/Health_Note.git
git push -u origin main
```

### 2. MacBook側（クローン ＆ Xcodeプロジェクトの1秒自動生成）
手作業でXcodeにファイルをドラッグ＆ドロップして設定する手間や設定漏れをなくすため、ルートに [project.yml](file:///g:/マイドライブ/アプリ開発/iOS%20APP/Release/helth%20note/project.yml) を用意してあります。MacBookのターミナルで以下を実行するだけで、App本体とWidget Extensionの2ターゲット・権限・Info.plist・PrivacyInfo.xcprivacyがすべて配線された `HealthNote.xcodeproj` が自動生成されます。

```bash
git clone https://github.com/lldkinn9/Health_Note.git
cd Health_Note

# XcodeGen が未インストールの場合は Homebrew でインストール
brew install xcodegen

# HealthNote.xcodeproj を自動生成して開く
xcodegen generate
open HealthNote.xcodeproj
```

1. Xcodeが開いたら、左上の `HealthNote` プロジェクトを選択し、**Signing & Capabilities** タブを開きます。
2. `HealthNote` ターゲットと `HealthNoteWidgetExtension` ターゲットの両方で、**Team** にご自身の Apple Developer アカウントを選択します（Bundle Identifier が既存の文字列と重複する場合は、末尾にご自身の識別子等を付与してください）。
3. iPhone実機またはシミュレーターを選択し、`Cmd + R` でビルド＆実行します。
4. エラーや修正点があればWindows側のAntigravityに伝えて修正 ➔ `git push` ➔ MacBook側で `git pull`（ファイル増減時は `xcodegen generate`）で即座に反映できます。

### 3. GitHub Pages で「サポートURL」「プライバシーポリシーURL」を無料公開
App Store Connectの申請に必須となる2つのWeb URLは、[docs/index.html](file:///g:/マイドライブ/アプリ開発/iOS%20APP/Release/helth%20note/docs/index.html) と [docs/privacy.html](file:///g:/マイドライブ/アプリ開発/iOS%20APP/Release/helth%20note/docs/privacy.html) をそのまま使えます：
1. GitHubリポジトリの **Settings** ＞ **Pages** を開く。
2. **Build and deployment** の Branch を `main`、フォルダを `/docs` に設定して **Save**。
3. 数分後に以下のURLが公開されるので、App Store Connect にそのまま登録できます：
   - **サポートURL**: `https://lldkinn9.github.io/Health_Note/`
   - **プライバシーポリシーURL**: `https://lldkinn9.github.io/Health_Note/privacy.html`

---

## 🛠️ Xcode 16 でのプロジェクト設定手順

### 1. Capabilities の追加
Xcode の **Signing & Capabilities** にて以下の項目を追加してください：
1. **iCloud**:
   - `CloudKit` にチェックを入れる。
   - Containers で `iCloud.com.yourcompany.healthnote` を作成または選択。
2. **HealthKit**:
   - `HealthKit` を追加し、Background Delivery（必要に応じて）を有効化。
3. **App Groups**:
   - `group.com.healthnote.app` を追加（WidgetKitとのデータ共有用）。

### 2. URL Types（ディープリンク）
ウィジェットの「＋ 食事登録」ボタンからアプリの食事登録画面へ直行するため、以下を設定：
- Identifier: `com.healthnote.app`
- URL Schemes: `healthnote`

### 3. Gemini APIキー（BYOK）
- ユーザー自身が Google AI Studio で無料取得したAPIキーをアプリ内の「設定」画面で登録します。
- 呼び出しモデルは動的に解決され、デフォルトは公式最新の `gemini-flash` エイリアスを使用します（特定バージョン番号のハードコードなし）。

---

## 🛡️ App Store 審査（Guidelines）および国内法令対策要件

- **Guideline 3.1.1（課金回避の排除 & Anti-Steering）**:
  - APIキーは「持っている人が活用できる上級者向け任意機能」として位置づけ、未登録でもすべての手動食事記録・PFC分析・ヘルスケア連携が無制限・完全無料で使用可能。
  - アプリ内からの外部APIキー購入・取得リンクを完全排除。
- **医師法第17条（医業の独占禁止） & 薬機法（医薬品的な効能効果の標榜禁止）**:
  - アドバイザー画面、食事評価ブロック、設定画面、Info.plist にて「病気の診断・治療や医薬品的な効能効果を標榜するものではなく、日常の栄養バランス向上のための参考指標である」旨の免責表記を常時配置。
  - AIプロンプトに厳格なセーフティガードレール（診断の禁止、投薬指示の禁止、体調不良時の医療機関受診勧奨）を実装。
- **Guideline 5.1.1（プライバシー & サーバーレス）**:
  - 外部サーバーを一切排除し、端末内およびユーザー個人の iCloud Private Database にのみ保存。
  - 設定画面に「全データ完全初期化機能（アカウント削除相当）」を実装。
  - Google無料枠利用時のモデル学習規約に関する開示をプライバシーポリシーに明記。

---

## 📋 App Store Connect 提出用審査メモ（Notes）

審査提出時にそのままコピー＆ペーストできる英文・和文の提出用メモは、以下のファイルに用意されています：
- [APP_REVIEW_NOTES.md](file:///g:/マイドライブ/アプリ開発/iOS APP/Release/helth note/HealthNote/Resources/APP_REVIEW_NOTES.md)（※セキュリティ保護のため `.gitignore` にてGitHubへの公開対象から除外済み）
  - 審査員用テストAPIキー（ローカルの `APP_REVIEW_NOTES.md` 内に記載）
  - 各ガイドラインに対する適合説明文（英文）
