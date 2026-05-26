/**
 * MiniMax「AI 优化语句 / AI 提取链接」提示词（与 Flutter ai_note_prompt.dart 语义一致）。
 */
export class AiNotePrompt {
  static readonly LINK_SUMMARY_MAX_RUNES: number = 300

  static readonly OPTIMIZE_SYSTEM: string =
    '你是轻羽云笔记的专业文字编辑。任务：在不改变作者原意与信息完整性的前提下，润色用户提供的笔记正文。\n\n' +
    '## 要求\n' +
    '1. 修正语病、错别字、标点与不通顺之处，使语句通顺自然。\n' +
    '2. 保持 Markdown 结构（标题、列表、引用、代码块、链接等）与段落层次不变。\n' +
    '3. 不增删核心事实，不编造内容；专有名词、数字、链接 URL 须原样保留。\n' +
    '4. 禁止输出思考过程、解释说明或 markdown 代码围栏；只输出润色后的正文。'

  static buildOptimizeUserMessage(content: string): string {
    const body = AiNotePrompt.truncateContent(content.trim())
    return `请润色以下笔记正文：\n\n${body}`
  }

  static readonly LINK_SUMMARY_SYSTEM: string =
    '你是轻羽云笔记的内容摘要助手。任务：根据用户提供的网页链接及可得的页面信息，提炼为一篇简洁的 Markdown 笔记摘要。\n\n' +
    '## 要求\n' +
    '1. 概括文章主旨与关键信息，语言通顺、客观准确。\n' +
    `2. 第一行必须是一级 Markdown 标题（# 文章标题），标题简洁概括主题；其后为摘要正文。\n` +
    `3. 全文不超过 ${AiNotePrompt.LINK_SUMMARY_MAX_RUNES} 个汉字（Unicode 码点）；可分段，使用简洁 Markdown。\n` +
    '4. 若无法获取页面正文，请根据链接域名与路径合理推断主题并给出简短说明，勿编造具体细节。\n' +
    '5. 禁止输出思考过程或多余说明；只输出标题行与摘要正文。'

  static buildLinkSummaryUserMessage(url: string, pageExcerpt: string = ''): string {
    const excerptBlock = pageExcerpt.trim().length === 0
      ? '（未能抓取页面正文，请结合链接本身推断）'
      : pageExcerpt.trim()
    return `链接：${url}\n\n页面正文节选：\n${excerptBlock}\n\n` +
      `请输出不超过 ${AiNotePrompt.LINK_SUMMARY_MAX_RUNES} 字的 Markdown 笔记摘要。`
  }

  private static truncateContent(content: string, maxRunes: number = 12000): string {
    if (content.length === 0) {
      return '（无）'
    }
    const runes = Array.from(content)
    if (runes.length <= maxRunes) {
      return content
    }
    return `${runes.slice(0, maxRunes).join('')}\n…（后文已省略）`
  }
}
