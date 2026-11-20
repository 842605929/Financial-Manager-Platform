import SwiftUI
import SwiftData
import Charts

struct OverviewView: View {
    var store: MarketDataStore
    @Environment(\.modelContext) private var context
    @Query(sort: \ValuationSnapshot.day, order: .reverse) private var snapshots: [ValuationSnapshot]

    @State private var view: ViewMode = .all
    @State private var editing: Asset?
    @State private var showingAdd = false

    enum ViewMode: String, CaseIterable { case all = "全部资产", liquid = "可动用" }

    private var result: ValuationEngine.Result { store.valuation }
    private var total: Decimal { view == .all ? result.totalCNY : result.liquidCNY }
    private var change: (amount: Decimal, pct: Decimal) { store.todayChange }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("视图", selection: $view) {
                        ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    heroCard
                    donutCard
                    bankCard
                    currencyCard
                    trendCard
                    assetCard
                    if view == .all { insuranceCard }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(red: 0.949, green: 0.953, blue: 0.969))
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing) { asset in
                AssetEditorView(asset: asset)
            }
            .sheet(isPresented: $showingAdd) {
                AssetEditorView(asset: nil)
            }
            .refreshable { await store.refresh() }
            .onAppear { store.updateAssets(allAssets) }
        }
    }

    @Query(sort: \Asset.createdAt) private var allAssets: [Asset]

    // MARK: - 卡片

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("\(view == .all ? "总资产" : "可动用资产") · 人民币计价")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.63))
            }
            Text(Formatter.money(total))
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()

            HStack(spacing: 8) {
                Text(Formatter.signed(change.amount))
                Text("(\(change.pct >= 0 ? "+" : "")\(Formatter.decimal(change.pct))%)")
                Text("今日")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 0.89, green: 0.23, blue: 0.23).opacity(0.16))
                    .clipShape(Capsule())
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(change.amount >= 0 ? Color(red: 1, green: 0.45, blue: 0.45) : Color(red: 0.28, green: 0.84, blue: 0.55))

            Divider().overlay(Color.white.opacity(0.1))

            HStack {
                Text(view == .all ? "其中锁定" : "已排除")
                + Text(" " + Formatter.money(result.lockedCNY)).fontWeight(.medium)
                Spacer()
                Text(store.lastRefresh.map { Formatter.time($0) } ?? "—")
            }
            .font(.caption2)
            .foregroundStyle(Color(white: 0.55))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.086, green: 0.098, blue: 0.15), Color(red: 0.14, green: 0.16, blue: 0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var donutCard: some View {
        Card(title: "资产构成", hint: "按类别") {
            HStack(spacing: 18) {
                Chart(result.byKind, id: \.kind) { item in
                    SectorMark(
                        angle: .value("金额", NSDecimalNumber(decimal: item.value).doubleValue),
                        innerRadius: .ratio(0.62),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("类别", item.kind.title))
                    .cornerRadius(3)
                }
                .chartLegend(.hidden)
                .frame(width: 108, height: 108)

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(result.byKind, id: \.kind) { item in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.forKind(item.kind))
                                .frame(width: 9, height: 9)
                            Text(item.kind.title).font(.subheadline)
                            Spacer()
                            Text(Formatter.percent(item.value / max(result.totalCNY, 1) * 100))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private var bankCard: some View {
        Card(title: "按银行汇总", hint: "\(result.byBank.count) 个机构") {
            VStack(spacing: 13) {
                ForEach(Array(result.byBank.enumerated()), id: \.offset) { idx, item in
                    BarRow(
                        title: item.bank,
                        subtitle: "\(item.count) 项",
                        value: item.value,
                        total: result.totalCNY,
                        ratio: Double(truncating: (item.value / max(result.byBank.first?.value ?? 1, 1)) as NSDecimalNumber),
                        color: Color.barColors[idx % Color.barColors.count]
                    )
                }
            }
        }
    }

    private var currencyCard: some View {
        Card(title: "币种敞口", hint: "折人民币") {
            VStack(spacing: 13) {
                ForEach(Array(result.byCurrency.enumerated()), id: \.offset) { idx, item in
                    BarRow(
                        title: item.currency.rawValue,
                        subtitle: item.currency.name,
                        value: item.cny,
                        total: result.totalCNY,
                        ratio: Double(truncating: (item.cny / max(result.byCurrency.first?.cny ?? 1, 1)) as NSDecimalNumber),
                        color: Color.barColors[idx % Color.barColors.count]
                    )
                }
            }
        }
    }

    private var trendCard: some View {
        Card(title: "净值走势", hint: "近 30 天") {
            if snapshots.count < 2 {
                Text("积累满 2 天后开始显示")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                Chart(snapshots.prefix(30).reversed(), id: \.dayKey) { snap in
                    LineMark(
                        x: .value("日期", snap.day),
                        y: .value("金额", NSDecimalNumber(decimal: snap.totalCNY).doubleValue)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.blue)
                    AreaMark(
                        x: .value("日期", snap.day),
                        y: .value("金额", NSDecimalNumber(decimal: snap.totalCNY).doubleValue)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(colors: [.blue.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                    )
                }
                .chartYAxis(.hidden)
                .chartXAxis(.hidden)
                .frame(height: 120)
            }
        }
    }

    private var assetCard: some View {
        Card(title: "资产明细", hint: view == .all ? "全部折人民币" : "仅可动用") {
            VStack(spacing: 0) {
                ForEach(visibleRows) { row in
                    AssetRowView(row: row, store: store) { editing = row.asset }
                }
                if visibleRows.isEmpty {
                    Text("当前视图下无资产").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 12)
                }
            }
        }
    }

    private var insuranceCard: some View {
        Card(title: "保险", hint: "退保价值，非可用资金") {
            VStack(spacing: 0) {
                ForEach(result.rows.filter { $0.asset.kind == .insurance }) { row in
                    AssetRowView(row: row, store: store) { editing = row.asset }
                }
                Text("保险以退保价值计入，不等于保额或已缴保费。非保证红利会随投资表现浮动。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var visibleRows: [ValuationEngine.Row] {
        let rows = result.rows.filter { $0.asset.kind != .insurance }
        return view == .all ? rows : rows.filter { $0.asset.isLiquid }
    }
}

// MARK: - 组件

struct Card<Content: View>: View {
    let title: String
    var hint: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let hint { Text(hint).font(.caption2).foregroundStyle(Color(white: 0.7)) }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct BarRow: View {
    let title: String
    let subtitle: String
    let value: Decimal
    let total: Decimal
    let ratio: Double
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.subheadline)
                Text(subtitle).font(.caption2).foregroundStyle(Color(white: 0.68))
                Spacer()
                Text("\(Formatter.money(value)) · \(Formatter.percent(value / max(total, 1) * 100))")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.95))
                    Capsule().fill(color).frame(width: max(geo.size.width * ratio, 8))
                }
            }
            .frame(height: 7)
        }
    }
}

struct AssetRowView: View {
    let row: ValuationEngine.Row
    let store: MarketDataStore
    let onTap: () -> Void

    private var a: Asset { row.asset }
    private var sub: String {
        let base = a.bank.isEmpty ? "其他" : a.bank
        if a.kind == .insurance {
            if a.valueBasis == .irr {
                return "\(base) · 现值 · 年化 \(Formatter.decimal(a.impliedRate ?? 0))%"
            }
            return "\(base) · 已缴 \(a.currency.symbol)\(Formatter.decimal(a.premium ?? 0))"
        }
        if a.kind == .deposit {
            return row.isInterestRow ? "\(base) · 已计利息 · 年息 \(Formatter.decimal(a.apy ?? 0))%" : "\(base) · 本金 · 年息 \(Formatter.decimal(a.apy ?? 0))%"
        }
        if a.qtyMode == .qty, let unit = a.unitPrice {
            let unitLabel = a.kind == .gold ? "克" : a.kind == .fund ? "份" : "股"
            return "\(base) · \(Formatter.decimal(a.quantity)) \(unitLabel) × \(a.currency.symbol)\(Formatter.decimal(unit))"
        }
        return "\(base) · \(a.currency.name) · \(a.kind.title)"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(iconText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.forKind(a.kind), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(a.name).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(Formatter.money(row.cny))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text("\(a.currency.symbol)\(Formatter.decimal(row.native))")
                        .font(.caption2)
                        .foregroundStyle(Color(white: 0.62))
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(white: 0.93)).frame(height: 1).padding(.leading, 50)
        }
    }

    private var iconText: String {
        switch a.kind {
        case .gold: "Au"
        case .fund: "基"
        case .stock: "股"
        case .insurance: "保"
        case .cash, .deposit: a.currency.rawValue
        }
    }
}

extension Color {
    static let barColors: [Color] = [
        Color(red: 0.18, green: 0.42, blue: 1.0),
        Color(red: 0.55, green: 0.36, blue: 0.96),
        Color(red: 0.96, green: 0.62, blue: 0.04),
        Color(red: 0.06, green: 0.72, blue: 0.50),
    ]

    static func forKind(_ kind: AssetKind) -> Color {
        switch kind {
        case .cash, .deposit: Color(red: 0.18, green: 0.42, blue: 1.0)
        case .fund: Color(red: 0.55, green: 0.36, blue: 0.96)
        case .stock: Color(red: 0.91, green: 0.35, blue: 0.05)
        case .gold: Color(red: 0.96, green: 0.62, blue: 0.04)
        case .insurance: Color(red: 0.23, green: 0.36, blue: 0.86)
        }
    }
}
