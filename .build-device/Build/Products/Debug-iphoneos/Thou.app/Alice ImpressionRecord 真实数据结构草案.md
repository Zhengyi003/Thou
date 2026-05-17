# Alice ImpressionRecord 真实数据结构草案

## 目的

这份文档比字段原型更进一步。

它不是泛泛的概念说明，而是面向 Thou 当前真实代码命名做的一版“可落到 Swift 的 ImpressionRecord 重构草案”。

当前真实锚点是：

- [Thou/Models/MemoryModels.swift](Thou/Models/MemoryModels.swift) 里，`ImpressionRecord` 目前还是 `entries: [String]`。
- [Thou/Services/MemorySkillService.swift](Thou/Services/MemorySkillService.swift) 目前也是把 `impressionUpdates: [String]` 直接 merge 进 `entries`。
- [Thou/Alice/Memory/AliceMemoryOrchestrator.swift](Thou/Alice/Memory/AliceMemoryOrchestrator.swift) 的 `buildSystemPrompt()` 目前只是把这些字符串拼成列表。

所以，这一步的核心不是再发明一套抽象词，而是回答：`entries: [String]` 下一步应该长成什么。

## 当前模型的真实问题

当前模型最大的问题不是“字段太少”本身，而是它把三类信息压扁成了一类：

1. 抽象判断。
2. 抽象判断的简短解释。
3. 通往具象证据的回溯线索。

这会直接导致三个后果：

- system prompt 里只能看到一串印象句，模型不知道哪些栏目已形成、哪些栏目仍空缺。
- 一条判断无法稳定挂到三我、大五、资源地基、需求满足策略等固定区域。
- 当模型想追索“为什么得出这个判断”时，当前 `entries` 没有 topic 级证据锚点可走。

## 设计目标

真实数据结构应同时满足四个目标：

1. 与 Thou 当前 Swift 模型风格兼容。
2. 可以直接格式化成聊天主调用的 Canonical Impressions 文本块。
3. 允许字段空缺，但空缺不能消失。
4. 重要判断必须能回指到 topic id。

## 建议的最小重构方向

不建议一步到位做成特别深的嵌套图谱。

第一版更稳的方式是：

- 保留 `ImpressionRecord` 这个顶层名字。
- 把 `entries: [String]` 升级为“结构化栏目 + judgments”。
- 尽量复用当前 `sourceTopicIDs`、`sourceArchiveIDs`、`updatedAt` 这些已有顶层元信息。

## 建议结构

```swift
struct ImpressionRecord: Codable, Equatable {
    var profileVersion: Int
    var completenessNotes: [String]

    var resourceFoundation: ImpressionSection
    var needFulfillmentPatterns: NeedFulfillmentPatterns
    var recurringTensions: [TensionItem]
    var relationalStyle: RelationalStyleSection

    var threeSelf: ThreeSelfSection
    var bigFive: BigFiveSection
    var tagIndex: [TagIndexItem]

    var stableJudgments: [StableJudgment]

    var sourceTopicIDs: [String]
    var sourceArchiveIDs: [UUID]
    var updatedAt: Date
}
```

## 子结构建议

### 1. ImpressionSection

适用于资源地基这类“有多个固定槽位”的区域。

```swift
struct ImpressionSection: Codable, Equatable {
    var slots: [ImpressionSlot]
    var summary: String?
}
```

### 2. ImpressionSlot

这是最关键的通用单元。

```swift
struct ImpressionSlot: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var status: ImpressionStatus
    var statement: String?
    var rationale: String?
    var evidenceTopicIDs: [String]
    var confidence: ImpressionConfidence
    var lastReviewedAt: Date?
}
```

它解决的正是你前面强调的那件事：

- 有抽象判断。
- 有略作解释。
- 有 topic 编号以便按图索骥。

### 3. NeedFulfillmentPatterns

这个部分不建议只用字符串数组，因为它本来就是 Methodology A 的核心之一。

```swift
struct NeedFulfillmentPatterns: Codable, Equatable {
    var survivalAndSafety: NeedPattern
    var socialAndEsteem: NeedPattern
    var cognitionAndAesthetics: NeedPattern
    var selfhoodAndActualization: NeedPattern
}
```

```swift
struct NeedPattern: Codable, Equatable {
    var status: ImpressionStatus
    var currentStrategy: String?
    var substituteStrategy: String?
    var costAndTradeoff: String?
    var unmetPart: String?
    var evidenceTopicIDs: [String]
    var confidence: ImpressionConfidence
}
```

### 4. TensionItem

```swift
struct TensionItem: Codable, Equatable, Identifiable {
    var id: String
    var statement: String
    var whyItMatters: String?
    var evidenceTopicIDs: [String]
    var confidence: ImpressionConfidence
    var status: ImpressionStatus
}
```

### 5. RelationalStyleSection

```swift
struct RelationalStyleSection: Codable, Equatable {
    var trustPattern: ImpressionSlot
    var intimacyPattern: ImpressionSlot
    var expressionPattern: ImpressionSlot
    var preferredSupportStyle: ImpressionSlot
}
```

### 6. ThreeSelfSection

这里不把三我写成长文，而写成结构化槽位。

```swift
struct ThreeSelfSection: Codable, Equatable {
    var idealSelf: ImpressionSlot
    var perceivedSelf: ImpressionSlot
    var currentSelf: ImpressionSlot
    var harmonyState: ImpressionSlot
    var gapNotes: [StableJudgment]
}
```

这意味着：

- 三我在 Thou 里可以作为 Impressions 主体部分存在。
- 但它先是结构化认知框架，不是结果页文案。

### 7. BigFiveSection

```swift
struct BigFiveSection: Codable, Equatable {
    var openness: TraitSlot
    var conscientiousness: TraitSlot
    var extraversion: TraitSlot
    var agreeableness: TraitSlot
    var neuroticism: TraitSlot
}
```

```swift
struct TraitSlot: Codable, Equatable {
    var tendency: String?
    var rationale: String?
    var evidenceTopicIDs: [String]
    var confidence: ImpressionConfidence
    var status: ImpressionStatus
}
```

### 8. TagIndexItem

标签索引应保留，但不应成为主叙述主体。

```swift
struct TagIndexItem: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var linkedTopicIDs: [String]
    var linkedJudgmentIDs: [String]
}
```

### 9. StableJudgment

这是兜底区，也是第一版最容易先落地的部分。

```swift
struct StableJudgment: Codable, Equatable, Identifiable {
    var id: String
    var category: ImpressionCategory
    var statement: String
    var rationale: String?
    var evidenceTopicIDs: [String]
    var confidence: ImpressionConfidence
    var status: ImpressionStatus
    var lastReviewedAt: Date?
}
```

## 枚举建议

### ImpressionStatus

```swift
enum ImpressionStatus: String, Codable {
    case unknown
    case tentative
    case active
    case needsReview
}
```

含义：

- `unknown`: 当前资料不足。
- `tentative`: 已有初步判断，但证据仍薄。
- `active`: 当前已有稳定判断。
- `needsReview`: 近期材料出现冲突，需复核。

### ImpressionConfidence

```swift
enum ImpressionConfidence: String, Codable {
    case low
    case medium
    case high
}
```

### ImpressionCategory

```swift
enum ImpressionCategory: String, Codable {
    case resource
    case needPattern
    case tension
    case relational
    case threeSelf
    case bigFive
    case general
}
```

## 最小 formatter 方案

这一步最重要的不是 UI formatter，而是聊天主调用前的 prompt formatter。

也就是说，需要一段逻辑把新的 `ImpressionRecord` 格式化成：

- 栏目完整。
- 空位可见。
- 重要判断带简短 rationale。
- 重要判断带 evidenceTopicIDs。

### 建议接口

```swift
enum ImpressionPromptFormatter {
    static func makeCanonicalImpressionsBlock(from record: ImpressionRecord) -> String
}
```

### 目标输出风格

```text
Current User Model

Resource Foundation
- money: tentative | 当前经济资源偏紧。因为近期多次提到现实资源约束。 evidenceTopicIDs=[topic-12, topic-19]
- time: unknown | 当前资料不足。

Need Fulfillment Patterns
- socialAndEsteem: active | 更常通过低压力、间接式连接满足社交需求。 evidenceTopicIDs=[topic-12, topic-27]

Three-Self
- idealSelf: unknown | 待观察
- perceivedSelf: tentative | 对自我要求偏高。 evidenceTopicIDs=[topic-33]

Stable Judgments
- 她在重要决定上偏保守。因为面对关系推进、消费和公开表达时，反复优先选择低风险路径。 evidenceTopicIDs=[topic-18, topic-27, topic-44]
```

## 为什么这里建议用“状态 + 人话 + 证据锚点”

这是为了同时解决三件事：

1. 让模型知道这个栏目有没有结论。
2. 让模型知道当前结论是什么。
3. 让模型知道要追证据时该去哪里拿。

如果只有判断，没有状态，模型会误把初步印象当稳定结论。

如果只有判断，没有 rationale，模型会很难理解这个结论在说什么。

如果只有判断，没有 evidenceTopicIDs，模型就没法按图索骥。

## 与当前代码最小兼容的渐进落地方式

不建议一下子把所有调用面全部推翻。

更稳的路径是三步：

### 第一步

先保留当前 `ArchiveRequest.impressionUpdates: [String]` 形态不动。

但把这些字符串不再直接塞进 `entries`，而是优先转成 `StableJudgment` 的初始数据。

也就是说，先把“字符串 impressions”降级为“结构化 judgments 的输入源”。

### 第二步

在 [Thou/Models/MemoryModels.swift](Thou/Models/MemoryModels.swift) 中重构 `ImpressionRecord`，新增上述结构，并保留一个兼容入口，例如：

```swift
init(legacyEntries: [String], sourceTopicIDs: [String], sourceArchiveIDs: [UUID], updatedAt: Date)
```

这样旧 archive 流程不会立刻全炸。

### 第三步

把 [Thou/Alice/Memory/AliceMemoryOrchestrator.swift](Thou/Alice/Memory/AliceMemoryOrchestrator.swift) 的 `buildSystemPrompt()` 改成调用 formatter，而不是把 `entries` 逐条拼成列表。

## 从 `了解一个人.md` 汲取的关键约束

如果回到 [Thou (iOS)/了解一个人.md](Thou%20(iOS)/%E4%BA%86%E8%A7%A3%E4%B8%80%E4%B8%AA%E4%BA%BA.md)，这一版真实数据结构真正吸收的是三条约束：

1. 资源地基不能缺席，因为很多判断首先受现实资源制约。
2. 需求理解不能只写“有没有”，而要写“如何满足、通过什么替代满足、代价是什么”。
3. 抽象认知必须能回到具象材料，否则模型会漂成空洞标签。

## 当前最值得先实现的最小子集

如果要控制实现风险，第一版不必把所有 section 一口气做完。

最值得先实现的是：

1. `StableJudgment`
2. `ImpressionStatus`
3. `ImpressionConfidence`
4. `NeedPattern`
5. `ImpressionPromptFormatter.makeCanonicalImpressionsBlock`

因为这五个已经足够把当前的 `entries: [String]` 升级成：

- 有结构。
- 有状态。
- 有证据锚点。
- 能直接供聊天主调用使用。
