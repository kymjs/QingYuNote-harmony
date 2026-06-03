/**
 * MiniMax「AI 优化语句 / AI 提取链接」提示词（与 Flutter ai_note_prompt.dart 语义一致）。
 */
export class AiNotePrompt {
  /** AI 优化语句要求的最少正文字数（Unicode 码点，与 Flutter 一致）。 */
  static readonly OPTIMIZE_MIN_RUNES: number = 100

  static readonly LINK_SUMMARY_MAX_RUNES: number = 300

  /** 含图笔记生成/整合目标字数（Unicode 码点）。 */
  static readonly OPTIMIZE_WITH_IMAGES_TARGET_RUNES: number = 300

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

  static readonly OPTIMIZE_WITH_IMAGES_SYSTEM: string =
    '你是轻羽云笔记的智能笔记助手。用户笔记中含有图片，请先分析图片内容与体裁，再结合正文（若有）输出笔记。\n\n' +
    '## 第一步：判断图片类型与笔记体裁\n' +
    '对画面做综合判断，选择最贴切的一类（可多图取主导类型）：PPT、板书、文字截图、风景/旅行、科技风（产品/界面/发布会/数码等）、学习资料、生活记录、其他。\n' +
    '笔记文风须与类型一致，例如：科技风→简洁专业、要点清晰；学习类→课堂/自学笔记体例；风景→游记散文；PPT/板书→条理化的讲义笔记。\n\n' +
    '## 第二步：按情形处理\n' +
    '### A. 仅有图片、无实质正文\n' +
    `必须主要依据图片生成一篇约 ${AiNotePrompt.OPTIMIZE_WITH_IMAGES_TARGET_RUNES} 字（Unicode 码点）的 Markdown 笔记（建议含一级标题），提炼图中关键信息；文风与上一步判断的类型一致，勿写成与画面无关的通用范文。\n\n` +
    '### B. 图片 + 正文\n' +
    `- PPT 或 板书：结合图片与正文，整合为约 ${AiNotePrompt.OPTIMIZE_WITH_IMAGES_TARGET_RUNES} 字的 Markdown 学习笔记；保留正文要点并补全图中信息。\n` +
    '- 文字截图：OCR 识别图中文字，润色原正文后将识别内容换段追加在后。\n' +
    '- 风景/旅行：在保留原意前提下，以游记笔触优化正文，可结合画面氛围。\n' +
    '- 科技风：保持专业简洁，优化或补充技术要点，风格统一。\n' +
    '- 学习资料：整理为结构化学习笔记。\n' +
    '- 其他：根据图片与正文推断用户意图，输出最有助于用户的笔记正文。\n\n' +
    '## 通用要求\n' +
    '1. 保持 Markdown 结构合理；不输出思考过程、类型标签或 markdown 代码围栏。\n' +
    '2. 只输出最终笔记正文。\n' +
    '3. 专有名词、数字、已有链接 URL 须合理保留。\n' +
    '4. 多图时综合处理，避免重复堆砌。'

  static buildOptimizeWithImagesUserMessage(
    content: string,
    imageCount: number,
    noteHasText: boolean
  ): string {
    if (!noteHasText) {
      return `本笔记仅有 ${imageCount} 张图片、无实质正文（见下方 image_url）。\n` +
        `请分析图片类型与主题，生成约 ${AiNotePrompt.OPTIMIZE_WITH_IMAGES_TARGET_RUNES} 字的 Markdown 笔记，` +
        '文风须与图片类型一致（如科技风、学习笔记、风景游记等）。'
    }
    const body = AiNotePrompt.truncateContent(content.trim())
    return `本笔记含 ${imageCount} 张图片（见下方 image_url）及用户正文。请先判断图片类型与合适文风，再按系统说明处理。\n\n` +
      `笔记正文：\n${body}`
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
