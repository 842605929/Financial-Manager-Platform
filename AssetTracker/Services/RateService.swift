import Foundation

/// 汇率：Frankfurter（ECB 参考价，工作日更新），失败时兜底 open.er-api
struct RateService {
    struct FrankfurterResponse: Decodable {
        let amount: Double
        let base: String
        let date: String
        let rates: [String: Double]
    }

    struct ERAPIResponse: Decodable {
        let result: String
        let rates: [String: Double]
    }

    /// 返回 ["USD": 6.6661, "HKD": 0.8496, ...]（1 外币 = X 人民币）
    func latestCNYRates() async throws -> [Currency: Decimal] {
        do {
            return try await frankfurter()
        } catch {
            return try await fallback()
        }
    }

    private func frankfurter() async throws -> [Currency: Decimal] {
        // 以 USD 为 base 一次拿全部目标币种，避免多次请求
        let symbols = "CNY,HKD,JPY"
        let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=USD&symbols=\(symbols)")!
        let r: FrankfurterResponse = try await HTTPClient.shared.json(url)

        // r.rates 是 1 USD = X 各币种；换算成 1 外币 = X CNY
        var out: [Currency: Decimal] = [.cny: 1]
        guard let usdToCNY = r.rates["CNY"], usdToCNY > 0 else {
            throw NetworkError.emptyBody
        }
        out[.usd] = Decimal(double: usdToCNY)
        for (code, perUSD) in r.rates where perUSD > 0 {
            guard let cur = Currency(rawValue: code), cur != .cny else { continue }
            // 1 CUR = (1/USD->CUR) USD = (USD->CNY / USD->CUR) CNY
            let perCurToCNY = usdToCNY / perUSD
            out[cur] = Decimal(double: perCurToCNY)
        }
        return out
    }

    private func fallback() async throws -> [Currency: Decimal] {
        let url = URL(string: "https://open.er-api.com/v6/latest/USD")!
        let r: ERAPIResponse = try await HTTPClient.shared.json(url)
        guard let usdToCNY = r.rates["CNY"], usdToCNY > 0 else { throw NetworkError.emptyBody }
        var out: [Currency: Decimal] = [.cny: 1, .usd: Decimal(double: usdToCNY)]
        for (code, perUSD) in r.rates where perUSD > 0 {
            guard let cur = Currency(rawValue: code), cur != .cny else { continue }
            out[cur] = Decimal(double: usdToCNY / perUSD)
        }
        return out
    }

    /// 历史日线，用于汇率趋势图。返回 [(日期, 1 USD = X CNY)]
    func usdCNYHistory(from: Date, to: Date) async throws -> [(Date, Decimal)] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        let a = fmt.string(from: from), b = fmt.string(from: to)
        let url = URL(string: "https://api.frankfurter.dev/v1/\(a)..\(b)?base=USD&symbols=CNY")!

        struct Resp: Decodable {
            let rates: [String: [String: Double]]
        }
        let r: Resp = try await HTTPClient.shared.json(url)
        return r.rates
            .compactMap { key, val -> (Date, Decimal)? in
                guard let cny = val["CNY"], let date = fmt.date(from: key) else { return nil }
                return (date, Decimal(double: cny))
            }
            .sorted { $0.0 < $1.0 }
    }
}
