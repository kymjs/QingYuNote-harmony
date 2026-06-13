/** MiniMax 笔记标题生成提示词（与 Flutter `ai_note_title_prompt.dart` 对齐）。 */
export class AiNoteTitlePrompt {
  static readonly MAX_TITLE_CHARS: number = 10

  static readonly SYSTEM: string =
    '你是轻羽云笔记的标题生成器。根据笔记正文概括主题，生成一条简短标题。\n' +
    '\n' +
    '## 输出格式（必须遵守）\n' +
    '禁止输出思考过程、分析文字或 markdown；只输出一行 JSON：{"title":"标题"}\n' +
    '\n' +
    '## 标题规则\n' +
    '1. 准确概括正文核心，不要照抄开头原句。\n' +
    `2. 总长不得超过 ${AiNoteTitlePrompt.MAX_TITLE_CHARS} 个字符（Unicode 码点）。\n` +
    '3. 禁止书名号、引号包裹、标点开头结尾、换行、多个标题。'

  static buildUserMessage(content: string): string {
    const body = AiNoteTitlePrompt.truncateContent(content.trim())
    return `正文：\n${body}\n\n请只输出一行：{"title":"标题"}`
  }

  static buildRetryUserMessage(previousTitle: string): string {
    return `上次标题「${previousTitle}」无效或过长。请重新概括，只输出一行 JSON：{"title":"标题"}，不超过 ${AiNoteTitlePrompt.MAX_TITLE_CHARS} 个字。`
  }

  private static truncateContent(content: string, maxRunes: number = 3500): string {
    if (content.length === 0) {
      return '（无）'
    }
    if (content.length <= maxRunes) {
      return content
    }
    return `${content.substring(0, maxRunes)}\n…（后文已省略）`
  }
}
