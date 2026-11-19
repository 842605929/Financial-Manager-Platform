import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    var store: MarketDataStore
    @Environment(\.modelContext) private var context

    @State private var mode: TrendMode = .fx
    @State private var pair: Currency = .usd
    @State private var range: TrendRange = .month

    @State private var fxSeries: [Point] = []
    @State private var goldSeries: [Point] = []
    @State private var loading = false

    enum TrendMode: String, CaseIterable { case fx = "汇率", gold = "金价", net = "我的资产" }
    enum TrendRange: String, CaseIterable {
        case day = "日", week = "周", month = "月", year = "年"
        var days: Int {
            switch self {
            case .day: 1
            case .week: 7
            case .month: 30
            case .year: 365
            }
        }
    }

    struct Point: Identifiable {
        var id: Date { date }
        let date: Date
        let value: Double
    }

    @Query(sort: \ValuationSnapshot.day) private var snapshots: [ValuationSnapshot]

    private var series: [Point] {
        switch mode {
        case .fx: fxSeries
        case .gold: goldSeries
        case .net: snapshots.map {
            Point(date: $0.day, value: NSDecimalNumber(decimal: $0.totalCNY).doubleValue)
        }
        }
    }

    private var filtered: [Point] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -range.days, to: .now) ?? .distantPast
        return series.filter { $0.date >= cutoff }
    }

    private var title: String {
        switch mode {
        case .fx: "\(pair.rawValue) / CNY"
        case .gold: "上金所 Au(T+D) · 元/克"
        case .net: "我的资产 · 折人民币"
        }
    }

    private var lastValue: Double { filtered.last?.value ?? series.last?.value ?? 0 }
    private var firstValue: Double { filtered.first?.value ?? 0 }
    private var pct: Double {
        guard firstValue != 0 else { return 0 }
        return (lastValue - firstValue) / firstValue * 100
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("模式", selection: $mode) {
                        ForEach(TrendMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _, _ in Task { await load() } }

                    if mode == .fx {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach([Currency.usd, .hkd, .jpy], id: \.self) { c in
                                    Chip(title: "\(c.rawValue)/CNY", selected: pair == c) {
                                        pair = c
                                        Task { await load() }
                                    }
                                }
                            }
                        }
                    }

                    Card(title: title, hint: nil) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(displayValue(lastValue))
                                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                Text(String(format: "%+.2f%%", pct))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(pct >= 0 ? Color.red : Color.green)
                            }

                            if filtered.count < 2 {
                                Text(loading ? "加载中…" : "数据不足，先刷新一次")
                                    .font(.footnote).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 150)
                            } else {
                                Chart(filtered) { p in
                                    AreaMark(
                                        x: .value("日期", p.date),
                                        y: .value("值", p.value)
                                    )
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [(pct >= 0 ? Color.red : Color.green).opacity(0.22), .clear],
                                            startPoint: .top, endPoint: .bottom
                                        )
                                    )
                                    LineMark(
                                        x: .value("日期", p.date),
                                        y: .value("值", p.value)
                                    )
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(pct >= 0 ? Color.red : Color.green)
                                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                                }
                                .chartYScale(domain: yDomain)
                                .chartXAxis(.hidden)
                                .frame(height: 160)
                            }

                            Picker("区间", selection: $range) {
                                ForEach(TrendRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)

                            HStack {
                                stat("区间高", filtered.map(\.value).max())
                                Divider().frame(height: 26)
                                stat("区间低", filtered.map(\.value).min())
                                Divider().frame(height: 26)
                                stat("区间涨跌", nil, text: String(format: "%+.2f%%", pct))
                            }
                            .padding(.top, 8)
                        }
                    }

                    if mode != .net {
                        Card(title: "数据说明", hint: nil) {
                            Text("汇率取自 ECB 官方参考价（Frankfurter），工作日更新，周末与节假日无数据，图表按相邻交易日连线。金价取自新浪财经上金所 Au(T+D)，交易时段实时。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(red: 0.949, green: 0.953, blue: 0.969))
            .navigationTitle("趋势")
            .task { await load() }
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = filtered.map(\.value)
        guard let lo = values.min(), let hi = values.max(), lo != hi else {
            return (values.first ?? 0) ... ((values.first ?? 0) + 1)
        }
        let pad = (hi - lo) * 0.15
        return (lo - pad) ... (hi + pad)
    }

    private func displayValue(_ v: Double) -> String {
        if mode == .net { return Formatter.money(Decimal(double: v)) }
        if mode == .gold { return String(format: "%.2f", v) }
        return String(format: "%.4f", v)
    }

    private func stat(_ key: String, _ value: Double?, text: String? = nil) -> some View {
        VStack(spacing: 4) {
            Text(key).font(.caption2).foregroundStyle(.secondary)
            Text(text ?? (value.map { mode == .net ? Formatter.money(Decimal(double: $0)) : String(format: "%.\(mode == .gold ? 2 : 4)f", $0) } ?? "—"))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        loading = true
        defer { loading = false }

        switch mode {
        case .fx:
            // 汇率历史：ECB 日线，一次拉够一年
            let from = Calendar.current.date(byAdding: .day, value: -370, to: .now) ?? .now
            if pair == .usd {
                if let hist = try? await RateService().usdCNYHistory(from: from, to: .now), !hist.isEmpty {
                    fxSeries = hist.map { Point(date: $0.0, value: NSDecimalNumber(decimal: $0.1).doubleValue) }
                    persistFX(hist, pair)
                } else {
                    fxSeries = loadFXFromStore(pair)
                }
            } else {
                // 交叉汇率：USD/CNY 除以 USD/该币种（简化处理，直接读缓存）
                fxSeries = loadFXFromStore(pair)
            }

        case .gold:
            let desc = FetchDescriptor<PricePoint>(
                predicate: #Predicate { $0.series == "gold.cny" },
                sortBy: [SortDescriptor(\.day)]
            )
            let points = (try? context.fetch(desc)) ?? []
            goldSeries = points.map { Point(date: $0.day, value: NSDecimalNumber(decimal: $0.value).doubleValue) }

        case .net:
            break
        }
    }

    private func persistFX(_ hist: [(Date, Decimal)], _ cur: Currency) {
        for (day, rate) in hist {
            context.insert(RateSnapshot(base: cur, quote: .cny, day: day, rate: rate))
        }
        try? context.save()
    }

    private func loadFXFromStore(_ cur: Currency) -> [Point] {
        let code = cur.rawValue
        let desc = FetchDescriptor<RateSnapshot>(
            predicate: #Predicate { $0.base == code && $0.quote == "CNY" },
            sortBy: [SortDescriptor(\.day)]
        )
        let snaps = (try? context.fetch(desc)) ?? []
        var seen = Set<Date>()
        return snaps.filter { seen.insert($0.day).inserted }
            .map { Point(date: $0.day, value: NSDecimalNumber(decimal: $0.rate).doubleValue) }
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selected ? Color(red: 0.08, green: 0.09, blue: 0.13) : .white)
                .foregroundStyle(selected ? .white : Color(white: 0.35))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(white: 0.9), lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}
