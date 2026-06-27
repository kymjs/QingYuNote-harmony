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

  async reportIfPossible(config: WebDAVConfig): Promise<void> {
    if (await PreferencesService.getInstance().isGuestMode()) {
      return
    }
    const userId = (await PreferencesService.getInstance().getNoteApiUserId()).trim()
    if (userId.length === 0) {
      return
    }
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
