import Foundation

/// 基金行情
/// - 场内 ETF：东财 push2 实时报价
/// - 场外基金：东财 f10/lsjz 最新确认净值（收盘后更新，无盘中估值）
struct FundService {

    enum Market: String {
        case otc, sh, sz
    }

    struct Quote {
        var code: String
        var name: String?
        var price: Decimal?      // 净值或报价
        var changePct: Decimal?  // 涨跌幅 %
        var asOf: Date?          // 净值日期 / 报价时间
        var isRealtime: Bool
        var note: String?
    }

    /// 场内：secid 前缀 1=沪 0=深
    func realtime(code: String, market: Market) async throws -> Quote {
        let prefix = market == .sh ? "1" : "0"
        let fields = "f43,f57,f58,f60,f170"
        let url = URL(string: "https://push2.eastmoney.com/api/qt/stock/get?secid=\(prefix).\(code)&fields=\(fields)&ut=fa5fd1943c7b386f172d6893dbfba10b")!

        struct Resp: Decodable {
            struct Data: Decodable {
                let f43: Double?
                let f57: String?
                let f58: String?
                let f60: Double?
                let f170: Double?
            }
            let data: Data?
        }

        let r: Resp = try await HTTPClient.shared.json(url, headers: HTTPClient.Headers.eastmoneyQuote)
        guard let d = r.data, let raw = d.f43, raw > 0 else { throw NetworkError.emptyBody }

        return Quote(
            code: code,
            name: d.f58,
            price: Decimal(double: raw / 1000, scale: 4),
            changePct: d.f170.map { Decimal(double: $0 / 100, scale: 3) },
            asOf: .now,
            isRealtime: true,
            note: nil
        )
    }

    /// 场外：最新确认净值
    func latestNAV(code: String) async throws -> Quote {
        let url = URL(string: "https://api.fund.eastmoney.com/f10/lsjz?fundCode=\(code)&pageIndex=1&pageSize=1")!

        struct Resp: Decodable {
            struct Data: Decodable {
                let LSJZList: [Item]
            }
            struct Item: Decodable {
                let FSRQ: String
                let DWJZ: String
                let JZZZL: String?
            }
            let Data: Data?
        }

        let r: Resp = try await HTTPClient.shared.json(url, headers: HTTPClient.Headers.eastmoneyFund)
        guard let item = r.Data?.LSJZList.first, let nav = Decimal(string: item.DWJZ) else {
            throw NetworkError.emptyBody
        }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")

        return Quote(
            code: code,
            name: nil,
            price: nav,
            changePct: item.JZZZL.flatMap { Decimal(string: $0) },
            asOf: f.date(from: item.FSRQ),
            isRealtime: false,
            note: "净值日期 \(item.FSRQ)"
        )
    }
}
