import { CryptoService } from './CryptoService'
import { NoteContentEncryptionService } from './NoteContentEncryptionService'
import { NoteRepository } from './NoteRepository'
import { NoteSettingsRemoteSync } from './NoteSettingsRemoteSync'
import { NoteSettingsService } from './NoteSettingsService'
import { NoteApiClient } from './NoteApiClient'
import { PreferencesService } from './PreferencesService'
import { AppContextHolder } from './AppContextHolder'
import { SyncService } from './SyncService'
import { Logger } from '../common/utils/Logger'

/** 应用锁：密码加密/校验与会话解锁状态（内存，进程重启后失效）。 */
export class AppLockService {
  private static instance: AppLockService = new AppLockService()
  private sessionUnlocked: boolean = false

  static getInstance(): AppLockService {
    return AppLockService.instance
  }

  isSessionUnlocked(): boolean {
    return this.sessionUnlocked
  }

  markSessionUnlocked(): void {
    this.sessionUnlocked = true
  }

  resetSession(): void {
    this.sessionUnlocked = false
  }

  async isAppLockEnabled(): Promise<boolean> {
    return await NoteSettingsService.getInstance().getAppLockEnabled()
  }

  async needsUnlockOnLaunch(): Promise<boolean> {
    if (this.sessionUnlocked) {
      return false
    }
    const enabled = await this.isAppLockEnabled()
    if (!enabled) {
      return false
    }
    const enc = await NoteSettingsService.getInstance().getAppLockPasswordEnc()
    return enc.length > 0
  }

  async hasStoredPassword(): Promise<boolean> {
    const enc = await NoteSettingsService.getInstance().getAppLockPasswordEnc()
    return enc.length > 0
  }

  async encryptPin(pin: string): Promise<string> {
    const userId = await NoteContentEncryptionService.getInstance().resolveUserId() ?? ''
    const crypto = CryptoService.getInstance()
    if (userId.length > 0) {
      return await crypto.encryptNoteText(pin, userId)
    }
    return await crypto.encryptText(pin)
  }

  async verifyPin(pin: string): Promise<boolean> {
    const stored = await NoteSettingsService.getInstance().getAppLockPasswordEnc()
    if (stored.length === 0) {
      return false
    }
    const userId = await NoteContentEncryptionService.getInstance().resolveUserId() ?? ''
    const crypto = CryptoService.getInstance()
    const decrypted = userId.length > 0
      ? await crypto.decryptNoteText(stored, userId)
      : await crypto.decryptText(stored)
    return decrypted === pin
  }

  async enableWithPin(pin: string): Promise<void> {
    const ctx = AppContextHolder.tryGetContext()
    if (ctx) {
      await PreferencesService.getInstance().init(ctx)
    }
    const enc = await this.encryptPin(pin)
    await PreferencesService.getInstance().enableAppLock(enc)
    this.markSessionUnlocked()
  }

  async disableAppLock(): Promise<void> {
    const ctx = AppContextHolder.tryGetContext()
    if (ctx) {
      await PreferencesService.getInstance().init(ctx)
    }
    await PreferencesService.getInstance().disableAppLock()
    this.markSessionUnlocked()
  }

  /** 验证登录密码；成功返回 `null`，失败返回可读说明。 */
  async verifyLoginPassword(password: string): Promise<string | null> {
    const ctx = AppContextHolder.tryGetContext()
    if (ctx) {
      await PreferencesService.getInstance().init(ctx)
    }
    if (await PreferencesService.getInstance().isGuestMode()) {
      return '游客模式无法验证登录密码'
    }
    const cached = await PreferencesService.getInstance().getCachedUserProfile()
    const passwordSet = cached !== null && cached['password_set'] === true
    if (!passwordSet) {
      return '未设置登录密码，请先在个人信息中设置'
    }
    const phoneRaw = cached !== null ? `${cached['phone'] ?? ''}`.trim() : ''
    if (phoneRaw.length === 0) {
      return '未绑定手机号，无法验证登录密码'
    }
    const err = await NoteApiClient.getInstance().loginWithPhonePassword(phoneRaw, password)
    if (err === null) {
      return null
    }
    return AppLockService.mapLoginPasswordError(err)
  }

  /** 设置页关闭应用锁：忘记 PIN 时用登录密码验证。 */
  async disableAppLockWithLoginPassword(password: string): Promise<string | null> {
    const err = await this.verifyLoginPassword(password)
    if (err !== null) {
      return err
    }
    await this.disableAppLock()
    return null
  }

  /** 启动页忘记 PIN：关闭应用锁 → 强制同步 → 退出登录。 */
  async forgotPasswordOnLaunch(): Promise<void> {
    const ctx = AppContextHolder.tryGetContext()
    if (ctx) {
      await PreferencesService.getInstance().init(ctx)
      await NoteRepository.getInstance().init(ctx)
    }
    await this.disableAppLock()
    try {
      await SyncService.getInstance().syncNow()
    } catch (error) {
      Logger.warn('AppLockService', `forgotPasswordOnLaunch sync failed: ${JSON.stringify(error)}`)
    }
    await NoteSettingsRemoteSync.getInstance().pushIfPossible(
      await NoteSettingsService.getInstance().exportDocument()
    )
    await NoteRepository.getInstance().clearAllLocalNotes()
    await PreferencesService.getInstance().clearLoginSession()
  }

  private static mapLoginPasswordError(code: string): string {
    switch (code.trim()) {
      case 'invalid_body':
        return '请输入登录密码'
      case 'invalid_credentials':
        return '手机号或密码错误'
      case 'password_not_set':
        return '该账号尚未设置登录密码'
      case 'db_failed':
        return '服务暂时不可用'
      case 'network_error':
        return '网络异常'
      default:
        return '登录密码验证失败'
    }
  }
}
