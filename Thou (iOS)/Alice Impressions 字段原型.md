# Alice Impressions 字段原型

## 目的

这份文档不是最终 JSON schema，也不是数据库设计，而是先把 Thou 里“完整的规范版 Impressions”长什么样说明白。

目标只有两个：

1. 让聊天主调用真的有一份可常驻注入的用户模型。
2. 让这份用户模型既是抽象认知，又能顺着 topic id 回到具象材料。

## 总体原则

- Impressions 是当前版本的用户模型，不是历史材料全集。
- Impressions 应完整，但这里的“完整”指栏目完整、当前判断完整，不是证据全集完整。
- 每个重要抽象判断，都应带简短解释和 evidenceTopicIDs。
- 栏目允许空缺；空缺不代表删除该栏目，而代表后续应继续观察。

## 推荐结构

```text
ImpressionRecord
- profileVersion
- lastUpdatedAt
- completenessNotes

- resourceFoundation
  - money
  - time
  - energy
  - stability
  - supportSystem
  - pressureSources[]
  - summary

- needFulfillmentPatterns
  - survivalAndSafety
  - socialAndEsteem
  - cognitionAndAesthetics
  - selfhoodAndActualization

- recurringTensions
  - tensionList[]

- relationalStyle
  - trustPattern
  - intimacyPattern
  - expressionPattern
  - preferredSupportStyle

- threeSelf
  - idealSelf
  - perceivedSelf
  - currentSelf
  - harmonyState
  - gapNotes

- bigFive
  - openness
  - conscientiousness
  - extraversion
  - agreeableness
  - neuroticism

- tagIndex[]

- stableJudgments[]
  - id
  - statement
  - rationale
  - evidenceTopicIDs[]
  - confidence
  - status
  - lastReviewedAt
```

## 字段解释

### 1. 顶层元信息

`profileVersion`

- 当前用户模型的版本号。
- 每次 archive 后若发生实质更新，可递增。

`lastUpdatedAt`

- 最近一次完整修订时间。

`completenessNotes`

- 说明当前用户模型仍有哪些维度资料不足。
- 这不是给用户看的文案，而是给系统和模型看的缺口提示。

### 2. resourceFoundation

这是 Alice 解释用户行为时的底板。

建议每个子项都允许三种状态：

- 已有稳定判断。
- 有初步判断但置信度低。
- 暂无足够材料。

例子：

```text
resourceFoundation
- money: 当前经济资源偏紧，对消费和选择存在明显约束。
- time: 时间支配权有限，经常被外部任务切碎。
- energy: 情绪和精力恢复速度偏慢。
- stability: 当前生活结构不算稳定。
- supportSystem: 有有限但真实可依赖的关系支持。
- pressureSources: [现实压力、对未来的不确定感]
- summary: 很多选择首先受现实资源约束，其次才谈理想偏好。
```

### 3. needFulfillmentPatterns

这是对“需求如何被满足”的分层理解，不是对需求有无的简单判定。

四个栏目建议固定存在：

- `survivalAndSafety`
- `socialAndEsteem`
- `cognitionAndAesthetics`
- `selfhoodAndActualization`

每个栏目都可先采用同一种最小格式：

```text
NeedPattern
- currentStrategy
- substituteStrategy
- costAndTradeoff
- unmetPart
- evidenceTopicIDs[]
```

例子：

```text
socialAndEsteem
- currentStrategy: 更常通过低压力、间接式连接满足社交需求。
- substituteStrategy: 会借助虚拟连接、内容消费、单向关注获得陪伴感。
- costAndTradeoff: 安全感较高，但互相确认感和现实互动密度偏低。
- unmetPart: 更深关系中的主动表达仍偏谨慎。
- evidenceTopicIDs: [topic-12, topic-27]
```

### 4. recurringTensions

这里记录用户反复出现的拉扯，而不是一时矛盾。

最小格式：

```text
TensionItem
- statement
- whyItMatters
- evidenceTopicIDs[]
- confidence
```

例子：

- 想靠近关系，但又持续规避高风险暴露。
- 想维持理想自我叙述，但现实资源常常不允许。

### 5. relationalStyle

这是 Alice 决定如何陪伴、提醒、回应的关键区域。

建议至少包括：

- `trustPattern`
- `intimacyPattern`
- `expressionPattern`
- `preferredSupportStyle`

例子：

```text
relationalStyle
- trustPattern: 信任建立较慢，需要持续一致性。
- intimacyPattern: 更能接受渐进式靠近，而不是高强度情感推进。
- expressionPattern: 更容易通过旁敲侧击表达，而不是直接摊开。
- preferredSupportStyle: 更偏好先被理解和命名，再接受建议。
```

### 6. threeSelf

如果三我是 Thou 用户模型的一部分，这里就不该缺席。

但它应先以结构化槽位存在，而不是长文画像。

最小格式：

```text
threeSelf
- idealSelf
- perceivedSelf
- currentSelf
- harmonyState
- gapNotes
```

这里允许空值。

空值的含义不是“不要这个栏目”，而是“该维度仍待观察”。

### 7. bigFive

大五也应先以结构化槽位存在。

建议每一维都使用统一格式：

```text
TraitSlot
- tendency
- rationale
- evidenceTopicIDs[]
- confidence
```

例子：

```text
extraversion
- tendency: 偏低到中。
- rationale: 关系需求真实存在，但更常通过低刺激、可控方式维持连接。
- evidenceTopicIDs: [topic-12, topic-31]
- confidence: medium
```

### 8. tagIndex

`tagIndex` 不是最终展示词云，而是模型快速扫描用户模型的索引层。

它应尽量短，且每个 tag 最好能回指到某个判断或 topic。

例子：

- 低风险满足
- 渐进信任
- 现实约束优先
- 虚拟连接补偿

### 9. stableJudgments

这是兜底区，承接那些已经足够稳定、但还不适合塞进固定栏目里的判断。

最关键的是，它必须带 rationale 和 evidenceTopicIDs。

例子：

```text
stableJudgments
- id: judgment-08
  statement: 她在重要决定上明显偏保守。
  rationale: 面对关系推进、消费和公开表达时，反复优先选择低风险路径。
  evidenceTopicIDs: [topic-18, topic-27, topic-44]
  confidence: medium-high
  status: active
  lastReviewedAt: 2026-04-22
```

## 字段空缺策略

字段空缺不应被清除，也不应被模型误读为否定结论。

更稳的写法是：

- `unknown`: 当前资料不足。
- `tentative`: 有初步判断，但证据仍薄。
- `active`: 已有稳定判断。
- `needs-review`: 曾有判断，但近期材料出现冲突。

## 和 Topics 的关系

Impressions 和 Topics 的关系不是二选一，而是抽象与具象的分工。

- Impressions 提供运行时常驻的用户模型。
- Topics 提供按需调用的具象材料。
- Impressions 中每个重要抽象判断，都应至少能追到一个或多个 topic。

## 聊天主调用时真正进入上下文的版本

进入聊天 system prompt 的，不一定需要把全部字段展开成超长说明文。

更合适的做法是：

1. 保留完整栏目。
2. 只写当前有效内容。
3. 对空栏明确标记“待观察”或“资料不足”。
4. 对重要判断保留 rationale 和 evidenceTopicIDs。

这样模型才能：

- 既拥有稳定用户画像。
- 又知道哪些判断还不稳。
- 还知道需要时该向哪个 topic 继续追索。