import Foundation

/// 金价：新浪财经
/// - gds_AUTD：上金所 Au(T+D)，人民币/克
/// - hf_GC：COMEX 黄金期货，美元/盎司
struct GoldService {
    struct Quote {
        var cnyPerGram: Decimal?
        var usdPerOunce: Decimal?
        var updatedAt: Date?
    }

    static let gramsPerOunce: Decimal = 31.1035

    func latest() async throws -> Quote {
        var quote = Quote()
        async let autd = fetch("gds_AUTD")
        async let gc = fetch("hf_GC")

        if let fields = try? await autd, let p = fields.first, let v = Decimal(string: p) {
            quote.cnyPerGram = v
            if fields.count > 5 { quote.updatedAt = parseTime(fields[5]) }
        }
        if let fields = try? await gc, let p = fields.first, let v = Decimal(string: p) {
            quote.usdPerOunce = v
        }
        guard quote.cnyPerGram != nil || quote.usdPerOunce != nil else {
            throw NetworkError.emptyBody
        }
        return quote
    }

    /// 解析 `var hq_str_gds_AUTD="809.34,0,809.25,...";`
    private func fetch(_ symbol: String) async throws -> [String] {
        let url = URL(string: "https://hq.sinajs.cn/list=\(symbol)")!
        let text = try await HTTPClient.shared.string(url, headers: HTTPClient.Headers.sina)
        guard let start = text.firstIndex(of: "\""), let end = text.lastIndex(of: "\""), start < end else {
            throw NetworkError.badEncoding
        }
        let body = text[text.index(after: start)..<end]
        let fields = body.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard let first = fields.first, !first.isEmpty else { throw NetworkError.emptyBody }
        return fields
    }

    private func parseTime(_ raw: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f.date(from: raw)
    }
}
