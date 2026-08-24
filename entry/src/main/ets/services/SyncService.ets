import type { Note, NoteSyncState, SyncResult } from '../common/model/Note'
import { NOTE_TYPE_FLOWCHART } from '../common/model/FlowchartGraph'
import { DatabaseService } from './DatabaseService'
import { NoteRepository } from './NoteRepository'
import { PreferencesService } from './PreferencesService'
import { WebDAVClient } from './WebDAVClient'
import type { RemoteIndexEntry, RemoteIndexSnapshot } from './WebDAVClient'
import { FileService } from './FileService'
import { NoteHistoryService } from './NoteHistoryService'
import { NoteHistoryReason } from '../common/model/NoteHistory'
import { TimeUtils } from '../common/utils/TimeUtils'
import { NoteStateCodec } from '../common/utils/NoteStateCodec'
import { Logger } from '../common/utils/Logger'
import { UserFacingMessage } from '../common/utils/UserFacingMessage'
import { AppContextHolder } from './AppContextHolder'
import { NoteImagesChangedEventPayload, SyncConstants } from '../common/constants/SyncConstants'
import { NoteSettingsRemoteSync } from './NoteSettingsRemoteSync'
import { blockWebDavSyncIfForceUpdateRequired } from './AppUpdateUi'

const WEBDAV_SYNC_FORCE_UPDATE_MESSAGE = '当前版本过低，请更新后再同步'

const TOMBSTONE_RETENTION_MS = 30 * 24 * 60 * 60 * 1000
const FULL_SYNC_CONCURRENCY = 3
const MEDIUM_SYNC_CONCURRENCY = 2
const LOW_SYNC_CONCURRENCY = 1
/** 索引中「待彻底删除」条目的并发度，纯本地+少量 DELETE，可略高于单条同步。 */
const INDEX_PURGE_CONCURRENCY = 4
/** 同一笔记内多图与 WebDAV 的并发上限，避免过多 HTTP 连接（与全量笔记并发叠加时仍可控）。 */
const IMAGE_WEBDAV_CONCURRENCY = 4
const MEDIUM_SYNC_NOTE_COUNT = 80
const LARGE_SYNC_NOTE_COUNT = 200
const MAX_RETRYABLE_SYNC_ATTEMPTS = 3
const RETRY_DELAY_MS = 600

interface RemoteStatSnapshot {
  exists: boolean
  remoteModified: number
  contentLength: number
}

interface ErrorLike {
  code?: number | string
  message?: string
  name?: string
}

/** 单条笔记内多图传输的工作单元（并行时保留 ref 便于日志）。 */
interface ImageRefWorkItem {
  ref: string
  fileName: string
  localPath: string
}

/** eventHub 第二参需为显式类型，不可使用无类型对象字面量 `{}` */
class QingyuSyncBlockedEventPayload {
}

export class SyncService {
  private static instance: SyncService = new SyncService()
  private initialized: boolean = false
  private scheduledTimers: Map<string, number> = new Map()
  private noteLocks: Set<string> = new Set()
  private currentSyncPromise?: Promise<SyncResult[]>
  private syncRunning: boolean = false
  /** 本轮全量同步是否因条目上限而截断（与 Flutter 对齐）。 */
  private lastFullSyncHadMoreNotesFlag: boolean = false

  static getInstance(): SyncService {
    return SyncService.instance
  }

  getLastFullSyncHadMoreNotes(): boolean {
    return this.lastFullSyncHadMoreNotesFlag
  }

  async init(): Promise<void> {
    if (this.initialized) {
      return
    }
    await NoteRepository.getInstance().init()
    NoteRepository.getInstance().setScheduleSyncHandler((noteId: string) => {
      this.scheduleSync(noteId)
    })
    try {
      AppContextHolder.tryGetContext()?.eventHub.on(
        SyncConstants.cloudSyncStopOnLogoutEvent,
        this.stopOnLogoutHandler)
    } catch (_) {
      Logger.warn('SyncService', 'eventHub.on cloud_sync_stop_on_logout failed')
    }
    this.syncRunning = false
    this.initialized = true
  }

  private stopOnLogoutHandler = (): void => {
    this.stopAllCloudSyncActivity()
  }

  private async ensureCanRunCloudSync(): Promise<boolean> {
    return await PreferencesService.getInstance().canRunCloudSync()
  }

  /** 取消已调度的 debounce 同步；不强制中断进行中的批次（入口与 emit 会再次门禁）。 */
  stopAllCloudSyncActivity(): void {
    this.cancelScheduledSync()
  }

  scheduleSync(noteId?: string): void {
    void this.init().then(async () => {
      if (!(await this.ensureCanRunCloudSync())) {
        return
      }
      const policy = await PreferencesService.getInstance().getSyncPolicy()
      if (!policy.autoSync) {
        return
      }
      if (noteId) {
        this.cancelScheduledSync(noteId)
        const timerId = setTimeout(() => {
          void this.syncNote(noteId)
          this.scheduledTimers.delete(noteId)
        }, policy.debounceSeconds * 1000)
        this.scheduledTimers.set(noteId, timerId)
      } else {
        this.cancelScheduledSync()
        const timerId = setTimeout(() => {
          void this.syncNow()
          this.scheduledTimers.delete('__all__')
        }, policy.debounceSeconds * 1000)
        this.scheduledTimers.set('__all__', timerId)
      }
    })
  }

  cancelScheduledSync(noteId?: string): void {
    if (noteId) {
      const timerId = this.scheduledTimers.get(noteId)
      if (timerId !== undefined) {
        clearTimeout(timerId)
        this.scheduledTimers.delete(noteId)
      }
      return
    }
    this.scheduledTimers.forEach((timerId: number) => clearTimeout(timerId))
    this.scheduledTimers.clear()
  }

  async syncNow(): Promise<SyncResult[]> {
    await this.init()
    if (!(await this.ensureCanRunCloudSync())) {
      return []
    }
    this.cancelScheduledSync()
    if (this.currentSyncPromise) {
      Logger.info('SyncService', 'syncNow reuse current sync promise')
      return await this.currentSyncPromise
    }
    Logger.info('SyncService', 'syncNow start')
    this.currentSyncPromise = this.drainFullSyncBatches()
    this.syncRunning = true
    try {
      const results = await this.currentSyncPromise
      Logger.info('SyncService',
        `syncNow success: total=${results.length}, failed=${results.filter((result: SyncResult) => !result.success).length}`)
      return results
    } finally {
      this.currentSyncPromise = undefined
      this.syncRunning = false
      Logger.info('SyncService', 'syncNow finish')
    }
  }

  /**
   * 连续执行多轮全量同步批次，直至无剩余或达到 `SyncConstants.maxFullSyncPassesPerUserAction`。
   */
  private async drainFullSyncBatches(): Promise<SyncResult[]> {
    const merged: SyncResult[] = []
    const maxPasses = SyncConstants.maxFullSyncPassesPerUserAction
    for (let pass = 0; pass < maxPasses; pass += 1) {
      const batch = await this.performFullSync()
      merged.push(...batch)
      if (!this.lastFullSyncHadMoreNotesFlag) {
        break
      }
      await new Promise<void>((resolve) => setTimeout(resolve, 80))
    }
    if (this.lastFullSyncHadMoreNotesFlag) {
      Logger.warn('SyncService',
        `drainFullSyncBatches: stopped after ${maxPasses} passes with remaining work`)
    }
    return merged
  }

  /**
   * @param reuseRemoteIndexSnapshot 全量同步批次内传入已在 `performFullSync` 拉取的索引，
   *   避免每条笔记重复 GET `.qingyu-index.json`（首页同步主要耗时来源之一）。
   */
  async syncNote(noteId: string, reuseRemoteIndexSnapshot?: RemoteIndexSnapshot): Promise<SyncResult> {
    await this.init()
    if (!(await this.ensureCanRunCloudSync())) {
      return {
        noteId,
        success: true,
        action: 'skip',
        message: '',
        remoteModified: 0
      }
    }
    if (!(await this.isQingyuSubscriptionSyncAllowed())) {
      this.notifyQingyuSyncBlockedThrottled()
      return {
        noteId,
        success: false,
        action: 'skip',
        message: '请开通轻羽云服务',
        remoteModified: 0
      }
    }
    if (await blockWebDavSyncIfForceUpdateRequired()) {
      return {
        noteId,
        success: false,
        action: 'skip',
        message: WEBDAV_SYNC_FORCE_UPDATE_MESSAGE,
        remoteModified: 0
      }
    }
    if (this.noteLocks.has(noteId)) {
      Logger.info('SyncService', `syncNote skipped by lock: noteId=${noteId}`)
      return {
        noteId,
        success: true,
        action: 'skip',
        message: '同步中的笔记已复用当前任务',
        remoteModified: 0
      }
    }
    this.noteLocks.add(noteId)
    try {
      Logger.info('SyncService', `syncNote start: noteId=${noteId}`)
      const permanentIds =
        reuseRemoteIndexSnapshot !== undefined
          ? reuseRemoteIndexSnapshot.permanentlyDeletedNoteIds
          : (await WebDAVClient.getInstance().getRemoteIndexSnapshot()).permanentlyDeletedNoteIds
      if (permanentIds.includes(noteId)) {
        return await this.applyPermanentDeleteListedInIndex(noteId)
      }
      const syncState = await DatabaseService.getInstance().getSyncState(noteId)
      const note = await NoteRepository.getInstance().getNote(noteId)
      if (!note && !syncState) {
        Logger.warn('SyncService', `syncNote aborted: local state missing, noteId=${noteId}`)
        return {
          noteId,
          success: false,
          action: 'skip',
          message: '笔记不存在',
          remoteModified: 0
        }
      }
      const remoteStat = await this.safeRemoteStat(noteId)
      if (syncState?.deleted) {
        Logger.info('SyncService', `syncNote route deleted note: noteId=${noteId}`)
        return await this.syncDeletedNote(noteId, syncState, remoteStat.remoteModified, remoteStat.exists)
      }
      if (!note) {
        const remoteOnlyResult = await this.syncRemoteOnlyNote(noteId)
        if (remoteOnlyResult !== null) {
          return remoteOnlyResult
        }
        return {
          noteId,
          success: true,
          action: 'skip',
          message: '本地与远端都不存在',
          remoteModified: 0
        }
      }
      Logger.info('SyncService',
        `syncNote state: noteId=${noteId}, deleted=${note.deleted}, localLastOperationAt=${note.lastOperationAt}, remoteExists=${remoteStat.exists}, remoteModified=${remoteStat.remoteModified}, contentLength=${note.content.length}`)
      if (this.isLocallyEmptyNote(note)) {
        Logger.info('SyncService', `syncNote skip upload empty note: noteId=${noteId}`)
        return {
          noteId,
          success: true,
          action: 'skip',
          message: '本地笔记无标题且无内容且未入回收站，跳过上传',
          remoteModified: 0
        }
      }
      await NoteRepository.getInstance().migrateNoteEncryptionIfNeeded(noteId)
      const rawContent = await FileService.getInstance().readNoteFile(noteId)
      if (!remoteStat.exists) {
        Logger.info('SyncService', `syncNote upload new note: noteId=${noteId}`)
        const uploaded = await WebDAVClient.getInstance().uploadNote(noteId, rawContent, note.lastOperationAt, {
          deletedTime: note.deletedTime,
          contentLength: note.content.length
        })
        await this.syncImagesForNote(note, rawContent)
        await this.syncAudioForNote(note)
        await this.uploadFlowchartSidecarIfNeeded(noteId, note)
        await this.syncHistoryQuietly(noteId)
        if (await DatabaseService.getInstance().updateSyncStatus(noteId, 'synced',
          uploaded.remoteModified || note.lastOperationAt, note.lastOperationAt)) {
          NoteRepository.getInstance().notifyNotesChanged()
        }
        return {
          noteId,
          success: true,
          action: 'upload',
          message: '本地新笔记已上传',
          remoteModified: uploaded.remoteModified || note.lastOperationAt
        }
      }
      const compareResult = TimeUtils.compareWithTolerance(note.lastOperationAt, remoteStat.remoteModified)
      Logger.info('SyncService', `syncNote compareResult: noteId=${noteId}, compareResult=${compareResult}`)
      if (compareResult > 0) {
        const remotePeek = await WebDAVClient.getInstance().downloadNote(noteId)
        const purgePeek =
          await this.applyRemotePermanentDeleteIfNeeded(noteId, remotePeek, remoteStat.remoteModified)
        if (purgePeek !== null) {
          return purgePeek
        }
        await NoteHistoryService.getInstance().captureFromRemoteRaw(
          noteId,
          remotePeek,
          NoteHistoryReason.remoteClobber
        )
        Logger.info('SyncService', `syncNote upload newer local note: noteId=${noteId}`)
        const uploaded = await WebDAVClient.getInstance().uploadNote(noteId, rawContent, note.lastOperationAt, {
          deletedTime: note.deletedTime,
          contentLength: note.content.length
        })
        await this.syncImagesForNote(note, rawContent)
        await this.syncAudioForNote(note)
        await this.uploadFlowchartSidecarIfNeeded(noteId, note)
        await this.syncHistoryQuietly(noteId)
        if (await DatabaseService.getInstance().updateSyncStatus(noteId, 'synced',
          uploaded.remoteModified || note.lastOperationAt, note.lastOperationAt)) {
          NoteRepository.getInstance().notifyNotesChanged()
        }
        return {
          noteId,
          success: true,
          action: 'upload',
          message: '本地更新覆盖了远端',
          remoteModified: uploaded.remoteModified || note.lastOperationAt
        }
      }
      if (compareResult < 0) {
        Logger.info('SyncService', `syncNote download newer remote note: noteId=${noteId}`)
        const remoteContent = await WebDAVClient.getInstance().downloadNote(noteId)
        const remotePermanent = await this.applyRemotePermanentDeleteIfNeeded(noteId, remoteContent,
          remoteStat.remoteModified)
        if (remotePermanent !== null) {
          return remotePermanent
        }
        await NoteRepository.getInstance().overwriteFromRemote(noteId, remoteContent, remoteStat.remoteModified)
        await this.downloadFlowchartSidecarIfRemote(noteId)
        await this.downloadImagesForNote(noteId, remoteContent)
        await this.downloadAudioForNote(noteId, remoteContent)
        await this.syncHistoryQuietly(noteId)
        return {
          noteId,
          success: true,
          action: 'download',
          message: '远端更新已覆盖本地',
          remoteModified: remoteStat.remoteModified
        }
      }
      const canSkipBodyGet =
        remoteStat.contentLength > 0 &&
        remoteStat.contentLength === rawContent.length &&
        remoteStat.remoteModified > 0
      let remoteWhenEqual = ''
      if (canSkipBodyGet) {
        remoteWhenEqual = rawContent
      } else {
        remoteWhenEqual = await WebDAVClient.getInstance().downloadNote(noteId)
      }
      const purgeWhenEqual =
        await this.applyRemotePermanentDeleteIfNeeded(noteId, remoteWhenEqual, remoteStat.remoteModified)
      if (purgeWhenEqual !== null) {
        return purgeWhenEqual
      }
      // 知识图谱：.md 时间戳容差内一致但 .qy 边车可能仍存在差异，仍拉一次以防漏同步。
      if (note.type_ === NOTE_TYPE_FLOWCHART) {
        await this.downloadFlowchartSidecarIfRemote(noteId)
      }
      await this.downloadImagesForNote(noteId, remoteWhenEqual)
      await this.downloadAudioForNote(noteId, remoteWhenEqual)
      await this.syncHistoryQuietly(noteId)
      if (await DatabaseService.getInstance().updateSyncStatus(noteId, 'synced', remoteStat.remoteModified, note.lastOperationAt)) {
        NoteRepository.getInstance().notifyNotesChanged()
      }
      Logger.info('SyncService', `syncNote skip unchanged note: noteId=${noteId}`)
      return {
        noteId,
        success: true,
        action: 'skip',
        message: '本地与远端一致',
        remoteModified: remoteStat.remoteModified
      }
    } catch (error) {
      const rawError = this.describeError(error as Object)
      const errorMessage = UserFacingMessage.forCatch(error as Object, '同步失败，请稍后重试')
      Logger.error('SyncService', `syncNote failed: noteId=${noteId}, error=${rawError}`)
      if (rawError.includes('authentication')) {
        await PreferencesService.getInstance().setAuthInvalid(true)
      }
      const syncState = await DatabaseService.getInstance().getSyncState(noteId)
      if (await DatabaseService.getInstance().updateSyncStatus(noteId, 'error', syncState?.remoteModified, syncState?.lastOperationAt)) {
        NoteRepository.getInstance().notifyNotesChanged()
      }
      return {
        noteId,
        success: false,
        action: 'skip',
        message: errorMessage,
        remoteModified: 0
      }
    } finally {
      this.noteLocks.delete(noteId)
      Logger.info('SyncService', `syncNote finish: noteId=${noteId}`)
    }
  }

  async retryFailedNotes(): Promise<SyncResult[]> {
    await this.init()
    if (!(await this.ensureCanRunCloudSync())) {
      return []
    }
    const pendingNoteIds = await DatabaseService.getInstance().listPendingNoteIds()
    const localNotes = await NoteRepository.getInstance().listAllNotes()
    const permanentSnapshot = await WebDAVClient.getInstance().getRemoteIndexSnapshot()
    return await this.runSyncBatchWithDeferredNotifications(
      pendingNoteIds,
      this.buildLocalNoteMap(localNotes),
      FULL_SYNC_CONCURRENCY,
      new Set<string>(permanentSnapshot.permanentlyDeletedNoteIds),
      permanentSnapshot
    )
  }

  async onNetworkRestored(): Promise<void> {
    const policy = await PreferencesService.getInstance().getSyncPolicy()
    if (!policy.autoSync || await PreferencesService.getInstance().isAuthInvalid()) {
      return
    }
    await this.retryFailedNotes()
  }

  async restorePendingAfterLaunch(): Promise<void> {
    if (!(await this.ensureCanRunCloudSync())) {
      await DatabaseService.getInstance().purgeDeletedBefore(Date.now() - TOMBSTONE_RETENTION_MS)
      return
    }
    const pendingNoteIds = await DatabaseService.getInstance().listPendingNoteIds()
    if (pendingNoteIds.length > 0) {
      await this.retryFailedNotes()
    }
    await DatabaseService.getInstance().purgeDeletedBefore(Date.now() - TOMBSTONE_RETENTION_MS)
  }

  private async prioritizedUnionIds(unionIds: string[]): Promise<string[]> {
    const set = new Set(unionIds)
    const pending = await DatabaseService.getInstance().listPendingNoteIds()
    const out: string[] = []
    const used = new Set<string>()
    for (const id of pending) {
      if (set.has(id)) {
        out.push(id)
        used.add(id)
      }
    }
    const rest = unionIds.filter((id) => !used.has(id)).sort()
    out.push(...rest)
    return out
  }

  private async performFullSync(): Promise<SyncResult[]> {
    Logger.info('SyncService', 'performFullSync start')
    this.lastFullSyncHadMoreNotesFlag = false
    if (await blockWebDavSyncIfForceUpdateRequired()) {
      Logger.info('SyncService', 'performFullSync blocked by force update policy')
      return []
    }
    if (!(await this.isQingyuSubscriptionSyncAllowed())) {
      this.notifyQingyuSyncBlockedThrottled()
      return []
    }
    try {
      await WebDAVClient.getInstance().ensureNotesDirectory()
    } catch (error) {
      Logger.warn('SyncService',
        `performFullSync ensureNotesDirectory failed (check WebDAVClient qingyu path + HEAD/PROPFIND diagnostics): ${this.describeError(error as Object)}`)
    }
    await WebDAVClient.getInstance().pruneRemoteIndexPermanentlyDeletedIfNeeded()
    await NoteSettingsRemoteSync.getInstance().syncWithRemote()
    const remoteIndexSnapshot = await WebDAVClient.getInstance().getRemoteIndexSnapshot()
    const remoteIndexEntries = remoteIndexSnapshot.noteEntries
    const permanentDeletedIds =
      new Set<string>(remoteIndexSnapshot.permanentlyDeletedNoteIds)
    const localNotesInitial = await NoteRepository.getInstance().listAllNotes()
    const tombstonesInitial = await DatabaseService.getInstance().listDeletedSyncStates()
    const remoteNoteIds = remoteIndexEntries.size > 0
      ? Array.from(remoteIndexEntries.keys())
      : await WebDAVClient.getInstance().listRemoteNotes()
    const pendingNoteIds = await DatabaseService.getInstance().listPendingNoteIds()
    const fpNow = WebDAVClient.canonicalRemoteIndexFingerprint(remoteIndexSnapshot)
    const lastFp = await PreferencesService.getInstance().getLastRemoteIndexFingerprint()
    const lastUa = await PreferencesService.getInstance().getLastRemoteIndexUpdatedAt()
    const allowFastPath =
      localNotesInitial.length > 0 ||
      tombstonesInitial.length > 0 ||
      remoteNoteIds.length === 0
    if (pendingNoteIds.length === 0 &&
      allowFastPath &&
      remoteIndexSnapshot.updatedAt > 0 &&
      lastUa > 0 &&
      remoteIndexSnapshot.updatedAt === lastUa &&
      fpNow === lastFp) {
      await PreferencesService.getInstance().setLastSyncTime(Date.now())
      Logger.info('SyncService', 'performFullSync fast path (remote index unchanged)')
      return []
    }
    Logger.info('SyncService',
      `performFullSync loaded state: localNotes=${localNotesInitial.length}, deletedStates=${tombstonesInitial.length}, remoteNotes=${remoteNoteIds.length}, indexEntries=${remoteIndexEntries.size}, permanentIndex=${permanentDeletedIds.size}`)
    if (localNotesInitial.length === 0 && remoteNoteIds.length === 0 && tombstonesInitial.length === 0) {
      await PreferencesService.getInstance().setLastSyncTime(Date.now())
      Logger.info('SyncService', 'performFullSync finish: no local or remote notes')
      return []
    }
    const unionIds = new Set<string>()
    localNotesInitial.forEach((note: Note) => unionIds.add(note.id))
    tombstonesInitial.forEach((state: NoteSyncState) => unionIds.add(state.noteId))
    remoteNoteIds.forEach((noteId: string) => unionIds.add(noteId))

    const unionNoteIds = Array.from(unionIds)
    const purgeCandidateIds = unionNoteIds.filter((pid: string) => permanentDeletedIds.has(pid))
    const indexPurgeResults =
      purgeCandidateIds.length === 0
        ? []
        : await this.runParallelNoteTasks(purgeCandidateIds, INDEX_PURGE_CONCURRENCY,
          (pid: string) => this.applyPermanentDeleteListedInIndex(pid))
    const localNotes = await NoteRepository.getInstance().listAllNotes()
    const tombstones = await DatabaseService.getInstance().listDeletedSyncStates()
    const localNoteMap = this.buildLocalNoteMap(localNotes)
    const unionIdsRefreshed = new Set<string>()
    localNotes.forEach((note: Note) => unionIdsRefreshed.add(note.id))
    tombstones.forEach((state: NoteSyncState) => unionIdsRefreshed.add(state.noteId))
    remoteNoteIds.forEach((noteId: string) => unionIdsRefreshed.add(noteId))
    const unionNoteIdsRefreshed = Array.from(unionIdsRefreshed)
    const indexedSkippedResults: SyncResult[] = []
    const noteIdsNeedingSync: string[] = []
    for (let i = 0; i < unionNoteIdsRefreshed.length; i += 1) {
      const noteId = unionNoteIdsRefreshed[i]
      if (permanentDeletedIds.has(noteId)) {
        noteIdsNeedingSync.push(noteId)
        continue
      }
      const indexedEntry = remoteIndexEntries.get(noteId)
      const note = localNoteMap.get(noteId)
      if (note !== undefined) {
        if (this.canSkipByRemoteIndex(noteId, localNoteMap, indexedEntry)) {
          indexedSkippedResults.push({
            noteId,
            success: true,
            action: 'skip',
            message: '索引判定未变化，跳过同步',
            remoteModified: indexedEntry?.remoteModified ?? 0
          })
          continue
        }
        if (await this.canSkipByHeadFallback(noteId, note, indexedEntry)) {
          indexedSkippedResults.push({
            noteId,
            success: true,
            action: 'skip',
            message: 'HEAD 判定未变化，跳过同步',
            remoteModified: indexedEntry?.remoteModified ?? 0
          })
          continue
        }
      }
      noteIdsNeedingSync.push(noteId)
    }
    Logger.info('SyncService',
      `performFullSync prefilter: total=${unionNoteIdsRefreshed.length}, skippedByIndex=${indexedSkippedResults.length}, needingSync=${noteIdsNeedingSync.length}`)
    let idsToSync = await this.prioritizedUnionIds(noteIdsNeedingSync)
    const cap = SyncConstants.maxNotesPerFullSyncPass
    if (idsToSync.length > cap) {
      idsToSync = idsToSync.slice(0, cap)
      this.lastFullSyncHadMoreNotesFlag = true
      Logger.info('SyncService',
        `performFullSync: capped to ${cap} notes (${noteIdsNeedingSync.length} needing sync)`)
    }
    const fullSyncConcurrency = this.resolveFullSyncConcurrency(idsToSync.length)
    WebDAVClient.getInstance().beginDeferRemoteIndexMerge()
    let syncResults: SyncResult[] = []
    try {
      syncResults = await this.runSyncBatchWithDeferredNotifications(idsToSync, localNoteMap,
        fullSyncConcurrency, permanentDeletedIds, remoteIndexSnapshot)
    } finally {
      WebDAVClient.getInstance().endDeferRemoteIndexMerge()
    }
    const results = [...indexPurgeResults, ...indexedSkippedResults, ...syncResults]
    const failedNoteIds = results
      .filter((result: SyncResult) => !result.success)
      .map((result: SyncResult) => result.noteId)
    if (failedNoteIds.length > 0) {
      Logger.warn('SyncService',
        `performFullSync retry failed notes: failedCount=${failedNoteIds.length}, retryConcurrency=1`)
      const retryLocalNotes = await NoteRepository.getInstance().listAllNotes()
      WebDAVClient.getInstance().beginDeferRemoteIndexMerge()
      try {
        const retryResults = await this.runSyncBatchWithDeferredNotifications(
          failedNoteIds,
          this.buildLocalNoteMap(retryLocalNotes),
          1,
          permanentDeletedIds,
          remoteIndexSnapshot
        )
        this.mergeRetryResults(results, retryResults)
        Logger.info('SyncService',
          `performFullSync retry finish: retried=${retryResults.length}, remainingFailed=${results.filter((result: SyncResult) => !result.success).length}`)
      } finally {
        WebDAVClient.getInstance().endDeferRemoteIndexMerge()
      }
    }
    const refreshedLocalNotes = await NoteRepository.getInstance().listAllNotes()
    await WebDAVClient.getInstance().flushRemoteIndexFromLocalNotes(refreshedLocalNotes)
    const afterSnap = await WebDAVClient.getInstance().getRemoteIndexSnapshot()
    await PreferencesService.getInstance().setLastRemoteIndexFingerprint(
      WebDAVClient.canonicalRemoteIndexFingerprint(afterSnap))
    await PreferencesService.getInstance().setLastRemoteIndexUpdatedAt(afterSnap.updatedAt)
    await PreferencesService.getInstance().setLastSyncTime(Date.now())
    Logger.info('SyncService',
      `performFullSync finish: unionIds=${unionIdsRefreshed.size}, total=${results.length}, failed=${results.filter((result: SyncResult) => !result.success).length}`)
    return results
  }

  private async isQingyuSubscriptionSyncAllowed(): Promise<boolean> {
    const intent = await PreferencesService.getInstance().getQingyuCloudSyncIntent()
    if (intent !== 'qingyu') {
      return true
    }
    const st = await WebDAVClient.getInstance().fetchQingyuCloudSubscriptionStatus()
    if (st.kind === 'lifetime' || st.kind === 'active') {
      return true
    }
    return false
  }

  /** 视频链接提取：须已登录且轻羽云同步可用（含有效订阅）。 */
  async isQingyuCloudAvailableForVideoExtract(): Promise<boolean> {
    const token = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (token === null || token.trim().length === 0) {
      return false
    }
    const intent = await PreferencesService.getInstance().getQingyuCloudSyncIntent()
    if (intent !== 'qingyu') {
      return false
    }
    const config = await PreferencesService.getInstance().getWebDAVConfig()
    if (config === null || !config.enabled) {
      return false
    }
    if (config.provider !== 'qingyu_cloud') {
      return false
    }
    return await this.isQingyuSubscriptionSyncAllowed()
  }

  private notifyQingyuSyncBlockedThrottled(): void {
    void this.emitQingyuBlockedUi()
  }

  private async emitQingyuBlockedUi(): Promise<void> {
    if (!(await this.ensureCanRunCloudSync())) {
      return
    }
    const hub = AppContextHolder.tryGetContext()?.eventHub
    if (hub === undefined) {
      return
    }
    let hasSelfHosted = false
    try {
      const ctx = AppContextHolder.tryGetContext()
      if (ctx !== undefined) {
        await PreferencesService.getInstance().init(ctx)
      }
      const snapshot = await PreferencesService.getInstance().getSavedCustomWebDAVConfigSnapshot()
      hasSelfHosted = snapshot !== null && snapshot.enabled
    } catch (_) {
      hasSelfHosted = false
    }
    try {
      if (!hasSelfHosted) {
        hub.emit(SyncConstants.cloudSyncNotConfiguredToastEvent, new QingyuSyncBlockedEventPayload())
      } else {
        hub.emit(SyncConstants.qingyuSyncBlockedEvent, new QingyuSyncBlockedEventPayload())
      }
    } catch (_) {
      Logger.warn('SyncService', 'emit qingyu_sync_blocked / cloud_sync_not_configured_toast failed')
    }
  }

  private mergeRetryResults(results: SyncResult[], retryResults: SyncResult[]): void {
    if (retryResults.length === 0 || results.length === 0) {
      return
    }
    const retryMap: Map<string, SyncResult> = new Map()
    retryResults.forEach((result: SyncResult) => retryMap.set(result.noteId, result))
    for (let index = 0; index < results.length; index += 1) {
      const current = results[index]
      if (current.success) {
        continue
      }
      const retried = retryMap.get(current.noteId)
      if (!retried) {
        continue
      }
      results[index] = retried
    }
  }

  private async syncDeletedNote(noteId: string, syncState: NoteSyncState, remoteModified: number,
    exists: boolean): Promise<SyncResult> {
    if (!exists) {
      if (await DatabaseService.getInstance().updateSyncStatus(noteId, 'synced', 0, syncState.lastOperationAt)) {
        NoteRepository.getInstance().notifyNotesChanged()
      }
      return {
        noteId,
        success: true,
        action: 'skip',
        message: '远端已不存在，删除状态完成',
        remoteModified: 0
      }
    }
    const compareResult = TimeUtils.compareWithTolerance(syncState.deletedAt, remoteModified)
    if (compareResult > 0) {
      const lastMs = syncState.deletedAt > 0 ? syncState.deletedAt : Date.now()
      const rawContent = await FileService.getInstance().readNoteFile(noteId)
      const payload = rawContent.length > 0 ? rawContent : NoteStateCodec.serializeRemoteRecycleBinFile(noteId, lastMs)
      const tombNote = await NoteRepository.getInstance().getNote(noteId)
      const uploaded = await WebDAVClient.getInstance().uploadNote(noteId, payload, lastMs, {
        deletedTime: tombNote?.deletedTime ?? 1
      })
      const nextRemote = uploaded.remoteModified > 0 ? uploaded.remoteModified : lastMs
      if (await DatabaseService.getInstance().updateSyncStatus(noteId, 'synced', nextRemote, syncState.lastOperationAt)) {
        NoteRepository.getInstance().notifyNotesChanged()
      }
      return {
        noteId,
        success: true,
        action: 'delete',
        message: '较新的本地删除已同步为远端回收站',
        remoteModified: nextRemote
      }
    }
    const remoteContent = await WebDAVClient.getInstance().downloadNote(noteId)
    const tombstonePurge = await this.applyRemotePermanentDeleteIfNeeded(noteId, remoteContent, remoteModified)
    if (tombstonePurge !== null) {
      return tombstonePurge
    }
    await NoteRepository.getInstance().overwriteFromRemote(noteId, remoteContent, remoteModified)
    await this.downloadFlowchartSidecarIfRemote(noteId)
    await this.downloadImagesForNote(noteId, remoteContent)
    await this.downloadAudioForNote(noteId, remoteContent)
    return {
      noteId,
      success: true,
      action: 'restore',
      message: '远端更新较新，已恢复本地笔记',
      remoteModified
    }
  }

  /**
   * 正文 trim 后为空，且标题为空或为占位「未命名笔记」（与列表解析一致），且 deleted_time 为 0 时，
   * 视为空草稿，不应 PUT 到远端。
   */
  private isLocallyEmptyNote(note: Note): boolean {
    if (note.type_ === 2) {
      return false
    }
    if (note.deletedTime !== 0) {
      return false
    }
    // 语音笔记：仅有录音、正文尚为空时仍需同步 audio 到远端供转写服务读取。
    if (note.audioId.trim().length > 0) {
      return false
    }
    const bodyEmpty = note.content.trim().length === 0
    if (!bodyEmpty) {
      return false
    }
    const t = note.title.trim()
    return t.length === 0 || t === '未命名笔记'
  }

  /** 语音转写前确保录音已上传 WebDAV；失败时抛出异常供上层展示。 */
  async uploadAudioForNoteOrThrow(noteId: string): Promise<void> {
    const note = await NoteRepository.getInstance().getNote(noteId)
    if (!note) {
      throw new Error('笔记不存在')
    }
    const audioId = note.audioId.trim()
    if (audioId.length === 0) {
      throw new Error('录音文件未找到，请稍后重试')
    }
    const ctx = AppContextHolder.getContext()
    if (!ctx) {
      throw new Error('同步失败，请稍后重试')
    }
    const localPath = `${ctx.filesDir}/audio/${audioId}`
    if (!FileService.fileExists(localPath)) {
      Logger.error('SyncService', `uploadAudioForNoteOrThrow missing local file: noteId=${noteId}, path=${localPath}`)
      throw new Error('录音文件未找到，请稍后重试')
    }
    const bytes = FileService.readFileAsArrayBuffer(localPath)
    Logger.info('SyncService', `uploadAudioForNoteOrThrow start: noteId=${noteId}, audioId=${audioId}, bytes=${bytes.byteLength}`)
    await WebDAVClient.getInstance().uploadAudio(audioId, bytes)
    Logger.info('SyncService', `uploadAudioForNoteOrThrow done: noteId=${noteId}, audioId=${audioId}`)
  }

  private async syncHistoryQuietly(noteId: string): Promise<void> {
    await NoteHistoryService.getInstance().syncWithCloud(noteId)
  }

  private async uploadFlowchartSidecarIfNeeded(noteId: string, note: Note): Promise<void> {
    if (note.type_ !== 2) {
      return
    }
    if (!FileService.getInstance().flowchartFileExists(noteId)) {
      return
    }
    const raw = await FileService.getInstance().readFlowchartFile(noteId)
    if (raw.trim().length === 0) {
      return
    }
    await WebDAVClient.getInstance().uploadFlowchart(noteId, raw, note.lastOperationAt)
  }

  private async downloadFlowchartSidecarIfRemote(noteId: string): Promise<void> {
    try {
      const stat = await WebDAVClient.getInstance().getFlowchartRemoteStat(noteId)
      if (!stat.exists) {
        return
      }
      const raw = await WebDAVClient.getInstance().downloadFlowchart(noteId)
      if (raw.length > 0) {
        await FileService.getInstance().writeFlowchartFile(noteId, raw)
      }
    } catch (error) {
      Logger.warn('SyncService', `flowchart download skipped: ${JSON.stringify(error)}`)
    }
  }

  private async safeRemoteStat(noteId: string): Promise<RemoteStatSnapshot> {
    try {
      const remoteStat = await WebDAVClient.getInstance().getRemoteStat(noteId)
      Logger.info('SyncService',
        `safeRemoteStat success: noteId=${noteId}, exists=${remoteStat.exists}, remoteModified=${remoteStat.remoteModified}`)
      return {
        exists: remoteStat.exists,
        remoteModified: remoteStat.remoteModified,
        contentLength: remoteStat.contentLength
      }
    } catch (error) {
      Logger.warn('SyncService', `safeRemoteStat fallback for ${noteId}: ${JSON.stringify(error)}`)
      return {
        exists: false,
        remoteModified: 0,
        contentLength: 0
      }
    }
  }

  private buildLocalNoteMap(notes: Note[]): Map<string, Note> {
    const noteMap: Map<string, Note> = new Map()
    notes.forEach((note: Note) => noteMap.set(note.id, note))
    return noteMap
  }

  /** 无顺序要求的并行任务（如索引 purge），与 `runSyncBatch` 同款 worker 模型。 */
  private async runParallelNoteTasks<T>(noteIds: string[], concurrency: number,
    task: (noteId: string) => Promise<T>): Promise<T[]> {
    if (noteIds.length === 0) {
      return []
    }
    const results: Array<T | null> = new Array(noteIds.length).fill(null)
    let nextIndex: number = 0
    const workerCount = Math.min(concurrency, noteIds.length)
    const workers: Promise<void>[] = []
    for (let workerIndex = 0; workerIndex < workerCount; workerIndex += 1) {
      workers.push((async () => {
        while (nextIndex < noteIds.length) {
          const currentIndex = nextIndex
          nextIndex += 1
          results[currentIndex] = await task(noteIds[currentIndex])
        }
      })())
    }
    await Promise.all(workers)
    const out: T[] = []
    for (const item of results) {
      if (item !== null) {
        out.push(item as T)
      }
    }
    return out
  }

  /** 固定并发上限的池化执行（用于笔记内多图等小文件批量 WebDAV）。 */
  private async runPoolLimited<I>(items: I[], concurrency: number, worker: (item: I) => Promise<void>): Promise<void> {
    if (items.length === 0) {
      return
    }
    let nextIndex: number = 0
    const workerCount = Math.min(concurrency, items.length)
    const workers: Promise<void>[] = []
    for (let workerIndex = 0; workerIndex < workerCount; workerIndex += 1) {
      workers.push((async () => {
        while (nextIndex < items.length) {
          const currentIndex = nextIndex
          nextIndex += 1
          await worker(items[currentIndex])
        }
      })())
    }
    await Promise.all(workers)
  }

  private async runSyncBatch(noteIds: string[], localNoteMap: Map<string, Note>, concurrency: number,
    permanentDeletedIds: Set<string>, reuseRemoteIndexSnapshot?: RemoteIndexSnapshot): Promise<SyncResult[]> {
    if (noteIds.length === 0) {
      return []
    }
    const results: Array<SyncResult | null> = new Array(noteIds.length).fill(null)
    let nextIndex: number = 0
    const workerCount = Math.min(concurrency, noteIds.length)
    const workers: Promise<void>[] = []
    for (let workerIndex = 0; workerIndex < workerCount; workerIndex += 1) {
      workers.push((async () => {
        while (nextIndex < noteIds.length) {
          const currentIndex = nextIndex
          nextIndex += 1
          results[currentIndex] =
            await this.syncNoteByIdWithRetry(noteIds[currentIndex], localNoteMap, permanentDeletedIds,
              reuseRemoteIndexSnapshot)
        }
      })())
    }
    await Promise.all(workers)
    const completedResults: SyncResult[] = []
    for (const result of results) {
      if (result !== null) {
        completedResults.push(result as SyncResult)
      }
    }
    return completedResults
  }

  private resolveFullSyncConcurrency(totalNoteCount: number): number {
    if (totalNoteCount >= LARGE_SYNC_NOTE_COUNT) {
      return LOW_SYNC_CONCURRENCY
    }
    if (totalNoteCount >= MEDIUM_SYNC_NOTE_COUNT) {
      return MEDIUM_SYNC_CONCURRENCY
    }
    return FULL_SYNC_CONCURRENCY
  }

  private canSkipByRemoteIndex(noteId: string, localNoteMap: Map<string, Note>,
    indexedEntry?: RemoteIndexEntry): boolean {
    if (!indexedEntry) {
      return false
    }
    const localNote = localNoteMap.get(noteId)
    if (!localNote) {
      return false
    }
    if (indexedEntry.remoteModified <= 0) {
      return false
    }
    if (indexedEntry.deletedTime !== localNote.deletedTime) {
      return false
    }
    if (indexedEntry.contentLength > 0 && indexedEntry.contentLength !== localNote.content.length) {
      return false
    }
    return TimeUtils.compareWithTolerance(localNote.lastOperationAt, indexedEntry.remoteModified) === 0
  }

  /** 索引缺少可靠 `remoteModified` 时，用 HEAD 与本地比对（与 Flutter `_canSkipByHeadFallback` 对齐）。 */
  private async canSkipByHeadFallback(noteId: string, note: Note,
    indexedEntry?: RemoteIndexEntry): Promise<boolean> {
    // 索引无该 id 时不走 HEAD 短路（首次同步）：避免串行 N 次 HEAD。
    if (indexedEntry === undefined) {
      return false
    }
    if (indexedEntry.remoteModified > 0) {
      return false
    }
    const remoteStat = await this.safeRemoteStat(noteId)
    if (!remoteStat.exists || remoteStat.remoteModified <= 0) {
      return false
    }
    if (remoteStat.contentLength > 0 && remoteStat.contentLength !== note.content.length) {
      return false
    }
    return TimeUtils.compareWithTolerance(note.lastOperationAt, remoteStat.remoteModified) === 0
  }

  private async runSyncBatchWithDeferredNotifications(noteIds: string[], localNoteMap: Map<string, Note>,
    concurrency: number, permanentDeletedIds: Set<string>,
    reuseRemoteIndexSnapshot?: RemoteIndexSnapshot): Promise<SyncResult[]> {
    NoteRepository.getInstance().beginBulkNotification()
    try {
      return await this.runSyncBatch(noteIds, localNoteMap, concurrency, permanentDeletedIds,
        reuseRemoteIndexSnapshot)
    } finally {
      NoteRepository.getInstance().endBulkNotification()
    }
  }

  private async syncNoteById(noteId: string, localNoteMap: Map<string, Note>,
    permanentDeletedIds: Set<string>, reuseRemoteIndexSnapshot?: RemoteIndexSnapshot): Promise<SyncResult | null> {
    if (permanentDeletedIds.has(noteId)) {
      return await this.applyPermanentDeleteListedInIndex(noteId)
    }
    const syncState = await DatabaseService.getInstance().getSyncState(noteId)
    if (!localNoteMap.has(noteId) && !syncState?.deleted) {
      return await this.syncRemoteOnlyNote(noteId)
    }
    return await this.syncNote(noteId, reuseRemoteIndexSnapshot)
  }

  private async syncNoteByIdWithRetry(noteId: string, localNoteMap: Map<string, Note>,
    permanentDeletedIds: Set<string>, reuseRemoteIndexSnapshot?: RemoteIndexSnapshot): Promise<SyncResult | null> {
    let latestResult: SyncResult | null = null
    for (let attempt = 1; attempt <= MAX_RETRYABLE_SYNC_ATTEMPTS; attempt += 1) {
      try {
        latestResult = await this.syncNoteById(noteId, localNoteMap, permanentDeletedIds,
          reuseRemoteIndexSnapshot)
        if (!latestResult || latestResult.success || !this.isRetryableSyncMessage(latestResult.message)
          || attempt >= MAX_RETRYABLE_SYNC_ATTEMPTS) {
          return latestResult
        }
        Logger.warn('SyncService',
          `syncNoteByIdWithRetry retry by failed result: noteId=${noteId}, attempt=${attempt}, message=${latestResult.message}`)
      } catch (error) {
        const rawError = this.describeError(error as Object)
        const errorMessage = UserFacingMessage.forCatch(error as Object, '同步失败，请稍后重试')
        if (!this.isRetryableSyncMessage(rawError) || attempt >= MAX_RETRYABLE_SYNC_ATTEMPTS) {
          Logger.error('SyncService',
            `syncNoteByIdWithRetry failed: noteId=${noteId}, attempt=${attempt}, error=${rawError}`)
          return {
            noteId,
            success: false,
            action: 'skip',
            message: errorMessage,
            remoteModified: 0
          }
        }
        Logger.warn('SyncService',
          `syncNoteByIdWithRetry retry by exception: noteId=${noteId}, attempt=${attempt}, error=${rawError}`)
      }
      await this.delay(RETRY_DELAY_MS * attempt)
    }
    return latestResult
  }

  private async syncRemoteOnlyNote(noteId: string): Promise<SyncResult | null> {
    const remoteStat = await this.safeRemoteStat(noteId)
    if (!remoteStat.exists) {
      return null
    }
    const remoteContent = await WebDAVClient.getInstance().downloadNote(noteId)
    const remotePermanent =
      await this.applyRemotePermanentDeleteIfNeeded(noteId, remoteContent, remoteStat.remoteModified)
    if (remotePermanent !== null) {
      return remotePermanent
    }
    await NoteRepository.getInstance().overwriteFromRemote(noteId, remoteContent, remoteStat.remoteModified)
    await this.downloadFlowchartSidecarIfRemote(noteId)
    await this.downloadImagesForNote(noteId, remoteContent)
    await this.downloadAudioForNote(noteId, remoteContent)
    return {
      noteId,
      success: true,
      action: 'download',
      message: '远端笔记已回灌到本地',
      remoteModified: remoteStat.remoteModified
    }
  }

  /**
   * `.qingyu-index.json` 中 `permanentlyDeletedNoteIds` 包含该 id 时：删除远端对象并清空本地（与正文 deleted_time 无关）。
   */
  private async applyPermanentDeleteListedInIndex(noteId: string): Promise<SyncResult> {
    let content = ''
    try {
      content = await FileService.getInstance().readNoteFile(noteId)
    } catch (_) {
      content = ''
    }
    if (content.length === 0) {
      try {
        const remoteStat = await this.safeRemoteStat(noteId)
        if (remoteStat.exists) {
          content = await WebDAVClient.getInstance().downloadNote(noteId)
        }
      } catch (_) {
        content = ''
      }
    }
    try {
      await WebDAVClient.getInstance().deleteNote(noteId)
    } catch (error) {
      Logger.warn('SyncService',
        `applyPermanentDeleteListedInIndex deleteNote failed: noteId=${noteId}, ${this.describeError(error as Object)}`)
    }
    try {
      await WebDAVClient.getInstance().deleteFlowchart(noteId)
    } catch (error) {
      Logger.warn('SyncService',
        `applyPermanentDeleteListedInIndex deleteFlowchart failed: noteId=${noteId}, ${this.describeError(error as Object)}`)
    }
    await this.deleteImagesForNote(content, noteId)
    const audioId = NoteStateCodec.parseNoteFile(content, noteId).state.audioId
    await this.deleteAudioForNote(audioId)
    await NoteRepository.getInstance().purgeLocalNoteCompletely(noteId)
    return {
      noteId,
      success: true,
      action: 'delete',
      message: '索引标记彻底删除，已移除本地与远端副本',
      remoteModified: 0
    }
  }

  /** 远端文件中 `deleted_time` 为 2 时表示彻底删除：删除 WebDAV 对象并清空本地。 */
  private async applyRemotePermanentDeleteIfNeeded(noteId: string, remoteContent: string,
    remoteModified: number): Promise<SyncResult | null> {
    const fallbackTs = remoteModified > 0 ? remoteModified : Date.now()
    const payload = NoteStateCodec.parseNoteFile(remoteContent, noteId, fallbackTs)
    if (payload.state.deletedTime !== 2) {
      return null
    }
    Logger.info('SyncService', `applyRemotePermanentDeleteIfNeeded: remote deleted_time=2, noteId=${noteId}`)
    await WebDAVClient.getInstance().deleteNote(noteId)
    try {
      await WebDAVClient.getInstance().deleteFlowchart(noteId)
    } catch (error) {
      Logger.warn('SyncService',
        `applyRemotePermanentDeleteIfNeeded deleteFlowchart failed: noteId=${noteId}, ${this.describeError(error as Object)}`)
    }
    await this.deleteImagesForNote(remoteContent, noteId)
    await this.deleteAudioForNote(payload.state.audioId)
    await NoteRepository.getInstance().purgeLocalNoteCompletely(noteId)
    return {
      noteId,
      success: true,
      action: 'delete',
      message: '远端标记彻底删除，已移除本地与远端副本',
      remoteModified: 0
    }
  }

  private describeError(error: Object): string {
    const detail = error as ErrorLike
    const raw = JSON.stringify(error)
    const fallbackRaw = raw.length > 0 && raw !== '{}' ? raw : `${error}`
    return `code=${detail.code ?? 'n/a'}, name=${detail.name ?? 'n/a'}, message=${detail.message ?? 'n/a'}, raw=${fallbackRaw}`
  }

  private isRetryableSyncMessage(message: string): boolean {
    const normalized = message.toLowerCase()
    if (normalized.includes('authentication') || normalized.includes('not configured')) {
      return false
    }
    return normalized.includes('timeout')
      || normalized.includes('timed out')
      || normalized.includes('network')
      || normalized.includes('socket')
      || normalized.includes('connect')
      || normalized.includes('503')
      || normalized.includes('502')
      || normalized.includes('504')
      || normalized.includes('429')
      || normalized.includes('econn')
      || normalized.includes('reset')
  }

  private async delay(ms: number): Promise<void> {
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), ms)
    })
  }

  private async syncImagesForNote(note: Note, content: string): Promise<void> {
    const imageRefs = note.imageRefs.length > 0
      ? note.imageRefs
      : NoteStateCodec.extractImageRefs(content)
    if (imageRefs.length === 0) {
      return
    }
    const ctx = AppContextHolder.getContext()
    if (!ctx) {
      return
    }
    const baseDir = ctx.filesDir
    const workItems: ImageRefWorkItem[] = []
    for (const ref of imageRefs) {
      const fileName = ref.split('/').pop() ?? ''
      if (fileName.length === 0) {
        continue
      }
      const localPath = `${baseDir}/qingyu-note-image/${fileName}`
      if (!FileService.fileExists(localPath)) {
        continue
      }
      workItems.push({ ref, fileName, localPath })
    }
    if (workItems.length === 0) {
      return
    }
    await this.runPoolLimited(workItems, IMAGE_WEBDAV_CONCURRENCY, async (item: ImageRefWorkItem) => {
      try {
        const bytes = FileService.readFileAsArrayBuffer(item.localPath)
        await WebDAVClient.getInstance().uploadImage(item.fileName, bytes)
      } catch (error) {
        Logger.warn('SyncService', `syncImagesForNote failed for ${item.ref}: ${this.describeError(error as Object)}`)
      }
    })
  }

  private async syncAudioForNote(note: Note): Promise<void> {
    const audioId = note.audioId.trim()
    if (audioId.length === 0) {
      return
    }
    const ctx = AppContextHolder.getContext()
    if (!ctx) {
      return
    }
    try {
      const localPath = `${ctx.filesDir}/audio/${audioId}`
      if (!FileService.fileExists(localPath)) {
        return
      }
      const bytes = FileService.readFileAsArrayBuffer(localPath)
      await WebDAVClient.getInstance().uploadAudio(audioId, bytes)
    } catch (error) {
      Logger.warn('SyncService', `syncAudioForNote failed for ${note.audioId}: ${this.describeError(error as Object)}`)
    }
  }

  private async downloadAudioForNote(noteId: string, content: string): Promise<void> {
    const parsed = NoteStateCodec.parseNoteFile(content, noteId)
    const audioId = parsed.state.audioId.trim()
    if (audioId.length === 0) {
      return
    }
    const ctx = AppContextHolder.getContext()
    if (!ctx) {
      return
    }
    const localPath = `${ctx.filesDir}/audio/${audioId}`
    if (FileService.fileExists(localPath)) {
      return
    }
    try {
      const bytes = await WebDAVClient.getInstance().downloadAudio(audioId)
      FileService.writeFile(localPath, bytes)
    } catch (error) {
      Logger.warn('SyncService', `downloadAudioForNote failed for ${audioId}: ${this.describeError(error as Object)}`)
    }
  }

  private async downloadImagesForNote(noteId: string, content: string): Promise<void> {
    const parsed = NoteStateCodec.parseNoteFile(content, noteId)
    const imageRefs = parsed.state.imageRefs.length > 0
      ? parsed.state.imageRefs
      : NoteStateCodec.extractImageRefs(parsed.content)
    if (imageRefs.length === 0) {
      return
    }
    const ctx = AppContextHolder.getContext()
    if (!ctx) {
      return
    }
    const baseDir = ctx.filesDir
    const workItems: ImageRefWorkItem[] = []
    for (const ref of imageRefs) {
      const fileName = ref.split('/').pop() ?? ''
      if (fileName.length === 0) {
        continue
      }
      const localPath = `${baseDir}/qingyu-note-image/${fileName}`
      if (FileService.fileExists(localPath)) {
        continue
      }
      workItems.push({ ref, fileName, localPath })
    }
    if (workItems.length === 0) {
      return
    }
    let downloadedAny = false
    await this.runPoolLimited(workItems, IMAGE_WEBDAV_CONCURRENCY, async (item: ImageRefWorkItem) => {
      try {
        const bytes = await WebDAVClient.getInstance().downloadImage(item.fileName)
        FileService.writeFile(item.localPath, bytes)
        downloadedAny = true
        this.emitNoteImagesChanged(noteId)
      } catch (error) {
        Logger.warn('SyncService',
          `downloadImagesForNote failed for ${item.ref}: ${this.describeError(error as Object)}`)
      }
    })
    if (downloadedAny) {
      this.emitNoteImagesChanged(noteId)
    }
  }

  private emitNoteImagesChanged(noteId: string): void {
    if (noteId.length === 0) {
      return
    }
    const hub = AppContextHolder.tryGetContext()?.eventHub
    hub?.emit(SyncConstants.noteImagesChangedEvent, new NoteImagesChangedEventPayload(noteId))
  }

  private async deleteImagesForNote(content: string, fallbackNoteId: string = ''): Promise<void> {
    const imageRefs = NoteStateCodec.collectImageRefsForDeletion(content, fallbackNoteId)
    if (imageRefs.length === 0) {
      return
    }
    const ctx = AppContextHolder.getContext()
    if (!ctx) {
      return
    }
    const baseDir = ctx.filesDir
    const workItems: ImageRefWorkItem[] = []
    for (const ref of imageRefs) {
      const fileName = ref.split('/').pop() ?? ''
      if (fileName.length === 0) {
        continue
      }
      const localPath = `${baseDir}/qingyu-note-image/${fileName}`
      workItems.push({ ref, fileName, localPath })
    }
    if (workItems.length === 0) {
      return
    }
    await this.runPoolLimited(workItems, IMAGE_WEBDAV_CONCURRENCY, async (item: ImageRefWorkItem) => {
      try {
        if (FileService.fileExists(item.localPath)) {
          FileService.deleteFile(item.localPath)
        }
        await WebDAVClient.getInstance().deleteImage(item.fileName)
      } catch (error) {
        Logger.warn('SyncService', `deleteImagesForNote failed for ${item.ref}: ${this.describeError(error as Object)}`)
      }
    })
  }

  private async deleteAudioForNote(audioId: string): Promise<void> {
    const trimmed = audioId.trim()
    if (trimmed.length === 0) {
      return
    }
    const ctx = AppContextHolder.getContext()
    if (!ctx) {
      return
    }
    try {
      const localPath = `${ctx.filesDir}/audio/${trimmed}`
      if (FileService.fileExists(localPath)) {
        FileService.deleteFile(localPath)
      }
      await WebDAVClient.getInstance().deleteAudio(trimmed)
    } catch (error) {
      Logger.warn('SyncService', `deleteAudioForNote failed for ${trimmed}: ${this.describeError(error as Object)}`)
    }
  }
}
