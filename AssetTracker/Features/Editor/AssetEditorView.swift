import SwiftUI
import SwiftData

struct AssetEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let asset: Asset?

    @State private var name = ""
    @State private var bank = "招商永隆"
    @State private var kind: AssetKind = .cash
    @State private var currency: Currency = .cny
    @State private var qtyMode: QtyMode = .amount
    @State private var amountText = ""
    @State private var qtyText = ""
    @State private var priceText = ""
    @State private var code = ""
    @State private var apyText = ""
    @State private var startedAt = Date()
    @State private var expiry = Date()
    @State private var premiumText = ""
    @State private var impliedRateText = ""
    @State private var sumAssuredText = ""
    @State private var basis: ValueBasis = .irr

    @State private var showDeleteConfirm = false

    private let banks = ["招商永隆", "众安银行", "保诚", "汇丰", "招行", "其他"]
    private var isFundLike: Bool { kind == .fund || kind == .stock || kind == .gold }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("资产名称", text: $name)
                    Picker("所属机构", selection: $bank) {
                        ForEach(banks, id: \.self) { Text($0) }
                    }
                    Picker("类型", selection: $kind) {
                        ForEach(AssetKind.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("币种", selection: $currency) {
                        ForEach(Currency.allCases) { Text("\($0.rawValue) \($0.name)").tag($0) }
                    }
                }

                if isFundLike {
                    Section("录入方式") {
                        Picker("方式", selection: $qtyMode) {
                            Text("按金额").tag(QtyMode.amount)
                            Text("按数量 × 价格").tag(QtyMode.qty)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section(qtyMode == .qty && isFundLike ? "持仓" : "金额") {
                    if qtyMode == .qty && isFundLike {
                        HStack {
                            Text(kind == .gold ? "克数" : kind == .fund ? "份额" : "股数")
                            Spacer()
                            TextField("0", text: $qtyText).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                        }
                        HStack {
                            Text(kind == .gold ? "克价" : "单价")
                            Spacer()
                            TextField("0", text: $priceText).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                        }
                        HStack {
                            Text("合计")
                            Spacer()
                            Text("\(currency.symbol)\(Formatter.decimal((Decimal(string: qtyText) ?? 0) * (Decimal(string: priceText) ?? 0)))")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            Text("金额")
                            Spacer()
                            TextField("0.00", text: $amountText).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                        }
                    }
                    if kind == .fund || kind == .stock {
                        TextField("代码（可选，便于自动拉取净值）", text: $code).keyboardType(.numbersAndPunctuation)
                    }
                }

                if kind == .deposit {
                    Section("定存") {
                        DatePicker("起存日", selection: $startedAt, displayedComponents: .date)
                        DatePicker("到期日", selection: $expiry, displayedComponents: .date)
                        HStack {
                            Text("年利率 %")
                            Spacer()
                            TextField("4.1", text: $apyText).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                        }
                        Text("已计利息按持有天数实时计算，会单独成行显示。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if kind == .insurance {
                    Section("保险") {
                        Picker("估值口径", selection: $basis) {
                            Text("按长期收益折现").tag(ValueBasis.irr)
                            Text("按已缴保费").tag(ValueBasis.premium)
                            Text("按官方退保价值").tag(ValueBasis.cashValue)
                        }
                        HStack {
                            Text("已缴保费")
                            Spacer()
                            TextField("0", text: $premiumText).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                        }
                        if basis == .irr {
                            HStack {
                                Text("折现年化 %")
                                Spacer()
                                TextField("2.915", text: $impliedRateText).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                            }
                        }
                        HStack {
                            Text("保额（不计入资产）")
                            Spacer()
                            TextField("0", text: $sumAssuredText).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                        }
                        HStack {
                            Text("计入资产的价值")
                            Spacer()
                            TextField("0", text: $amountText).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                        }
                        Text("保险按退保价值计入，不等于保额。第 1-2 年现金价值通常为 0。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if asset != nil {
                    Section {
                        Button("删除这项资产", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle(asset == nil ? "新增资产" : "编辑资产")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("删除后不可恢复", isPresented: $showDeleteConfirm) {
                Button("删除", role: .destructive) { delete() }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let a = asset else { return }
        name = a.name
        bank = a.bank
        kind = a.kind
        currency = a.currency
        qtyMode = a.qtyMode
        amountText = "\(a.amount)"
        qtyText = a.quantity == 0 ? "" : "\(a.quantity)"
        priceText = a.unitPrice.map { "\($0)" } ?? ""
        code = a.code ?? ""
        apyText = a.apy.map { "\($0)" } ?? ""
        startedAt = a.startedAt ?? .now
        expiry = a.expiry ?? Date()
        premiumText = a.premium.map { "\($0)" } ?? ""
        impliedRateText = a.impliedRate.map { "\($0)" } ?? ""
        sumAssuredText = a.sumAssured.map { "\($0)" } ?? ""
        basis = a.valueBasis ?? .irr
    }

    private func save() {
        let target = asset ?? Asset(name: name, bank: bank, kind: kind, currency: currency)
        if asset == nil { context.insert(target) }

        target.name = name.trimmingCharacters(in: .whitespaces)
        target.bank = bank
        target.kind = kind
        target.currency = currency
        target.qtyMode = isFundLike ? qtyMode : .amount
        target.amount = Decimal(string: amountText) ?? 0
        target.quantity = Decimal(string: qtyText) ?? 0
        target.unitPrice = Decimal(string: priceText)
        target.code = code.isEmpty ? nil : code
        target.apy = Decimal(string: apyText)
        target.startedAt = kind == .deposit ? startedAt : nil
        target.expiry = kind == .deposit ? expiry : nil
        target.premium = Decimal(string: premiumText)
        target.impliedRate = Decimal(string: impliedRateText)
        target.sumAssured = Decimal(string: sumAssuredText)
        target.valueBasis = kind == .insurance ? basis : nil
        target.updatedAt = .now

        try? context.save()
        dismiss()
    }

    private func delete() {
        guard let a = asset else { return }
        context.delete(a)
        try? context.save()
        dismiss()
    }
}
