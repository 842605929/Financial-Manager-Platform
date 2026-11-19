import SwiftUI
import SwiftData

struct DetailView: View {
    var store: MarketDataStore
    @Query(sort: \ValuationSnapshot.day, order: .reverse) private var snapshots: [ValuationSnapshot]

    private var recent: [ValuationSnapshot] { Array(snapshots.prefix(7)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Card(title: "每日快照", hint: "近 7 天") {
                        if recent.isEmpty {
                            Text("还没有快照，下拉刷新后生成").font(.footnote).foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(recent.enumerated()), id: \.element.dayKey) { idx, snap in
                                    HStack {
                                        Text(Formatter.day(snap.day)).font(.subheadline)
                                        Spacer()
                                        Text(Formatter.money(snap.totalCNY))
                                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                                        delta(idx)
                                            .frame(width: 88, alignment: .trailing)
                                    }
                                    .padding(.vertical, 10)
                                    .overlay(alignment: .bottom) {
                                        Rectangle().fill(Color(white: 0.93)).frame(height: 1)
                                    }
                                }
                            }
                        }
                    }

                    Card(title: "数据源状态", hint: nil) {
                        VStack(spacing: 0) {
                            StatusRow(label: "汇率 · Frankfurter (ECB)", detail: store.status["汇率"] ?? "未更新")
                            StatusRow(label: "金价 · 上金所 Au(T+D)", detail: store.status["金价"] ?? "未更新")
                            StatusRow(label: "场外基金 · 东财净值", detail: "需配置代码后拉取")
                            StatusRow(label: "场内 ETF · 东财实时", detail: "需配置代码后拉取")
                        }
                        if let err = store.lastError {
                            Text(err).font(.caption2).foregroundStyle(.red).padding(.top, 8)
                        }
                    }

                    Card(title: "计价规则", hint: nil) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("每个资产 = 原币数量 × 单价 × 汇率 → 人民币")
                            Text("今日涨跌使用昨日汇率重算昨日资产，避免把汇率波动误算成资产增长。")
                            Text("定存拆为「本金 + 已计利息」两条，利息按持有天数实时计算。")
                            Text("保险按退保价值计入，不等于保额，也不等于已缴保费。")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Card(title: "当前汇率", hint: nil) {
                        VStack(spacing: 0) {
                            ForEach(Currency.allCases.filter { $0 != .cny }) { c in
                                HStack {
                                    Text("1 \(c.rawValue)").font(.subheadline)
                                    Spacer()
                                    Text(Formatter.decimal(store.rates[c] ?? 0, digits: 4) + " CNY")
                                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                                }
                                .padding(.vertical, 9)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(red: 0.949, green: 0.953, blue: 0.969))
            .navigationTitle("明细")
            .refreshable { await store.refresh() }
        }
    }

    @ViewBuilder
    private func delta(_ idx: Int) -> some View {
        let newer = recent[idx]
        if idx + 1 < recent.count {
            let older = recent[idx + 1]
            let diff = newer.totalCNY - older.totalCNY
            Text(Formatter.signed(diff))
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(diff >= 0 ? Color.red : Color.green)
        } else {
            Text("—").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct StatusRow: View {
    let label: String
    let detail: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: detail.contains("失败") ? "exclamationmark.circle" : "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(detail.contains("失败") ? Color.orange : Color.green)
            Text(label).font(.subheadline)
            Spacer()
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}
