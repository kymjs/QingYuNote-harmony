import { preferences } from '@kit.ArkData'
import type common from '@ohos.app.ability.common'
import type { SyncPolicy, WebDAVConfig, WebDAVProvider } from '../common/model/Note'
import { Logger } from '../common/utils/Logger'
import { CryptoService } from './CryptoService'
import { SyncConstants } from '../common/constants/SyncConstants'

const PREFERENCES_NAME = 'qingyu_preferences'
const TAG_LIST_KEY = 'note_tags'
const WECHAT_LOGGED_IN_KEY = 'account_wechat_logged_in'
const HUAWEI_LOGGED_IN_KEY = 'account_huawei_logged_in'
const THIRD_PARTY_USER_ID_KEY = 'third_party_user_id'
const THIRD_PARTY_HUAWEI_USER_ID_KEY = 'third_party_huawei_user_id'
const THIRD_PARTY_WECHAT_USER_ID_KEY = 'third_party_wechat_user_id'
/** 设置页展示用：当 Account Kit 未返回 union/open/idToken 时，缓存授权码指纹（不参与云目录派生）。 */
const HUAWEI_SETTINGS_DISPLAY_ID_KEY = 'huawei_settings_display_id'

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
      await this.migrateLegacyConnectionPrefs(store)
      return store.getSync('sync_provider', 'webdav') as WebDAVProvider
    } catch (error) {
      Logger.warn('PreferencesService', `getSyncProvider failed: ${this.describeError(error as Object)}`)
      return 'webdav'
    }
  }

  async getWebDAVConfig(): Promise<WebDAVConfig | null> {
    try {
      const store = this.ensureStore()
      await this.migrateLegacyConnectionPrefs(store)
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
   * 与 getWebDAVConfig() 不同，此方法不读取 sync_provider，始终按当前三方登录推导轻羽 WebDAV 配置。
   */
  async getQingyuCloudConfigPreview(): Promise<WebDAVConfig | null> {
    try {
      const store = this.ensureStore()
      await this.migrateLegacyConnectionPrefs(store)
      return await this.buildQingyuCloudConfig(store)
    } catch (error) {
      Logger.warn('PreferencesService',
        `getQingyuCloudConfigPreview failed: ${this.describeError(error as Object)}`)
      return null
    }
  }

  private async migrateLegacyConnectionPrefs(store: preferences.Preferences): Promise<void> {
    try {
      const done = store.getSync('conn_prefs_migrated', false) as boolean
      if (done) {
        return
      }
      const legacyUrl = store.getSync('webdav_baseUrl', '') as string
      const savedUrl = store.getSync('saved_webdav_baseUrl', '') as string
      if (legacyUrl.length > 0 && savedUrl.length === 0) {
        store.putSync('saved_webdav_baseUrl', legacyUrl)
        store.putSync('saved_webdav_username', store.getSync('webdav_username', '') as string)
        store.putSync('saved_webdav_notesDir', store.getSync('webdav_notesDir', '/qingyu-notes/') as string)
        store.putSync('saved_webdav_password_enc', store.getSync('webdav_password', '') as string)
        store.putSync('sync_provider', 'webdav')
      }
      store.putSync('conn_prefs_migrated', true)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService',
        `migrateLegacyConnectionPrefs failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
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
   * 轻羽云同步目录：`md5(当前三方登录唯一标识)`；标识优先微信登录会话，其次华为。
   */
  async resolveActiveQingyuFolderIdentityKey(): Promise<string | null> {
    await this.migrateLegacyThirdPartyUserIdIfNeeded(this.ensureStore())
    const wechatOn = await this.isWeChatLoggedIn()
    const huaweiOn = await this.isHuaweiLoggedIn()
    const wxId = this.ensureStore().getSync(THIRD_PARTY_WECHAT_USER_ID_KEY, '') as string
    const hwId = this.ensureStore().getSync(THIRD_PARTY_HUAWEI_USER_ID_KEY, '') as string
    if (wechatOn && wxId.trim().length > 0) {
      return wxId.trim()
    }
    if (huaweiOn && hwId.trim().length > 0) {
      return hwId.trim()
    }
    if (wxId.trim().length > 0) {
      return wxId.trim()
    }
    if (hwId.trim().length > 0) {
      return hwId.trim()
    }
    return null
  }

  private async migrateLegacyThirdPartyUserIdIfNeeded(store: preferences.Preferences): Promise<void> {
    try {
      const legacy = store.getSync(THIRD_PARTY_USER_ID_KEY, '') as string
      if (legacy.trim().length === 0) {
        return
      }
      const tri = legacy.trim()
      if (tri.startsWith('hw')) {
        const cur = store.getSync(THIRD_PARTY_HUAWEI_USER_ID_KEY, '') as string
        if (cur.length === 0) {
          store.putSync(THIRD_PARTY_HUAWEI_USER_ID_KEY, tri)
        }
      } else if (tri.startsWith('wx')) {
        const cur = store.getSync(THIRD_PARTY_WECHAT_USER_ID_KEY, '') as string
        if (cur.length === 0) {
          store.putSync(THIRD_PARTY_WECHAT_USER_ID_KEY, tri)
        }
      }
      store.putSync(THIRD_PARTY_USER_ID_KEY, '')
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService',
        `migrateLegacyThirdPartyUserIdIfNeeded failed: ${this.describeError(error as Object)}`)
    }
  }

  private async buildQingyuCloudConfig(_store: preferences.Preferences): Promise<WebDAVConfig | null> {
    try {
      const folderKey = await this.resolveActiveQingyuFolderIdentityKey()
      if (folderKey === null || folderKey.length === 0) {
        Logger.warn('PreferencesService', 'buildQingyuCloudConfig: no third-party login id for folder derivation')
        return null
      }
      const md5Dir = await CryptoService.getInstance().md5Hex(folderKey)
      const notesDir = `/${md5Dir}/`
      Logger.info('PreferencesService',
        `buildQingyuCloudConfig: derived md5Dir=${md5Dir}, notesDir=${notesDir}, baseUrl=${SyncConstants.qingyuWebDavBaseUrl}`)
      const encFromStore = _store.getSync('webdav_password', '') as string
      const encryptedPassword = encFromStore.length > 0
        ? encFromStore
        : await CryptoService.getInstance().encryptText(SyncConstants.qingyuWebDavPassword)
      return {
        baseUrl: SyncConstants.qingyuWebDavBaseUrl,
        username: SyncConstants.qingyuWebDavUsername,
        encryptedPassword,
        notesDir,
        enabled: true,
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

  /** 任一第三方账号登录成功即视为已登录（用于首屏与登录页跳转）。 */
  async isUserLoggedIn(): Promise<boolean> {
    const wechat = await this.isWeChatLoggedIn()
    if (wechat) {
      return true
    }
    return await this.isHuaweiLoggedIn()
  }

  async setHuaweiThirdPartyUserId(id: string): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(THIRD_PARTY_HUAWEI_USER_ID_KEY, id)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `setHuaweiThirdPartyUserId failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async setWeChatThirdPartyUserId(id: string): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(THIRD_PARTY_WECHAT_USER_ID_KEY, id)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `setWeChatThirdPartyUserId failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async getHuaweiThirdPartyUserId(): Promise<string> {
    try {
      await this.migrateLegacyThirdPartyUserIdIfNeeded(this.ensureStore())
      return this.ensureStore().getSync(THIRD_PARTY_HUAWEI_USER_ID_KEY, '') as string
    } catch (error) {
      Logger.warn('PreferencesService', `getHuaweiThirdPartyUserId failed: ${this.describeError(error as Object)}`)
      return ''
    }
  }

  async getWeChatThirdPartyUserId(): Promise<string> {
    try {
      await this.migrateLegacyThirdPartyUserIdIfNeeded(this.ensureStore())
      return this.ensureStore().getSync(THIRD_PARTY_WECHAT_USER_ID_KEY, '') as string
    } catch (error) {
      Logger.warn('PreferencesService', `getWeChatThirdPartyUserId failed: ${this.describeError(error as Object)}`)
      return ''
    }
  }

  async setHuaweiSettingsDisplayId(id: string): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(HUAWEI_SETTINGS_DISPLAY_ID_KEY, id)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `setHuaweiSettingsDisplayId failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async getHuaweiSettingsDisplayId(): Promise<string> {
    try {
      return this.ensureStore().getSync(HUAWEI_SETTINGS_DISPLAY_ID_KEY, '') as string
    } catch (error) {
      Logger.warn('PreferencesService', `getHuaweiSettingsDisplayId failed: ${this.describeError(error as Object)}`)
      return ''
    }
  }

  /** 清除第三方登录态及本地缓存的用户标识（不删除笔记与 WebDAV 等业务配置）。 */
  async clearLoginSession(): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(WECHAT_LOGGED_IN_KEY, false)
      store.putSync(HUAWEI_LOGGED_IN_KEY, false)
      store.putSync(THIRD_PARTY_WECHAT_USER_ID_KEY, '')
      store.putSync(THIRD_PARTY_HUAWEI_USER_ID_KEY, '')
      store.putSync(THIRD_PARTY_USER_ID_KEY, '')
      store.putSync(HUAWEI_SETTINGS_DISPLAY_ID_KEY, '')
      store.putSync('auth_invalid', false)
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
