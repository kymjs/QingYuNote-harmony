import { PreferencesService } from './PreferencesService'
import { Logger } from '../common/utils/Logger'

/** 与 Flutter `AppConst.prefLinkExtractHistoryPrefix` 一致。 */
const LINK_EXTRACT_HISTORY_PREFIX = 'link_extract_history_'

export interface LinkExtractHistoryItem {
  noteId: string
  url: string
  title: string
  createdAtMs: number
}

/** 按 userId 隔离的本地链接提取历史（最多 4 条；登出不删）。 */
export class LinkExtractHistoryService {
  private static instance: LinkExtractHistoryService = new LinkExtractHistoryService()

  static getInstance(): LinkExtractHistoryService {
    return LinkExtractHistoryService.instance
  }

  static readonly MAX_ITEMS: number = 4

  private async historyKey(): Promise<string | null> {
    const userId = (await PreferencesService.getInstance().getNoteApiUserId()).trim()
    if (userId.length === 0) {
      return null
    }
    return `${LINK_EXTRACT_HISTORY_PREFIX}${userId}`
  }

  async list(): Promise<LinkExtractHistoryItem[]> {
    const key = await this.historyKey()
    if (key === null) {
      return []
    }
    try {
      const raw = (await PreferencesService.getInstance().getPreferenceString(key)).trim()
      if (raw.length === 0) {
        return []
      }
      const decoded = JSON.parse(raw) as Object[]
      if (!Array.isArray(decoded)) {
        return []
      }
      const items: LinkExtractHistoryItem[] = []
      for (let i = 0; i < decoded.length; i++) {
        const entry = decoded[i] as Record<string, Object>
        const noteId = `${entry['noteId'] ?? ''}`.trim()
        const url = `${entry['url'] ?? ''}`.trim()
        if (noteId.length === 0 || url.length === 0) {
          continue
        }
        items.push({
          noteId: noteId,
          url: url,
          title: `${entry['title'] ?? ''}`.trim(),
          createdAtMs: Number(entry['createdAtMs'] ?? 0)
        })
        if (items.length >= LinkExtractHistoryService.MAX_ITEMS) {
          break
        }
      }
      return items
    } catch (error) {
      Logger.warn('LinkExtractHistory', `list failed: ${JSON.stringify(error)}`)
      return []
    }
  }

  async addSuccess(noteId: string, url: string, title: string, createdAtMs: number = 0): Promise<void> {
    const key = await this.historyKey()
    if (key === null) {
      return
    }
    const id = noteId.trim()
    const link = url.trim()
    if (id.length === 0 || link.length === 0) {
      return
    }
    const now = createdAtMs > 0 ? createdAtMs : Date.now()
    const next: LinkExtractHistoryItem[] = [{
      noteId: id,
      url: link,
      title: title.trim(),
      createdAtMs: now
    }]
    const existing = await this.list()
    for (let i = 0; i < existing.length; i++) {
      const item = existing[i]
      if (item.noteId === id || item.url === link) {
        continue
      }
      next.push(item)
      if (next.length >= LinkExtractHistoryService.MAX_ITEMS) {
        break
      }
    }
    try {
      await PreferencesService.getInstance().setPreferenceString(key, JSON.stringify(next))
    } catch (error) {
      Logger.warn('LinkExtractHistory', `addSuccess failed: ${JSON.stringify(error)}`)
    }
  }
}
