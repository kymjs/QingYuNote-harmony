/** 笔记编辑 Markdown 快捷插入（与 Flutter `editor_markdown_insert.dart` 对齐）。 */
export interface EditorInsertResult {
  text: string
  caret: number
}

export interface EditorTextDiff {
  start: number
  end: number
  insert: string
}

export class EditorMarkdownInsert {
  /** 计算 oldText → newText 的最小替换区间，供 TextAreaController 增量插入。 */
  static computeTextDiff(oldText: string, newText: string): EditorTextDiff {
    let prefix = 0
    const minLen = Math.min(oldText.length, newText.length)
    while (prefix < minLen && oldText.charAt(prefix) === newText.charAt(prefix)) {
      prefix++
    }
    let suffix = 0
    while (
      suffix < oldText.length - prefix &&
      suffix < newText.length - prefix &&
      oldText.charAt(oldText.length - 1 - suffix) === newText.charAt(newText.length - 1 - suffix)
    ) {
      suffix++
    }
    const start = prefix
    const end = oldText.length - suffix
    const insert = newText.substring(prefix, newText.length - suffix)
    return { start, end, insert }
  }

  private static lineStart(text: string, offset: number): number {
    const o = Math.max(0, Math.min(offset, text.length))
    if (o === 0) {
      return 0
    }
    const idx = text.lastIndexOf('\n', o - 1)
    return idx < 0 ? 0 : idx + 1
  }

  private static lineEnd(text: string, offset: number): number {
    const o = Math.max(0, Math.min(offset, text.length))
    const idx = text.indexOf('\n', o)
    return idx < 0 ? text.length : idx
  }

  /** 空行或仅含块级前缀的行，按空行处理，避免重复点击多出空行（与 Flutter 对齐）。 */
  private static isEffectivelyEmptyLine(line: string): boolean {
    const trimmed = line.trim()
    if (trimmed.length === 0) {
      return true
    }
    return /^\>\s*$/.test(trimmed) ||
      /^\d+\.\s*$/.test(trimmed) ||
      /^\*\s*$/.test(trimmed) ||
      /^-\s*$/.test(trimmed) ||
      /^---\s*$/.test(trimmed)
  }

  private static ensureTrailingSpaces(line: string): string {
    let count = 0
    for (let i = line.length - 1; i >= 0; i--) {
      if (line.charAt(i) === ' ') {
        count++
      } else {
        break
      }
    }
    if (count >= 2) {
      return line
    }
    return `${line}  `
  }

  static nextOrderedListNumber(text: string): number {
    const lines = text.split('\n')
    let max = 0
    const re = /^\s*(\d+)\.\s/
    for (const line of lines) {
      const m = line.match(re)
      if (m !== null && m[1] !== undefined) {
        const n = parseInt(m[1], 10)
        if (!isNaN(n) && n > max) {
          max = n
        }
      }
    }
    return max + 1
  }

  static insertBlockPrefix(text: string, caret: number, prefix: string): EditorInsertResult {
    const cursor = Math.max(0, Math.min(caret, text.length))
    const lineStart = EditorMarkdownInsert.lineStart(text, cursor)
    const lineEnd = EditorMarkdownInsert.lineEnd(text, cursor)
    const line = text.substring(lineStart, lineEnd)

    if (EditorMarkdownInsert.isEffectivelyEmptyLine(line)) {
      const newText = text.substring(0, lineStart) + prefix + text.substring(lineEnd)
      return { text: newText, caret: lineStart + prefix.length }
    }

    const paddedLine = EditorMarkdownInsert.ensureTrailingSpaces(line)
    const insertSuffix = `\n${prefix}`
    const newText =
      text.substring(0, lineStart) + paddedLine + insertSuffix + text.substring(lineEnd)
    const newCaret = lineStart + paddedLine.length + insertSuffix.length
    return { text: newText, caret: newCaret }
  }

  static insertOrderedListItem(text: string, caret: number): EditorInsertResult {
    const next = EditorMarkdownInsert.nextOrderedListNumber(text)
    return EditorMarkdownInsert.insertBlockPrefix(text, caret, `${next}. `)
  }

  static wrapPlaceholder(
    text: string,
    caretStart: number,
    caretEnd: number,
    left: string,
    right: string,
    placeholder: string,
    cursorBackFromEnd: number
  ): EditorInsertResult {
    const start = caretStart >= 0 ? caretStart : text.length
    const end = caretEnd >= 0 ? caretEnd : text.length
    const insert = `${left}${placeholder}${right}`
    const newText = text.substring(0, start) + insert + text.substring(end)
    const newCaret = start + insert.length - cursorBackFromEnd
    return { text: newText, caret: newCaret }
  }

  static insertLink(text: string, caretStart: number, caretEnd: number, label: string, url: string): EditorInsertResult {
    const start = caretStart >= 0 ? caretStart : text.length
    const end = caretEnd >= 0 ? caretEnd : text.length
    const insert = `[${label}](${url})`
    const newText = text.substring(0, start) + insert + text.substring(end)
    return { text: newText, caret: start + insert.length }
  }
}
