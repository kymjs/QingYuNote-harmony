import { preferences } from '@kit.ArkData'
import { AppContextHolder } from './AppContextHolder'
import { NoteApiClient } from './NoteApiClient'
import { PreferencesService } from './PreferencesService'

const PREFERENCES_NAME = 'qingyu_preferences'
const LATEST_KEY_PREFIX = 'feedback_reply_latest_json_'
const LAST_READ_KEY_PREFIX = 'feedback_reply_last_read_id_'

export interface FeedbackReplyItem {
  id: number
  feedbackContent: string
  feedbackType: string
  officialReply: string
  createdAt: string
}

type InboxListener = () => void

/** 官方反馈回复本地收件箱（与 Flutter FeedbackReplyInbox 对齐）。 */
export class FeedbackReplyInbox {
  private static instance: FeedbackReplyInbox = new FeedbackReplyInbox()
  private latest: FeedbackReplyItem | null = null
  private lastReadId: number = 0
  private loaded: boolean = false
  private listeners: InboxListener[] = []

  static getInstance(): FeedbackReplyInbox {
    return FeedbackReplyInbox.instance
  }

  addListener(listener: InboxListener): void {
    this.listeners.push(listener)
  }

  removeListener(listener: InboxListener): void {
    this.listeners = this.listeners.filter((item: InboxListener) => item !== listener)
  }

  private notify(): void {
    const copy = this.listeners.slice()
    for (let i = 0; i < copy.length; i++) {
      try {
        copy[i]()
      } catch (_) {
      }
    }
  }

  getLatest(): FeedbackReplyItem | null {
    return this.latest
  }

  hasReply(): boolean {
    return this.latest !== null && this.latest.id > 0
  }

  hasUnread(): boolean {
    return this.hasReply() && this.latest !== null && this.latest.id !== this.lastReadId
  }

  latestToJsonObject(): Record<string, Object> | null {
    if (this.latest === null) {
      return null
    }
    const out: Record<string, Object> = {
      'id': this.latest.id,
      'feedback_content': this.latest.feedbackContent,
      'feedback_type': this.latest.feedbackType,
      'official_reply': this.latest.officialReply,
      'created_at': this.latest.createdAt
    }
    return out
  }

  async ensureLoaded(): Promise<void> {
    if (this.loaded) {
      return
    }
    await this.readLocal()
    this.loaded = true
    this.notify()
  }

  async refreshFromServer(): Promise<void> {
    const prefs = PreferencesService.getInstance()
    if (await prefs.isGuestMode()) {
      await this.clearLocal()
      return
    }
    const loggedIn = await prefs.isUserLoggedIn()
    if (!loggedIn) {
      await this.clearLocal()
      return
    }
    await this.readLocal()
    const result = await NoteApiClient.getInstance().fetchLatestFeedbackReply()
    if (result === 'network_error') {
      this.loaded = true
      this.notify()
      return
    }
    if (result === null) {
      await this.persistLatest(null)
    } else {
      await this.persistLatest(result)
    }
    this.loaded = true
    this.notify()
  }

  async markCurrentRead(): Promise<void> {
    await this.ensureLoaded()
    if (this.latest === null || this.latest.id <= 0) {
      return
    }
    if (this.lastReadId === this.latest.id) {
      return
    }
    this.lastReadId = this.latest.id
    const userId = (await PreferencesService.getInstance().getNoteApiUserId()).trim()
    if (userId.length === 0) {
      return
    }
    const store = await this.openStore()
    if (store === null) {
      return
    }
    store.putSync(`${LAST_READ_KEY_PREFIX}${userId}`, this.lastReadId)
    await store.flush()
    this.notify()
  }

  async clearLocal(): Promise<void> {
    const userId = (await PreferencesService.getInstance().getNoteApiUserId()).trim()
    const store = await this.openStore()
    if (store !== null && userId.length > 0) {
      store.deleteSync(`${LATEST_KEY_PREFIX}${userId}`)
      store.deleteSync(`${LAST_READ_KEY_PREFIX}${userId}`)
      await store.flush()
    }
    this.latest = null
    this.lastReadId = 0
    this.loaded = true
    this.notify()
  }

  private async openStore(): Promise<preferences.Preferences | null> {
    try {
      const context = AppContextHolder.tryGetContext()
      if (context === undefined) {
        return null
      }
      return preferences.getPreferencesSync(context, { name: PREFERENCES_NAME })
    } catch (_) {
      return null
    }
  }

  private async readLocal(): Promise<void> {
    const userId = (await PreferencesService.getInstance().getNoteApiUserId()).trim()
    if (userId.length === 0) {
      this.latest = null
      this.lastReadId = 0
      return
    }
    const store = await this.openStore()
    if (store === null) {
      this.latest = null
      this.lastReadId = 0
      return
    }
    const raw = (store.getSync(`${LATEST_KEY_PREFIX}${userId}`, '') as string) ?? ''
    if (raw.trim().length === 0) {
      this.latest = null
    } else {
      try {
        const obj = JSON.parse(raw) as Record<string, Object>
        this.latest = FeedbackReplyInbox.parseItem(obj)
      } catch (_) {
        this.latest = null
      }
    }
    const readRaw = store.getSync(`${LAST_READ_KEY_PREFIX}${userId}`, 0)
    this.lastReadId = typeof readRaw === 'number' ? readRaw : 0
  }

  private async persistLatest(item: FeedbackReplyItem | null): Promise<void> {
    const userId = (await PreferencesService.getInstance().getNoteApiUserId()).trim()
    if (userId.length === 0) {
      this.latest = null
      return
    }
    const store = await this.openStore()
    this.latest = item
    if (store === null) {
      return
    }
    if (item === null) {
      store.deleteSync(`${LATEST_KEY_PREFIX}${userId}`)
      await store.flush()
      return
    }
    const json = JSON.stringify({
      'id': item.id,
      'feedback_content': item.feedbackContent,
      'feedback_type': item.feedbackType,
      'official_reply': item.officialReply,
      'created_at': item.createdAt
    })
    store.putSync(`${LATEST_KEY_PREFIX}${userId}`, json)
    await store.flush()
  }

  static parseItem(obj: Record<string, Object> | null): FeedbackReplyItem | null {
    if (obj === null) {
      return null
    }
    const idRaw = obj['id']
    const id = typeof idRaw === 'number' ? idRaw : Number(idRaw)
    const content = `${obj['feedback_content'] ?? ''}`.trim()
    const reply = `${obj['official_reply'] ?? ''}`.trim()
    if (!Number.isFinite(id) || id <= 0 || content.length === 0 || reply.length === 0) {
      return null
    }
    return {
      id: Math.floor(id),
      feedbackContent: content,
      feedbackType: `${obj['feedback_type'] ?? ''}`.trim(),
      officialReply: reply,
      createdAt: `${obj['created_at'] ?? ''}`.trim()
    }
  }
}
