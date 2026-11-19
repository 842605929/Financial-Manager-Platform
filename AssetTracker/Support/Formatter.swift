import Foundation

enum Formatter {
    private static let moneyFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = .current
        return f
    }()

    private static let plain: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.locale = .current
        return f
    }()

    static func money(_ d: Decimal) -> String {
        "¥" + (moneyFmt.string(from: d as NSDecimalNumber) ?? "0.00")
    }

    static func decimal(_ d: Decimal) -> String {
        plain.string(from: d as NSDecimalNumber) ?? "0"
    }

    static func decimal(_ d: Decimal?, digits: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: (d ?? 0) as NSDecimalNumber) ?? "0"
    }

    static func signed(_ d: Decimal) -> String {
        let sign = d >= 0 ? "+" : "−"
        return sign + "¥" + (moneyFmt.string(from: abs(d) as NSDecimalNumber) ?? "0.00")
    }

    static func percent(_ d: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return (f.string(from: d as NSDecimalNumber) ?? "0") + "%"
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    static func day(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f.string(from: d)
    }
}
