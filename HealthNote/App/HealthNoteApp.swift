import SwiftUI
import SwiftData

@main
struct HealthNoteApp: App {
    // SwiftDataコンテナ（CloudKit Private Database自動同期対応）
    let container: ModelContainer

    init() {
        self.container = ModelContainerFactory.createLiveContainer(enableCloudKit: true)
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(container)
    }
}
