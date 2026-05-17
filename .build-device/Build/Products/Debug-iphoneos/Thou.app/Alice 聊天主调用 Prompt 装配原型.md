# Alice 聊天主调用 Prompt 装配原型

## 目的

这份文档回答一个更具体的问题：

当 Alice 在 Thou 中进行一次正常聊天主调用时，system prompt 到底应该如何装配。

这里不讨论 archive 子调用，只讨论“回复用户这一轮”时模型应该看到什么。

## 结论先行

聊天主调用的默认上下文包应由五部分组成：

1. 产品定位。
2. 完整 Methodology A。
3. 完整的规范版 Impressions。
4. 当前消息窗口。
5. 按需调取的 Topics。

这五部分里：

- 1、2、3 属于默认常驻可见。
- 4 是当前现场。
- 5 是检索后动态拼接。

## 建议装配顺序

### Part 1. Product Identity

这一段回答“你是谁、你在 Thou 里扮演什么角色”。

建议包含：

- Thou 的产品定位。
- Alice 的角色定位。
- Alice 与用户关系的边界。
- 交互语气与目标。

这一段要稳定，不应频繁被个体记忆污染。

### Part 2. Methodology A

这一段回答“你用什么方法理解这个人”。

它不该写成抽象论文，而应写成面向执行的理解协议。

建议结构：

- 先看资源地基。
- 再看需求满足策略。
- 再看代价与收益。
- 再看反复出现的矛盾。
- 最后结合当前互动诉求决定回应方式。

这一段应完整常驻。

### Part 3. Canonical Impressions

这一段回答“你现在对这个用户已经形成了什么理解”。

这不是随手拼几条印象，而是一份结构化用户模型。

建议分块写入：

- `Resource Foundation`
- `Need Fulfillment Patterns`
- `Recurring Tensions`
- `Relational Style`
- `Three-Self Slots`
- `Big Five Slots`
- `Tag Index`
- `Stable Judgments`

这里应遵守四条原则：

1. 栏目完整。
2. 当前判断完整。
3. 重要判断附 rationale。
4. 重要判断附 evidenceTopicIDs。

### Part 4. Retrieved Topics

这一段回答“针对这轮消息，还有哪些具象材料值得临时补进来”。

它应来自 retrieve，而不是把全量 topics 常驻注入。

每个 topic 建议只保留：

- title
- short summary
- 2 到 4 条 key facts
- 1 到 3 个 open questions
- topic id

### Part 5. Active Conversation Window

这一段就是当前消息窗口。

它提供眼前语境，防止 Alice 只盯着用户模型，而忽略本轮真正说了什么。

## 一份建议的 system prompt 骨架

下面不是最终文案，而是推荐结构。

```text
[Product Identity]
<产品定位、角色边界、语气原则>

[Methodology A]
<完整理解方法>

[Canonical Impressions]
<完整规范版用户模型>

[Retrieved Topics]
<若命中则注入；未命中可为空>

[Active Conversation]
<最近若干轮消息>
```

## Canonical Impressions 的建议写法

关键点不是“短”，而是“有结构”。

更推荐这种风格：

```text
[Canonical Impressions]

Resource Foundation
- money: 当前经济资源偏紧。
- time: 时间支配权有限。
- energy: 精力恢复偏慢。
- summary: 很多选择首先受现实约束。

Need Fulfillment Patterns
- socialAndEsteem:
  - currentStrategy: 更常通过低压力、间接式连接满足社交需求。
  - substituteStrategy: 会借助虚拟连接和内容消费获得陪伴感。
  - costAndTradeoff: 安全感较高，但现实互动密度偏低。
  - evidenceTopicIDs: [topic-12, topic-27]

Recurring Tensions
- 想靠近关系，但持续规避高风险暴露。

Relational Style
- preferredSupportStyle: 更偏好先被理解和命名，再接受建议。

Three-Self Slots
- idealSelf: 待观察
- perceivedSelf: 初步判断为对自我要求偏高
- currentSelf: 待观察
- harmonyState: 尚未形成稳定判断

Big Five Slots
- extraversion: 偏低到中；关系需求真实存在，但更常通过低刺激方式维持连接。 evidenceTopicIDs=[topic-12, topic-31]

Tag Index
- 低风险满足
- 渐进信任

Stable Judgments
- 她在重要决定上偏保守；面对关系推进、消费和公开表达时，反复优先选择低风险路径。 evidenceTopicIDs=[topic-18, topic-27, topic-44]
```

## 为什么不是只放“少量稳定判断”

因为 Alice 不是做一次性摘要，而是在长期相处。

如果只放几条稳定判断，会有三个问题：

1. 模型看不到用户模型的栏目全貌。
2. 空缺维度会消失，模型反而不会主动继续观察。
3. 新话题到来时，模型无法判断该把它并到哪个认知栏目里。

所以更稳的做法是：

- 让完整结构常驻。
- 让内容随阶段逐步填充。
- 让空栏也可见。

## 空栏该怎么写

不建议留完全空白。

建议显式写成：

- 待观察
- 当前资料不足
- 仅有初步判断
- 近期出现冲突，待复核

这会让模型知道：

- 这里不是没有意义。
- 而是当前尚未形成稳定认知。

## Retrieved Topics 的触发原则

不是每一轮都必须检索。

更合适的触发条件是：

- 当前消息明确延续了某个已知主题。
- 当前消息提到过去事件、人物、承诺、计划。
- 当前消息触碰到某条稳定判断背后的具象证据。
- 当前消息和某个“待观察”栏目相关，需要调具象材料辅助判断。

## L4 在这份装配稿中的地位

先按当前理解，L4 不进入普通聊天主调用。

也就是说：

- 不默认注入三我长文。
- 不默认注入大五结果页说明文。
- 不默认注入标签云卡片文案。

但这不意味着它们不属于 Thou。

只是现阶段它们先不占用聊天主调用的上下文预算。

## 当前可执行的最小实现思路

如果只做第一版，不必一上来追求复杂模板引擎。

可以先做三步：

1. 固定写出 Product Identity + Methodology A。
2. 读取 ImpressionRecord，格式化成 Canonical Impressions 文本块。
3. 命中检索时，再追加 Retrieved Topics 块。

这样就已经足够验证 Thou 的主心智是否成立。