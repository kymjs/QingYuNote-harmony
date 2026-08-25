import type { Note } from '../common/model/Note'
import {
  NoteHistoryEntry,
  NoteHistoryLogic,
  NoteHistoryManifest,
  NoteHistoryReason
} from '../common/model/NoteHistory'
import { SyncConstants } from '../common/constants/SyncConstants'
import { IdUtils } from '../common/utils/IdUtils'
import { NoteStateCodec } from '../common/utils/NoteStateCodec'
import { CryptoService } from './CryptoService'
import { FileService } from './FileService'
import { NoteContentEncryptionService } from './NoteContentEncryptionService'
import { NoteRepository } from './NoteRepository'
import { WebDAVClient } from './WebDAVClient'
import { Logger } from '../common/utils/Logger'

export class NoteHistoryService {
  private static instance: NoteHistoryService = new NoteHistoryService()

  static getInstance(): NoteHistoryService {
    return NoteHistoryService.instance
  }

  async captureIfNeeded(snapshot: Note, reason: string): Promise<void> {
    try {
      if (NoteHistoryLogic.isNoteEmpty(snapshot.title, snapshot.content)) {
        return
      }
      const hash = await CryptoService.getInstance().sha256Hex(
        NoteHistoryLogic.contentHashSource(snapshot.title, snapshot.content)
      )
      const manifest = await this.readLocalManifest(snapshot.id)
      const latest = manifest.versions.length > 0 ? manifest.versions[0] : undefined
      const now = Date.now()
      const ok = NoteHistoryLogic.shouldCapture(
        true,
        false,
        false,
        hash,
        latest !== undefined ? latest.contentHash : '',
        now,
        latest !== undefined ? latest.createdAt : 0,
        reason
      )
      if (!ok) {
        return
      }
      await this.writeVersion(snapshot, reason, hash, now, '')
    } catch (error) {
      Logger.warn('NoteHistoryService', `captureIfNeeded failed: ${JSON.stringify(error)}`)
    }
  }

  async captureFromRemoteRaw(noteId: string, rawMarkdown: string, reason: string): Promise<void> {
    try {
      if (rawMarkdown.trim().length === 0) {
        return
      }
      const parsed = NoteStateCodec.parseNoteFile(rawMarkdown, noteId, Date.now())
      let title = parsed.state.title
      let content = parsed.content
      const userId = await NoteContentEncryptionService.getInstance().resolveUserId()
      const local = await NoteRepository.getInstance().getNote(noteId)
      if (userId !== null && local !== null) {
        const dummy = this.cloneWithText(local, title, content)
        dummy.rsa = parsed.state.rsa
        const plain = await NoteContentEncryptionService.getInstance().decryptNoteForDisplay(dummy, userId)
        title = plain.title
        content = plain.content
      }
      if (NoteHistoryLogic.isNoteEmpty(title, content)) {
        return
      }
      const hash = await CryptoService.getInstance().sha256Hex(
        NoteHistoryLogic.contentHashSource(title, content)
      )
      const manifest = await this.readLocalManifest(noteId)
      if (manifest.versions.length > 0 && manifest.versions[0].contentHash === hash) {
        return
      }
      const snapshot = local !== null ? this.cloneWithText(local, title, content) : local
      if (snapshot === null) {
        await this.writeRawVersion(noteId, rawMarkdown, reason, hash, content.length)
        return
      }
      await this.writeVersion(snapshot, reason, hash, Date.now(), rawMarkdown)
    } catch (error) {
      Logger.warn('NoteHistoryService', `captureFromRemoteRaw failed: ${JSON.stringify(error)}`)
    }
  }

  async listVersions(noteId: string): Promise<NoteHistoryEntry[]> {
    await this.syncWithCloud(noteId)
    const manifest = await this.readLocalManifest(noteId)
    const userId = await NoteContentEncryptionService.getInstance().resolveUserId()
    if (userId === null) {
      return manifest.versions
    }
    const decoded: NoteHistoryEntry[] = []
    for (let i = 0; i < manifest.versions.length; i++) {
      const entry = manifest.versions[i]
      try {
        const plain = await CryptoService.getInstance().decryptNoteText(entry.title, userId)
        if (plain.length > 0) {
          entry.title = plain
        }
      } catch (_) {
      }
      decoded.push(entry)
    }
    return decoded
  }

  async readVersion(noteId: string, versionId: string): Promise<Note | null> {
    const path = FileService.getInstance().historyVersionPath(noteId, versionId)
    const raw = FileService.getInstance().readHistoryTextFile(path)
    if (raw.length === 0) {
      return null
    }
    const parsed = NoteStateCodec.parseNoteFile(raw, noteId, Date.now())
    const local = await NoteRepository.getInstance().getNote(noteId)
    if (local === null) {
      return null
    }
    const note = this.cloneWithText(local, parsed.state.title, parsed.content)
    note.rsa = parsed.state.rsa
    const userId = await NoteContentEncryptionService.getInstance().resolveUserId()
    if (userId !== null) {
      return await NoteContentEncryptionService.getInstance().decryptNoteForDisplay(note, userId)
    }
    return note
  }

  async restore(noteId: string, versionId: string): Promise<Note> {
    const current = await NoteRepository.getInstance().getNote(noteId)
    if (current === null) {
      throw new Error(`Note ${noteId} does not exist`)
    }
    await this.captureIfNeeded(current, NoteHistoryReason.restore)
    const version = await this.readVersion(noteId, versionId)
    if (version === null) {
      throw new Error(`Version ${versionId} not found`)
    }
    const restored = await NoteRepository.getInstance().saveDraft(noteId, {
      title: version.title,
      content: version.content,
      historyReason: NoteHistoryReason.restore
    })
    const qyPath = FileService.getInstance().historyFlowchartPath(noteId, versionId)
    if (FileService.getInstance().historyFileExists(qyPath)) {
      const qy = FileService.getInstance().readHistoryTextFile(qyPath)
      if (qy.length > 0) {
        await FileService.getInstance().writeFlowchartFile(noteId, qy)
      }
    }
    return restored
  }

  async deleteForNote(noteId: string): Promise<void> {
    await FileService.getInstance().deleteHistoryDirForNote(noteId)
  }

  async syncWithCloud(noteId: string): Promise<void> {
    try {
      await WebDAVClient.getInstance().ensureHistoryDirectories(noteId)
      const local = await this.readLocalManifest(noteId)
      const remoteRaw = await WebDAVClient.getInstance().downloadHistoryFile(
        noteId,
        SyncConstants.noteHistoryManifestFile
      )
      let remote = NoteHistoryManifest.empty(noteId)
      if (remoteRaw !== null && remoteRaw.trim().length > 0) {
        try {
          const decoded = JSON.parse(remoteRaw) as Record<string, Object>
          remote = NoteHistoryManifest.fromJson(decoded, noteId)
        } catch (_) {
        }
      }
      const mergedVersions = NoteHistoryLogic.mergeAndPrune(local.versions, remote.versions)
      const merged = NoteHistoryManifest.empty(noteId)
      merged.versions = mergedVersions
      const keep = new Set<string>()
      for (let i = 0; i < merged.versions.length; i++) {
        keep.add(merged.versions[i].id)
      }
      for (let i = 0; i < merged.versions.length; i++) {
        const entry = merged.versions[i]
        const localPath = FileService.getInstance().historyVersionPath(noteId, entry.id)
        if (!FileService.getInstance().historyFileExists(localPath)) {
          const remoteBody = await WebDAVClient.getInstance().downloadHistoryFile(noteId, `${entry.id}.md`)
          if (remoteBody !== null && remoteBody.length > 0) {
            FileService.getInstance().writeHistoryTextFile(localPath, remoteBody)
          }
        } else {
          const body = FileService.getInstance().readHistoryTextFile(localPath)
          if (body.length > 0) {
            await WebDAVClient.getInstance().uploadHistoryFile(noteId, `${entry.id}.md`, body)
          }
        }
      }
      for (let i = 0; i < local.versions.length; i++) {
        const entry = local.versions[i]
        if (keep.has(entry.id)) {
          continue
        }
        FileService.getInstance().deleteHistoryFile(
          FileService.getInstance().historyVersionPath(noteId, entry.id)
        )
        FileService.getInstance().deleteHistoryFile(
          FileService.getInstance().historyFlowchartPath(noteId, entry.id)
        )
      }
      for (let i = 0; i < remote.versions.length; i++) {
        const entry = remote.versions[i]
        if (keep.has(entry.id)) {
          continue
        }
        await WebDAVClient.getInstance().deleteHistoryFile(noteId, `${entry.id}.md`)
      }
      await this.writeLocalManifest(merged)
      await WebDAVClient.getInstance().uploadHistoryFile(
        noteId,
        SyncConstants.noteHistoryManifestFile,
        JSON.stringify(merged.toJson())
      )
    } catch (error) {
      Logger.warn('NoteHistoryService', `syncWithCloud failed: ${JSON.stringify(error)}`)
    }
  }

  private async writeVersion(snapshot: Note, reason: string, hash: string, createdAt: number,
    rawMarkdown: string): Promise<void> {
    const versionId = IdUtils.uuid()
    await FileService.getInstance().ensureHistoryDir(snapshot.id)
    const versionPath = FileService.getInstance().historyVersionPath(snapshot.id, versionId)
    if (rawMarkdown.length > 0) {
      FileService.getInstance().writeHistoryTextFile(versionPath, rawMarkdown)
    } else {
      let storageNote = snapshot
      const userId = await NoteContentEncryptionService.getInstance().resolveUserId()
      if (userId !== null) {
        storageNote = await NoteContentEncryptionService.getInstance().encryptNoteForStorage(snapshot, userId)
      }
      FileService.getInstance().writeHistoryTextFile(versionPath, NoteStateCodec.serializeNoteFile(storageNote))
    }
    let hasFlowchart = false
    if (FileService.getInstance().flowchartFileExists(snapshot.id)) {
      const qy = await FileService.getInstance().readFlowchartFile(snapshot.id)
      if (qy.length > 0) {
        hasFlowchart = true
        FileService.getInstance().writeHistoryTextFile(
          FileService.getInstance().historyFlowchartPath(snapshot.id, versionId), qy)
      }
    }
    let titleForManifest = snapshot.title
    const userId = await NoteContentEncryptionService.getInstance().resolveUserId()
    if (userId !== null && titleForManifest.length > 0) {
      titleForManifest = await CryptoService.getInstance().encryptNoteText(titleForManifest, userId)
    }
    const entry = new NoteHistoryEntry()
    entry.id = versionId
    entry.createdAt = createdAt
    entry.contentHash = hash
    entry.contentLength = snapshot.content.length
    entry.reason = reason
    entry.title = titleForManifest
    entry.hasFlowchart = hasFlowchart
    const manifest = await this.readLocalManifest(snapshot.id)
    const next = NoteHistoryLogic.prune([entry, ...manifest.versions])
    await this.writeLocalManifest(this.withVersions(snapshot.id, next))
    void this.syncWithCloud(snapshot.id)
  }

  private async writeRawVersion(noteId: string, rawMarkdown: string, reason: string, hash: string,
    contentLength: number): Promise<void> {
    const versionId = IdUtils.uuid()
    await FileService.getInstance().ensureHistoryDir(noteId)
    FileService.getInstance().writeHistoryTextFile(
      FileService.getInstance().historyVersionPath(noteId, versionId), rawMarkdown)
    const entry = new NoteHistoryEntry()
    entry.id = versionId
    entry.createdAt = Date.now()
    entry.contentHash = hash
    entry.contentLength = contentLength
    entry.reason = reason
    const manifest = await this.readLocalManifest(noteId)
    const next = NoteHistoryLogic.prune([entry, ...manifest.versions])
    await this.writeLocalManifest(this.withVersions(noteId, next))
    void this.syncWithCloud(noteId)
  }

  private async readLocalManifest(noteId: string): Promise<NoteHistoryManifest> {
    const raw = FileService.getInstance().readHistoryTextFile(
      FileService.getInstance().historyManifestPath(noteId))
    if (raw.trim().length === 0) {
      return NoteHistoryManifest.empty(noteId)
    }
    try {
      const decoded = JSON.parse(raw) as Record<string, Object>
      return NoteHistoryManifest.fromJson(decoded, noteId)
    } catch (_) {
      return NoteHistoryManifest.empty(noteId)
    }
  }

  private async writeLocalManifest(manifest: NoteHistoryManifest): Promise<void> {
    await FileService.getInstance().ensureHistoryDir(manifest.noteId)
    FileService.getInstance().writeHistoryTextFile(
      FileService.getInstance().historyManifestPath(manifest.noteId),
      JSON.stringify(manifest.toJson())
    )
  }

  private withVersions(noteId: string, versions: NoteHistoryEntry[]): NoteHistoryManifest {
    const manifest = NoteHistoryManifest.empty(noteId)
    manifest.versions = versions
    return manifest
  }

  private cloneWithText(note: Note, title: string, content: string): Note {
    return {
      id: note.id,
      title: title,
      content: content,
      tags: [...note.tags],
      imageRefs: [...note.imageRefs],
      audioId: note.audioId,
      summary: note.summary,
      localModified: note.localModified,
      remoteModified: note.remoteModified,
      deleted: note.deleted,
      deletedAt: note.deletedAt,
      lastOperationAt: note.lastOperationAt,
      syncStatus: note.syncStatus,
      filePath: note.filePath,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      parentId: note.parentId,
      isConflict: note.isConflict,
      latitude: note.latitude,
      longitude: note.longitude,
      altitude: note.altitude,
      author: note.author,
      sourceUrl: note.sourceUrl,
      isFavorite: note.isFavorite,
      isTodo: note.isTodo,
      todoDue: note.todoDue,
      todoCompleted: note.todoCompleted,
      todoPriority: note.todoPriority,
      todoStatus: note.todoStatus,
      todoReminderMinutes: note.todoReminderMinutes,
      startTime: note.startTime,
      endTime: note.endTime,
      source: note.source,
      order: note.order,
      userData: note.userData,
      rsa: note.rsa,
      deletedTime: note.deletedTime,
      type_: note.type_,
      extractStatus: note.extractStatus,
      extractJobId: note.extractJobId,
      extractError: note.extractError,
      extractedAt: note.extractedAt,
      extractProgress: note.extractProgress,
      voiceSummary: note.voiceSummary,
      voiceSegmentsJson: note.voiceSegmentsJson,
      voiceTranscribeStatus: note.voiceTranscribeStatus
    }
  }
}
