/**
 * MiniMax「AI 创建标签」系统与用户提示词（与 Flutter ai_tag_prompt.dart 语义一致）。
 */
export class AiTagPrompt {
  static readonly MAX_NEW_TAG_CHARS: number = 8

  static readonly SYSTEM: string =
    '你是轻羽云笔记的标签分类器。任务：根据笔记的语义主题为该笔记选定恰好一个标签。\n' +
    '\n' +
    '## 输出格式（必须遵守）\n' +
    '禁止输出思考过程、分析文字或 markdown；只输出一行 JSON：{"tag":"标签名"}\n' +
    '\n' +
    '## 标签规则\n' +
    '1. 语义分类：标签是笔记所属的分类目录名，不是标题摘抄、不是正文里出现的词。先理解笔记在讲什么主题，再决定标签。\n' +
    '2. 匹配已有库（按含义，禁止按字面）：\n' +
    '   - 只能在你理解笔记主题后，判断「已有标签库」里哪一项在含义上最适合本篇。\n' +
    '   - 禁止因为标签文字出现在标题/正文里就选它；禁止因部分字相同、同义词、近义词而选库中项。\n' +
    '   - 若选中库中某项，JSON 里的 tag 必须与该项【完全一致】（逐字相同）。\n' +
    `3. 新建标签：仅当库中没有任何一项在含义上适合本篇时才新建。\n` +
    '   - 新建标签须与库中标签的命名风格一致：字数、语种（中/英）、抽象程度（如库中多为 2 字主题词，你也用 2 字）。\n' +
    `   - 新建标签总长不得超过 ${AiTagPrompt.MAX_NEW_TAG_CHARS} 个字符（Unicode 码点）；建议 2～4 字。\n` +
    '4. 禁止：笔记、日记、备忘、杂项、未分类、资料、其他、待办；禁止标点、空格、换行、多个标签。'

  static buildUserMessage(title: string, content: string, existingTags: string[]): string {
    const titleLine = title.trim().length > 0 ? title.trim() : '（无）'
    const tagLine = existingTags.length > 0
      ? existingTags.map((t: string) => `「${t}」`).join('、')
      : '（无）'
    const body = AiTagPrompt.truncateContent(content.trim())
    const tagHint = existingTags.length === 0
      ? `库为空：请按笔记含义新建一个风格简短的标签（≤${AiTagPrompt.MAX_NEW_TAG_CHARS} 字）。`
      : '请按【含义】在库中选一项并原样输出；仅当库中无一合适时才新建（≤' +
        `${AiTagPrompt.MAX_NEW_TAG_CHARS} 字，风格与库一致）。勿因正文出现某词就选该标签。`
    return `标题：${titleLine}\n\n正文（节选）：\n${body}\n\n已有标签库：${tagLine}\n\n${tagHint}\n请只输出一行：{"tag":"标签名"}`
  }

  static buildRetryUserMessage(previousTag: string, tooLong: boolean): string {
    if (tooLong) {
      return `上次标签「${previousTag}」为新建项且超过 ${AiTagPrompt.MAX_NEW_TAG_CHARS} 字。请按含义重选：库中有合适项则原样输出库中字符串；否则新建更短标签（≤${AiTagPrompt.MAX_NEW_TAG_CHARS} 字）。格式：{"tag":"标签名"}`
    }
    return '上次返回无效。请按笔记含义与已有库【语义】匹配后，只输出一行 JSON：{"tag":"标签名"}。'
  }

  private static truncateContent(content: string, maxChars: number = 3500): string {
    if (content.length === 0) {
      return '（无）'
    }
    const chars = Array.from(content)
    if (chars.length <= maxChars) {
      return content
    }
    return `${chars.slice(0, maxChars).join('')}\n…（后文已省略）`
  }
}
