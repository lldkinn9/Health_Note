import Foundation
import StoreKit

/// StoreKit 2 による「Proプラン（500円買い切り・広告完全非表示）」課金管理マネージャー
@MainActor
public final class PurchaseManager: ObservableObject {
    public static let shared = PurchaseManager()

    /// App Store Connect に登録する非消耗型（買い切り）課金アイテムの Product ID
    public static let proProductID = "com.lldkinn9.HealthNote.pro"
    private static let proKeychainIdentifier = "com.lldkinn9.HealthNote.isProUnlocked"

    @Published public private(set) var isProUnlocked: Bool = false
    @Published public private(set) var proProduct: Product? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var statusMessage: String? = nil

    private var updatesTask: Task<Void, Never>? = nil

    private init() {
        // Keychain からキャッシュされたPro状態を読み込み（オフライン起動時にも即座に広告を非表示にするため）
        if KeychainManager.shared.load(key: Self.proKeychainIdentifier) == "true" {
            self.isProUnlocked = true
        }

        // トランザクション更新の監視を開始
        self.updatesTask = Task {
            await observeTransactionUpdates()
        }

        // 起動時に商品情報と最新の購入権利を確認
        Task {
            await loadProducts()
            await updateCustomerProductStatus()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// 表示用の価格文字列（StoreKit取得前は「¥500」をフォールバック表示）
    public var displayPrice: String {
        proProduct?.displayPrice ?? "¥500"
    }

    // MARK: - 1. 商品情報の取得
    public func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            if let first = products.first {
                self.proProduct = first
            }
        } catch {
            print("StoreKit loadProducts failed: \(error.localizedDescription)")
        }
    }

    // MARK: - 2. Proプランの購入実行（500円買い切り）
    public func purchasePro() async {
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        defer { isLoading = false }

        // 商品情報が未取得の場合は再取得を試みる
        if proProduct == nil {
            await loadProducts()
        }

        guard let product = proProduct else {
            #if DEBUG
            // シミュレーターで StoreKit Configuration 未設定の場合でもデバッグ検証できるよう即時アンロックを提供
            unlockProLocally()
            statusMessage = "【開発用シミュレーター確認】Proプラン（広告非表示）を有効化しました。"
            return
            #else
            errorMessage = "App Storeから商品情報を取得できませんでした。通信環境をご確認の上、しばらくしてから再度お試しください。"
            return
            #endif
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                unlockProLocally()
                await transaction.finish()
                statusMessage = "Proプランへのアップグレードが完了しました！すべての広告が非表示になります。"

            case .userCancelled:
                break

            case .pending:
                statusMessage = "購入承認待ちです。承認され次第Proプランが有効になります。"

            @unknown default:
                break
            }
        } catch {
            errorMessage = "購入処理中にエラーが発生しました: \(error.localizedDescription)"
        }
    }

    // MARK: - 3. 購入の復元（App Store 審査 Guideline 3.1.1 必須機能）
    public func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await updateCustomerProductStatus()
            if isProUnlocked {
                statusMessage = "購入履歴を復元しました。Proプラン（広告非表示）が有効です。"
            } else {
                errorMessage = "復元可能なProプランの購入履歴が見つかりませんでした。"
            }
        } catch {
            errorMessage = "購入の復元に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - 4. 現在の購入権利（Entitlements）の確認
    public func updateCustomerProductStatus() async {
        var unlocked = false

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.proProductID && transaction.revocationDate == nil {
                    unlocked = true
                }
            }
        }

        if unlocked {
            unlockProLocally()
        }
    }

    #if DEBUG
    /// 開発・デバッグ用：無料状態（広告表示あり）に戻すヘルパー
    public func debugResetProStatus() {
        isProUnlocked = false
        KeychainManager.shared.delete(key: Self.proKeychainIdentifier)
    }
    #endif

    // MARK: - Private Helpers
    private func unlockProLocally() {
        isProUnlocked = true
        KeychainManager.shared.save(key: Self.proKeychainIdentifier, value: "true")
    }

    private func observeTransactionUpdates() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.proProductID {
                    if transaction.revocationDate == nil {
                        unlockProLocally()
                    } else {
                        isProUnlocked = false
                        KeychainManager.shared.delete(key: Self.proKeychainIdentifier)
                    }
                }
                await transaction.finish()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    public enum StoreError: LocalizedError {
        case failedVerification
        public var errorDescription: String? {
            "購入情報の署名検証に失敗しました。"
        }
    }
}
