export class PathUtils {
  static normalizeBaseUrl(baseUrl: string): string {
    return baseUrl.trim().replace(/\/+$/, '')
  }

  static normalizeNotesDir(notesDir: string): string {
    const normalized = notesDir.trim().replace(/^\/+/, '').replace(/\/+$/, '')
    return normalized.length > 0 ? `/${normalized}/` : '/qingyu-notes/'
  }

  static fileNameForNote(noteId: string): string {
    return `${noteId}.md`
  }

  static fileNameForFlowchart(noteId: string): string {
    return `${noteId}.qy`
  }

  static joinRemoteFileUrl(baseUrl: string, notesDir: string, noteId: string): string {
    const cleanBase = PathUtils.normalizeBaseUrl(baseUrl)
    const cleanDir = PathUtils.normalizeNotesDir(notesDir)
    return `${cleanBase}${cleanDir}${encodeURIComponent(PathUtils.fileNameForNote(noteId))}`
  }

  /** 同步目录根下的原始文件名（如 `.qingyu-cloud.json`），不添加 .md 后缀。 */
  static joinRemotePathFileUrl(baseUrl: string, notesDir: string, fileName: string): string {
    const cleanBase = PathUtils.normalizeBaseUrl(baseUrl)
    const cleanDir = PathUtils.normalizeNotesDir(notesDir)
    return `${cleanBase}${cleanDir}${encodeURIComponent(fileName)}`
  }

  static joinRemoteDirectoryUrl(baseUrl: string, notesDir: string): string {
    return `${PathUtils.normalizeBaseUrl(baseUrl)}${PathUtils.normalizeNotesDir(notesDir)}`
  }

  static joinRemoteNestedFileUrl(baseUrl: string, notesDir: string, segments: string[]): string {
    const cleanBase = PathUtils.normalizeBaseUrl(baseUrl)
    const cleanDir = PathUtils.normalizeNotesDir(notesDir)
    const encoded: string[] = []
    for (let i = 0; i < segments.length; i++) {
      if (segments[i].trim().length > 0) {
        encoded.push(encodeURIComponent(segments[i]))
      }
    }
    return `${cleanBase}${cleanDir}${encoded.join('/')}`
  }

  static joinRemoteNestedDirectoryUrl(baseUrl: string, notesDir: string, segments: string[]): string {
    return `${PathUtils.joinRemoteNestedFileUrl(baseUrl, notesDir, segments)}/`
  }
}
