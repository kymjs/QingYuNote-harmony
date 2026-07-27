import { WebDAVConfig } from '../common/model/Note'
import { CryptoService } from './CryptoService'
import { Logger } from '../common/utils/Logger'
import { NoteApiClient } from './NoteApiClient'
import { PreferencesService } from './PreferencesService'

/** 云同步方案上报 Note API（供管理后台「云服务」列展示）。 */
export class SyncSettingsRemoteReport {
  private static instance: SyncSettingsRemoteReport = new SyncSettingsRemoteReport()

  static getInstance(): SyncSettingsRemoteReport {
    return SyncSettingsRemoteReport.instance
  }

  /** 按本地 preferences 上报当前云同步方案（首页进入 / 自动开通后调用）。 */
  async reportCurrentIfPossible(): Promise<void> {
    if (!(await PreferencesService.getInstance().canRunCloudSync())) {
      return
    }
    const custom = await PreferencesService.getInstance().getSavedCustomWebDAVConfigSnapshot()
    if (custom !== null && custom.enabled) {
      await this.reportIfPossible(custom)
      return
    }
    const intent = await PreferencesService.getInstance().getQingyuCloudSyncIntent()
    if (intent === 'qingyu') {
      await this.reportIfPossible({
        baseUrl: '',
        username: '',
        encryptedPassword: '',
        notesDir: '/qingyu-notes/',
        enabled: true,
        provider: 'qingyu_cloud'
      })
      return
    }
    if (intent === 'disabled') {
      await this.reportIfPossible({
        baseUrl: '',
        username: '',
        encryptedPassword: '',
        notesDir: '/qingyu-notes/',
        enabled: false,
        provider: 'qingyu_cloud'
      })
    }
  }

  async reportIfPossible(config: WebDAVConfig): Promise<void> {
    if (!(await PreferencesService.getInstance().canRunCloudSync())) {
      return
    }
    const userId = (await PreferencesService.getInstance().getNoteApiUserId()).trim()
    try {
      const api = NoteApiClient.getInstance()
      if (config.provider === 'qingyu_cloud') {
        await api.putSyncSettings('qingyu_cloud', config.enabled)
        return
      }
      if (config.provider !== 'webdav') {
        return
      }
      let usernameEnc = ''
      let passwordEnc = ''
      if (config.enabled) {
        usernameEnc = await CryptoService.getInstance().encryptWebDavSecretForServer(config.username, userId)
        if (config.encryptedPassword.length > 0) {
          const plainPassword = await CryptoService.getInstance().decryptText(config.encryptedPassword)
          passwordEnc = await CryptoService.getInstance().encryptWebDavSecretForServer(plainPassword, userId)
        }
      }
      await api.putSyncSettings('webdav', config.enabled, config.baseUrl, config.notesDir, usernameEnc, passwordEnc)
    } catch (error) {
      Logger.warn('SyncSettingsRemoteReport', `reportIfPossible failed: ${JSON.stringify(error)}`)
    }
  }
}
