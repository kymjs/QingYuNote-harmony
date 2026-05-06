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

  static joinRemoteFileUrl(baseUrl: string, notesDir: string, noteId: string): string {
    const cleanBase = PathUtils.normalizeBaseUrl(baseUrl)
    const cleanDir = PathUtils.normalizeNotesDir(notesDir)
    return `${cleanBase}${cleanDir}${encodeURIComponent(PathUtils.fileNameForNote(noteId))}`
  }

  static joinRemoteDirectoryUrl(baseUrl: string, notesDir: string): string {
    return `${PathUtils.normalizeBaseUrl(baseUrl)}${PathUtils.normalizeNotesDir(notesDir)}`
  }
}
