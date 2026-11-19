import Foundation
import SwiftData

/// 每日汇率缓存。key = "USD->CNY"，一一对应一天。
@Model
final class RateSnapshot {
    @Attribute(.unique) var key: String
    var base: String
    var quote: String
    var day: Date
    var rate: Decimal
    var fetchedAt: Date

    init(base: Currency, quote: Currency, day: Date, rate: Decimal) {
        let d = Calendar.current.startOfDay(for: day)
        self.key = "\(base.rawValue)->\(quote.rawValue)@\(d.timeIntervalSince1970)"
        self.base = base.rawValue
        self.quote = quote.rawValue
        self.day = d
        self.rate = rate
        self.fetchedAt = .now
    }
}

/// 每日资产快照。用于净值曲线与"今日涨跌"。
@Model
final class ValuationSnapshot {
    @Attribute(.unique) var dayKey: String
    var day: Date
    var totalCNY: Decimal
    var liquidCNY: Decimal
    var breakdownJSON: String
    var computedAt: Date

    init(day: Date, totalCNY: Decimal, liquidCNY: Decimal, breakdown: [BreakdownRow]) {
        let d = Calendar.current.startOfDay(for: day)
        self.dayKey = "\(d.timeIntervalSince1970)"
        self.day = d
        self.totalCNY = totalCNY
        self.liquidCNY = liquidCNY
        self.breakdownJSON = (try? JSONEncoder().encode(breakdown)).flatMap {
            String(data: $0, encoding: .utf8)
        } ?? "[]"
        self.computedAt = .now
    }

    var breakdown: [BreakdownRow] {
        guard let data = breakdownJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([BreakdownRow].self, from: data)) ?? []
    }
}

struct BreakdownRow: Codable, Identifiable {
    var id: String { "\(bank)-\(name)" }
    var bank: String
    var name: String
    var currency: String
    var native: Double
    var cny: Double
}

/// 历史行情点（金价、汇率趋势用）
@Model
final class PricePoint {
    @Attribute(.unique) var key: String
    var series: String      // "gold.cny" / "gold.usd" / "fx.USD"
    var day: Date
    var value: Decimal

    init(series: String, day: Date, value: Decimal) {
        let d = Calendar.current.startOfDay(for: day)
        self.key = "\(series)@\(d.timeIntervalSince1970)"
        self.series = series
        self.day = d
        self.value = value
    }
}
