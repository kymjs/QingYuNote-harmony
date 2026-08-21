/** Mermaid 源码预览前消毒（与 Flutter `mermaid_source_sanitize.dart` 对齐）。 */
export class MermaidSourceSanitize {
  private static readonly SEQUENCE_RESERVED: string[] = [
    'loop', 'alt', 'opt', 'par', 'and', 'critical', 'break', 'rect', 'else',
    'option', 'end', 'note', 'activate', 'deactivate', 'autonumber', 'title',
    'participant', 'actor', 'as', 'over', 'left', 'right', 'of'
  ]

  static sanitize(source: string): string {
    const trimmed = source.replace(/^\s+/, '')
    if (!trimmed.startsWith('sequenceDiagram')) {
      return source
    }

    const renames: Map<string, string> = new Map()
    const lines = source.split('\n')
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i]
      const match = line.match(/^([ \t]*)(participant|actor)[ \t]+(\S+)(.*)$/)
      if (match === null) {
        continue
      }
      const id = MermaidSourceSanitize.stripQuotes(match[3])
      if (id.length === 0) {
        continue
      }
      if (MermaidSourceSanitize.SEQUENCE_RESERVED.indexOf(id.toLowerCase()) < 0) {
        continue
      }
      if (!renames.has(id)) {
        renames.set(id, `${id}_actor`)
      }
    }

    if (renames.size === 0) {
      return source
    }

    let next = source
    renames.forEach((to: string, from: string) => {
      next = MermaidSourceSanitize.renameActor(next, from, to)
    })
    return next
  }

  private static stripQuotes(id: string): string {
    if (id.length >= 2) {
      const a = id.charAt(0)
      const b = id.charAt(id.length - 1)
      if ((a === '"' && b === '"') || (a === "'" && b === "'")) {
        return id.substring(1, id.length - 1)
      }
    }
    return id
  }

  private static renameActor(source: string, from: string, to: string): string {
    const esc = from.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    let out = source
    out = out.replace(
      new RegExp(`((?:^|\\n)[ \\t]*(?:participant|actor)[ \\t]+)${esc}([ \\t]|$)`, 'g'),
      `$1${to}$2`
    )
    out = out.replace(
      new RegExp(`((?:^|\\n)[ \\t]*(?:participant|actor)[ \\t]+)"${esc}"([ \\t]|$)`, 'g'),
      `$1"${to}"$2`
    )
    out = out.replace(
      new RegExp(`(^|[\\n\\s])${esc}(->>|-->>|-->>|->|-->|--x|-x|--)\\b`, 'gm'),
      `$1${to}$2`
    )
    out = out.replace(
      new RegExp(`(->>|-->>|-->>|->|-->|--x|-x|--)${esc}(?=\\s|:|$)`, 'g'),
      `$1${to}`
    )
    return out
  }
}
