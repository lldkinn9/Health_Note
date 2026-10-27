import SwiftUI
import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

/// 案A：カード埋め込み型バナー広告コンポーネント
/// サマリ画面および食事ログ画面の最下部に、アプリの角丸カードデザインに馴染む形で配置
public struct AdBannerCardView: View {
    public let placementName: String

    public init(placementName: String = "banner") {
        self.placementName = placementName
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SPONSORED")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(Capsule())

                Spacer()

                Text("広告")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            #if canImport(GoogleMobileAds)
            AdMobBannerRepresentable(adUnitID: AdMobManager.shared.bannerAdUnitID)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            #else
            // GoogleMobileAds SDK パッケージ追加前でもレイアウト確認＆エラーゼロでビルドできるプレビュー枠
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.emerald.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.emerald)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Google AdMob バナー広告枠（320×50）")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    Text("XcodeでGoogleMobileAds追加後に実広告が配信されます")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(.tertiarySystemGroupedBackground).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            #endif
        }
        .padding(12)
        .appCard()
    }
}

#if canImport(GoogleMobileAds)
/// GoogleMobileAds SDK 導入時に自動で有効化される UIViewRepresentable
private struct AdMobBannerRepresentable: UIViewRepresentable {
    let adUnitID: String

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = adUnitID
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            banner.rootViewController = rootVC
        }
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}
#endif
