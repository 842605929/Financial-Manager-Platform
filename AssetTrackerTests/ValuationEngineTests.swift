import XCTest
import SwiftData
@testable import AssetTracker

final class ValuationEngineTests: XCTestCase {

    private func asset(
        kind: AssetKind,
        currency: Currency,
        amount: Decimal,
        qtyMode: QtyMode = .amount,
        quantity: Decimal = 0,
        unitPrice: Decimal? = nil
    ) -> Asset {
        Asset(
            name: "test", bank: "testbank", kind: kind, currency: currency,
            qtyMode: qtyMode, amount: amount, quantity: quantity, unitPrice: unitPrice
        )
    }

    func testForeignCurrencyConversion() {
        let a = asset(kind: .cash, currency: .usd, amount: 1000)
        let result = ValuationEngine().compute(assets: [a], rates: [.cny: 1, .usd: 6.6661])
        XCTAssertEqual(result.totalCNY, 6666.1)
    }

    func testLiquidExcludesDepositAndInsurance() {
        let cash = asset(kind: .cash, currency: .cny, amount: 10000)
        let dep = asset(kind: .deposit, currency: .cny, amount: 50000)
        let ins = asset(kind: .insurance, currency: .cny, amount: 20000)

        let r = ValuationEngine().compute(assets: [cash, dep, ins], rates: [.cny: 1])
        XCTAssertEqual(r.totalCNY, 80000)
        XCTAssertEqual(r.liquidCNY, 10000)
        XCTAssertEqual(r.lockedCNY, 70000)
    }

    func testQtyTimesPrice() {
        let gold = asset(
            kind: .gold, currency: .cny, amount: 0,
            qtyMode: .qty, quantity: 100, unitPrice: 809.34
        )
        let r = ValuationEngine().compute(assets: [gold], rates: [.cny: 1])
        XCTAssertEqual(r.totalCNY, 80934)
    }

    func testGoldRevaluationUsesLivePrice() {
        let gold = asset(
            kind: .gold, currency: .cny, amount: 0,
            qtyMode: .qty, quantity: 7.45, unitPrice: 800
        )
        let r = ValuationEngine().compute(assets: [gold], rates: [.cny: 1], goldCNYPerGram: 809.34)
        XCTAssertEqual(r.totalCNY, Decimal(string: "6029.583") ?? 0, accuracy: 0.001)
    }

    func testDepositAccrual() {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 28))!
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 19))!
        let expiry = cal.date(from: DateComponents(year: 2027, month: 4, day: 28))!

        let dep = Asset(
            name: "dep", bank: "b", kind: .deposit, currency: .usd,
            amount: 4000, expiry: expiry, apy: 4.1, startedAt: start
        )
        let interest = dep.accruedInterest(on: today)
        // 22 天，4000 × 4.1% × 22/365 ≈ 9.88
        XCTAssertEqual(NSDecimalNumber(decimal: interest).doubleValue, 9.88, accuracy: 0.05)
    }

    func testDailyChangeUsesYesterdayRates() {
        let a = asset(kind: .cash, currency: .usd, amount: 1000)
        let change = ValuationEngine().dailyChange(
            assets: [a],
            todayRates: [.cny: 1, .usd: 7.0],
            yesterdayRates: [.cny: 1, .usd: 6.5],
            goldToday: nil,
            goldYesterday: nil
        )
        // 汇率变动本身应体现为涨跌：1000×(7.0−6.5) = 500
        XCTAssertEqual(change.amount, 500)
    }

    func testImpliedRateSolvesToMaturityValue() {
        let r = ValuationEngine.impliedRate(
            premiumPerYear: 10000, years: 5, maturityYears: 10, maturityValue: 62972
        )
        let unwrapped = NSDecimalNumber(decimal: r ?? 0).doubleValue
        XCTAssertEqual(unwrapped, 2.915, accuracy: 0.01)
    }

    func testByBankGrouping() {
        let a = Asset(name: "a", bank: "永隆", kind: .cash, currency: .cny, amount: 1000)
        let b = Asset(name: "b", bank: "永隆", kind: .cash, currency: .cny, amount: 500)
        let c = Asset(name: "c", bank: "众安", kind: .cash, currency: .cny, amount: 2000)

        let r = ValuationEngine().compute(assets: [a, b, c], rates: [.cny: 1])
        XCTAssertEqual(r.byBank.first?.bank, "众安")
        XCTAssertEqual(r.byBank.first?.value, 2000)
        XCTAssertEqual(r.byBank.last?.count, 2)
    }
}
