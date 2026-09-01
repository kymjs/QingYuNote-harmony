import type { FlowchartGraphModel } from '../common/model/FlowchartGraph'
import { createEmptyFlowchartGraph } from '../common/model/FlowchartGraph'
import { FlowchartMermaidCodec } from '../common/utils/FlowchartMermaidCodec'
import { Logger } from '../common/utils/Logger'
import { CryptoService } from './CryptoService'
import { FileService } from './FileService'
import { NoteRepository } from './NoteRepository'
import { PreferencesService } from './PreferencesService'

/** 流程图笔记读写（`.md` mermaid 围栏 + NOTE_STATE `flowchart_ext`）。 */
export class FlowchartService {
  private static instance: FlowchartService = new FlowchartService()
  private static readonly LEGACY_AAD = 'qingyu-flowchart-aad'

  static getInstance(): FlowchartService {
    return FlowchartService.instance
  }

  emptyGraph(): FlowchartGraphModel {
    const graph = createEmptyFlowchartGraph()
    return graph
  }

  async load(noteId: string): Promise<FlowchartGraphModel> {
    try {
      const note = await NoteRepository.getInstance().getNote(noteId)
      if (note === null) {
        return createEmptyFlowchartGraph()
      }
      const mermaidBody = FlowchartMermaidCodec.unwrapMermaidFence(note.content)
      if (mermaidBody !== undefined && mermaidBody.length > 0) {
        return FlowchartMermaidCodec.parseFromNote(note.content, note.flowchartExt)
      }
      return await this.loadLegacyQy(noteId)
    } catch (_) {
      return createEmptyFlowchartGraph()
    }
  }

  private async loadLegacyQy(noteId: string): Promise<FlowchartGraphModel> {
    if (!FileService.getInstance().flowchartFileExists(noteId)) {
      return createEmptyFlowchartGraph()
    }
    try {
      const raw = await FileService.getInstance().readFlowchartFile(noteId)
      if (raw.trim().length === 0) {
        return createEmptyFlowchartGraph()
      }
      const jsonText = await this.decryptLegacyPayload(raw.trim())
      return JSON.parse(jsonText) as FlowchartGraphModel
    } catch (error) {
      Logger.warn('FlowchartService', `legacy .qy load failed: ${JSON.stringify(error)}`)
      return createEmptyFlowchartGraph()
    }
  }

  private async decryptLegacyPayload(raw: string): Promise<string> {
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

  async save(graph: FlowchartGraphModel, noteId: string): Promise<void> {
    await NoteRepository.getInstance().saveFlowchartNote(noteId, graph)
  }
}
