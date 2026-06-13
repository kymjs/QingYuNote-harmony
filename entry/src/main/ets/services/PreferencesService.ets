import { preferences } from '@kit.ArkData'
import type common from '@ohos.app.ability.common'
import type { SyncPolicy, WebDAVConfig, WebDAVProvider } from '../common/model/Note'
import { util } from '@kit.ArkTS'
import { Logger } from '../common/utils/Logger'
import { buildQingyuCloudWebDavConfig } from './QingyuCloudConfigHelper'
import { NoteSettingsService } from './NoteSettingsService'
import { NoteSettingsRemoteSync } from './NoteSettingsRemoteSync'

const PREFERENCES_NAME = 'qingyu_preferences'
const TAG_LIST_KEY = 'note_tags'
/** 与 Flutter `AppConst.prefHomeSidebarFilterModeKey` 一致：`tag` | `folder` */
const HOME_SIDEBAR_FILTER_MODE_KEY = 'home_sidebar_filter_mode'
const HUAWEI_LOGGED_IN_KEY = 'account_huawei_logged_in'
const NOTE_API_USER_ID_KEY = 'note_api_user_id'
const NOTE_API_ACCESS_TOKEN_KEY = 'note_api_access_token'
const NOTE_API_EXPIRES_AT_MS_KEY = 'note_api_expires_at_ms'
/** 与 Flutter `AppConst.prefCachedUserProfileKey` 一致：最近一次成功拉取的 profile，按用户 id 隔离 */
const NOTE_API_CACHED_USER_PROFILE_KEY = 'note_api_cached_user_profile'
/**
 * 与 Flutter `AppConst.prefSmsDeviceIdKey` 键名一致（`note_api_sms_device_id`）。
 *
 * **服务端（维护者）**：`POST /api/v1/register/sms/send` 与 `POST /api/v1/password/reset/sms/send` 在调阿里云前，
 * 对客户端 IP、规范化手机号、设备 ID 三轴各自做滑动 24 小时窗口计数，每轴上限 3 次；两接口共用计数。
 * 详见仓库 `server/TECHNICAL.md` §2.11 与 `internal/api/sms_public_quota.go`。
 *
 * **对用户**：错误码 `sms_quota_exceeded` 时仅展示泛化 Toast，勿写「每 IP / 每设备 / 3 次」等文案。
 */
const NOTE_SMS_DEVICE_ID_KEY = 'note_api_sms_device_id'
/** 与 Flutter `prefGuestModeKey` 对齐：未绑定 Note API 亦可进入首页 */
const GUEST_MODE_KEY = 'guest_mode'
/** 与 Flutter `prefNoteQuickActionBarEnabledKey` 一致 */
const NOTE_QUICK_ACTION_BAR_ENABLED_KEY = 'note_quick_action_bar_enabled'
/** 与 Flutter `prefNoteFolderModeEnabledKey` 一致 */
const NOTE_FOLDER_MODE_ENABLED_KEY = 'note_folder_mode_enabled'
/** 与 Flutter `prefBetaTestInviteDialogShownKey` 一致：公测邀请弹窗已展示过则不再弹出 */
const BETA_TEST_INVITE_DIALOG_SHOWN_KEY = 'beta_test_invite_dialog_shown'
/** 与 Flutter `prefMembershipExpiryReminderLastShownYmdKey` 一致：会员到期提醒弹窗上次展示日期 */
const MEMBERSHIP_EXPIRY_REMINDER_LAST_SHOWN_YMD_KEY = 'membership_expiry_reminder_last_shown_ymd'
/** 与 Flutter `prefAiMembershipGateDialogShownKey` 一致：AI 会员拦截弹窗已展示过则不再弹出 */
const AI_MEMBERSHIP_GATE_DIALOG_SHOWN_KEY = 'ai_membership_gate_dialog_shown'
/** 与 Flutter `AppConst.prefShareCardThemeKey` 一致 */
const SHARE_CARD_THEME_KEY = 'share_card_theme'
/** 与 Flutter `AppConst.prefShareCardToneKey` 一致 */
const SHARE_CARD_TONE_KEY = 'share_card_tone'
/** 登录成功后导航：`Login` 消费并清空（OAuth 返回后 router params 可能丢失） */
const LOGIN_RETURN_TARGET_KEY = 'login_return_target'
/** 与 Flutter `AppConst.prefBiometricLockEnabledKey` 一致：本机生物识别锁，不同步远端 */
const APP_BIOMETRIC_LOCK_ENABLED_KEY = 'app_biometric_lock_enabled'
/** 与 Flutter `AppConst.prefWereadApiKeyKey` 一致：微信读书 Skills API Key */
const WEREAD_API_KEY = 'weread_api_key'

export interface LegacyNoteSettingsFlags {
  quick: boolean
  folder: boolean
}

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

  /**
   * 仅读 preferences，不请求 Note API。
   * 用于订阅状态展示；避免 `getWebDAVConfig` 因 `/qingyu/webdav` 失败为 null 时被误判为未开通轻羽云。
   */
  async getQingyuCloudSyncIntent(): Promise<'not_qingyu' | 'disabled' | 'qingyu'> {
    try {
      const store = this.ensureStore()
      const provider = store.getSync('sync_provider', 'webdav') as WebDAVProvider
      const enabled = store.getSync('webdav_enabled', true) as boolean
      if (provider !== 'qingyu_cloud') {
        return 'not_qingyu'
      }
      if (!enabled) {
        return 'disabled'
      }
      return 'qingyu'
    } catch (error) {
      Logger.warn('PreferencesService', `getQingyuCloudSyncIntent failed: ${this.describeError(error as Object)}`)
      return 'not_qingyu'
    }
  }

  async getWebDAVConfig(): Promise<WebDAVConfig | null> {
    try {
      const store = this.ensureStore()
      const custom = this.buildCustomWebDAVConfig(store)
      if (custom !== null && custom.enabled) {
        return custom
      }
      const provider = store.getSync('sync_provider', 'webdav') as WebDAVProvider
      if (provider === 'qingyu_cloud') {
        return await this.buildQingyuCloudConfig(store)
      }
      return custom
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

  /** 是否曾保存过自建 WebDAV（`saved_webdav_baseUrl` 非空）。与 Flutter 对齐。 */
  async hasSavedCustomWebDAVConfig(): Promise<boolean> {
    try {
      const store = this.ensureStore()
      const baseUrl = (store.getSync('saved_webdav_baseUrl', '') as string).trim()
      return baseUrl.length > 0
    } catch (error) {
      Logger.warn('PreferencesService',
        `hasSavedCustomWebDAVConfig failed: ${this.describeError(error as Object)}`)
      return false
    }
  }

  /** 读取持久化的自建 WebDAV（`saved_*`），不受当前 sync_provider 影响。 */
  async getSavedCustomWebDAVConfigSnapshot(): Promise<WebDAVConfig | null> {
    try {
      const store = this.ensureStore()
      return this.buildCustomWebDAVConfig(store)
    } catch (error) {
      Logger.warn('PreferencesService',
        `getSavedCustomWebDAVConfigSnapshot failed: ${this.describeError(error as Object)}`)
      return null
    }
  }

  /** 首页自动选用轻羽云：无自建 WebDAV、且本地未处于「已启用轻羽云同步」或「用户已关闭轻羽同步」。 */
  async shouldAttemptAutoQingyuCloudProvisioning(): Promise<boolean> {
    try {
      if (await this.isGuestMode()) {
        return false
      }
      if (!(await this.isUserLoggedIn())) {
        return false
      }
      if (await this.hasSavedCustomWebDAVConfig()) {
        return false
      }
      const intent = await this.getQingyuCloudSyncIntent()
      if (intent === 'qingyu') {
        return false
      }
      if (intent === 'disabled') {
        return false
      }
      return true
    } catch (error) {
      Logger.warn('PreferencesService',
        `shouldAttemptAutoQingyuCloudProvisioning failed: ${this.describeError(error as Object)}`)
      return false
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

  /** 与 Flutter `prefLastRemoteIndexUpdatedAtKey` 对齐。 */
  async setLastRemoteIndexUpdatedAt(timestamp: number): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync('last_remote_index_updated_at', timestamp)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService',
        `setLastRemoteIndexUpdatedAt failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async getLastRemoteIndexUpdatedAt(): Promise<number> {
    try {
      return this.ensureStore().getSync('last_remote_index_updated_at', 0) as number
    } catch (error) {
      Logger.warn('PreferencesService',
        `getLastRemoteIndexUpdatedAt failed: ${this.describeError(error as Object)}`)
      return 0
    }
  }

  /** 与 Flutter `prefLastRemoteIndexFingerprintKey` 对齐。 */
  async setLastRemoteIndexFingerprint(value: string): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync('last_remote_index_fingerprint', value)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService',
        `setLastRemoteIndexFingerprint failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async getLastRemoteIndexFingerprint(): Promise<string> {
    try {
      return this.ensureStore().getSync('last_remote_index_fingerprint', '') as string
    } catch (error) {
      Logger.warn('PreferencesService',
        `getLastRemoteIndexFingerprint failed: ${this.describeError(error as Object)}`)
      return ''
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

  /** 写入当前登录用户的资料缓存（与 [getCachedUserProfile] 成对使用）。 */
  async saveCachedUserProfile(profile: Record<string, Object>): Promise<void> {
    try {
      const userId = (await this.getNoteApiUserId()).trim()
      if (userId.length === 0) {
        return
      }
      const store = this.ensureStore()
      store.putSync(
        NOTE_API_CACHED_USER_PROFILE_KEY,
        JSON.stringify({ user_id: userId, profile: profile })
      )
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `saveCachedUserProfile failed: ${this.describeError(error as Object)}`)
    }
  }

  /** 读取当前登录用户上次成功拉取的资料；用户 id 不匹配时返回 null。 */
  async getCachedUserProfile(): Promise<Record<string, Object> | null> {
    try {
      const userId = (await this.getNoteApiUserId()).trim()
      if (userId.length === 0) {
        return null
      }
      const store = this.ensureStore()
      const raw = `${store.getSync(NOTE_API_CACHED_USER_PROFILE_KEY, '') ?? ''}`.trim()
      if (raw.length === 0) {
        return null
      }
      const decoded = JSON.parse(raw) as Record<string, Object>
      if (`${decoded['user_id'] ?? ''}`.trim() !== userId) {
        return null
      }
      const profile = decoded['profile']
      if (profile === null || profile === undefined || typeof profile !== 'object') {
        return null
      }
      return profile as Record<string, Object>
    } catch (error) {
      Logger.warn('PreferencesService', `getCachedUserProfile failed: ${this.describeError(error as Object)}`)
      return null
    }
  }

  async clearCachedUserProfile(): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(NOTE_API_CACHED_USER_PROFILE_KEY, '')
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `clearCachedUserProfile failed: ${this.describeError(error as Object)}`)
    }
  }

  /** 公测邀请弹窗是否已在本地展示过（设备维度，永久不再弹出）。 */
  async hasBetaTestInviteDialogShown(): Promise<boolean> {
    try {
      const store = this.ensureStore()
      return store.getSync(BETA_TEST_INVITE_DIALOG_SHOWN_KEY, false) as boolean
    } catch (error) {
      Logger.warn('PreferencesService',
        `hasBetaTestInviteDialogShown failed: ${this.describeError(error as Object)}`)
      return false
    }
  }

  async setBetaTestInviteDialogShown(value: boolean): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(BETA_TEST_INVITE_DIALOG_SHOWN_KEY, value)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService',
        `setBetaTestInviteDialogShown failed: ${this.describeError(error as Object)}`)
    }
  }

  /** 会员到期提醒弹窗上次展示日期（`YYYY-MM-DD`）；空表示当日尚未展示。 */
  async getMembershipExpiryReminderLastShownYmd(): Promise<string> {
    try {
      const store = this.ensureStore()
      return (store.getSync(MEMBERSHIP_EXPIRY_REMINDER_LAST_SHOWN_YMD_KEY, '') as string).trim()
    } catch (error) {
      Logger.warn('PreferencesService',
        `getMembershipExpiryReminderLastShownYmd failed: ${this.describeError(error as Object)}`)
      return ''
    }
  }

  /** AI 会员拦截弹窗是否已在本地展示过（设备维度，再次点击直达充值页）。 */
  async hasAiMembershipGateDialogShown(): Promise<boolean> {
    try {
      const store = this.ensureStore()
      return store.getSync(AI_MEMBERSHIP_GATE_DIALOG_SHOWN_KEY, false) as boolean
    } catch (error) {
      Logger.warn('PreferencesService',
        `hasAiMembershipGateDialogShown failed: ${this.describeError(error as Object)}`)
      return false
    }
  }

  async setAiMembershipGateDialogShown(value: boolean): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(AI_MEMBERSHIP_GATE_DIALOG_SHOWN_KEY, value)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService',
        `setAiMembershipGateDialogShown failed: ${this.describeError(error as Object)}`)
    }
  }

  async setMembershipExpiryReminderLastShownYmd(ymd: string): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(MEMBERSHIP_EXPIRY_REMINDER_LAST_SHOWN_YMD_KEY, ymd.trim())
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService',
        `setMembershipExpiryReminderLastShownYmd failed: ${this.describeError(error as Object)}`)
    }
  }

  /**
   * 首次调用生成 UUID 写入 preferences，之后只读；与 Flutter `getOrCreateSmsDeviceId` 对齐。
   * 值通过 `X-Device-Id` / JSON `device_id` 发往 Note API，供公开短信频控「设备」维度使用。
   * 规则与运维注意见 `server/TECHNICAL.md` §2.11。
   */
  async getOrCreateSmsDeviceId(): Promise<string> {
    try {
      const store = this.ensureStore()
      let v = (store.getSync(NOTE_SMS_DEVICE_ID_KEY, '') as string).trim()
      if (v.length > 0) {
        return v
      }
      v = util.generateRandomUUID()
      store.putSync(NOTE_SMS_DEVICE_ID_KEY, v)
      await store.flush()
      return v
    } catch (error) {
      Logger.warn('PreferencesService', `getOrCreateSmsDeviceId failed: ${this.describeError(error as Object)}`)
      return util.generateRandomUUID()
    }
  }

  /** 覆盖安装等场景：userId 与 token 仅残留其一时清除，由启动页重新登录。 */
  async repairAbnormalLoginSessionIfNeeded(): Promise<boolean> {
    try {
      if (await this.isGuestMode()) {
        return false
      }
      const hasUserId = (await this.getNoteApiUserId()).trim().length > 0
      const tok = await this.getNoteApiAccessToken()
      const hasToken = tok !== null && tok.length > 0
      if (hasUserId === hasToken) {
        return false
      }
      await this.clearLoginSession()
      return true
    } catch (error) {
      Logger.warn('PreferencesService', `repairAbnormalLoginSessionIfNeeded failed: ${this.describeError(error as Object)}`)
      return false
    }
  }

  async clearLoginSession(): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(HUAWEI_LOGGED_IN_KEY, false)
      store.putSync(NOTE_API_USER_ID_KEY, '')
      store.putSync(GUEST_MODE_KEY, false)
      store.putSync('auth_invalid', false)
      store.putSync(NOTE_API_ACCESS_TOKEN_KEY, '')
      store.putSync(NOTE_API_EXPIRES_AT_MS_KEY, 0)
      store.putSync(LOGIN_RETURN_TARGET_KEY, '')
      store.putSync(NOTE_API_CACHED_USER_PROFILE_KEY, '')
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

  getWereadApiKey(): string {
    try {
      const store = this.ensureStore()
      return (store.getSync(WEREAD_API_KEY, '') as string) ?? ''
    } catch (_) {
      return ''
    }
  }

  async setWereadApiKey(value: string): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(WEREAD_API_KEY, value.trim())
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `setWereadApiKey failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  readLegacyNoteSettingsFlags(): LegacyNoteSettingsFlags {
    try {
      const store = this.ensureStore()
      const result: LegacyNoteSettingsFlags = {
        quick: store.getSync(NOTE_QUICK_ACTION_BAR_ENABLED_KEY, true) as boolean,
        folder: store.getSync(NOTE_FOLDER_MODE_ENABLED_KEY, false) as boolean
      }
      return result
    } catch (_) {
      const fallback: LegacyNoteSettingsFlags = { quick: true, folder: false }
      return fallback
    }
  }

  async writeLegacyNoteSettingsFlags(quick: boolean, folder: boolean): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(NOTE_QUICK_ACTION_BAR_ENABLED_KEY, quick)
      store.putSync(NOTE_FOLDER_MODE_ENABLED_KEY, folder)
      await store.flush()
    } catch (error) {
      Logger.warn(
        'PreferencesService',
        `writeLegacyNoteSettingsFlags failed: ${this.describeError(error as Object)}`
      )
    }
  }

  async getNoteQuickActionBarEnabled(): Promise<boolean> {
    return await NoteSettingsService.getInstance().getNoteQuickActionBarEnabled()
  }

  async setNoteQuickActionBarEnabled(enabled: boolean): Promise<void> {
    await NoteSettingsService.getInstance().setNoteQuickActionBarEnabled(enabled)
    await NoteSettingsRemoteSync.getInstance().pushIfPossible(
      await NoteSettingsService.getInstance().exportDocument()
    )
  }

  async getNoteFolderModeEnabled(): Promise<boolean> {
    return await NoteSettingsService.getInstance().getNoteFolderModeEnabled()
  }

  async setNoteFolderModeEnabled(enabled: boolean): Promise<void> {
    await NoteSettingsService.getInstance().setNoteFolderModeEnabled(enabled)
    await NoteSettingsRemoteSync.getInstance().pushIfPossible(
      await NoteSettingsService.getInstance().exportDocument()
    )
  }

  async getAppLockEnabled(): Promise<boolean> {
    return await NoteSettingsService.getInstance().getAppLockEnabled()
  }

  async getAppLockPasswordEnc(): Promise<string> {
    return await NoteSettingsService.getInstance().getAppLockPasswordEnc()
  }

  async enableAppLock(encryptedPassword: string): Promise<void> {
    await NoteSettingsService.getInstance().enableAppLock(encryptedPassword)
    await NoteSettingsRemoteSync.getInstance().pushIfPossible(
      await NoteSettingsService.getInstance().exportDocument()
    )
  }

  async disableAppLock(): Promise<void> {
    await NoteSettingsService.getInstance().disableAppLock()
    await this.setBiometricLockEnabled(false)
    await NoteSettingsRemoteSync.getInstance().pushIfPossible(
      await NoteSettingsService.getInstance().exportDocument()
    )
  }

  async getBiometricLockEnabled(): Promise<boolean> {
    try {
      return this.ensureStore().getSync(APP_BIOMETRIC_LOCK_ENABLED_KEY, false) as boolean
    } catch (error) {
      Logger.warn('PreferencesService', `getBiometricLockEnabled failed: ${this.describeError(error as Object)}`)
      return false
    }
  }

  async setBiometricLockEnabled(enabled: boolean): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(APP_BIOMETRIC_LOCK_ENABLED_KEY, enabled)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `setBiometricLockEnabled failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async getHomeSidebarFilterMode(): Promise<'tag' | 'folder'> {
    try {
      const store = this.ensureStore()
      const raw = `${store.getSync(HOME_SIDEBAR_FILTER_MODE_KEY, 'tag') ?? 'tag'}`.trim()
      return raw === 'folder' ? 'folder' : 'tag'
    } catch (error) {
      Logger.warn(
        'PreferencesService',
        `getHomeSidebarFilterMode failed: ${this.describeError(error as Object)}`
      )
      return 'tag'
    }
  }

  async setHomeSidebarFilterMode(mode: 'tag' | 'folder'): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(HOME_SIDEBAR_FILTER_MODE_KEY, mode === 'folder' ? 'folder' : 'tag')
      await store.flush()
    } catch (error) {
      Logger.warn(
        'PreferencesService',
        `setHomeSidebarFilterMode failed: ${this.describeError(error as Object)}`
      )
      throw this.toRuntimeError(error as Object)
    }
  }

  /** 分享卡片上次选择的主题（默认经典）。 */
  async getShareCardTheme(): Promise<string> {
    try {
      const raw = `${this.ensureStore().getSync(SHARE_CARD_THEME_KEY, '') ?? ''}`.trim()
      return raw.length > 0 ? raw : 'classic'
    } catch (error) {
      Logger.warn('PreferencesService', `getShareCardTheme failed: ${this.describeError(error as Object)}`)
      return 'classic'
    }
  }

  async setShareCardTheme(theme: string): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(SHARE_CARD_THEME_KEY, theme)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `setShareCardTheme failed: ${this.describeError(error as Object)}`)
    }
  }

  /** 分享卡片上次选择的色调（默认深色）。 */
  async getShareCardTone(): Promise<string> {
    try {
      const raw = `${this.ensureStore().getSync(SHARE_CARD_TONE_KEY, '') ?? ''}`.trim()
      return raw.length > 0 ? raw : 'dark'
    } catch (error) {
      Logger.warn('PreferencesService', `getShareCardTone failed: ${this.describeError(error as Object)}`)
      return 'dark'
    }
  }

  async setShareCardTone(tone: string): Promise<void> {
    try {
      const store = this.ensureStore()
      store.putSync(SHARE_CARD_TONE_KEY, tone)
      await store.flush()
    } catch (error) {
      Logger.warn('PreferencesService', `setShareCardTone failed: ${this.describeError(error as Object)}`)
    }
  }

  async getNoteTags(): Promise<string[]> {
    try {
      const store = this.ensureStore()
      const serialized = store.getSync(TAG_LIST_KEY, '[]') as string
      if (serialized.trim().length === 0) {
        return []
      }
      let parsed: string[] = []
      try {
        const raw: Object = JSON.parse(serialized) as Object
        if (Array.isArray(raw)) {
          parsed = raw as string[]
        }
      } catch (_) {
        parsed = []
      }
      if (!Array.isArray(parsed)) {
        return []
      }
      return this.normalizeTags(parsed)
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
