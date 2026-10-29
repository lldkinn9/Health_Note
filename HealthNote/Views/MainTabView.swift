import SwiftUI

public enum AppTab: Int {
    case summary = 0
    case meals = 1
    case profile = 2
    case advisor = 3
    case settings = 4
}

public extension Notification.Name {
    static let openProfileMedicationSection = Notification.Name("openProfileMedicationSection")
}

/// メインタブ画面（5タブ ＆ ウィジェットからのディープリンクハンドリング）
public struct MainTabView: View {
    @State private var selectedTab: AppTab = .summary
    @State private var showingQuickAddMealSheet: Bool = false

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            SummaryView(
                onOpenProfileMedicationSettings: {
                    selectedTab = .profile
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .openProfileMedicationSection, object: nil)
                    }
                }
            )
            .tabItem {
                Label("サマリ", systemImage: "house.fill")
            }
            .tag(AppTab.summary)

            MealsView()
                .tabItem {
                    Label("食事", systemImage: "fork.knife")
                }
                .tag(AppTab.meals)

            HealthProfileView()
                .tabItem {
                    Label("マイカルテ", systemImage: "heart.text.square.fill")
                }
                .tag(AppTab.profile)

            AdvisorView()
                .tabItem {
                    Label("アドバイザー", systemImage: "sparkles")
                }
                .tag(AppTab.advisor)

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape.fill")
                }
                .tag(AppTab.settings)
        }
        .tint(AppTheme.emerald)
        .sheet(isPresented: $showingQuickAddMealSheet) {
            AddMealView()
        }
        .onOpenURL { url in
            handleDeepLink(url: url)
        }
        .task {
            await AdMobManager.shared.requestATTAndStartAds()
        }
    }

    /// ウィジェットや通知からのディープリンク処理（例: healthnote://add-meal）
    private func handleDeepLink(url: URL) {
        guard url.scheme == "healthnote" else { return }

        switch url.host {
        case "add-meal":
            selectedTab = .meals
            showingQuickAddMealSheet = true
        case "advisor":
            selectedTab = .advisor
        case "profile":
            selectedTab = .profile
        default:
            selectedTab = .summary
        }
    }
}
