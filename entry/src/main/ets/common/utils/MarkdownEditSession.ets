import {
  MarkdownEmbedKind,
  MarkdownEmbedMatch,
  MarkdownEmbedMatcher
} from './MarkdownEmbedMatcher'

/** 编辑态图片/链接会话态（仅内存）。 */
export class MarkdownEditSession {
  richKeys: Set<string> = new Set()
  sourceOnlyKeys: Set<string> = new Set()
  toolbarKeys: Set<string> = new Set()

  onEnterEdit(source: string): void {
    this.richKeys.clear()
    this.sourceOnlyKeys.clear()
    this.toolbarKeys.clear()
    const matches = MarkdownEmbedMatcher.findAll(source)
    for (let i = 0; i < matches.length; i++) {
      this.richKeys.add(matches[i].key)
    }
  }

  onToolbarInsert(kind: MarkdownEmbedKind, label: string, url: string, sourceAfterInsert: string): string {
    const matches = MarkdownEmbedMatcher.findAll(sourceAfterInsert)
    let found: MarkdownEmbedMatch | undefined = undefined
    for (let i = 0; i < matches.length; i++) {
      const m = matches[i]
      if (m.kind === kind && m.url === url.trim() && m.label === label) {
        found = m
      }
    }
    const key = found !== undefined ? found.key : MarkdownEmbedMatcher.keyFor(kind, url.trim(), 0)
    this.richKeys.add(key)
    this.toolbarKeys.add(key)
    this.sourceOnlyKeys.delete(key)
    return key
  }

  onEmbedTapped(key: string): void {
    this.richKeys.delete(key)
    this.toolbarKeys.delete(key)
    this.sourceOnlyKeys.add(key)
  }

  shouldRenderRich(match: MarkdownEmbedMatch): boolean {
    if (this.sourceOnlyKeys.has(match.key)) {
      return false
    }
    return this.richKeys.has(match.key) || this.toolbarKeys.has(match.key)
  }

  reindexAfterTextChange(oldSource: string, newSource: string): void {
    if (oldSource === newSource) {
      return
    }
    const oldMatches = MarkdownEmbedMatcher.findAll(oldSource)
    const newMatches = MarkdownEmbedMatcher.findAll(newSource)
    const oldByRaw: Map<string, MarkdownEmbedMatch[]> = new Map()
    for (let i = 0; i < oldMatches.length; i++) {
      const m = oldMatches[i]
      const list = oldByRaw.get(m.raw) ?? []
      list.push(m)
      oldByRaw.set(m.raw, list)
    }
    const nextRich: Set<string> = new Set()
    const nextSourceOnly: Set<string> = new Set()
    const nextToolbar: Set<string> = new Set()
    const consumed: Map<string, number> = new Map()

    for (let i = 0; i < newMatches.length; i++) {
      const n = newMatches[i]
      const list = oldByRaw.get(n.raw)
      const idx = consumed.get(n.raw) ?? 0
      let old: MarkdownEmbedMatch | undefined = undefined
      if (list !== undefined && idx < list.length) {
        old = list[idx]
        consumed.set(n.raw, idx + 1)
      }
      const oldKey = old?.key
      if (oldKey !== undefined && this.sourceOnlyKeys.has(oldKey)) {
        nextSourceOnly.add(n.key)
      } else if (oldKey !== undefined && this.toolbarKeys.has(oldKey)) {
        nextToolbar.add(n.key)
        nextRich.add(n.key)
      } else if (oldKey !== undefined && this.richKeys.has(oldKey)) {
        nextRich.add(n.key)
      } else {
        if (this.toolbarKeys.has(n.key)) {
          nextToolbar.add(n.key)
        }
        if (this.richKeys.has(n.key)) {
          nextRich.add(n.key)
        }
        if (this.sourceOnlyKeys.has(n.key)) {
          nextSourceOnly.add(n.key)
        }
      }
    }
    this.richKeys = nextRich
    this.sourceOnlyKeys = nextSourceOnly
    this.toolbarKeys = nextToolbar
  }
}
