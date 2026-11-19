import Foundation
import SwiftData

enum SeedData {
    static func installIfNeeded(_ ctx: ModelContext) async {
        let existing = (try? ctx.fetchCount(FetchDescriptor<Asset>())) ?? 0
        guard existing == 0 else { return }

        let cal = Calendar(identifier: .gregorian)
        let expiry = cal.date(from: DateComponents(year: 2027, month: 4, day: 28))
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 28))

        let items: [Asset] = [
            Asset(name: "富兰克林生物基金 21066", bank: "招商永隆", kind: .fund, currency: .hkd,
                  amount: 9820.02, code: "21066"),
            Asset(name: "博时美元 76003", bank: "招商永隆", kind: .fund, currency: .usd,
                  amount: 1499.98, code: "76003"),
            Asset(name: "美元定存", bank: "招商永隆", kind: .deposit, currency: .usd,
                  amount: 4000, expiry: expiry, apy: 4.1, startedAt: start),
            Asset(name: "永隆灵活资金", bank: "招商永隆", kind: .cash, currency: .hkd,
                  amount: 8579.24),
            Asset(name: "众安银行活期", bank: "众安银行", kind: .cash, currency: .hkd,
                  amount: 3488),
            Asset(name: "黄金持有", bank: "其他", kind: .gold, currency: .cny,
                  qtyMode: .qty, quantity: 7.45, unitPrice: 809.34),
            Asset(name: "信守明天多元货币计划", bank: "保诚", kind: .insurance, currency: .usd,
                  amount: 10017.33, premium: 10000, impliedRate: 2.915, payYears: 5,
                  valueBasis: .irr),
            Asset(name: "重疾险", bank: "保诚", kind: .insurance, currency: .usd,
                  amount: 2385.38, premium: 2385.38, sumAssured: 100000,
                  valueBasis: .premium),
        ]

        items.forEach { ctx.insert($0) }
        try? ctx.save()
    }
}
