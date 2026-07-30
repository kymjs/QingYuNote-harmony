/** 编辑态图片/链接 Markdown 匹配（与 Flutter MarkdownEmbedMatcher 对齐）。 */
export type MarkdownEmbedKind = 'image' | 'link'

export interface MarkdownEmbedMatch {
  kind: MarkdownEmbedKind
  start: number
  end: number
  label: string
  url: string
  raw: string
  key: string
}

export class MarkdownEmbedMatcher {
  static keyFor(kind: MarkdownEmbedKind, url: string, occurrenceIndex: number): string {
    return `${kind}|${url}|${occurrenceIndex}`
  }

  static findAll(source: string): MarkdownEmbedMatch[] {
    if (source.length === 0) {
      return []
    }
    const occupied: Array<[number, number]> = []
    const matches: MarkdownEmbedMatch[] = []
    const urlCounts: Map<string, number> = new Map()

    const overlaps = (start: number, end: number): boolean => {
      for (let i = 0; i < occupied.length; i++) {
        const r = occupied[i]
        if (start < r[1] && end > r[0]) {
          return true
        }
      }
      return false
    }

    const addMatch = (kind: MarkdownEmbedKind, start: number, end: number, label: string,
      url: string, raw: string): void => {
      if (overlaps(start, end)) {
        return
      }
      const trimmedUrl = url.trim()
      const countKey = `${kind}|${trimmedUrl}`
      const occurrence = urlCounts.get(countKey) ?? 0
      urlCounts.set(countKey, occurrence + 1)
      occupied.push([start, end])
      matches.push({
        kind: kind,
        start: start,
        end: end,
        label: label,
        url: trimmedUrl,
        raw: raw,
        key: MarkdownEmbedMatcher.keyFor(kind, trimmedUrl, occurrence)
      })
    }

    const imageRe = /!\[([^\]]*)\]\(([^)]+)\)/g
    let m: RegExpExecArray | null = imageRe.exec(source)
    while (m !== null) {
      addMatch('image', m.index, m.index + m[0].length, m[1] ?? '', m[2] ?? '', m[0])
      m = imageRe.exec(source)
    }

    const linkRe = /\[([^\]]+)\]\(([^)]+)\)/g
    m = linkRe.exec(source)
    while (m !== null) {
      if (m.index > 0 && source.charAt(m.index - 1) === '!') {
        m = linkRe.exec(source)
        continue
      }
      addMatch('link', m.index, m.index + m[0].length, m[1] ?? '', m[2] ?? '', m[0])
      m = linkRe.exec(source)
    }

    matches.sort((a, b) => a.start - b.start)
    return matches
  }
}
