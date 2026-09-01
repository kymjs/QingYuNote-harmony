import type { FlowchartGraphModel } from '../model/FlowchartGraph'
import { Logger } from './Logger'
import { CryptoService } from '../../services/CryptoService'
import { FileService } from '../../services/FileService'
import { NoteRepository } from '../../services/NoteRepository'
import { PreferencesService } from '../../services/PreferencesService'
import { WebDAVClient } from '../../services/WebDAVClient'

/** 编辑器打开时，将旧 `.qy` JSON 一次性迁移到 `.md` mermaid 格式。 */
export class FlowchartLegacyMigrate {
  private static readonly LEGACY_AAD = 'qingyu-flowchart-aad'

  /** 若存在旧 `.qy`，迁移并删除本地边车；返回是否执行了迁移。 */
  static async migrateIfNeeded(noteId: string): Promise<boolean> {
    await FileService.getInstance().ensureBaseDir()
    if (!FileService.getInstance().flowchartFileExists(noteId)) {
      return false
    }
    try {
      const raw = await FileService.getInstance().readFlowchartFile(noteId)
      if (raw.trim().length === 0) {
        await FileService.getInstance().deleteFlowchartFile(noteId)
        return false
      }
      const jsonText = await FlowchartLegacyMigrate.decryptPayload(raw.trim())
      const graph = JSON.parse(jsonText) as FlowchartGraphModel
      const note = await NoteRepository.getInstance().getNote(noteId)
      await NoteRepository.getInstance().saveFlowchartNote(
        noteId,
        graph,
        note?.title,
        undefined,
        true
      )
      await FileService.getInstance().deleteFlowchartFile(noteId)
      try {
        await WebDAVClient.getInstance().deleteFlowchart(noteId)
      } catch (error) {
        Logger.warn('FlowchartLegacyMigrate', `remote delete skipped: ${JSON.stringify(error)}`)
      }
      return true
    } catch (error) {
      Logger.warn('FlowchartLegacyMigrate', `migrate failed: ${JSON.stringify(error)}`)
      return false
    }
  }

  private static async decryptPayload(raw: string): Promise<string> {
    const userId = (await PreferencesService.getInstance().getNoteApiUserId()).trim()
    if (userId.length === 0) {
      return raw
    }
    try {
      return await CryptoService.getInstance().decryptFlowchartText(raw, userId)
    } catch (_) {
      return raw
    }
  }
}
