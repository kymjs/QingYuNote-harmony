import type { FlowchartGraphModel } from '../common/model/FlowchartGraph'
import { createEmptyFlowchartGraph } from '../common/model/FlowchartGraph'
import { Logger } from '../common/utils/Logger'
import { CryptoService } from './CryptoService'
import { FileService } from './FileService'
import { PreferencesService } from './PreferencesService'

export class FlowchartService {
  private static instance: FlowchartService = new FlowchartService()

  static getInstance(): FlowchartService {
    return FlowchartService.instance
  }

  emptyGraph(): FlowchartGraphModel {
    return createEmptyFlowchartGraph()
  }

  private async userId(): Promise<string> {
    return (await PreferencesService.getInstance().getNoteApiUserId()).trim()
  }

  private async encryptPayload(plainJson: string): Promise<string> {
    const userId = await this.userId()
    if (userId.length === 0) {
      return plainJson
    }
    return CryptoService.getInstance().encryptFlowchartText(plainJson, userId)
  }

  private async decryptPayload(raw: string): Promise<string> {
    const userId = await this.userId()
    if (userId.length === 0) {
      return raw
    }
    return CryptoService.getInstance().decryptFlowchartText(raw, userId)
  }

  async load(noteId: string): Promise<FlowchartGraphModel> {
    await FileService.getInstance().ensureBaseDir()
    try {
      const raw = await FileService.getInstance().readFlowchartFile(noteId)
      if (raw.trim().length === 0) {
        return createEmptyFlowchartGraph()
      }
      const jsonText = await this.decryptPayload(raw.trim())
      return JSON.parse(jsonText) as FlowchartGraphModel
    } catch (error) {
      Logger.warn('FlowchartService', `load failed: ${JSON.stringify(error)}`)
      return createEmptyFlowchartGraph()
    }
  }

  async save(graph: FlowchartGraphModel, noteId: string): Promise<void> {
    const plain = JSON.stringify(graph)
    const encrypted = await this.encryptPayload(plain)
    await FileService.getInstance().writeFlowchartFile(noteId, encrypted)
  }
}
