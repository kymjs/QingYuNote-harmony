import { preferences } from '@kit.ArkData'
import type common from '@ohos.app.ability.common'
import type { SyncPolicy, WebDAVConfig, WebDAVProvider } from '../common/model/Note'
import { Logger } from '../common/utils/Logger'
import { buildQingyuCloudWebDavConfig } from './QingyuCloudConfigHelper'

const PREFERENCES_NAME = 'qingyu_preferences'
const TAG_LIST_KEY = 'note_tags'
const WECHAT_LOGGED_IN_KEY = 'account_wechat_logged_in'
const HUAWEI_LOGGED_IN_KEY = 'account_huawei_logged_in'
const NOTE_API_USER_ID_KEY = 'note_api_user_id'
const NOTE_API_ACCESS_TOKEN_KEY = 'note_api_access_token'
const NOTE_API_EXPIRES_AT_MS_KEY = 'note_api_expires_at_ms'
/** 与 Flutter `prefGuestModeKey` 对齐：未绑定 Note API 亦可进入首页 */
const GUEST_MODE_KEY = 'guest_mode'
/** 登录成功后导航：`Login` 消费并清空（OAuth 返回后 router params 可能丢失） */
const LOGIN_RETURN_TARGET_KEY = 'login_return_target'

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
      const provider: WebDAVProvider = config.provider
      store.putSync('sync_provider', provider)
      if (provider === 'qingyu_cloud') {
        // 轻羽云：仅持久化是否启用与方案选择；URL/账号/目录由启动时从 Note API 拉取，不落盘。
        store.putSync('webdav_enabled', config.enabled)
        store.putSync('webdav_baseUrl', '')
        store.putSync('webdav_username', '')
        store.putSync('webdav_password', '')
        store.putSync('webdav_notesDir', '')
        await store.flush()
        return
      }
      store.putSync('webdav_baseUrl', config.baseUrl)
      store.putSync('webdav_username', config.username)
      store.putSync('webdav_password', config.encryptedPassword)
      store.putSync('webdav_notesDir', config.notesDir)
      store.putSync('webdav_enabled', config.enabled)
      if (provider === 'webdav') {
        store.putSync('saved_webdav_baseUrl', config.baseUrl)
        store.putSync('saved_webdav_username', config.username)
        store.putSync('saved_webdav_notesDir', config.notesDir)
        store.putSync('saved_webdav_password_enc', config.encryptedPassword)
      }
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `saveWebDAVConfig failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async getSyncProvider(): Promise<WebDAVProvider> {
    try {
      const store = this.ensureStore()
      return store.getSync('sync_provider', 'webdav') as WebDAVProvider
    } catch (error) {
      Logger.warn('PreferencesService', `getSyncProvider failed: ${this.describeError(error as Object)}`)
      return 'webdav'
    }
  }

  async getWebDAVConfig(): Promise<WebDAVConfig | null> {
    try {
      const store = this.ensureStore()
      const provider = store.getSync('sync_provider', 'webdav') as WebDAVProvider
      if (provider === 'qingyu_cloud') {
        return await this.buildQingyuCloudConfig(store)
      }
      return this.buildCustomWebDAVConfig(store)
    } catch (error) {
      Logger.warn('PreferencesService', `getWebDAVConfig failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  /**
   * 云同步设置页在「已选轻羽云但尚未保存 sync_provider」时，仍需按轻羽目录拉取订阅状态；
   * 与 getWebDAVConfig() 不同，此方法不读取 sync_provider，始终按当前 Note API 会话推导轻羽 WebDAV 配置。
   */
  async getQingyuCloudConfigPreview(): Promise<WebDAVConfig | null> {
    try {
      const store = this.ensureStore()
      return await this.buildQingyuCloudConfig(store)
    } catch (error) {
      Logger.warn('PreferencesService',
        `getQingyuCloudConfigPreview failed: ${this.describeError(error as Object)}`)
      return null
    }
  }

  private buildCustomWebDAVConfig(store: preferences.Preferences): WebDAVConfig | null {
    try {
      const baseUrl = store.getSync('saved_webdav_baseUrl', '') as string
      if (baseUrl.length === 0) {
        return null
      }
      const username = store.getSync('saved_webdav_username', '') as string
      const encryptedPassword = store.getSync('saved_webdav_password_enc', '') as string
      const notesDir = store.getSync('saved_webdav_notesDir', '/qingyu-notes/') as string
      const enabled =
        baseUrl.length > 0 && username.length > 0 && encryptedPassword.length > 0
      return {
        baseUrl,
        username,
        encryptedPassword,
        notesDir,
        enabled,
        provider: 'webdav'
      }
    } catch (error) {
      Logger.warn('PreferencesService',
        `buildCustomWebDAVConfig failed: ${this.describeError(error as Object)}`)
      return null
    }
  }

  /**
   * 轻羽云目录名派生用稳定身份：与 Note API 用户主键 `users.id` 一致（字符串十进制）。
   */
  async resolveActiveQingyuFolderIdentityKey(): Promise<string | null> {
    try {
      const id = (await this.getNoteApiUserId()).trim()
      return id.length > 0 ? id : null
    } catch (error) {
      Logger.warn('PreferencesService',
        `resolveActiveQingyuFolderIdentityKey failed: ${this.describeError(error as Object)}`)
      return null
    }
  }

  private async buildQingyuCloudConfig(store: preferences.Preferences): Promise<WebDAVConfig | null> {
    const base = await buildQingyuCloudWebDavConfig()
    if (base === null) {
      return null
    }
    try {
      const enabled = store.getSync('webdav_enabled', true) as boolean
      return {
        baseUrl: base.baseUrl,
        username: base.username,
        encryptedPassword: base.encryptedPassword,
        notesDir: base.notesDir,
        enabled,
        provider: 'qingyu_cloud'
      }
    } catch (error) {
      Logger.warn('PreferencesService',
        `buildQingyuCloudConfig failed: ${this.describeError(error as Object)}`)
      return null
    }
  }

  async saveSyncProvider(provider: WebDAVProvider): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync('sync_provider', provider)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `saveSyncProvider failed: ${this.describeError(error as Object)}`)
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

  async setWeChatLoggedIn(loggedIn: boolean): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(WECHAT_LOGGED_IN_KEY, loggedIn)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `setWeChatLoggedIn failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async isWeChatLoggedIn(): Promise<boolean> {
    try {
      return this.ensureStore().getSync(WECHAT_LOGGED_IN_KEY, false) as boolean
    } catch (error) {
      Logger.warn('PreferencesService', `isWeChatLoggedIn failed: ${this.describeError(error as Object)}`)
      return false
    }
  }

  async setHuaweiLoggedIn(loggedIn: boolean): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(HUAWEI_LOGGED_IN_KEY, loggedIn)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `setHuaweiLoggedIn failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async isHuaweiLoggedIn(): Promise<boolean> {
    try {
      return this.ensureStore().getSync(HUAWEI_LOGGED_IN_KEY, false) as boolean
    } catch (error) {
      Logger.warn('PreferencesService', `isHuaweiLoggedIn failed: ${this.describeError(error as Object)}`)
      return false
    }
  }

  /** 存在 Note API 用户主键即视为已登录（用于首屏与登录页跳转）。 */
  async isUserLoggedIn(): Promise<boolean> {
    try {
      return (await this.getNoteApiUserId()).trim().length > 0
    } catch (error) {
      Logger.warn('PreferencesService', `isUserLoggedIn failed: ${this.describeError(error as Object)}`)
      return false
    }
  }

  /** 与 Flutter `isGuestMode` / `setGuestMode` 对齐 */
  async isGuestMode(): Promise<boolean> {
    try {
      return this.ensureStore().getSync(GUEST_MODE_KEY, false) as boolean
    } catch (error) {
      Logger.warn('PreferencesService', `isGuestMode failed: ${this.describeError(error as Object)}`)
      return false
    }
  }

  async setGuestMode(value: boolean): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(GUEST_MODE_KEY, value)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `setGuestMode failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  /** 从云同步等页打开 `Login` 前写入；见 `peekLoginReturnTarget` / `clearLoginReturnTarget` */
  async setLoginReturnTarget(value: string): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(LOGIN_RETURN_TARGET_KEY, value.trim())
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `setLoginReturnTarget failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async peekLoginReturnTarget(): Promise<string> {
    try {
      return (this.ensureStore().getSync(LOGIN_RETURN_TARGET_KEY, '') as string).trim()
    } catch (error) {
      Logger.warn('PreferencesService', `peekLoginReturnTarget failed: ${this.describeError(error as Object)}`)
      return ''
    }
  }

  async clearLoginReturnTarget(): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(LOGIN_RETURN_TARGET_KEY, '')
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `clearLoginReturnTarget failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async setNoteApiUserId(id: string): Promise<void> {
    try {
      const store = this.ensureStore()
      const trimmed = id.trim()
      store.putSync(NOTE_API_USER_ID_KEY, trimmed)
      if (trimmed.length > 0) {
        store.putSync(GUEST_MODE_KEY, false)
      }
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `setNoteApiUserId failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async getNoteApiUserId(): Promise<string> {
    try {
      return this.ensureStore().getSync(NOTE_API_USER_ID_KEY, '') as string
    } catch (error) {
      Logger.warn('PreferencesService', `getNoteApiUserId failed: ${this.describeError(error as Object)}`)
      return ''
    }
  }

  /** 清除第三方登录态及本地缓存的用户标识（不删除笔记与 WebDAV 等业务配置）。 */
  async setNoteApiSession(accessToken: string, expiresInSec: number): Promise<void> {
    try {
      const store = this.ensureStore()
      const skewMs = 60_000
      const exp = Date.now() + expiresInSec * 1000 - skewMs
      store.putSync(NOTE_API_ACCESS_TOKEN_KEY, accessToken)
      store.putSync(NOTE_API_EXPIRES_AT_MS_KEY, exp)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `setNoteApiSession failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async getNoteApiAccessToken(): Promise<string | null> {
    try {
      const store = this.ensureStore()
      const tok = store.getSync(NOTE_API_ACCESS_TOKEN_KEY, '') as string
      const exp = store.getSync(NOTE_API_EXPIRES_AT_MS_KEY, 0) as number
      if (tok.trim().length === 0) {
        return null
      }
      if (exp > 0 && Date.now() > exp) {
        return null
      }
      return tok.trim()
    } catch (error) {
      Logger.warn('PreferencesService', `getNoteApiAccessToken failed: ${this.describeError(error as Object)}`)
      return null
    }
  }

  async clearNoteApiSession(): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(NOTE_API_ACCESS_TOKEN_KEY, '')
      store.putSync(NOTE_API_EXPIRES_AT_MS_KEY, 0)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `clearNoteApiSession failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async clearLoginSession(): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(WECHAT_LOGGED_IN_KEY, false)
      store.putSync(HUAWEI_LOGGED_IN_KEY, false)
      store.putSync(NOTE_API_USER_ID_KEY, '')
      store.putSync(GUEST_MODE_KEY, false)
      store.putSync('auth_invalid', false)
      store.putSync(NOTE_API_ACCESS_TOKEN_KEY, '')
      store.putSync(NOTE_API_EXPIRES_AT_MS_KEY, 0)
      store.putSync(LOGIN_RETURN_TARGET_KEY, '')
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `clearLoginSession failed: ${this.describeError(error as Object)}`)
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
