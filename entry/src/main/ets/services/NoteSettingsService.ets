import fs from '@ohos.file.fs'
import { AppContextHolder } from './AppContextHolder'
import { NoteSettingsDocument } from '../common/model/NoteSettingsDocument'
import { PreferencesService } from './PreferencesService'
import { Logger } from '../common/utils/Logger'
import { SyncConstants } from '../common/constants/SyncConstants'

const LOCAL_FILE_NAME = 'note_settings.json'

/** EventHub 载荷：笔记设置文档 revision 递增。 */
export class NoteSettingsChangedEventPayload {
  revision: number

  constructor(revision: number) {
    this.revision = revision
  }
}

/** 笔记设置本地 JSON + 与 Preferences 键同步。 */
export class NoteSettingsService {
  private static instance: NoteSettingsService = new NoteSettingsService()
  private cached?: NoteSettingsDocument
  private loaded: boolean = false
  private revision: number = 0

  static getInstance(): NoteSettingsService {
    return NoteSettingsService.instance
  }

  getRevision(): number {
    return this.revision
  }

  async getNoteQuickActionBarEnabled(): Promise<boolean> {
    return (await this.current()).quickActionBarEnabled
  }

  async getNoteFolderModeEnabled(): Promise<boolean> {
    return (await this.current()).folderModeEnabled
  }

  async getAppLockEnabled(): Promise<boolean> {
    return (await this.current()).appLockEnabled
  }

  async getAppLockPasswordEnc(): Promise<string> {
    return (await this.current()).appLockPasswordEnc
  }

  async setNoteQuickActionBarEnabled(enabled: boolean): Promise<void> {
    const cur = await this.current()
    if (cur.quickActionBarEnabled === enabled) {
      return
    }
    const next = new NoteSettingsDocument(
      Date.now(),
      enabled,
      cur.folderModeEnabled,
      cur.version,
      true,
      cur.appLockEnabled,
      cur.appLockPasswordEnc
    )
    await this.persistLocal(next)
  }

  async setNoteFolderModeEnabled(enabled: boolean): Promise<void> {
    const cur = await this.current()
    if (cur.folderModeEnabled === enabled) {
      return
    }
    const next = new NoteSettingsDocument(
      Date.now(),
      cur.quickActionBarEnabled,
      enabled,
      cur.version,
      true,
      cur.appLockEnabled,
      cur.appLockPasswordEnc
    )
    await this.persistLocal(next)
  }

  async enableAppLock(encryptedPassword: string): Promise<void> {
    const cur = await this.current()
    const next = new NoteSettingsDocument(
      Date.now(),
      cur.quickActionBarEnabled,
      cur.folderModeEnabled,
      cur.version,
      true,
      true,
      encryptedPassword
    )
    await this.persistLocal(next)
  }

  async disableAppLock(): Promise<void> {
    const cur = await this.current()
    if (!cur.appLockEnabled && cur.appLockPasswordEnc.length === 0) {
      return
    }
    const next = new NoteSettingsDocument(
      Date.now(),
      cur.quickActionBarEnabled,
      cur.folderModeEnabled,
      cur.version,
      true,
      false,
      ''
    )
    await this.persistLocal(next)
  }

  async exportDocument(): Promise<NoteSettingsDocument> {
    return await this.current()
  }

  async applyRemoteDocument(doc: NoteSettingsDocument): Promise<void> {
    await this.persistLocal(doc)
  }

  private async current(): Promise<NoteSettingsDocument> {
    await this.ensureLoaded()
    if (this.cached !== undefined) {
      return this.cached
    }
    return NoteSettingsDocument.defaults()
  }

  private async ensureLoaded(): Promise<void> {
    if (this.loaded) {
      return
    }
    const ctx = AppContextHolder.tryGetContext()
    if (ctx) {
      await PreferencesService.getInstance().init(ctx)
    }
    this.cached = await this.readLocalFile() ?? await this.migrateFromLegacyPrefs()
    this.loaded = true
  }

  private localPath(): string {
    const filesDir = AppContextHolder.tryGetContext()?.filesDir ?? ''
    return `${filesDir}/${LOCAL_FILE_NAME}`
  }

  private async readLocalFile(): Promise<NoteSettingsDocument | null> {
    const path = this.localPath()
    if (path.length === 0) {
      return null
    }
    try {
      if (!fs.accessSync(path)) {
        return null
      }
      const raw = fs.readTextSync(path, { encoding: 'utf-8' })
      if (raw.trim().length === 0) {
        return null
      }
      const json = JSON.parse(raw) as Record<string, Object>
      return NoteSettingsDocument.fromJsonRecord(json)
    } catch (error) {
      Logger.warn('NoteSettingsService',
        `readLocalFile failed: ${JSON.stringify(error)}`)
      return null
    }
  }

  private async migrateFromLegacyPrefs(): Promise<NoteSettingsDocument> {
    const legacy = PreferencesService.getInstance().readLegacyNoteSettingsFlags()
    const doc = new NoteSettingsDocument(
      NoteSettingsDocument.pristineUpdatedAt,
      legacy.quick,
      legacy.folder
    )
    await this.persistLocal(doc, false)
    return doc
  }

  private async persistLocal(doc: NoteSettingsDocument, syncLegacyPrefs: boolean = true): Promise<void> {
    this.cached = doc
    this.loaded = true
    const path = this.localPath()
    if (path.length > 0) {
      try {
        const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
        try {
          await fs.write(file.fd, JSON.stringify(doc.toJsonRecord(), null, 2), { encoding: 'utf-8' })
        } finally {
          fs.closeSync(file)
        }
      } catch (error) {
        Logger.warn('NoteSettingsService',
          `persistLocal file failed: ${JSON.stringify(error)}`)
      }
    }
    if (syncLegacyPrefs) {
      await PreferencesService.getInstance().writeLegacyNoteSettingsFlags(
        doc.quickActionBarEnabled,
        doc.folderModeEnabled
      )
    }
    this.revision += 1
    const hub = AppContextHolder.tryGetContext()?.eventHub
    if (hub !== undefined) {
      try {
        hub.emit(SyncConstants.noteSettingsChangedEvent,
          new NoteSettingsChangedEventPayload(this.revision))
      } catch (error) {
        Logger.warn('NoteSettingsService',
          `emit noteSettingsChanged failed: ${JSON.stringify(error)}`)
      }
    }
  }
}
