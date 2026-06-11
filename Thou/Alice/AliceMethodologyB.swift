/**
 Alice 的归档方法学定义。

 这个文件承载一轮对话结束后，Alice 应如何把 Messages 沉淀成 Topics / Impressions，
 供后续 archive 流程与记忆技能继续扩展。
 */

import Foundation

enum AliceMethodologyB {
    static let archiveGuide = """
    归档时遵循以下原则：
    1. 优先沉淀稳定事实、长期偏好、反复出现的主题，而不是短期情绪噪音。
    2. Topics 应可复用，能在未来 retrieve 时帮助理解用户，而不是纯粹复读聊天原文。
    3. Impressions 应简洁、可注入到下一轮 system prompt，不要写成冗长总结。
    4. 保留最近若干轮前台 messages，其余历史归档到长期记忆文件。
    """
}