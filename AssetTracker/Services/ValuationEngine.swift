import Foundation

/// 算账核心。纯函数，不碰网络和数据库，方便单测。
struct ValuationEngine {

    struct Result {
        var totalCNY: Decimal
        var liquidCNY: Decimal
        var lockedCNY: Decimal
        var byBank: [(bank: String, value: Decimal, count: Int)]
        var byCurrency: [(currency: Currency, natives: Decimal, cny: Decimal)]
        var byKind: [(kind: AssetKind, value: Decimal)]
        var rows: [Row]
    }

    struct Row: Identifiable {
        var id: UUID
        var asset: Asset
        var cny: Decimal
        var native: Decimal
        var isInterestRow: Bool = false
    }

    /// - Parameters:
    ///   - rates: 1 外币 = X 人民币
    ///   - goldCNYPerGram: 可选覆盖，黄金资产按此单价重估
    func compute(assets: [Asset], rates: [Currency: Decimal], goldCNYPerGram: Decimal? = nil, on date: Date = .now) -> Result {
        var rows: [Row] = []
        var total: Decimal = 0
        var liquid: Decimal = 0
        var byBank: [String: (Decimal, Int)] = [:]
        var byCur: [Currency: (Decimal, Decimal)] = [:]
        var byKind: [AssetKind: Decimal] = [:]

        for asset in assets {
            let rate = rates[asset.currency] ?? 1
            var native = asset.nativeValue(on: date)

            // 黄金按最新克价重估
            if asset.kind == .gold, let gram = goldCNYPerGram, asset.currency == .cny, asset.qtyMode == .qty {
                native = asset.quantity * gram
            }

            let cny = native * rate
            total += cny
            rows.append(Row(id: asset.id, asset: asset, cny: cny, native: native))
            if asset.isLiquid { liquid += cny }

            let bank = asset.bank.isEmpty ? "其他" : asset.bank
            let prev = byBank[bank] ?? (0, 0)
            byBank[bank] = (prev.0 + cny, prev.1 + 1)

            let prevCur = byCur[asset.currency] ?? (0, 0)
            byCur[asset.currency] = (prevCur.0 + native, prevCur.1 + cny)

            byKind[asset.kind, default: 0] += cny

            // 定存利息单独成行
            if asset.kind == .deposit {
                let interest = asset.accruedInterest(on: date)
                if interest > 0 {
                    rows.append(Row(
                        id: UUID(),
                        asset: asset,
                        cny: interest * rate,
                        native: interest,
                        isInterestRow: true
                    ))
                }
            }
        }

        return Result(
            totalCNY: total,
            liquidCNY: liquid,
            lockedCNY: total - liquid,
            byBank: byBank.map { (bank: $0.key, value: $0.value.0, count: $0.value.1) }
                .sorted { $0.value > $1.value },
            byCurrency: byCur.map { (currency: $0.key, natives: $0.value.0, cny: $0.value.1) }
                .sorted { $0.cny > $1.cny },
            byKind: byKind.map { (kind: $0.key, value: $0.value) }.sorted { $0.value > $1.value },
            rows: rows
        )
    }

    /// 今日涨跌：用昨日汇率重算昨日资产，剔除汇率波动干扰。
    func dailyChange(
        assets: [Asset],
        todayRates: [Currency: Decimal],
        yesterdayRates: [Currency: Decimal],
        goldToday: Decimal?,
        goldYesterday: Decimal?,
        on date: Date = .now
    ) -> (amount: Decimal, pct: Decimal) {
        let today = compute(assets: assets, rates: todayRates, goldCNYPerGram: goldToday, on: date)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        let prev = compute(assets: assets, rates: yesterdayRates, goldCNYPerGram: goldYesterday, on: yesterday)

        let diff = today.totalCNY - prev.totalCNY
        guard prev.totalCNY > 0 else { return (diff, 0) }
        let pct = diff / prev.totalCNY * 100
        return (diff, pct)
    }

    /// 保险：按长期预期收益反推年化后，算当前折现值
    /// FV = Σ premium × (1+r)^(payYears-1 - t)  ... 简化：用 IRR 对首期保费滚到今日
    static func impliedRate(premiumPerYear: Decimal, years: Int, maturityYears: Int, maturityValue: Decimal) -> Decimal? {
        // 二分法求解 r，使 Σ premium×(1+r)^(maturityYears-t) = maturityValue
        func fv(_ r: Double) -> Double {
            (0..<years).reduce(0.0) { sum, t in
                sum + (premiumPerYear as NSDecimalNumber).doubleValue * pow(1 + r, Double(maturityYears - t))
            }
        }
        let target = (maturityValue as NSDecimalNumber).doubleValue
        var lo = 0.0, hi = 0.3
        for _ in 0..<200 {
            let mid = (lo + hi) / 2
            if fv(mid) < target { lo = mid } else { hi = mid }
        }
        return Decimal(double: (lo + hi) / 2 * 100, scale: 3)
    }
}
