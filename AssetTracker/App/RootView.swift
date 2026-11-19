import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Asset.createdAt) private var assets: [Asset]
    @State private var store = MarketDataStore()
    @State private var tab: Tab = .overview

    enum Tab { case overview, trends, detail }

    var body: some View {
        TabView(selection: $tab) {
            OverviewView(store: store)
                .tabItem { Label("总览", systemImage: "house") }
                .tag(Tab.overview)

            TrendsView(store: store)
                .tabItem { Label("趋势", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.trends)

            DetailView(store: store)
                .tabItem { Label("明细", systemImage: "list.bullet") }
                .tag(Tab.detail)
        }
        .tint(Color(red: 0.12, green: 0.12, blue: 0.16))
        .task {
            store.bind(context: context, assets: assets)
            await store.refresh()
        }
    }
}
