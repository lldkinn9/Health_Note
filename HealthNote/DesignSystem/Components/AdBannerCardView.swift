import SwiftUI
import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

/// 案C：タブバー直上に常時表示する下部固定バナー広告バー
/// ・Proプラン（500円買い切り）購入済みの場合は自動的に完全非表示
/// ・マイカルテ画面で「未保存の変更（FloatingSaveBar）」が出ている間は干渉防止のため自動非表示
public struct AdBottomBannerBar: View {
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @State private var showingProSheet: Bool = false

    /// マイカルテのFloatingSaveBar表示中など、一時的に隠すかどうか
    public var isTemporarilyHidden: Bool

    public init(isTemporarilyHidden: Bool = false) {
        self.isTemporarilyHidden = isTemporarilyHidden
    }

    public var body: some View {
        if !purchaseManager.isProUnlocked && !isTemporarilyHidden {
            VStack(spacing: 0) {
                Divider()

                // ミニヘッダー（広告ラベル ＆ 広告非表示Pro案内リンク）
                HStack {
                    Text("SPONSORED")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.7))

                    Spacer()

                    Button(action: {
                        showingProSheet = true
                    }) {
                        HStack(spacing: 2) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9))
                            Text("広告を非表示 (Pro)")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 3)
                .padding(.bottom, 2)

                // バナー本体（高さ50pt固定）
                #if canImport(GoogleMobileAds)
                AdMobBannerRepresentable(adUnitID: AdMobManager.shared.bannerAdUnitID)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                #else
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppTheme.emerald.opacity(0.15))
                            .frame(width: 34, height: 34)
                        Image(systemName: "megaphone.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.emerald)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Google AdMob バナー広告（320×50）")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.primary)
                        Text("Proプラン（¥500買い切り）で広告をすべて非表示にできます")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(.tertiarySystemGroupedBackground).opacity(0.5))
                #endif
            }
            .background(Color(.secondarySystemGroupedBackground))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .sheet(isPresented: $showingProSheet) {
                ProUpgradeSheetView()
            }
        }
    }
}

/// Proプラン（500円買い切り・広告完全非表示）アップグレード案内シート
public struct ProUpgradeSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var purchaseManager = PurchaseManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    // ヘッダーアイコン
                    ZStack {
                        Circle()
                            .fill(AppTheme.emeraldGradient)
                            .frame(width: 72, height: 72)
                            .shadow(color: AppTheme.emerald.opacity(0.35), radius: 10, x: 0, y: 5)

                        Image(systemName: "crown.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 16)

                    VStack(spacing: 6) {
                        Text("Health Note Pro")
                            .font(.system(size: 24, weight: .black, design: .rounded))

                        Text("500円（税込）買い切り・月額料金なし")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AppTheme.emerald)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(AppTheme.emerald.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    // 特典リスト
                    VStack(alignment: .leading, spacing: 14) {
                        benefitRow(
                            icon: "eye.slash.fill",
                            color: .indigo,
                            title: "すべてのバナー広告を永久に非表示",
                            subtitle: "画面下部のバナー広告が完全に消え、さらに広く快適に記録できます。"
                        )
                        Divider()
                        benefitRow(
                            icon: "yensign.circle.fill",
                            color: AppTheme.emerald,
                            title: "一度きりの買い切り（追加課金一切なし）",
                            subtitle: "サブスクリプションではなく1回のみのお支払いで、ずっとProプランをご利用いただけます。"
                        )
                        Divider()
                        benefitRow(
                            icon: "arrow.triangle.2.circlepath.circle.fill",
                            color: .orange,
                            title: "機種変更時も無料で復元可能",
                            subtitle: "同じApple IDであれば、新しいiPhoneでも「購入を復元」からいつでも引き継げます。"
                        )
                    }
                    .padding(18)
                    .appCard()

                    // ステータスメッセージ / エラー表示
                    if let status = purchaseManager.statusMessage {
                        Text(status)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppTheme.emerald)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    if let error = purchaseManager.errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // 購入ボタン ＆ 復元ボタン
                    if purchaseManager.isProUnlocked {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(AppTheme.emerald)
                            Text("現在 Proプランが有効です（広告非表示）")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(AppTheme.emerald)
                        }
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(AppTheme.emerald.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        VStack(spacing: 12) {
                            Button(action: {
                                Task { await purchaseManager.purchasePro() }
                            }) {
                                HStack(spacing: 8) {
                                    if purchaseManager.isLoading {
                                        ProgressView().tint(.white)
                                    } else {
                                        Image(systemName: "crown.fill")
                                        Text("Proプランにアップグレード（\(purchaseManager.displayPrice) 買い切り）")
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(AppTheme.actionGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .shadow(color: Color.purple.opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                            .disabled(purchaseManager.isLoading)

                            Button(action: {
                                Task { await purchaseManager.restorePurchases() }
                            }) {
                                Text("購入を復元する（以前に購入された方）")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .disabled(purchaseManager.isLoading)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Proプランのご案内")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func benefitRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
        }
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
