import Foundation
import AppTrackingTransparency
import AdSupport
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

/// Google AdMob 初期化 ＆ ATT（App Tracking Transparency）許可管理マネージャー
@MainActor
public final class AdMobManager: ObservableObject {
    public static let shared = AdMobManager()

    /// Google 公式 iOS バナーテスト用広告ユニットID（開発・審査検証時に安全に表示される公式ID）
    public static let testBannerAdUnitID = "ca-app-pub-3940256099942544/2435281174"

    @Published public var isInitialized: Bool = false
    @Published public var trackingAuthorizationStatus: ATTrackingManager.AuthorizationStatus = .notDetermined

    private init() {
        self.trackingAuthorizationStatus = ATTrackingManager.trackingAuthorizationStatus
    }

    /// バナー広告ユニットIDの解決（DEBUG時は常にGoogle公式テストIDを返し、自己クリック規約違反を防止）
    public var bannerAdUnitID: String {
        #if DEBUG
        return Self.testBannerAdUnitID
        #else
        if let envID = ProcessInfo.processInfo.environment["ADMOB_BANNER_UNIT_ID"], !envID.isEmpty {
            return envID
        }
        if let plistID = Bundle.main.object(forInfoDictionaryKey: "GADBannerAdUnitID") as? String,
           !plistID.isEmpty,
           !plistID.contains("3940256099942544") {
            return plistID
        }
        return Self.testBannerAdUnitID
        #endif
    }

    /// アプリ起動後のATTトラッキング許可リクエスト ＆ AdMob SDK初期化
    public func requestATTAndStartAds() async {
        // 少し待機してからATTダイアログを表示（画面描画完了後でないとiOSがダイアログを表示しないため）
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            let status = await ATTrackingManager.requestTrackingAuthorization()
            self.trackingAuthorizationStatus = status
        } else {
            self.trackingAuthorizationStatus = ATTrackingManager.trackingAuthorizationStatus
        }

        #if canImport(GoogleMobileAds)
        MobileAds.shared.start { _ in
            Task { @MainActor in
                self.isInitialized = true
            }
        }
        #else
        self.isInitialized = true
        #endif
    }
}

