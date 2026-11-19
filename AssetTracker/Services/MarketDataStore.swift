import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class MarketDataStore {
    var rates: [Currency: Decimal] = [.cny: 1]
    var yesterdayRates: [Currency: Decimal] = [.cny: 1]
    var goldCNYPerGram: Decimal?
    var goldUSDPerOunce: Decimal?
    var goldUpdatedAt: Date?

    var isLoading = false
    var lastError: String?
    var lastRefresh: Date?
    var rateSource = "—"

    // 各数据源状态，明细页展示
    var status: [String: String] = [:]

    private var context: ModelContext?
    private var assets: [Asset] = []

    var valuation: ValuationEngine.Result {
        ValuationEngine().compute(assets: assets, rates: rates, goldCNYPerGram: goldCNYPerGram)
    }

    var todayChange: (amount: Decimal, pct: Decimal) {
        ValuationEngine().dailyChange(
            assets: assets,
            todayRates: rates,
            yesterdayRates: yesterdayRates,
            goldToday: goldCNYPerGram,
            goldYesterday: nil
        )
    }

    func bind(context: ModelContext, assets: [Asset]) {
        self.context = context
        self.assets = assets
    }

    func updateAssets(_ assets: [Asset]) {
        self.assets = assets
    }

    func refresh() async {
        isLoading = true
        lastError = nil

        do {
            rates = try await RateService().latestCNYRates()
            rateSource = "Frankfurter (ECB)"
            status["汇率"] = "已更新"
            if let ctx = context { persistRates(rates, ctx) }
        } catch {
            lastError = "汇率: \(error.localizedDescription)"
            status["汇率"] = "失败"
        }

        if let cached = loadYesterdayRates() {
            yesterdayRates = cached
        }

        do {
            let q = try await GoldService().latest()
            goldCNYPerGram = q.cnyPerGram
            goldUSDPerOunce = q.usdPerOunce
            goldUpdatedAt = q.updatedAt ?? .now
            status["金价"] = "Au(T+D) \(q.cnyPerGram.map { "\($0)" } ?? "—") 元/克"
            if let ctx = context {
                persistPrice("gold.cny", q.cnyPerGram, ctx)
                persistPrice("gold.usd", q.usdPerOunce, ctx)
            }
        } catch {
            status["金价"] = "失败"
        }

        if let ctx = context {
            persistValuation(ctx)
        }

        lastRefresh = .now
        isLoading = false
    }

    // MARK: - 持久化

    private func persistRates(_ rates: [Currency: Decimal], _ ctx: ModelContext) {
        for (cur, rate) in rates where cur != .cny {
            let snap = RateSnapshot(base: cur, quote: .cny, day: .now, rate: rate)
            ctx.insert(snap)
        }
        try? ctx.save()
    }

    private func loadYesterdayRates() -> [Currency: Decimal]? {
        guard let ctx = context else { return nil }
        let yesterday = Calendar.current.startOfDay(for: .now).addingTimeInterval(-86400)
        let start = Calendar.current.startOfDay(for: yesterday)
        let desc = FetchDescriptor<RateSnapshot>(predicate: #Predicate { $0.day == start })
        guard let snaps = try? ctx.fetch(desc), !snaps.isEmpty else { return nil }
        var out: [Currency: Decimal] = [.cny: 1]
        for s in snaps {
            if let c = Currency(rawValue: s.base) { out[c] = s.rate }
        }
        return out
    }

    private func persistPrice(_ series: String, _ value: Decimal?, _ ctx: ModelContext) {
        guard let value else { return }
        ctx.insert(PricePoint(series: series, day: .now, value: value))
        try? ctx.save()
    }

    private func persistValuation(_ ctx: ModelContext) {
        let v = valuation
        let breakdown = v.rows.map {
            BreakdownRow(
                bank: $0.asset.bank,
                name: $0.asset.name,
                currency: $0.asset.currency.rawValue,
                native: NSDecimalNumber(decimal: $0.native).doubleValue,
                cny: NSDecimalNumber(decimal: $0.cny).doubleValue
            )
        }
        ctx.insert(ValuationSnapshot(day: .now, totalCNY: v.totalCNY, liquidCNY: v.liquidCNY, breakdown: breakdown))
        try? ctx.save()
    }
}
