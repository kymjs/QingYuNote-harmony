import { NoteSettingsDocument } from '../common/model/NoteSettingsDocument'
import { NoteSettingsService } from './NoteSettingsService'
import { PreferencesService } from './PreferencesService'
import { WebDAVClient } from './WebDAVClient'
import { Logger } from '../common/utils/Logger'

/** 笔记设置 WebDAV 同步（与 Flutter `NoteSettingsRemoteSync` 对齐）。 */
export class NoteSettingsRemoteSync {
  private static instance: NoteSettingsRemoteSync = new NoteSettingsRemoteSync()

  static getInstance(): NoteSettingsRemoteSync {
    return NoteSettingsRemoteSync.instance
  }

  private async canSync(): Promise<boolean> {
    if (await PreferencesService.getInstance().isGuestMode()) {
      return false
    }
    if (await PreferencesService.getInstance().isAuthInvalid()) {
      return false
    }
    try {
      await WebDAVClient.getInstance().requireConfig()
      return true
    } catch (_) {
      return false
    }
  }

  async pushIfPossible(doc: NoteSettingsDocument): Promise<void> {
    if (!(await this.canSync())) {
      return
    }
    try {
      await WebDAVClient.getInstance().uploadNoteSettingsDocument(doc)
    } catch (error) {
      Logger.warn('NoteSettingsRemoteSync',
        `push failed: ${JSON.stringify(error)}`)
    }
  }

  async syncWithRemote(): Promise<void> {
    if (!(await this.canSync())) {
      return
    }
    const local = await NoteSettingsService.getInstance().exportDocument()
    let remote: NoteSettingsDocument | null = null
    try {
      remote = await WebDAVClient.getInstance().fetchNoteSettingsDocument()
    } catch (error) {
      Logger.warn('NoteSettingsRemoteSync',
        `fetch failed: ${JSON.stringify(error)}`)
      return
    }
    if (remote === null) {
      await this.pushIfPossible(local)
      return
    }
    if (remote.updatedAt > local.updatedAt) {
      await NoteSettingsService.getInstance().applyRemoteDocument(remote)
      return
    }
    if (local.updatedAt > remote.updatedAt) {
      await this.pushIfPossible(local)
    }
  }
}
