import { userAuth } from '@kit.UserAuthenticationKit'
import { PreferencesService } from './PreferencesService'
import { AppContextHolder } from './AppContextHolder'
import { Logger } from '../common/utils/Logger'

export type BiometricLockKind = 'none' | 'face' | 'fingerprint'

export type BiometricAuthOutcome = 'success' | 'failed' | 'canceled' | 'fallback'

/** 指纹/面容锁：仅本机 Preferences，不同步 WebDAV。 */
export class BiometricLockService {
  private static instance: BiometricLockService = new BiometricLockService()
  static readonly maxConsecutiveFailures: number = 3
  private static readonly CHALLENGE: Uint8Array = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8])

  static getInstance(): BiometricLockService {
    return BiometricLockService.instance
  }

  async isPlatformSupported(): Promise<boolean> {
    return (await this.getAvailableKind()) !== 'none'
  }

  async getAvailableKind(): Promise<BiometricLockKind> {
    try {
      if (this.isAuthTypeAvailable(userAuth.UserAuthType.FACE)) {
        return 'face'
      }
      if (this.isAuthTypeAvailable(userAuth.UserAuthType.FINGERPRINT)) {
        return 'fingerprint'
      }
    } catch (error) {
      Logger.warn('BiometricLockService', `getAvailableKind failed: ${JSON.stringify(error)}`)
    }
    return 'none'
  }

  settingsLabelFor(kind: BiometricLockKind): string {
    return kind === 'face' ? '面容锁' : '指纹锁'
  }

  unlockPromptFor(kind: BiometricLockKind): string {
    if (kind === 'face') {
      return '验证面容以进入轻羽云笔记'
    }
    if (kind === 'fingerprint') {
      return '验证指纹以进入轻羽云笔记'
    }
    return '验证身份以进入轻羽云笔记'
  }

  async isEnabledLocally(): Promise<boolean> {
    const ctx = AppContextHolder.tryGetContext()
    if (ctx) {
      await PreferencesService.getInstance().init(ctx)
    }
    return await PreferencesService.getInstance().getBiometricLockEnabled()
  }

  async setEnabledLocally(enabled: boolean): Promise<void> {
    const ctx = AppContextHolder.tryGetContext()
    if (ctx) {
      await PreferencesService.getInstance().init(ctx)
    }
    await PreferencesService.getInstance().setBiometricLockEnabled(enabled)
  }

  async ensureConsistentWithAppLock(appLockEnabled: boolean): Promise<void> {
    if (appLockEnabled) {
      return
    }
    if (await this.isEnabledLocally()) {
      await this.setEnabledLocally(false)
    }
  }

  async authenticate(title?: string): Promise<BiometricAuthOutcome> {
    const kind = await this.getAvailableKind()
    if (kind === 'none') {
      return 'failed'
    }
    const authType = kind === 'face'
      ? userAuth.UserAuthType.FACE
      : userAuth.UserAuthType.FINGERPRINT
    const prompt = title ?? this.unlockPromptFor(kind)
    return await new Promise<BiometricAuthOutcome>((resolve) => {
      try {
        const authParam: userAuth.AuthParam = {
          challenge: BiometricLockService.CHALLENGE,
          authType: [authType],
          authTrustLevel: userAuth.AuthTrustLevel.ATL1,
        }
        const widgetParam: userAuth.WidgetParam = { title: prompt }
        const instance = userAuth.getUserAuthInstance(authParam, widgetParam)
        instance.on('result', {
          onResult: (result: userAuth.UserAuthResult) => {
            if (result.result === userAuth.UserAuthResultCode.SUCCESS) {
              resolve('success')
              return
            }
            if (result.result === userAuth.UserAuthResultCode.CANCELED) {
              resolve('canceled')
              return
            }
            resolve('failed')
          }
        })
        instance.start()
      } catch (error) {
        Logger.warn('BiometricLockService', `authenticate failed: ${JSON.stringify(error)}`)
        resolve('failed')
      }
    })
  }

  private isAuthTypeAvailable(authType: userAuth.UserAuthType): boolean {
    try {
      userAuth.getAvailableStatus(authType, userAuth.AuthTrustLevel.ATL1)
      return true
    } catch (_) {
      return false
    }
  }
}
