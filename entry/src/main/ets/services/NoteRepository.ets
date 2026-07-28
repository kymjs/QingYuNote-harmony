import fs from '@ohos.file.fs'
import type common from '@ohos.app.ability.common'
import type { CreateNoteInput, ExtractStatus, Note, NoteFilePayload, NoteStateBlock, NoteSyncState, RecycleBinLoadResult,
  UpdateExtractInfo, UpdateNoteInput } from '../common/model/Note'
import { isExtractStatusPending } from '../common/model/Note'
import { Logger } from '../common/utils/Logger'
import { MarkdownUtils, shouldShowTodoNoteInHomeList } from '../common/utils/MarkdownUtils'
import { NoteFolderTree } from '../common/utils/NoteFolderTree'
import { NoteSortUtils } from '../common/utils/NoteSortUtils'
import { NoteStateCodec } from '../common/utils/NoteStateCodec'
import { IdUtils } from '../common/utils/IdUtils'
import type { FlowchartGraphModel } from '../common/model/FlowchartGraph'
import {
  FLOWCHART_DEFAULT_TITLE,
  flowchartSearchSummary,
  flowchartSearchableText,
  isDefaultFlowchartTitle,
  shouldShowFlowchartInHomeList
} from '../common/model/FlowchartGraph'
import { FlowchartService } from './FlowchartService'
import { DatabaseService } from './DatabaseService'
import { FileService } from './FileService'
import { AppContextHolder } from './AppContextHolder'
import { PreferencesService } from './PreferencesService'
import { WebDAVClient } from './WebDAVClient'
import { NoteContentEncryptionService } from './NoteContentEncryptionService'
import { WereadImportService } from './WereadImportService'
import { YinxiangImportService } from './YinxiangImportService'
import { LinkExtractClient } from './LinkExtractClient'

export class NoteRepository {
  private static instance: NoteRepository = new NoteRepository()
  private initialized: boolean = false
  private context: common.UIAbilityContext | undefined = undefined
  private scheduleSyncHandler?: (noteId: string) => void
  private notesVersion: number = 0
  private cachedActiveNotes?: Note[]
  private cachedAllNotes?: Note[]
  private cachedActiveNotesVersion: number = -1
  private cachedAllNotesVersion: number = -1
  private notificationSuspendCount: number = 0
  private pendingNotesChanged: boolean = false
  /** 本地全量读盘时的并发度；仅缩短墙钟时间，不改变解析与合并顺序。 */
  private static readonly LOAD_ALL_NOTES_CONCURRENCY: number = 6

  static getInstance(): NoteRepository {
    return NoteRepository.instance
  }

  async init(context?: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      return
    }
    const resolvedContext: common.UIAbilityContext = context ?? AppContextHolder.getContext()
    if (!resolvedContext) {
      throw new Error('NoteRepository requires ability context')
    }
    await DatabaseService.getInstance().init(resolvedContext)
    await FileService.getInstance().init(resolvedContext)
    this.context = resolvedContext
    this.notesVersion = 0
    this.initialized = true
  }

  setScheduleSyncHandler(handler: (noteId: string) => void): void {
    this.scheduleSyncHandler = handler
  }

  getNotesVersion(): number {
    return this.notesVersion
  }

  notifyNotesChanged(): void {
    if (this.notificationSuspendCount > 0) {
      this.pendingNotesChanged = true
      return
    }
    this.bumpVersion()
  }

  invalidateCachesForIdentityChange(): void {
    this.invalidateListCaches()
    this.bumpVersion()
  }

  private async noteForDisplay(note: Note): Promise<Note> {
    const userId = await NoteContentEncryptionService.getInstance().resolveUserId()
    if (userId === null) {
      return note
    }
    const out = await NoteContentEncryptionService.getInstance().decryptNoteForDisplay(note, userId)
    if (note.extractJobId.length > 0 && out.extractJobId.length === 0) {
      Logger.warn('LinkExtractDebug',
        `noteForDisplay DROPPED extractJobId noteId=${note.id} in=${note.extractJobId} out=${out.extractJobId} ` +
        `extractStatus=${out.extractStatus}`
      )
    }
    return out
  }

  beginBulkNotification(): void {
    this.notificationSuspendCount += 1
  }

  endBulkNotification(): void {
    if (this.notificationSuspendCount <= 0) {
      return
    }
    this.notificationSuspendCount -= 1
    if (this.notificationSuspendCount === 0 && this.pendingNotesChanged) {
      this.pendingNotesChanged = false
      this.bumpVersion()
    }
  }

  async createNote(input: CreateNoteInput): Promise<Note> {
    await this.init()
    const now = Date.now()
    const id = IdUtils.uuid()
    const trimmedContent = input.content
    const trimmedTitle = input.title.trim()
    const resolvedTitle =
      input.skipTitleAutoFill === true && trimmedTitle.length === 0 ? '' :
        trimmedTitle.length > 0 ? trimmedTitle : MarkdownUtils.extractTitle(trimmedContent)
    const state = NoteStateCodec.createDefaultState(id, resolvedTitle, now)
    const userData = (input.userData ?? '').trim()
    if (userData.length > 0) {
      state.userData = userData
    }
    const sourceUrl = (input.sourceUrl ?? '').trim()
    if (sourceUrl.length > 0) {
      state.sourceUrl = sourceUrl
    }
    const note = this.createNoteFromState(state, trimmedContent, {
      noteId: id,
      remoteModified: 0,
      deleted: false,
      deletedAt: 0,
      lastOperationAt: now,
      syncStatus: 'pending'
    }, input.tags)
    await FileService.getInstance().writeNoteFile(note)
    await DatabaseService.getInstance().upsertSyncState(this.toSyncState(note))
    this.bumpVersion()
    this.scheduleSyncHandler?.(id)
    return note
  }

  async createFlowchartNote(title: string = ''): Promise<Note> {
    await this.init()
    const now = Date.now()
    const id = IdUtils.uuid()
    const resolvedTitle = title.trim().length > 0 ? title.trim() : '编辑标题'
    const state = NoteStateCodec.createDefaultState(id, resolvedTitle, now, 2)
    state.userData = '{"kind":"flowchart","formatVersion":1}'
    const note = this.createNoteFromState(state, '', {
      noteId: id,
      remoteModified: 0,
      deleted: false,
      deletedAt: 0,
      lastOperationAt: now,
      syncStatus: 'pending'
    }, [])
    await FileService.getInstance().writeNoteFile(note)
    await DatabaseService.getInstance().upsertSyncState(this.toSyncState(note))
    this.bumpVersion()
    this.scheduleSyncHandler?.(id)
    return note
  }

  async ensureFlowchartNote(noteId: string, title: string = ''): Promise<Note> {
    await this.init()
    const existing = await this.getNote(noteId)
    if (existing) {
      return existing
    }
    const now = Date.now()
    const resolvedTitle = title.trim().length > 0 ? title.trim() : FLOWCHART_DEFAULT_TITLE
    const state = NoteStateCodec.createDefaultState(noteId, resolvedTitle, now, 2)
    state.userData = '{"kind":"flowchart","formatVersion":1}'
    const note = this.createNoteFromState(state, '', {
      noteId: noteId,
      remoteModified: 0,
      deleted: false,
      deletedAt: 0,
      lastOperationAt: now,
      syncStatus: 'pending'
    }, [])
    await FileService.getInstance().writeNoteFile(note)
    await DatabaseService.getInstance().upsertSyncState(this.toSyncState(note))
    this.bumpVersion()
    this.scheduleSyncHandler?.(noteId)
    return note
  }

  async saveFlowchartNote(id: string, graph: FlowchartGraphModel, title?: string): Promise<Note> {
    await this.init()
    const existing = await this.getNote(id)
    if (!existing) {
      throw new Error(`Note ${id} does not exist`)
    }
    await FlowchartService.getInstance().save(graph, id)
    const searchable = flowchartSearchableText(graph)
    const resolvedTitle = (title ?? existing.title ?? '').trim()
    const nextTitle = resolvedTitle.length > 0 ? resolvedTitle : '编辑标题'
    const now = Date.now()
    const updated = this.cloneNote(existing)
    updated.title = nextTitle
    updated.content = searchable
    updated.summary = flowchartSearchSummary(graph)
    updated.type_ = 2
    updated.localModified = now
    updated.deleted = false
    updated.deletedAt = 0
    updated.lastOperationAt = now
    updated.syncStatus = 'pending'
    updated.updatedAt = now
    await FileService.getInstance().writeNoteFile(updated)
    await DatabaseService.getInstance().upsertSyncState(this.toSyncState(updated))
    this.bumpVersion()
    this.scheduleSyncHandler?.(id)
    return updated
  }

  async getNote(id: string): Promise<Note | null> {
    await this.init()
    await this.migrateNoteEncryptionIfNeeded(id)
    const payload = await FileService.getInstance().readParsedNote(id)
    if (!payload) {
      return null
    }
    const syncState = await DatabaseService.getInstance().getSyncState(id)
    return this.noteForDisplay(this.createNoteFromPayload(payload, syncState ?? undefined))
  }

  async listNotes(): Promise<Note[]> {
    await this.init()
    if (this.cachedActiveNotesVersion === this.notesVersion && this.cachedActiveNotes) {
      const notes: Note[] = []
      for (const note of this.cachedActiveNotes) {
        notes.push(await this.noteForDisplay(this.cloneNote(note)))
      }
      return notes
    }
    const notes = (await this.loadAllNotes()).filter((note: Note) => !note.deleted && note.deletedTime === 0)
    const sortedNotes = NoteSortUtils.sortByLastEditedDesc(notes)
    const displayNotes: Note[] = []
    for (const note of sortedNotes) {
      if (!(await this.shouldIncludeNoteInHomeList(note))) {
        continue
      }
      displayNotes.push(await this.noteForDisplay(this.cloneNote(note)))
    }
    this.cachedActiveNotes = displayNotes
    this.cachedActiveNotesVersion = this.notesVersion
    return this.cloneNotes(displayNotes)
  }

  async listAllNotes(): Promise<Note[]> {
    await this.init()
    if (this.cachedAllNotesVersion === this.notesVersion && this.cachedAllNotes) {
      const notes: Note[] = []
      for (const note of this.cachedAllNotes) {
        notes.push(await this.noteForDisplay(this.cloneNote(note)))
      }
      return notes
    }
    const notes = await this.loadAllNotes()
    const sortedNotes = NoteSortUtils.sortByLastEditedDesc(notes)
    const displayNotes: Note[] = []
    for (const note of sortedNotes) {
      displayNotes.push(await this.noteForDisplay(this.cloneNote(note)))
    }
    this.cachedAllNotes = displayNotes
    this.cachedAllNotesVersion = this.notesVersion
    return this.cloneNotes(displayNotes)
  }

  /**
   * 本地回收站：同步库中 delete=1 的墓碑，以及笔记文件中 deleted_time=1 的条目。
   */
  async listRecycleBinNotes(): Promise<Note[]> {
    await this.init()
    const map: Map<string, Note> = new Map()
    const tombstones = await DatabaseService.getInstance().listDeletedSyncStates()
    for (const state of tombstones) {
      const fromFile = await this.getNote(state.noteId)
      if (fromFile) {
        // 仅「回收站」条目（deleted_time=1）留在列表；彻底删除（如 2）或已还原的不展示
        if (fromFile.deletedTime === 1) {
          map.set(fromFile.id, fromFile)
        }
      } else {
        map.set(state.noteId, this.createDeletedTombstoneNote(state))
      }
    }
    const allLocal = await this.loadAllNotes()
    for (const note of allLocal) {
      if (note.deletedTime === 1) {
        map.set(note.id, note)
      }
    }
    return NoteSortUtils.sortByLastEditedDesc(Array.from(map.values()))
  }

  /**
   * 在 listRecycleBinNotes 基础上合并远端：下载远程 .md 并解析，若文档状态中 deleted_time 为 1 则纳入列表。
   * 仅存在于远端且未写入本地的条目 id 记入 remoteOnlyIds（打开详情前需 persistRemoteRecycleBinSnapshot）。
   */
  async listRecycleBinNotesMergedWithRemote(): Promise<RecycleBinLoadResult> {
    const localNotes = await this.listRecycleBinNotes()
    const map: Map<string, Note> = new Map()
    localNotes.forEach((note: Note) => {
      map.set(note.id, note)
    })
    const remoteOnlyIds: string[] = []
    const context = AppContextHolder.tryGetContext()
    if (!context) {
      return { notes: localNotes, remoteOnlyIds: [] }
    }
    try {
      await PreferencesService.getInstance().init(context)
    } catch (_) {
      return { notes: localNotes, remoteOnlyIds: [] }
    }
    const config = await PreferencesService.getInstance().getWebDAVConfig()
    if (!config || !config.enabled || await PreferencesService.getInstance().isAuthInvalid()) {
      return { notes: localNotes, remoteOnlyIds: [] }
    }
    try {
      const remoteIds = await WebDAVClient.getInstance().listRemoteNotes()
      for (let i = 0; i < remoteIds.length; i += 1) {
        const noteId = remoteIds[i]
        // 本地仅有墓碑或无文件时仍需拉远端；仅当本地已有 deleted_time=1 的完整 md 时再跳过，避免重复下载。
        if (await this.hasRecycleBinMarkdownLocally(noteId)) {
          continue
        }
        try {
          const remoteStat = await WebDAVClient.getInstance().getRemoteStat(noteId)
          if (!remoteStat.exists) {
            continue
          }
          const raw = await WebDAVClient.getInstance().downloadNote(noteId)
          const payload = NoteStateCodec.parseNoteFile(raw, noteId,
            remoteStat.remoteModified > 0 ? remoteStat.remoteModified : Date.now())
          if (payload.state.deletedTime !== 1) {
            continue
          }
          const existingSync = await DatabaseService.getInstance().getSyncState(noteId)
          const fallbackSync: NoteSyncState = {
            noteId,
            remoteModified: remoteStat.remoteModified > 0 ? remoteStat.remoteModified : payload.modifiedAt,
            deleted: false,
            deletedAt: 0,
            lastOperationAt: remoteStat.remoteModified > 0 ? remoteStat.remoteModified : payload.modifiedAt,
            syncStatus: 'synced'
          }
          const merged = await this.noteForDisplay(
            this.createNoteFromPayload(payload, existingSync ?? fallbackSync))
          map.set(noteId, merged)
          if (!(await FileService.getInstance().readParsedNote(noteId))) {
            remoteOnlyIds.push(noteId)
          }
        } catch (error) {
          Logger.warn('NoteRepository', `listRecycleBinNotesMergedWithRemote skip noteId=${noteId}: ${JSON.stringify(error)}`)
        }
      }
    } catch (error) {
      Logger.warn('NoteRepository', `listRecycleBinNotesMergedWithRemote remote branch failed: ${JSON.stringify(error)}`)
    }
    return {
      notes: NoteSortUtils.sortByLastEditedDesc(Array.from(map.values())),
      remoteOnlyIds
    }
  }

  /** 将远端回收站快照写入本地后再编辑（GET WebDAV）。 */
  async persistRemoteRecycleBinSnapshot(noteId: string): Promise<Note | null> {
    await this.init()
    const holderContext = AppContextHolder.tryGetContext()
    if (!holderContext) {
      return null
    }
    try {
      await PreferencesService.getInstance().init(holderContext)
    } catch (_) {
      return null
    }
    const config = await PreferencesService.getInstance().getWebDAVConfig()
    if (!config || !config.enabled) {
      return null
    }
    try {
      const remoteStat = await WebDAVClient.getInstance().getRemoteStat(noteId)
      if (!remoteStat.exists) {
        return null
      }
      const raw = await WebDAVClient.getInstance().downloadNote(noteId)
      const payload = NoteStateCodec.parseNoteFile(raw, noteId,
        remoteStat.remoteModified > 0 ? remoteStat.remoteModified : Date.now())
      if (payload.state.deletedTime !== 1) {
        return null
      }
      const syncedState: NoteSyncState = {
        noteId,
        remoteModified: remoteStat.remoteModified > 0 ? remoteStat.remoteModified : payload.modifiedAt,
        deleted: false,
        deletedAt: 0,
        lastOperationAt: remoteStat.remoteModified > 0 ? remoteStat.remoteModified : payload.modifiedAt,
        syncStatus: 'synced'
      }
      const note = await this.noteForDisplay(this.createNoteFromPayload(payload, syncedState))
      await FileService.getInstance().writeNoteFile(note)
      await DatabaseService.getInstance().upsertSyncState(this.toSyncState(note))
      this.bumpVersion()
      return note
    } catch (error) {
      Logger.warn('NoteRepository', `persistRemoteRecycleBinSnapshot failed: ${JSON.stringify(error)}`)
      return null
    }
  }

  async saveDraft(id: string, patch: UpdateNoteInput): Promise<Note> {
    await this.init()
    const existing = await this.getNote(id)
    if (!existing) {
      throw new Error(`Note ${id} does not exist`)
    }
    const nextContent = patch.content ?? existing.content
    const nextTitle = (patch.title ?? existing.title).trim()
    const nextTags = patch.tags ?? existing.tags
    const allNoteIds = new Set(await FileService.getInstance().listNoteIds())
    const nextParentId = NoteFolderTree.sanitizeParentId(
      patch.parentId !== undefined ? patch.parentId : existing.parentId,
      allNoteIds,
      id
    )
    const resolvedTitle =
      patch.skipTitleAutoFill === true && nextTitle.length === 0 ? '' :
        nextTitle.length > 0 ? nextTitle : MarkdownUtils.extractTitle(nextContent)
    const nextSummary = MarkdownUtils.summary(nextContent)
    const contentChanged = nextContent !== existing.content
    const titleChanged = resolvedTitle !== existing.title
    const summaryChanged = nextSummary !== existing.summary
    const tagsChanged = !this.areTagsEqual(nextTags, existing.tags)
    const parentIdChanged = nextParentId !== existing.parentId
    const nextAudioId = patch.audioId !== undefined ? patch.audioId : existing.audioId
    const audioIdChanged = nextAudioId !== existing.audioId
    const nextSourceUrl = patch.sourceUrl !== undefined ? patch.sourceUrl : existing.sourceUrl
    const sourceUrlChanged = nextSourceUrl !== existing.sourceUrl
    const nextVoiceSummary = patch.voiceSummary !== undefined ? patch.voiceSummary : existing.voiceSummary
    const voiceSummaryChanged = nextVoiceSummary !== existing.voiceSummary
    const nextVoiceSegmentsJson =
      patch.voiceSegmentsJson !== undefined ? patch.voiceSegmentsJson : existing.voiceSegmentsJson
    const voiceSegmentsChanged = nextVoiceSegmentsJson !== existing.voiceSegmentsJson
    const nextVoiceTranscribeStatus =
      patch.voiceTranscribeStatus !== undefined ? patch.voiceTranscribeStatus : existing.voiceTranscribeStatus
    const voiceStatusChanged = nextVoiceTranscribeStatus !== existing.voiceTranscribeStatus
    if (!contentChanged && !titleChanged && !summaryChanged && !tagsChanged && !parentIdChanged && !audioIdChanged &&
      !sourceUrlChanged && !voiceSummaryChanged && !voiceSegmentsChanged && !voiceStatusChanged) {
      return this.cloneNote(existing)
    }

    const now = Date.now()
    const updated: Note = this.cloneNote(existing)
    updated.title = resolvedTitle
    updated.content = nextContent
    updated.tags = [...nextTags]
    updated.parentId = nextParentId
    updated.summary = nextSummary
    updated.audioId = nextAudioId
    updated.sourceUrl = nextSourceUrl
    updated.voiceSummary = nextVoiceSummary
    updated.voiceSegmentsJson = nextVoiceSegmentsJson
    updated.voiceTranscribeStatus = nextVoiceTranscribeStatus
    updated.localModified = now
    updated.deleted = false
    updated.deletedAt = 0
    updated.lastOperationAt = now
    updated.syncStatus = 'pending'
    updated.updatedAt = now
    await FileService.getInstance().writeNoteFile(updated)
    await DatabaseService.getInstance().upsertSyncState(this.toSyncState(updated))
    this.bumpVersion()
    this.scheduleSyncHandler?.(id)
    return updated
  }

  /**
   * 回收站侧滑「删除」：front matter `deleted_time` 设为 2，条目不再出现在回收站列表。
   * 无本地正文时清除同步库墓碑（等价于彻底移除该项）。
   */
  async setRecycleBinNoteDeletedTimePermanent(id: string): Promise<void> {
    await this.init()
    const now = Date.now()
    let note = await this.getNote(id)
    if (!note) {
      note = await this.persistRemoteRecycleBinSnapshot(id)
    }
    if (!note) {
      await DatabaseService.getInstance().deleteSyncState(id)
      this.bumpVersion()
      await WebDAVClient.getInstance().appendPermanentlyDeletedNoteId(id)
      this.scheduleSyncHandler?.(id)
      return
    }
    const updated = this.cloneNote(note)
    updated.deletedTime = 2
    updated.updatedAt = now
    updated.lastOperationAt = now
    updated.syncStatus = 'pending'
    updated.deleted = true
    if (updated.deletedAt <= 0) {
      updated.deletedAt = now
    }
    await FileService.getInstance().writeNoteFile(updated)
    await DatabaseService.getInstance().upsertSyncState(this.toSyncState(updated))
    await this.deleteImagesForNote(updated.content, updated.imageRefs)
    await this.deleteAudioForNote(updated.audioId)
    this.bumpVersion()
    await WebDAVClient.getInstance().appendPermanentlyDeletedNoteId(id)
    this.scheduleSyncHandler?.(id)
  }

  /**
   * Update the async link-extract fields for a note without rewriting the
   * note body (unless [UpdateExtractInfo.title/content] are provided). Used
   * by the background link-extract flow to flip status / persist job id after
   * submitting the async job, and to overwrite title + content when the
   * server2 job completes.
   */
  async updateExtractInfo(patch: UpdateExtractInfo): Promise<Note> {
    await this.init()
    const existing = await this.getNote(patch.noteId)
    if (!existing) {
      Logger.warn('LinkExtractDebug', `updateExtractInfo note not found noteId=${patch.noteId}`)
      throw new Error(`Note ${patch.noteId} does not exist`)
    }
    Logger.info('LinkExtractDebug',
      `updateExtractInfo begin noteId=${patch.noteId} ` +
      `oldStatus=${existing.extractStatus} oldJobId=${existing.extractJobId} ` +
      `oldTitleLen=${existing.title.length} oldContentLen=${existing.content.length} ` +
      `patch.status=${patch.status ?? 'null'} patch.jobId=${patch.jobId ?? 'null'} ` +
      `patch.titleLen=${patch.title?.length ?? 'null'} patch.contentLen=${patch.content?.length ?? 'null'}`
    )
    const now = Date.now()
    const nextTitle: string = patch.title ?? existing.title
    const nextContent: string = patch.content ?? existing.content
    let nextSummary = existing.summary
    let nextImageRefs = existing.imageRefs
    if (patch.content !== undefined) {
      nextSummary = MarkdownUtils.summary(nextContent)
      nextImageRefs = NoteStateCodec.extractImageRefs(nextContent)
    }
    const updated: Note = {
      id: existing.id,
      title: nextTitle,
      content: nextContent,
      tags: existing.tags,
      summary: nextSummary,
      localModified: now,
      remoteModified: existing.remoteModified,
      deleted: existing.deleted,
      deletedAt: existing.deletedAt,
      lastOperationAt: now,
      syncStatus: 'pending',
      filePath: existing.filePath,
      createdAt: existing.createdAt,
      updatedAt: now,
      parentId: existing.parentId,
      isConflict: existing.isConflict,
      latitude: existing.latitude,
      longitude: existing.longitude,
      altitude: existing.altitude,
      author: existing.author,
      sourceUrl: existing.sourceUrl,
      isTodo: existing.isTodo,
      todoDue: existing.todoDue,
      todoCompleted: existing.todoCompleted,
      source: existing.source,
      order: existing.order,
      userData: existing.userData,
      rsa: existing.rsa,
      imageRefs: nextImageRefs,
      audioId: patch.audioId !== undefined ? patch.audioId : existing.audioId,
      deletedTime: existing.deletedTime,
      type_: existing.type_,
      extractStatus: patch.status ?? existing.extractStatus,
      extractJobId: patch.jobId ?? existing.extractJobId,
      extractError: patch.error ?? existing.extractError,
      extractedAt: patch.extractedAt ?? existing.extractedAt,
      extractProgress: patch.progress ?? existing.extractProgress,
      voiceSummary: patch.voiceSummary !== undefined ? patch.voiceSummary : existing.voiceSummary,
      voiceSegmentsJson: existing.voiceSegmentsJson,
      voiceTranscribeStatus: patch.voiceTranscribeStatus !== undefined
        ? patch.voiceTranscribeStatus
        : existing.voiceTranscribeStatus
    }
    await FileService.getInstance().writeNoteFile(updated)
    await DatabaseService.getInstance().upsertSyncState(this.toSyncState(updated))
    this.bumpVersion()
    Logger.info('LinkExtractDebug',
      `updateExtractInfo done noteId=${patch.noteId} ` +
      `newStatus=${updated.extractStatus} newJobId=${updated.extractJobId} ` +
      `newTitleLen=${updated.title.length} newContentLen=${updated.content.length} ` +
      `syncStatus=${updated.syncStatus}`
    )
    if (this.scheduleSyncHandler) {
      await this.scheduleSyncHandler(updated.id)
    }
    return updated
  }

  /**
   * Notes whose link-extract job is still in flight (queued / running). The
   * caller (e.g. home page pull-to-refresh / onPageShow) should poll server2
   * for these to refresh their state.
   */
  async listNotesNeedingExtract(): Promise<Note[]> {
    await this.init()
    const notes = await this.loadAllNotes()
    const candidates = notes.filter((n): boolean => {
      if (n.deleted || n.deletedTime !== 0) {
        return false
      }
      return isExtractStatusPending(n.extractStatus)
    })
    // Sample some loaded notes so we can see what's actually in memory.
    const sample = notes.slice(0, 3).map((n): string =>
      `id=${n.id.substring(0, 8)} extractStatus=${n.extractStatus} extractJobId=${n.extractJobId} deleted=${n.deleted} deletedTime=${n.deletedTime}`
    )
    const sampleHasJob = notes.filter(n => !!n.extractJobId).slice(0, 3).map((n): string =>
      `hit id=${n.id.substring(0, 8)} extractStatus=${n.extractStatus} extractJobId=${n.extractJobId}`
    )
    Logger.info('LinkExtractDebug',
      `listNotesNeedingExtract totalLoaded=${notes.length} ` +
      `candidates=${candidates.length} ` +
      `withExtractJobId=${notes.filter(n => !!n.extractJobId).length} ` +
      `pending=${notes.filter(n => isExtractStatusPending(n.extractStatus)).length} ` +
      `sample=[${sample.join(' | ')}] ` +
      `sampleHasJob=[${sampleHasJob.join(' | ')}]`
    )
    return candidates
  }

  async refreshExtractJobForNote(noteId: string): Promise<Note | null> {
    await this.init()
    const id = noteId.trim()
    if (id.length === 0) {
      return null
    }
    let note = await this.getNote(id)
    if (note === null || note.deleted || !isExtractStatusPending(note.extractStatus)) {
      return note
    }
    let jobId = note.extractJobId.trim()
    if (jobId.length === 0) {
      note = await this.recoverExtractJobId(note)
      if (note === null || !isExtractStatusPending(note.extractStatus)) {
        return note
      }
      jobId = note.extractJobId.trim()
      if (jobId.length === 0) {
        return note
      }
    }
    try {
      const job = await LinkExtractClient.getInstance().getJob(jobId)
      if (job.status === 'succeeded' && job.result !== null) {
        const result = job.result
        const isVideo = result.mediaKind === 'video' || result.audioId.trim().length > 0
        return await this.updateExtractInfo({
          noteId: id,
          jobId: job.jobId,
          status: 'succeeded',
          title: job.result.title.length > 0 ? job.result.title : note.title,
          content: job.result.content.length > 0 ? job.result.content : note.content,
          extractedAt: job.finishedAt ?? job.updatedAt,
          progress: 1.0,
          audioId: result.audioId.trim().length > 0 ? result.audioId.trim() : undefined,
          voiceSummary: isVideo ? result.voiceSummary : undefined,
          voiceTranscribeStatus: isVideo ? 'succeeded' : undefined
        })
      }
      if (job.status === 'partial' && job.result !== null) {
        const result = job.result
        const isVideo = result.mediaKind === 'video' || result.audioId.trim().length > 0
        return await this.updateExtractInfo({
          noteId: id,
          jobId: job.jobId,
          status: 'partial',
          title: job.result.title.length > 0 ? job.result.title : note.title,
          content: job.result.content.length > 0 ? job.result.content : note.content,
          extractedAt: job.finishedAt ?? job.updatedAt,
          progress: 1.0,
          error: job.error?.code ?? '',
          audioId: result.audioId.trim().length > 0 ? result.audioId.trim() : undefined,
          voiceSummary: isVideo ? result.voiceSummary : undefined,
          voiceTranscribeStatus: isVideo ? 'succeeded' : undefined
        })
      }
      if (job.status === 'failed') {
        const isVideoNote = (note.audioId ?? '').trim().length > 0
        return await this.updateExtractInfo({
          noteId: id,
          jobId: job.jobId,
          status: 'failed',
          error: job.error?.code ?? 'extract_failed',
          voiceTranscribeStatus: isVideoNote ? 'failed' : undefined
        })
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : ''
      if (msg === 'job_not_found') {
        return await this.updateExtractInfo({
          noteId: id,
          status: 'failed',
          error: 'job_not_found'
        })
      }
      return note
    }
    return await this.getNote(id)
  }

  /** pending 但缺少 extract_job_id 时：重新 submit（或 409 复用）写回隐藏字段。 */
  private async recoverExtractJobId(note: Note): Promise<Note | null> {
    const url = (note.sourceUrl ?? '').trim()
    if (url.length === 0) {
      return await this.updateExtractInfo({
        noteId: note.id,
        status: 'failed',
        error: 'missing_source_url'
      })
    }
    try {
      const job = await LinkExtractClient.getInstance().submitJob(
        url,
        '请根据链接内容生成结构化的 Markdown 笔记摘要。',
        0,
        note.id
      )
      if (job.jobId.trim().length === 0) {
        return await this.updateExtractInfo({
          noteId: note.id,
          status: 'failed',
          error: 'extract_failed'
        })
      }
      let nextStatus: ExtractStatus = 'running'
      if (job.status === 'queued') {
        nextStatus = 'queued'
      }
      // 终态仍先落 jobId 为 running，随后由 getJob 路径覆盖 title/content。
      if (job.status === 'succeeded' || job.status === 'partial' || job.status === 'failed') {
        nextStatus = 'running'
      }
      return await this.updateExtractInfo({
        noteId: note.id,
        jobId: job.jobId,
        status: nextStatus
      })
    } catch (_) {
      return note
    }
  }

  async hasAnyPendingExtract(): Promise<boolean> {
    await this.init()
    const notes = await this.loadAllNotes()
    return notes.some((note: Note): boolean => {
      if (note.deleted || note.deletedTime !== 0) {
        return false
      }
      return isExtractStatusPending(note.extractStatus)
    })
  }

  async cancelPendingExtractJob(note: Note): Promise<void> {
    if (!isExtractStatusPending(note.extractStatus)) {
      return
    }
    const jobId = note.extractJobId.trim()
    if (jobId.length === 0) {
      return
    }
    try {
      await LinkExtractClient.getInstance().cancelJob(jobId)
    } catch (_) {
      // Best-effort; local delete should proceed even if server is unreachable.
    }
  }

  /**
   * 回收站侧滑「还原」：`deleted_time` 设为 0，并清除本地删除同步状态。
   */
  async restoreRecycleBinNote(id: string): Promise<void> {
    await this.init()
    const now = Date.now()
    let note = await this.getNote(id)
    if (!note) {
      note = await this.persistRemoteRecycleBinSnapshot(id)
    }
    if (!note) {
      throw new Error('无法还原：缺少笔记数据')
    }
    const updated = this.cloneNote(note)
    updated.deletedTime = 0
    updated.deleted = false
    updated.deletedAt = 0
    updated.updatedAt = now
    updated.lastOperationAt = now
    updated.syncStatus = 'pending'
    await FileService.getInstance().writeNoteFile(updated)
    await DatabaseService.getInstance().clearDeleted(id, updated.remoteModified, now, 'pending')
    this.bumpVersion()
    this.scheduleSyncHandler?.(id)
  }

  async deleteNote(id: string, operationTime: number): Promise<void> {
    await this.init()
    const existing = await this.getNote(id)
    if (!existing) {
      await DatabaseService.getInstance().markDeleted(id, operationTime)
      this.bumpVersion()
      this.scheduleSyncHandler?.(id)
      return
    }
    await this.cancelPendingExtractJob(existing)
    const updated = this.cloneNote(existing)
    updated.deletedTime = 1
    updated.updatedAt = operationTime
    updated.lastOperationAt = operationTime
    updated.syncStatus = 'pending'
    updated.deleted = true
    updated.deletedAt = operationTime
    await FileService.getInstance().writeNoteFile(updated)
    await DatabaseService.getInstance().upsertSyncState(this.toSyncState(updated))
    this.bumpVersion()
    this.scheduleSyncHandler?.(id)
  }

  /** 退出登录时清空本地笔记、图片与同步库，并重置标签/同步游标（保留 WebDAV 配置）。 */
  async clearAllLocalNotes(): Promise<void> {
    // 若仍有正在跑的微信读书导入，先把它停掉再清空，避免它在我们删除笔记文件之后
    // 继续往本地写新笔记（旧账号的内容残留到下一个会话）。
    await WereadImportService.getInstance().cancelImport()
    // 印象笔记导入同理。
    await YinxiangImportService.getInstance().cancelImport()
    await this.init()
    this.beginBulkNotification()
    try {
      await FileService.getInstance().clearAllNoteFiles()
      await DatabaseService.getInstance().clearAllSyncStates()
      await this.clearLocalImagesDirectory()
      await PreferencesService.getInstance().saveNoteTags([])
      await PreferencesService.getInstance().setLastSyncTime(0)
      await PreferencesService.getInstance().setLastRemoteIndexUpdatedAt(0)
      await PreferencesService.getInstance().setLastRemoteIndexFingerprint('')
    } finally {
      this.endBulkNotification()
      this.invalidateCachesForIdentityChange()
    }
  }

  private async clearLocalImagesDirectory(): Promise<void> {
    const ctx = this.context ?? AppContextHolder.tryGetContext()
    if (!ctx) {
      return
    }
    const imagesDir = `${ctx.filesDir ?? ''}/qingyu-note-image`
    try {
      if (!fs.accessSync(imagesDir)) {
        return
      }
      const entries = fs.listFileSync(imagesDir, {
        recursion: false,
        listNum: 0
      }) as string[]
      for (const name of entries) {
        const filePath = `${imagesDir}/${name}`
        if (fs.accessSync(filePath)) {
          fs.unlinkSync(filePath)
        }
      }
    } catch (error) {
      Logger.warn('NoteRepository', `clearLocalImagesDirectory failed: ${JSON.stringify(error)}`)
    }
  }

  /** 删除本地笔记文件并移除同步库记录（远端 `deleted_time` 为 2 时与远端一并清空）。 */
  async purgeLocalNoteCompletely(noteId: string): Promise<void> {
    await this.init()
    const note = await this.getNote(noteId)
    if (note !== null) {
      await this.deleteImagesForNote(note.content, note.imageRefs)
      await this.deleteAudioForNote(note.audioId)
    }
    await FileService.getInstance().deleteNoteFile(noteId)
    await FileService.getInstance().deleteFlowchartFile(noteId)
    await DatabaseService.getInstance().deleteSyncState(noteId)
    this.bumpVersion()
  }

  async restoreNoteFromRemote(note: Note, content: string): Promise<void> {
    await this.init()
    await this.overwriteFromRemote(note.id, content, note.remoteModified)
  }

  async overwriteFromRemote(noteId: string, content: string, remoteModified: number): Promise<Note> {
    await this.init()
    const payload = NoteStateCodec.parseNoteFile(content, noteId, remoteModified > 0 ? remoteModified : Date.now())
    const allNoteIds = new Set(await FileService.getInstance().listNoteIds())
    payload.state.parentId = NoteFolderTree.sanitizeParentId(
      payload.state.parentId,
      allNoteIds,
      noteId
    )
    payload.filePath = FileService.getInstance().getNotePath(noteId)
    payload.modifiedAt = remoteModified > 0 ? remoteModified : payload.modifiedAt
    const migrated = await this.persistEncryptionMigrationFromRaw(noteId, payload, remoteModified, true)
    if (migrated !== null) {
      await DatabaseService.getInstance().clearDeleted(noteId, remoteModified, migrated.lastOperationAt,
        migrated.syncStatus)
      this.bumpVersion()
      return migrated
    }
    const syncedState: NoteSyncState = {
      noteId,
      remoteModified,
      deleted: false,
      deletedAt: 0,
      lastOperationAt: remoteModified > 0 ? remoteModified : payload.modifiedAt,
      syncStatus: 'synced'
    }
    const updated = await this.noteForDisplay(this.createNoteFromPayload(payload, syncedState))
    await FileService.getInstance().writeNoteFile(updated)
    await DatabaseService.getInstance().clearDeleted(noteId, remoteModified, syncedState.lastOperationAt, 'synced')
    this.bumpVersion()
    return updated
  }

  /** 老版本未加密笔记：按磁盘原文加密标题/正文并写入 `rsa: true`。 */
  async migrateNoteEncryptionIfNeeded(noteId: string, rawPayload?: NoteFilePayload): Promise<Note | null> {
    await this.init()
    const payload = rawPayload ?? await FileService.getInstance().readRawParsedNote(noteId)
    if (!payload) {
      return null
    }
    const syncState = await DatabaseService.getInstance().getSyncState(noteId)
    return this.persistEncryptionMigrationFromRaw(noteId, payload, syncState?.remoteModified ?? 0, true, syncState ?? undefined)
  }

  private async persistEncryptionMigrationFromRaw(noteId: string, rawPayload: NoteFilePayload,
    remoteModified: number, scheduleSyncOnMigrate: boolean,
    syncState?: NoteSyncState): Promise<Note | null> {
    const userId = await NoteContentEncryptionService.getInstance().resolveUserId()
    if (userId === null) {
      return null
    }
    const encryption = NoteContentEncryptionService.getInstance()
    const rsa = rawPayload.state.rsa
    const title = rawPayload.state.title
    const content = rawPayload.content
    const needsMigrate = encryption.needsEncryptionMigration(rsa, title, content)
    const needsRepair = encryption.needsRsaFlagRepair(rsa, title, content)
    if (!needsMigrate && !needsRepair) {
      return null
    }
    const plaintextPayload =
      await encryption.plaintextPayloadFromRaw(rawPayload, userId)
    const now = Date.now()
    const effectiveSyncState: NoteSyncState = syncState ?? {
      noteId,
      remoteModified,
      deleted: false,
      deletedAt: 0,
      lastOperationAt: rawPayload.modifiedAt > 0 ? rawPayload.modifiedAt : now,
      syncStatus: 'pending'
    }
    let writeNote = this.createNoteFromPayload(plaintextPayload, effectiveSyncState)
    if (needsMigrate && scheduleSyncOnMigrate) {
      writeNote = this.cloneNote(writeNote)
      writeNote.syncStatus = 'pending'
      writeNote.lastOperationAt = now
    }
    await FileService.getInstance().writeNoteFile(writeNote)
    if (needsMigrate && scheduleSyncOnMigrate) {
      await DatabaseService.getInstance().upsertSyncState(this.toSyncState(writeNote))
      this.scheduleSyncHandler?.(noteId)
    } else if (needsRepair) {
      await DatabaseService.getInstance().upsertSyncState(this.toSyncState(writeNote))
    }
    this.bumpVersion()
    const display = await this.noteForDisplay(this.createNoteFromPayload(plaintextPayload, effectiveSyncState))
    display.syncStatus = writeNote.syncStatus
    display.lastOperationAt = writeNote.lastOperationAt
    return display
  }

  async startupRepair(): Promise<void> {
    await this.init()
    const noteIds = await FileService.getInstance().listNoteIds()
    const allNoteIds = new Set(noteIds)
    let repaired: boolean = false
    let checkedNotes: number = 0
    const syncStateMap = await this.loadSyncStateMap()
    const userId = await NoteContentEncryptionService.getInstance().resolveUserId()
    for (const noteId of noteIds) {
      const rawPayload = await FileService.getInstance().readRawParsedNote(noteId)
      if (!rawPayload) {
        continue
      }
      if (await this.migrateNoteEncryptionIfNeeded(noteId, rawPayload) !== null) {
        repaired = true
        checkedNotes += 1
        if (checkedNotes % 10 === 0) {
          await this.yieldToMainThread()
        }
        continue
      }
      const displayPayload = userId === null
        ? rawPayload
        : await NoteContentEncryptionService.getInstance().decryptPayloadForDisplay(rawPayload, userId)
      let note = this.createNoteFromPayload(displayPayload, syncStateMap.get(noteId))
      const sanitizedParent = NoteFolderTree.sanitizeParentId(
        note.parentId,
        allNoteIds,
        note.id
      )
      let needsWrite = !rawPayload.hasStateBlock || displayPayload.state.title !== note.title
      if (sanitizedParent !== note.parentId) {
        note = this.cloneNote(note)
        note.parentId = sanitizedParent
        needsWrite = true
      }
      if (!needsWrite) {
        checkedNotes += 1
        if (checkedNotes % 10 === 0) {
          await this.yieldToMainThread()
        }
        continue
      }
      await FileService.getInstance().writeNoteFile(note)
      repaired = true
      checkedNotes += 1
      if (checkedNotes % 10 === 0) {
        await this.yieldToMainThread()
      }
    }
    if (repaired) {
      this.bumpVersion()
    }
  }

  private async shouldIncludeNoteInHomeList(note: Note): Promise<boolean> {
    if (note.type_ !== 2) {
      if (!shouldShowTodoNoteInHomeList(note.title ?? '', note.content ?? '', note.tags ?? [])) {
        await this.purgeLocalNoteCompletely(note.id)
        return false
      }
      return true
    }
    if (!isDefaultFlowchartTitle(note.title ?? '')) {
      return true
    }
    // 标题为默认占位「编辑标题」时，需要 `.qy` 边车至少有非占位节点才展示。
    // `.qy` 缺失只表明本地未同步完成（远端可能仍有），不应 purge 笔记，
    // 否则 `syncRemoteOnlyNote` 拉 `.md` 之后没拉到 `.qy` 时会被这里一并清掉。
    const hasFlowchartFile = FileService.getInstance().flowchartFileExists(note.id)
    if (!hasFlowchartFile) {
      return false
    }
    const graph = await FlowchartService.getInstance().load(note.id)
    if (shouldShowFlowchartInHomeList(note.title ?? '', graph)) {
      return true
    }
    await this.purgeLocalNoteCompletely(note.id)
    return false
  }

  private async loadAllNotes(): Promise<Note[]> {
    const noteIds = await FileService.getInstance().listNoteIds()
    const syncStateMap = await this.loadSyncStateMap()
    if (noteIds.length === 0) {
      return []
    }
    const slots: Array<Note | null> = this.createNullFilledArray(noteIds.length)
    const workerCount = Math.min(NoteRepository.LOAD_ALL_NOTES_CONCURRENCY, noteIds.length)
    let nextIndex: number = 0
    const workers: Promise<void>[] = []
    for (let w = 0; w < workerCount; w += 1) {
      workers.push((async () => {
        while (nextIndex < noteIds.length) {
          const currentIndex = nextIndex
          nextIndex += 1
          const noteId = noteIds[currentIndex]
          try {
            await NoteRepository.getInstance().migrateNoteEncryptionIfNeeded(noteId)
            let payload = await FileService.getInstance().readParsedNote(noteId)
            // 极少数情况下文件在 listNoteIds 后被并发删除/截断（writeNoteFile 用 TRUNC），
            // 短暂等待后重试一次。这能避免「pending 笔记彻底从 listNotesNeedingExtract 视野消失」。
            if (!payload) {
              await new Promise<void>(resolve => setTimeout(resolve, 30))
              payload = await FileService.getInstance().readParsedNote(noteId)
              if (!payload) {
                Logger.warn('LinkExtractDebug',
                  `loadAllNotes readParsedNote returned null after retry for noteId=${noteId}`)
              }
            }
            if (payload) {
              slots[currentIndex] = await this.noteForDisplay(
                this.createNoteFromPayload(payload, syncStateMap.get(noteId)))
            }
          } catch (e) {
            Logger.warn('LinkExtractDebug',
              `loadAllNotes worker failed for noteId=${noteId}: ${JSON.stringify(e)}`)
          }
        }
      })())
    }
    await Promise.all(workers)
    const notes: Note[] = []
    for (let i = 0; i < slots.length; i += 1) {
      const n = slots[i]
      if (n !== null) {
        notes.push(n)
      }
    }
    const withJob = notes.filter(n => !!n.extractJobId)
    const withStatusRunning = notes.filter(n => n.extractStatus === 'running' || n.extractStatus === 'queued')
    const slotFilled = slots.filter(s => s !== null).length
    const slotNull = slots.filter(s => s === null).length
    const nullIds: string[] = []
    for (let i = 0; i < slots.length; i += 1) {
      if (slots[i] === null) {
        nullIds.push(noteIds[i].substring(0, 8))
        if (nullIds.length >= 10) break
      }
    }
    Logger.info('LinkExtractDebug',
      `loadAllNotes slots=${slots.length} filled=${slotFilled} null=${slotNull} ` +
      `notes=${notes.length} withJob=${withJob.length} withStatus=${withStatusRunning.length} ` +
      `nullIds=[${nullIds.join(',')}] firstWithJob=${withJob.slice(0, 3).map(n => `id=${n.id.substring(0, 8)} jobId=${n.extractJobId.substring(0, 16)}`).join(' | ')} ` +
      `anyJobInNotes=${withJob.length > 0} anyJobIds=${notes.filter(n => !!n.extractJobId).map(n => n.id.substring(0, 8)).slice(0, 5).join(',')}`
    )
    return notes
  }

  private createNullFilledArray(length: number): Array<Note | null> {
    const arr: Array<Note | null> = new Array(length)
    for (let i = 0; i < length; i += 1) {
      arr[i] = null
    }
    return arr
  }

  /**
   * 本地已有笔记正文时不必再为回收站列表拉 WebDAV 覆盖：
   * deleted_time=1 仍在回收站；=2 本地已彻底删除；=0 已还原待同步，远端可能仍为回收站，
   * 若以本地为准则不可再合并远端回收站快照，否则还原后列表仍会出现该条。
   */
  private async hasRecycleBinMarkdownLocally(noteId: string): Promise<boolean> {
    const payload = await FileService.getInstance().readParsedNote(noteId)
    if (!payload) {
      return false
    }
    const dt = payload.state.deletedTime
    return dt === 0 || dt === 1 || dt === 2
  }

  private async loadSyncStateMap(): Promise<Map<string, NoteSyncState>> {
    const syncStates = await DatabaseService.getInstance().listAllSyncStates()
    const syncStateMap: Map<string, NoteSyncState> = new Map()
    for (const syncState of syncStates) {
      syncStateMap.set(syncState.noteId, syncState)
    }
    return syncStateMap
  }

  private createDeletedTombstoneNote(state: NoteSyncState): Note {
    const fallback =
      state.lastOperationAt > 0 ? state.lastOperationAt : (state.deletedAt > 0 ? state.deletedAt : Date.now())
    const base = NoteStateCodec.createDefaultState(state.noteId, '', fallback)
    return {
      id: state.noteId,
      title: '',
      content: '',
      tags: [],
      imageRefs: [...base.imageRefs],
      audioId: '',
      summary: '',
      localModified: fallback,
      remoteModified: state.remoteModified,
      deleted: true,
      deletedAt: state.deletedAt,
      lastOperationAt: state.lastOperationAt,
      syncStatus: state.syncStatus,
      filePath: '',
      createdAt: base.createdAt,
      updatedAt: fallback,
      parentId: base.parentId,
      isConflict: base.isConflict,
      latitude: base.latitude,
      longitude: base.longitude,
      altitude: base.altitude,
      author: base.author,
      sourceUrl: base.sourceUrl,
      isTodo: base.isTodo,
      todoDue: base.todoDue,
      todoCompleted: base.todoCompleted,
      source: base.source,
      order: base.order,
      userData: base.userData,
      rsa: base.rsa,
      deletedTime: 0,
      type_: base.type_,
      extractStatus: base.extractStatus,
      extractJobId: base.extractJobId,
      extractError: base.extractError,
      extractedAt: base.extractedAt,
      extractProgress: base.extractProgress,
      voiceSummary: base.voiceSummary,
      voiceSegmentsJson: base.voiceSegmentsJson,
      voiceTranscribeStatus: base.voiceTranscribeStatus
    }
  }

  private createNoteFromPayload(payload: NoteFilePayload, syncState?: NoteSyncState, tags?: string[]): Note {
    return this.createNoteFromState(payload.state, payload.content, syncState, tags, payload.filePath, payload.modifiedAt)
  }

  private createNoteFromState(state: NoteStateBlock, content: string, syncState?: NoteSyncState, tags?: string[],
    filePath?: string, modifiedAt?: number): Note {
    const resolvedTitle = state.title.trim().length > 0 ? state.title.trim() : MarkdownUtils.extractTitle(content)
    const resolvedCreatedAt = state.createdAt > 0 ? state.createdAt : (modifiedAt ?? Date.now())
    const resolvedUpdatedAt = state.updatedAt > 0 ? state.updatedAt : resolvedCreatedAt
    const resolvedLocalModified = Math.max(resolvedUpdatedAt, modifiedAt ?? 0)
    const effectiveSyncState = syncState ?? {
      noteId: state.id,
      remoteModified: 0,
      deleted: false,
      deletedAt: 0,
      lastOperationAt: resolvedLocalModified,
      syncStatus: 'pending'
    }
    const resolvedTags = tags ?? state.tags ?? []
    const resolvedImageRefs: string[] = state.imageRefs ?? []
    const note: Note = {
      id: state.id,
      title: resolvedTitle,
      content,
      tags: [...resolvedTags],
      imageRefs: resolvedImageRefs,
      audioId: state.audioId ?? '',
      summary: MarkdownUtils.summary(content),
      localModified: resolvedLocalModified,
      remoteModified: effectiveSyncState.remoteModified,
      deleted: effectiveSyncState.deleted,
      deletedAt: effectiveSyncState.deletedAt,
      lastOperationAt: effectiveSyncState.lastOperationAt > 0 ? effectiveSyncState.lastOperationAt : resolvedLocalModified,
      syncStatus: effectiveSyncState.syncStatus,
      filePath: filePath ?? FileService.getInstance().getNotePath(state.id),
      createdAt: resolvedCreatedAt,
      updatedAt: resolvedUpdatedAt,
      parentId: state.parentId,
      isConflict: state.isConflict,
      latitude: state.latitude,
      longitude: state.longitude,
      altitude: state.altitude,
      author: state.author,
      sourceUrl: state.sourceUrl,
      isTodo: state.isTodo,
      todoDue: state.todoDue,
      todoCompleted: state.todoCompleted,
      source: state.source,
      order: state.order,
      userData: state.userData,
      rsa: state.rsa,
      deletedTime: state.deletedTime,
      type_: state.type_,
      extractStatus: state.extractStatus,
      extractJobId: state.extractJobId,
      extractError: state.extractError,
      extractedAt: state.extractedAt,
      extractProgress: state.extractProgress,
      voiceSummary: state.voiceSummary,
      voiceSegmentsJson: state.voiceSegmentsJson,
      voiceTranscribeStatus: state.voiceTranscribeStatus
    }
    if (state.extractJobId.length > 0 && note.extractJobId.length === 0) {
      Logger.warn('LinkExtractDebug',
        `createNoteFromState DROPPED extractJobId noteId=${state.id} in=${state.extractJobId} out=${note.extractJobId}`
      )
    }
    return note
  }

  private toSyncState(note: Note): NoteSyncState {
    return {
      noteId: note.id,
      remoteModified: note.remoteModified,
      deleted: note.deleted,
      deletedAt: note.deletedAt,
      lastOperationAt: note.lastOperationAt,
      syncStatus: note.syncStatus
    }
  }

  private bumpVersion(): void {
    if (this.notificationSuspendCount > 0) {
      this.pendingNotesChanged = true
      return
    }
    this.notesVersion += 1
    this.invalidateListCaches()
  }

  private invalidateListCaches(): void {
    this.cachedActiveNotes = undefined
    this.cachedAllNotes = undefined
    this.cachedActiveNotesVersion = -1
    this.cachedAllNotesVersion = -1
  }

  private cloneNotes(notes: Note[]): Note[] {
    const clonedNotes: Note[] = []
    for (const note of notes) {
      clonedNotes.push(this.cloneNote(note))
    }
    return clonedNotes
  }

  private cloneNote(note: Note): Note {
    return {
      id: note.id,
      title: note.title,
      content: note.content,
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
      isTodo: note.isTodo,
      todoDue: note.todoDue,
      todoCompleted: note.todoCompleted,
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

  private areTagsEqual(left: string[], right: string[]): boolean {
    if (left.length !== right.length) {
      return false
    }
    for (let index = 0; index < left.length; index += 1) {
      if (left[index] !== right[index]) {
        return false
      }
    }
    return true
  }

  private async yieldToMainThread(): Promise<void> {
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), 0)
    })
  }

  private async deleteImagesForNote(content: string, stateImageRefs?: string[]): Promise<void> {
    const refs = new Set<string>(NoteStateCodec.extractImageRefs(content))
    if (stateImageRefs !== undefined) {
      for (const ref of stateImageRefs) {
        if (ref.length > 0) {
          refs.add(ref)
        }
      }
    }
    const imageRefs = Array.from(refs)
    if (imageRefs.length === 0) {
      return
    }
    const ctx = this.context
    if (!ctx) {
      return
    }
    const baseDir = ctx.filesDir
    for (const ref of imageRefs) {
      try {
        const fileName = ref.split('/').pop() ?? ''
        if (fileName.length === 0) {
          continue
        }
        const localPath = `${baseDir}/qingyu-note-image/${fileName}`
        if (FileService.fileExists(localPath)) {
          FileService.deleteFile(localPath)
        }
      } catch (error) {
        Logger.warn('NoteRepository', `deleteImagesForNote failed for ${ref}: ${JSON.stringify(error)}`)
      }
    }
  }

  private async deleteAudioForNote(audioId: string): Promise<void> {
    const trimmed = audioId.trim()
    if (trimmed.length === 0) {
      return
    }
    const ctx = this.context
    if (!ctx) {
      return
    }
    try {
      const localPath = `${ctx.filesDir}/audio/${trimmed}`
      if (FileService.fileExists(localPath)) {
        FileService.deleteFile(localPath)
      }
    } catch (error) {
      Logger.warn('NoteRepository', `deleteAudioForNote failed for ${audioId}: ${JSON.stringify(error)}`)
    }
  }
}
