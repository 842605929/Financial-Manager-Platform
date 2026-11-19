import Foundation

enum NetworkError: LocalizedError {
    case badStatus(Int)
    case badEncoding
    case emptyBody

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): "接口返回 \(code)"
        case .badEncoding: "响应编码无法解析"
        case .emptyBody: "响应为空"
        }
    }
}

struct HTTPClient {
    static let shared = HTTPClient()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 15
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    /// 国内财经接口需要伪装 UA 和 Referer，否则返回 403
    enum Headers {
        static let sina = [
            "Referer": "https://finance.sina.com.cn",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
        ]
        static let eastmoneyFund = [
            "Referer": "https://fund.eastmoney.com/",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
        ]
        static let eastmoneyQuote = [
            "Referer": "https://quote.eastmoney.com/",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
        ]
    }

    func string(_ url: URL, headers: [String: String] = [:], retries: Int = 2) async throws -> String {
        var lastError: Error = NetworkError.emptyBody
        for attempt in 0...retries {
            do {
                var req = URLRequest(url: url)
                headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else { throw NetworkError.emptyBody }
                guard (200..<300).contains(http.statusCode) else { throw NetworkError.badStatus(http.statusCode) }
                guard let text = String(data: data, encoding: .utf8) else { throw NetworkError.badEncoding }
                return text
            } catch {
                lastError = error
                if attempt < retries {
                    try? await Task.sleep(nanoseconds: UInt64(300 * (attempt + 1)) * 1_000_000)
                }
            }
        }
        throw lastError
    }

    func json<T: Decodable>(_ url: URL, headers: [String: String] = [:], retries: Int = 2) async throws -> T {
        let text = try await string(url, headers: headers, retries: retries)
        guard let data = text.data(using: .utf8) else { throw NetworkError.badEncoding }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension Decimal {
    /// 由 Double 构造 Decimal 时走字符串，避免二进制误差
    init(double: Double, scale: Int = 6) {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = scale
        f.locale = Locale(identifier: "en_US_POSIX")
        let s = f.string(from: NSNumber(value: double)) ?? "\(double)"
        self = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }
}
