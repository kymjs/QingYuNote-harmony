import { preferences } from '@kit.ArkData'
import type common from '@ohos.app.ability.common'
import type { SyncPolicy, WebDAVConfig } from '../common/model/Note'
import { Logger } from '../common/utils/Logger'

const PREFERENCES_NAME = 'qingyu_preferences'
const TAG_LIST_KEY = 'note_tags'

export class PreferencesService {
  private static instance: PreferencesService = new PreferencesService()
  private context?: common.Context
  private store?: preferences.Preferences

  static getInstance(): PreferencesService {
    return PreferencesService.instance
  }

  async init(context: common.Context): Promise<void> {
    if (this.store) {
      return
    }
    try {
      this.context = context
      this.store = preferences.getPreferencesSync(this.context, {
        name: PREFERENCES_NAME
      })
    } catch (error) {
      Logger.warn('PreferencesService', `init failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  private ensureStore(): preferences.Preferences {
    if (!this.store) {
      throw new Error('PreferencesService has not been initialized')
    }
    return this.store
  }

  async saveWebDAVConfig(config: WebDAVConfig): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync('webdav_baseUrl', config.baseUrl)
      store.putSync('webdav_username', config.username)
      store.putSync('webdav_password', config.encryptedPassword)
      store.putSync('webdav_notesDir', config.notesDir)
      store.putSync('webdav_enabled', config.enabled)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `saveWebDAVConfig failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async getWebDAVConfig(): Promise<WebDAVConfig | null> {
    try {
      const store = this.ensureStore()
      const baseUrl = store.getSync('webdav_baseUrl', '') as string
      if (baseUrl.length === 0) {
        return null
      }
      return {
        baseUrl,
        username: store.getSync('webdav_username', '') as string,
        encryptedPassword: store.getSync('webdav_password', '') as string,
        notesDir: store.getSync('webdav_notesDir', '/qingyu-notes/') as string,
        enabled: store.getSync('webdav_enabled', false) as boolean
      }
    } catch (error) {
      Logger.warn('PreferencesService', `getWebDAVConfig failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async saveSyncPolicy(policy: SyncPolicy): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync('sync_autoSync', policy.autoSync)
      store.putSync('sync_interval', policy.syncIntervalMinutes)
      store.putSync('sync_wifiOnly', policy.wifiOnly)
      store.putSync('sync_debounce', policy.debounceSeconds)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `saveSyncPolicy failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async getSyncPolicy(): Promise<SyncPolicy> {
    try {
      const store = this.ensureStore()
      return {
        autoSync: store.getSync('sync_autoSync', true) as boolean,
        syncIntervalMinutes: store.getSync('sync_interval', 60) as number,
        wifiOnly: store.getSync('sync_wifiOnly', false) as boolean,
        debounceSeconds: store.getSync('sync_debounce', 5) as number
      }
    } catch (error) {
      Logger.warn('PreferencesService', `getSyncPolicy failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async setLastSyncTime(timestamp: number): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync('last_sync_time', timestamp)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `setLastSyncTime failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async getLastSyncTime(): Promise<number> {
    try {
      return this.ensureStore().getSync('last_sync_time', 0) as number
    } catch (error) {
      Logger.warn('PreferencesService', `getLastSyncTime failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async setAuthInvalid(isInvalid: boolean): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync('auth_invalid', isInvalid)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `setAuthInvalid failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async isAuthInvalid(): Promise<boolean> {
    try {
      return this.ensureStore().getSync('auth_invalid', false) as boolean
    } catch (error) {
      Logger.warn('PreferencesService', `isAuthInvalid failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async saveNoteTags(tags: string[]): Promise<void> {
    try {
      const normalized = this.normalizeTags(tags)
      const store = this.ensureStore()
      store.putSync(TAG_LIST_KEY, JSON.stringify(normalized))
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `saveNoteTags failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async getNoteTags(): Promise<string[]> {
    try {
      const store = this.ensureStore()
      const serialized = store.getSync(TAG_LIST_KEY, '[]') as string
      if (serialized.trim().length === 0) {
        return []
      }
      let parsed: Object = []
      try {
        parsed = JSON.parse(serialized)
      } catch (_) {
        parsed = []
      }
      if (!Array.isArray(parsed)) {
        return []
      }
      return this.normalizeTags(parsed as string[])
    } catch (error) {
      Logger.warn('PreferencesService', `getNoteTags failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  private normalizeTags(tags: string[]): string[] {
    const seen: Set<string> = new Set()
    const normalized: string[] = []
    for (const rawTag of tags) {
      const tag = `${rawTag ?? ''}`.trim()
      if (tag.length === 0 || seen.has(tag)) {
        continue
      }
      seen.add(tag)
      normalized.push(tag)
    }
    normalized.sort((left: string, right: string) => left.localeCompare(right, 'zh-Hans-CN'))
    return normalized
  }

  private describeError(error: Object): string {
    const raw = JSON.stringify(error)
    return raw.length > 0 && raw !== '{}' ? raw : `${error}`
  }

  private toRuntimeError(error: Object): Error {
    return new Error(this.describeError(error))
  }
}
