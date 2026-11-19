import Foundation
import SwiftData

enum AssetKind: String, Codable, CaseIterable, Identifiable {
    case cash, deposit, fund, stock, gold, insurance
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: "活期"
        case .deposit: "定存"
        case .fund: "基金"
        case .stock: "股票"
        case .gold: "黄金"
        case .insurance: "保险"
        }
    }

    /// 可动用资产：不含定存（锁定期）与保险（退保价值不可随时支取）
    var isLiquid: Bool {
        switch self {
        case .cash, .fund, .stock, .gold: true
        case .deposit, .insurance: false
        }
    }
}

enum Currency: String, Codable, CaseIterable, Identifiable {
    case cny = "CNY", usd = "USD", hkd = "HKD", jpy = "JPY"
    var id: String { rawValue }

    var name: String {
        switch self {
        case .cny: "人民币"
        case .usd: "美元"
        case .hkd: "港币"
        case .jpy: "日元"
        }
    }

    var symbol: String {
        switch self {
        case .cny, .jpy: "¥"
        case .usd: "$"
        case .hkd: "HK$"
        }
    }
}

/// 录入方式：直接填金额，或填 数量 × 单价
enum QtyMode: String, Codable {
    case amount, qty
}

/// 保险估值口径
enum ValueBasis: String, Codable {
    case irr       // 按长期预期收益折现的现值
    case premium   // 按已缴保费计入
    case cashValue // 按官方退保价值
}

@Model
final class Asset {
    var id: UUID
    var name: String
    var bank: String
    var kindRaw: String
    var currencyRaw: String
    var qtyModeRaw: String

    // 金额口径或数量口径
    var amount: Decimal
    var quantity: Decimal
    var unitPrice: Decimal?

    var code: String?          // 基金/股票代码
    var expiry: Date?          // 定存到期日
    var apy: Decimal?          // 定存年利率（百分数，如 4.1）
    var startedAt: Date?       // 定存起存日

    // 保险
    var premium: Decimal?      // 已缴保费
    var impliedRate: Decimal?  // 折现年化（百分数）
    var payYears: Int?
    var sumAssured: Decimal?
    var valueBasisRaw: String?

    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        bank: String,
        kind: AssetKind,
        currency: Currency,
        qtyMode: QtyMode = .amount,
        amount: Decimal = 0,
        quantity: Decimal = 0,
        unitPrice: Decimal? = nil,
        code: String? = nil,
        expiry: Date? = nil,
        apy: Decimal? = nil,
        startedAt: Date? = nil,
        premium: Decimal? = nil,
        impliedRate: Decimal? = nil,
        payYears: Int? = nil,
        sumAssured: Decimal? = nil,
        valueBasis: ValueBasis? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.bank = bank
        self.kindRaw = kind.rawValue
        self.currencyRaw = currency.rawValue
        self.qtyModeRaw = qtyMode.rawValue
        self.amount = amount
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.code = code
        self.expiry = expiry
        self.apy = apy
        self.startedAt = startedAt
        self.premium = premium
        self.impliedRate = impliedRate
        self.payYears = payYears
        self.sumAssured = sumAssured
        self.valueBasisRaw = valueBasis?.rawValue
        self.createdAt = .now
        self.updatedAt = .now
    }
}

extension Asset {
    var kind: AssetKind {
        get { AssetKind(rawValue: kindRaw) ?? .cash }
        set { kindRaw = newValue.rawValue }
    }

    var currency: Currency {
        get { Currency(rawValue: currencyRaw) ?? .cny }
        set { currencyRaw = newValue.rawValue }
    }

    var qtyMode: QtyMode {
        get { QtyMode(rawValue: qtyModeRaw) ?? .amount }
        set { qtyModeRaw = newValue.rawValue }
    }

    var valueBasis: ValueBasis? {
        get { valueBasisRaw.flatMap(ValueBasis.init(rawValue:)) }
        set { valueBasisRaw = newValue?.rawValue }
    }

    /// 原币价值。定存拆本金/利息两条，利息按持有天数实时计算。
    func nativeValue(on date: Date = .now) -> Decimal {
        switch kind {
        case .insurance:
            return amount
        case .deposit:
            guard let apy, apy > 0 else { return amount }
            let start = startedAt ?? Calendar.current.date(byAdding: .month, value: -6, to: expiry ?? date) ?? date
            let days = Decimal(Calendar.current.dateComponents([.day], from: start, to: date).day ?? 0)
            let interest = amount * apy / 100 * days / 365
            return amount + interest
        case .gold, .fund, .stock:
            if qtyMode == .qty {
                return quantity * (unitPrice ?? 0)
            }
            return amount
        case .cash:
            return amount
        }
    }

    /// 定存当前已计利息（单独成行展示）
    func accruedInterest(on date: Date = .now) -> Decimal {
        guard kind == .deposit, let apy, apy > 0 else { return 0 }
        let start = startedAt ?? Calendar.current.date(byAdding: .month, value: -6, to: expiry ?? date) ?? date
        let days = Decimal(Calendar.current.dateComponents([.day], from: start, to: date).day ?? 0)
        return amount * apy / 100 * days / 365
    }

    var isLiquid: Bool { kind.isLiquid }
}
