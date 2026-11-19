# 资产查看器（iOS）

多币种资产的每日总览：统一折人民币、按银行/币种/类别拆分、汇率与金价趋势、定存按日计息、保险按退保价值单独分区。

> 本机是 Windows，无法编译 iOS。以下文件是可直接导入 Xcode 的完整工程源码。

## 环境要求

- macOS + Xcode 16 或更新
- iOS 17.0+（用到了 SwiftData 与 `SectorMark`）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（可选，用于从 `project.yml` 生成工程）

## 生成并运行

```bash
brew install xcodegen          # 只需一次
cd apps/AssetTracker
xcodegen generate             # 生成 AssetTracker.xcodeproj
open AssetTracker.xcodeproj
```

没有 XcodeGen 的话：在 Xcode 里新建一个 iOS App 工程，把 `AssetTracker/` 目录拖进去，确认 target 的 iOS 部署版本为 17.0，并勾选 `AssetTrackerTests`。

首次打开需要配置签名（Signing & Capabilities → Team）。

## 目录结构

```
AssetTracker/
├── App/
│   ├── AssetTrackerApp.swift      @main + ModelContainer
│   └── RootView.swift             三个 Tab
├── Models/
│   ├── Asset.swift                @Model 资产（含枚举与计算属性）
│   └── Snapshots.swift            汇率/估值/行情快照
├── Services/
│   ├── HTTPClient.swift           URLSession 封装（超时、重试、伪装头）
│   ├── RateService.swift          Frankfurter + open.er-api 兜底
│   ├── GoldService.swift          新浪 gds_AUTD / hf_GC
│   ├── FundService.swift          东财 push2 + f10/lsjz
│   ├── ValuationEngine.swift      算账纯函数（有单测）
│   ├── MarketDataStore.swift      全局状态 + 持久化
│   └── SeedData.swift             首次启动写入你的 8 项资产
├── Features/
│   ├── Overview/OverviewView.swift
│   ├── Editor/AssetEditorView.swift
│   ├── Trends/TrendsView.swift
│   └── Detail/DetailView.swift
└── Support/Formatter.swift
```

## 已实现

| 功能 | 说明 |
|---|---|
| 多币种折人民币 | 每个资产显示「折人民币 / 原币」两行 |
| 全部 vs 可动用视图 | 可动用排除定存与保险 |
| 按银行汇总 | 招商永隆 / 众安 / 保诚 / 其他 |
| 币种敞口 | USD / HKD / CNY / JPY 占比条 |
| 类别环形图 | 现金 / 基金 / 黄金 / 保险 |
| 资产增删改 | 原生 Form，含定存到期日、保险口径 |
| 定存按日计息 | 本金与已计利息拆成两行，利息随天数增长 |
| 汇率趋势 | 日/周/月/年，卡片切换币种 |
| 金价趋势 | 上金所 Au(T+D) 元/克 |
| 日均快照 | 每次刷新落库，形成自己的净值曲线 |
| 数据源状态 | 明细页显示各接口是否更新 |

## 数据源

| 用途 | 接口 | 备注 |
|---|---|---|
| 汇率 | `api.frankfurter.dev` | 无 key，ECB 参考价，工作日更新 |
| 汇率兜底 | `open.er-api.com` | ~160 币种 |
| 国内金价 | `hq.sinajs.cn/list=gds_AUTD` | 需 Referer，实时 |
| 国际金价 | `hq.sinajs.cn/list=hf_GC` | 美元/盎司 |
| 场内 ETF | `push2.eastmoney.com` | 实时，`secid` 前缀 1=沪 0=深 |
| 场外基金 | `api.fund.eastmoney.com/f10/lsjz` | 仅确认净值，**无盘中估值** |

场外基金没有免费的盘中估值接口（`fundgz.1234567.com.cn` 已下线）。App 只展示最新确认净值，并标注净值日期。

## 核心计算

```
原币价值 → 人民币：value = qty × price × rate(currency → CNY)
定存已计利息：    principal × apy / 100 × 持有天数 / 365
今日涨跌：        今日总值(今日汇率) − 昨日总值(昨日汇率)
保险现值：        Σ 保费 × (1+r)^(缴费年起算的剩余年数) 反解 r
```

**今日涨跌必须用昨日汇率重算昨日资产**，否则汇率波动会被误算成资产增长。

## 首次启动的种子数据

从 `docs/资产.txt` 导入，共 8 项：永隆两只基金、美元定存、灵活资金、众安活期、黄金 7.45 克、信守明天、重疾险。人民币资产可在 App 里直接添加。

## 后续可做

- WidgetKit 小组件（总资产 + 今日涨跌）
- 后台每日自动刷新 + 本地通知
- 导出 CSV / JSON
- 基金代码自动拉净值（`FundService` 已就绪，需在编辑页填代码）
- 汇率历史落库后，跨币种趋势走本地缓存而非重复请求

## 测试

```bash
xcodebuild test -scheme AssetTracker -destination 'platform=iOS Simulator,name=iPhone 16'
```

覆盖：汇率换算、可动用口径、数量×单价、黄金按实时克价重估、定存计息、昨日汇率重算、IRR 反解、按银行聚合。
