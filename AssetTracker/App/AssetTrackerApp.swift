import SwiftUI
import SwiftData

@main
struct AssetTrackerApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Asset.self, RateSnapshot.self, ValuationSnapshot.self, PricePoint.self)
        } catch {
            fatalError("ModelContainer 初始化失败: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task { await SeedData.installIfNeeded(container.mainContext) }
        }
        .modelContainer(container)
    }
}
