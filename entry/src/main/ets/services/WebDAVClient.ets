import http from '@ohos.net.http'
import { util } from '@kit.ArkTS'
import type { Note, RemoteNoteStat, WebDAVConfig, WebDAVProvider } from '../common/model/Note'
import type {
  QingyuCloudStatusActive,
  QingyuCloudStatusExpired,
  QingyuCloudStatusFetchFailed,
  QingyuCloudStatusLifetime,
  QingyuCloudStatusMalformed,
  QingyuCloudStatusNeedNoteApiSession,
  QingyuCloudStatusNotConfigured,
  QingyuCloudStatusNotPurchased,
  QingyuCloudStatusNotQingyu,
  QingyuCloudSubscriptionStatus
} from '../common/model/QingyuCloudSubscription'
import { NoteApiClient, type SubscriptionBody } from './NoteApiClient'
import { PreferencesService } from './PreferencesService'
import { CryptoService } from './CryptoService'
import { PathUtils } from '../common/utils/PathUtils'
import { TimeUtils } from '../common/utils/TimeUtils'
import { Logger } from '../common/utils/Logger'
import { SyncConstants } from '../common/constants/SyncConstants'
import { NoteSettingsDocument } from '../common/model/NoteSettingsDocument'
interface HeaderOverrides {
  contentType?: string
  modifiedAt?: string
  depth?: string
  rawData?: ArrayBuffer
  expectArrayBuffer?: boolean
}

interface RequestHeaders {
  Authorization: string
  Accept: string
  Contentx2dType?: string
  Xx2dQingyux2dModified?: string
  Depth?: string
}

interface ErrorLike {
  code?: number | string
  message?: string
  name?: string
}

export interface RemoteIndexEntry {
  remoteModified: number
  deletedTime: number
  contentLength: number
}

interface RemoteIndexPayloadV2 {
  version: number
  updatedAt: number
  /** 写入时为 id → 索引条目；解析时另支持对方写入的 `noteIds` 字符串数组。 */
  noteIds: Record<string, RemoteIndexEntry>
}

/** 上传 `.qingyu-index.json` 时的 JSON 结构（满足 arkts-no-untyped-obj-literals）。 */
interface RemoteIndexWritePayload {
  version: number
  updatedAt: number
  noteIds: Record<string, RemoteIndexEntry>
  permanentlyDeletedNoteIds: string[]
}

/** 单次 GET `.qingyu-index.json` 解析结果（笔记条目 + 彻底删除 id 列表）。 */
export interface RemoteIndexSnapshot {
  noteEntries: Map<string, RemoteIndexEntry>
  permanentlyDeletedNoteIds: Set<string>
  /** 索引文件中的毫秒时间戳（与 Flutter `RemoteIndexSnapshot.updatedAt` 对齐）。 */
  updatedAt: number
}

export class WebDAVClient {
  private static instance: WebDAVClient = new WebDAVClient()
  private deferRemoteIndexMergeDepth: number = 0

  /** 全量同步批次内调用：跳过每条上传后的索引读写，结束时配合 [flushRemoteIndexFromLocalNotes]。 */
  beginDeferRemoteIndexMerge(): void {
    this.deferRemoteIndexMergeDepth += 1
  }

  endDeferRemoteIndexMerge(): void {
    if (this.deferRemoteIndexMergeDepth > 0) {
      this.deferRemoteIndexMergeDepth -= 1
    }
  }

  private isDeferRemoteIndexMerge(): boolean {
    return this.deferRemoteIndexMergeDepth > 0
  }

  /** 与 Flutter `WebDavClient.canonicalRemoteIndexFingerprint` 算法一致（跨端可比）。 */
  static canonicalRemoteIndexFingerprint(snapshot: RemoteIndexSnapshot): string {
    const parts: string[] = []
    parts.push(`${snapshot.updatedAt}`)
    const perm = Array.from(snapshot.permanentlyDeletedNoteIds).filter((id: string) => id.length > 0).sort()
    parts.push(perm.join(','))
    const ids = Array.from(snapshot.noteEntries.keys()).filter((id: string) => id.length > 0).sort()
    for (let i = 0; i < ids.length; i += 1) {
      const id = ids[i]
      const e = snapshot.noteEntries.get(id)!
      parts.push(`${id}:${e.remoteModified}:${e.deletedTime}:${e.contentLength}`)
    }
    return parts.join('|')
  }

  /** 与 Flutter `WebDavClient._remoteIndexFileName` 一致。 */
  private static readonly _remoteIndexFileName: string = '.qingyu-index.json'
  /** 与 Flutter `WebDavClient.imageDirName` 一致。 */
  static readonly imageDirName: string = 'qingyu-note-image'
  /** 与 Flutter `WebDavClient._propfindRequestBody` 一致。 */
  private static readonly _propfindRequestBody: string =
    '<?xml version="1.0" encoding="utf-8"?>' +
    '<d:propfind xmlns:d="DAV:"><d:allprop/></d:propfind>'
  private readonly base64: util.Base64Helper = new util.Base64Helper()
  private cachedAuthSignature: string = ''
  private cachedAuthorizationHeader: string = ''

  static getInstance(): WebDAVClient {
    return WebDAVClient.instance
  }

  async testConnection(): Promise<boolean> {
    Logger.info('WebDAVClient', 'testConnection start')
    const config = await this.loadConfig()
    if (!config) {
      Logger.warn('WebDAVClient', 'testConnection aborted: config is null')
      return false
    }
    if (this.isQingyuProvider(config.provider)) {
      this.logResolvedDirectoryPaths(config, 'testConnection')
    }
    const targetUrl = PathUtils.joinRemoteDirectoryUrl(config.baseUrl, config.notesDir)
    Logger.info('WebDAVClient',
      `testConnection config loaded: enabled=${config.enabled}, url=${this.sanitizeUrl(targetUrl)}, usernameLength=${config.username.length}, notesDir=${PathUtils.normalizeNotesDir(config.notesDir)}`)
    if (!config.enabled) {
      Logger.warn('WebDAVClient', 'testConnection aborted: config is disabled')
      return false
    }
    let phase = 'before-send-request'
    try {
      phase = 'send-head-request'
      const response = await this.sendRequest(targetUrl, http.RequestMethod.HEAD)
      const ok = this.isReachableDirectoryResponse(response.responseCode)
      Logger.info('WebDAVClient',
        `testConnection HEAD result: responseCode=${response.responseCode}, reachable=${ok}`)
      if (!ok && this.isQingyuProvider(config.provider)) {
        await this.logDirectoryHeadFailureDiagnostics(targetUrl, response.responseCode, 'testConnection-notes-root')
      }
      return ok
    } catch (error) {
      if (this.isCredentialDecryptFailure(error)) {
        Logger.warn('WebDAVClient', `testConnection failed before request dispatch: phase=${phase}, ${this.describeError(error)}`)
        throw this.toRuntimeError(error)
      }
      Logger.warn('WebDAVClient', `testConnection failed: phase=${phase}, ${this.describeError(error)}`)
      return false
    }
  }

  /**
   * 轻羽云订阅：从 Note API 拉取（不再读取 WebDAV 上 `.qingyu-cloud.json`）。
   * @param configOverride 若传入（如云同步设置页预览），则不再按已保存的 sync_provider 解析配置。
   */
  async fetchQingyuCloudSubscriptionStatus(configOverride?: WebDAVConfig | null): Promise<QingyuCloudSubscriptionStatus> {
    if (configOverride !== undefined && configOverride !== null) {
      if (!configOverride.enabled) {
        const s: QingyuCloudStatusNotConfigured = { kind: 'not_configured' }
        return s
      }
      if (!this.isQingyuProvider(configOverride.provider)) {
        const s: QingyuCloudStatusNotQingyu = { kind: 'not_qingyu' }
        return s
      }
    } else {
      const intent = await PreferencesService.getInstance().getQingyuCloudSyncIntent()
      if (intent === 'not_qingyu') {
        const s: QingyuCloudStatusNotQingyu = { kind: 'not_qingyu' }
        return s
      }
      if (intent === 'disabled') {
        const s: QingyuCloudStatusNotConfigured = { kind: 'not_configured' }
        return s
      }
    }
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      const need: QingyuCloudStatusNeedNoteApiSession = { kind: 'need_note_api_session' }
      return need
    }
    let body: SubscriptionBody | null = null
    for (let attempt = 0; attempt < 3; attempt += 1) {
      if (attempt > 0) {
        await new Promise<void>((resolve) => setTimeout(resolve, 400))
      }
      body = await NoteApiClient.getInstance().fetchSubscription()
      if (body !== null) {
        break
      }
    }
    if (body === null) {
      const failed: QingyuCloudStatusFetchFailed = { kind: 'fetch_failed' }
      return failed
    }
    return WebDAVClient.mapNoteSubscriptionBody(body)
  }

  private static mapNoteSubscriptionBody(body: SubscriptionBody): QingyuCloudSubscriptionStatus {
    const state = body.state?.trim() ?? ''
    if (state === 'lifetime' || body.is_lifetime === true) {
      const s: QingyuCloudStatusLifetime = { kind: 'lifetime' }
      return s
    }
    if (state === 'none') {
      const s: QingyuCloudStatusNotPurchased = { kind: 'not_purchased' }
      return s
    }
    const ymd = body.expires_at?.trim() ?? ''
    if (state === 'expired') {
      if (ymd.length === 0) {
        const s: QingyuCloudStatusMalformed = { kind: 'malformed' }
        return s
      }
      const s: QingyuCloudStatusExpired = { kind: 'expired', expiresDisplayYmd: ymd }
      return s
    }
    if (state === 'active') {
      if (ymd.length === 0) {
        const s: QingyuCloudStatusMalformed = { kind: 'malformed' }
        return s
      }
      const s: QingyuCloudStatusActive = { kind: 'active', expiresDisplayYmd: ymd }
      return s
    }
    const s: QingyuCloudStatusMalformed = { kind: 'malformed' }
    return s
  }

  async ensureNotesDirectory(): Promise<void> {
    const config = await this.requireConfig()
    if (this.isQingyuProvider(config.provider)) {
      Logger.info('WebDAVClient', 'ensureNotesDirectory: qingyu_cloud (create tree + metadata merge)')
      await this.ensureQingyuNotesTreeAndMetadata(config)
      return
    }
    const targetUrl = PathUtils.joinRemoteDirectoryUrl(config.baseUrl, config.notesDir)
    Logger.info('WebDAVClient', `ensureNotesDirectory start: url=${this.sanitizeUrl(targetUrl)}`)
    try {
      const response = await this.sendRequest(targetUrl, http.RequestMethod.HEAD)
      Logger.info('WebDAVClient',
        `ensureNotesDirectory response: url=${this.sanitizeUrl(targetUrl)}, responseCode=${response.responseCode}`)
      if (!this.isReachableDirectoryResponse(response.responseCode)) {
        await this.createDirectoryPath(config.baseUrl, config.notesDir)
      }
    } catch (error) {
      Logger.warn('WebDAVClient', `Remote notes directory HEAD failed: ${this.describeError(error as Object)}`)
      await this.createDirectoryPath(config.baseUrl, config.notesDir)
    }
    await this.ensureImageDirectory(config)
  }

  private async ensureQingyuNotesTreeAndMetadata(config: WebDAVConfig): Promise<void> {
    this.logResolvedDirectoryPaths(config, 'ensureQingyuNotesTreeAndMetadata')
    const targetUrl = PathUtils.joinRemoteDirectoryUrl(config.baseUrl, config.notesDir)
    try {
      const response = await this.sendRequest(targetUrl, http.RequestMethod.HEAD)
      if (this.isReachableDirectoryResponse(response.responseCode)) {
        await this.ensureImageDirectory(config)
        return
      }
    } catch (error) {
      Logger.warn('WebDAVClient',
        `ensureQingyuNotesTreeAndMetadata HEAD failed: ${this.describeError(error as Object)}`)
    }
    await this.createDirectoryPath(config.baseUrl, config.notesDir)
    await this.ensureImageDirectory(config)
  }

  private isQingyuProvider(provider: WebDAVProvider): boolean {
    return provider === 'qingyu_cloud'
  }

  /** 轻羽云排查：打印规范化路径与最终请求的目录 URL（应与浏览器/WebDAV 根下文件夹一致）。 */
  private logResolvedDirectoryPaths(config: WebDAVConfig, label: string): void {
    const normBase = PathUtils.normalizeBaseUrl(config.baseUrl)
    const normNotes = PathUtils.normalizeNotesDir(config.notesDir)
    const joined = PathUtils.joinRemoteDirectoryUrl(config.baseUrl, config.notesDir)
    Logger.info('WebDAVClient',
      `${label}: provider=${config.provider}, baseUrl(raw)=${config.baseUrl}, baseUrl(norm)=${normBase}, notesDir(raw)=${config.notesDir}, notesDir(norm)=${normNotes}, directoryUrl=${this.sanitizeUrl(joined)}`)
  }

  /**
   * HEAD 对集合目录常返回 404/501，但 PROPFIND 仍成功；失败时记录 PROPFIND 以便区分「路径错误」与「HEAD 不支持」。
   */
  private async logDirectoryHeadFailureDiagnostics(url: string, headCode: number, label: string): Promise<void> {
    Logger.warn('WebDAVClient',
      `qingyu ${label}: HEAD not treated as reachable (code=${headCode}); acceptableReachabilityCodes=200-399 or 405. Diagnostic PROPFIND depth=0 same URL.`)
    try {
      const response = await this.sendRequest(url, 'PROPFIND', WebDAVClient._propfindRequestBody, {
        contentType: 'application/xml; charset=utf-8',
        depth: '0'
      })
      Logger.warn('WebDAVClient',
        `qingyu ${label}: diagnostic PROPFIND depth=0 responseCode=${response.responseCode} (if 2xx/405 here but HEAD failed, server may not support HEAD on collections)`)
    } catch (error) {
      Logger.warn('WebDAVClient',
        `qingyu ${label}: diagnostic PROPFIND failed: ${this.describeError(error as Object)}`)
    }
  }

  private async ensureImageDirectory(config: WebDAVConfig): Promise<void> {
    const directoryUrl = PathUtils.joinRemoteDirectoryUrl(config.baseUrl, config.notesDir)
    const imageUrl = `${directoryUrl}${WebDAVClient.imageDirName}/`
    Logger.info('WebDAVClient', `ensureImageDirectory start: url=${this.sanitizeUrl(imageUrl)}`)
    try {
      const response = await this.sendRequest(imageUrl, http.RequestMethod.HEAD)
      Logger.info('WebDAVClient',
        `ensureImageDirectory HEAD response: url=${this.sanitizeUrl(imageUrl)}, responseCode=${response.responseCode}`)
      if (this.isReachableDirectoryResponse(response.responseCode)) {
        return
      }
    } catch (error) {
      Logger.warn('WebDAVClient', `ensureImageDirectory HEAD failed: ${this.describeError(error as Object)}`)
    }
    try {
      const response = await this.sendRequest(imageUrl, 'MKCOL')
      Logger.info('WebDAVClient',
        `ensureImageDirectory MKCOL response: url=${this.sanitizeUrl(imageUrl)}, responseCode=${response.responseCode}`)
    } catch (error) {
      Logger.warn('WebDAVClient',
        `ensureImageDirectory MKCOL failed: url=${this.sanitizeUrl(imageUrl)}, ${this.describeError(error as Object)}`)
    }
  }

  private async createDirectoryPath(baseUrl: string, notesDir: string): Promise<void> {
    const cleanBase = PathUtils.normalizeBaseUrl(baseUrl)
    const normalized = PathUtils.normalizeNotesDir(notesDir)
    const segments = normalized.split('/').filter((s: string) => s.length > 0)
    let currentPath = cleanBase
    for (const segment of segments) {
      currentPath = `${currentPath}/${segment}`
      Logger.info('WebDAVClient', `createDirectoryPath MKCOL: url=${this.sanitizeUrl(currentPath)}`)
      try {
        const response = await this.sendRequest(currentPath, 'MKCOL')
        Logger.info('WebDAVClient',
          `createDirectoryPath MKCOL response: url=${this.sanitizeUrl(currentPath)}, responseCode=${response.responseCode}`)
      } catch (error) {
        Logger.warn('WebDAVClient',
          `createDirectoryPath MKCOL failed: url=${this.sanitizeUrl(currentPath)}, ${this.describeError(error as Object)}`)
      }
    }
  }

  async getRemoteStat(noteId: string): Promise<RemoteNoteStat> {
    const targetUrl = await this.noteUrl(noteId)
    Logger.info('WebDAVClient', `getRemoteStat start: noteId=${noteId}, url=${this.sanitizeUrl(targetUrl)}`)
    const response = await this.sendRequest(targetUrl, http.RequestMethod.HEAD)
    Logger.info('WebDAVClient',
      `getRemoteStat response: noteId=${noteId}, responseCode=${response.responseCode}`)
    if (response.responseCode === 401 || response.responseCode === 403) {
      throw new Error('WebDAV authentication failed')
    }
    if (response.responseCode === 404) {
      return {
        exists: false,
        remoteModified: 0,
        eTag: '',
        contentLength: 0
      }
    }
    const lastModified = this.pickHeader(response.header, 'last-modified')
    Logger.info('WebDAVClient',
      `getRemoteStat success: noteId=${noteId}, exists=${response.responseCode >= 200 && response.responseCode < 300}, lastModified=${lastModified}`)
    return {
      exists: response.responseCode >= 200 && response.responseCode < 300,
      remoteModified: TimeUtils.normalizeRemoteTimestamp(TimeUtils.fromHttpDate(lastModified)),
      eTag: this.pickHeader(response.header, 'etag'),
      contentLength: Number(this.pickHeader(response.header, 'content-length') ?? '0')
    }
  }

  async downloadNote(noteId: string): Promise<string> {
    const targetUrl = await this.noteUrl(noteId)
    Logger.info('WebDAVClient', `downloadNote start: noteId=${noteId}, url=${this.sanitizeUrl(targetUrl)}`)
    const response = await this.sendRequest(targetUrl, http.RequestMethod.GET)
    Logger.info('WebDAVClient', `downloadNote response: noteId=${noteId}, responseCode=${response.responseCode}`)
    if (response.responseCode >= 400) {
      throw new Error(`Download failed with status ${response.responseCode}`)
    }
    if (typeof response.result === 'string') {
      return response.result
    }
    return JSON.stringify(response.result)
  }

  async uploadNote(noteId: string, content: string, lastModified: number,
    indexHint?: Partial<RemoteIndexEntry>): Promise<RemoteNoteStat> {
    const uploadHeaders: HeaderOverrides = {
      contentType: 'text/markdown; charset=utf-8',
      modifiedAt: `${lastModified}`
    }
    const targetUrl = await this.noteUrl(noteId)
    Logger.info('WebDAVClient',
      `uploadNote start: noteId=${noteId}, url=${this.sanitizeUrl(targetUrl)}, contentLength=${content.length}, lastModified=${lastModified}`)
    const response = await this.sendRequest(targetUrl, http.RequestMethod.PUT, content, uploadHeaders)
    Logger.info('WebDAVClient', `uploadNote response: noteId=${noteId}, responseCode=${response.responseCode}`)
    if (response.responseCode >= 400) {
      throw new Error(`Upload failed with status ${response.responseCode}`)
    }
    const remoteModified = TimeUtils.normalizeRemoteTimestamp(
      TimeUtils.fromHttpDate(this.pickHeader(response.header, 'last-modified')) || lastModified
    )
    if (!this.isDeferRemoteIndexMerge()) {
      await this.addNoteToRemoteIndex(noteId, {
        remoteModified,
        deletedTime: indexHint?.deletedTime ?? 0,
        contentLength: indexHint?.contentLength ?? content.length
      })
    }
    Logger.info('WebDAVClient',
      `uploadNote success: noteId=${noteId}, lastModifiedHeader=${this.pickHeader(response.header, 'last-modified')}`)
    return {
      exists: response.responseCode >= 200 && response.responseCode < 300,
      remoteModified,
      eTag: this.pickHeader(response.header, 'etag'),
      contentLength: content.length
    }
  }

  async deleteNote(noteId: string): Promise<void> {
    const targetUrl = await this.noteUrl(noteId)
    Logger.info('WebDAVClient', `deleteNote start: noteId=${noteId}, url=${this.sanitizeUrl(targetUrl)}`)
    const response = await this.sendRequest(targetUrl, http.RequestMethod.DELETE)
    Logger.info('WebDAVClient', `deleteNote response: noteId=${noteId}, responseCode=${response.responseCode}`)
    if (response.responseCode >= 400 && response.responseCode !== 404) {
      throw new Error(`Delete failed with status ${response.responseCode}`)
    }
    if (!this.isDeferRemoteIndexMerge()) {
      await this.removeNoteFromRemoteIndex(noteId)
    }
  }

  async uploadImage(fileName: string, bytes: ArrayBuffer): Promise<void> {
    const config = await this.requireConfig()
    const directoryUrl = PathUtils.joinRemoteDirectoryUrl(config.baseUrl, config.notesDir)
    const imageUrl = `${directoryUrl}${WebDAVClient.imageDirName}/${encodeURIComponent(fileName)}`
    Logger.info('WebDAVClient', `uploadImage start: fileName=${fileName}, url=${this.sanitizeUrl(imageUrl)}, byteLength=${bytes.byteLength}`)
    const response = await this.sendRequest(imageUrl, http.RequestMethod.PUT, '', {
      contentType: 'application/octet-stream',
      rawData: bytes
    })
    Logger.info('WebDAVClient', `uploadImage response: fileName=${fileName}, responseCode=${response.responseCode}`)
    if (response.responseCode >= 400) {
      throw new Error(`Image upload failed with status ${response.responseCode}`)
    }
  }

  async downloadImage(fileName: string): Promise<ArrayBuffer> {
    const config = await this.requireConfig()
    const directoryUrl = PathUtils.joinRemoteDirectoryUrl(config.baseUrl, config.notesDir)
    const imageUrl = `${directoryUrl}${WebDAVClient.imageDirName}/${encodeURIComponent(fileName)}`
    Logger.info('WebDAVClient', `downloadImage start: fileName=${fileName}, url=${this.sanitizeUrl(imageUrl)}`)
    const response = await this.sendRequest(imageUrl, http.RequestMethod.GET, undefined, {
      expectArrayBuffer: true
    })
    Logger.info('WebDAVClient', `downloadImage response: fileName=${fileName}, responseCode=${response.responseCode}`)
    if (response.responseCode >= 400) {
      throw new Error(`Image download failed with status ${response.responseCode}`)
    }
    if (response.result instanceof ArrayBuffer) {
      return response.result as ArrayBuffer
    }
    throw new Error('Unexpected response type for image download')
  }

  async deleteImage(fileName: string): Promise<void> {
    const config = await this.requireConfig()
    const directoryUrl = PathUtils.joinRemoteDirectoryUrl(config.baseUrl, config.notesDir)
    const imageUrl = `${directoryUrl}${WebDAVClient.imageDirName}/${encodeURIComponent(fileName)}`
    Logger.info('WebDAVClient', `deleteImage start: fileName=${fileName}, url=${this.sanitizeUrl(imageUrl)}`)
    const response = await this.sendRequest(imageUrl, http.RequestMethod.DELETE)
    Logger.info('WebDAVClient', `deleteImage response: fileName=${fileName}, responseCode=${response.responseCode}`)
    if (response.responseCode >= 400 && response.responseCode !== 404) {
      throw new Error(`Image delete failed with status ${response.responseCode}`)
    }
  }

  async listRemoteNotes(): Promise<string[]> {
    const config = await this.requireConfig()
    const targetUrl = PathUtils.joinRemoteDirectoryUrl(config.baseUrl, config.notesDir)
    Logger.info('WebDAVClient', `listRemoteNotes start: url=${this.sanitizeUrl(targetUrl)}`)
    const results = new Set<string>()
    try {
      const response = await this.sendRequest(targetUrl, 'PROPFIND', WebDAVClient._propfindRequestBody, {
        contentType: 'application/xml; charset=utf-8',
        depth: '1'
      })
      Logger.info('WebDAVClient', `listRemoteNotes PROPFIND response: responseCode=${response.responseCode}`)
      if (response.responseCode >= 200 && response.responseCode < 300) {
        this.parseNoteIdsFromText(this.responseBodyToText(response.result)).forEach((noteId: string) => results.add(noteId))
      } else {
        Logger.warn('WebDAVClient', `listRemoteNotes PROPFIND failed: responseCode=${response.responseCode}`)
      }
    } catch (error) {
      Logger.warn('WebDAVClient', `listRemoteNotes PROPFIND exception: ${this.describeError(error as Object)}`)
    }
    try {
      const response = await this.sendRequest(targetUrl, http.RequestMethod.GET)
      Logger.info('WebDAVClient', `listRemoteNotes GET response: responseCode=${response.responseCode}`)
      if (response.responseCode < 400) {
        this.parseNoteIdsFromText(this.responseBodyToText(response.result)).forEach((noteId: string) => results.add(noteId))
      }
    } catch (error) {
      Logger.warn('WebDAVClient', `listRemoteNotes GET fallback exception: ${this.describeError(error as Object)}`)
    }
    try {
      const indexSnapshot = await this.fetchRemoteIndexSnapshotBestEffort()
      indexSnapshot.noteEntries.forEach((_: RemoteIndexEntry, noteId: string) => results.add(noteId))
    } catch (error) {
      Logger.warn('WebDAVClient', `listRemoteNotes index fallback exception: ${this.describeError(error as Object)}`)
    }
    Logger.info('WebDAVClient', `listRemoteNotes success: parsedCount=${results.size}`)
    return Array.from(results)
  }

  /** 全量同步一批结束后调用一次（与 Flutter `flushRemoteIndexFromLocalNotes` 对齐）。 */
  async flushRemoteIndexFromLocalNotes(notes: Note[]): Promise<void> {
    let snapshot: RemoteIndexSnapshot
    try {
      snapshot = await this.fetchRemoteIndexSnapshotStrict()
    } catch (error) {
      Logger.warn('WebDAVClient',
        `flushRemoteIndexFromLocalNotes skipped (GET failed): ${this.describeError(error as Object)}`)
      return
    }
    for (let i = 0; i < notes.length; i += 1) {
      const note = notes[i]
      if (note.id.length === 0) {
        continue
      }
      snapshot.noteEntries.set(note.id, {
        remoteModified: note.lastOperationAt,
        deletedTime: note.deletedTime,
        contentLength: note.content.length
      })
    }
    try {
      await this.writeRemoteIndexEntries(snapshot.noteEntries, snapshot.permanentlyDeletedNoteIds)
    } catch (error) {
      Logger.warn('WebDAVClient',
        `flushRemoteIndexFromLocalNotes PUT failed: ${this.describeError(error as Object)}`)
    }
  }

  async reconcileRemoteIndex(noteIds: string[], deletedNoteIds: string[]): Promise<void> {
    let snapshot: RemoteIndexSnapshot
    try {
      snapshot = await this.fetchRemoteIndexSnapshotStrict()
    } catch (error) {
      Logger.warn('WebDAVClient',
        `reconcileRemoteIndex skipped (index GET failed): ${this.describeError(error as Object)}`)
      return
    }
    const mergedEntries = snapshot.noteEntries
    noteIds.forEach((noteId: string) => {
      if (noteId.length > 0) {
        if (!mergedEntries.has(noteId)) {
          mergedEntries.set(noteId, this.defaultRemoteIndexEntry())
        }
      }
    })
    deletedNoteIds.forEach((noteId: string) => {
      if (noteId.length > 0) {
        mergedEntries.delete(noteId)
      }
    })
    try {
      await this.writeRemoteIndexEntries(mergedEntries, snapshot.permanentlyDeletedNoteIds)
    } catch (error) {
      Logger.warn('WebDAVClient',
        `reconcileRemoteIndex PUT failed: ${this.describeError(error as Object)}`)
    }
  }

  async getRemoteIndexEntries(): Promise<Map<string, RemoteIndexEntry>> {
    const snapshot = await this.fetchRemoteIndexSnapshotBestEffort()
    return snapshot.noteEntries
  }

  /** 供同步逻辑一次性读取索引（避免重复 GET）。 */
  async getRemoteIndexSnapshot(): Promise<RemoteIndexSnapshot> {
    return await this.fetchRemoteIndexSnapshotBestEffort()
  }

  /**
   * 回收站彻底删除后写入：将 id 记入 `.qingyu-index.json` 的彻底删除数组，并从索引笔记条目中移除。
   */
  async appendPermanentlyDeletedNoteId(noteId: string): Promise<void> {
    if (noteId.length === 0) {
      return
    }
    if (this.isDeferRemoteIndexMerge()) {
      return
    }
    try {
      const snapshot = await this.fetchRemoteIndexSnapshotStrict()
      snapshot.noteEntries.delete(noteId)
      snapshot.permanentlyDeletedNoteIds.add(noteId)
      await this.writeRemoteIndexEntries(snapshot.noteEntries, snapshot.permanentlyDeletedNoteIds)
    } catch (error) {
      Logger.warn('WebDAVClient',
        `appendPermanentlyDeletedNoteId failed: noteId=${noteId}, ${this.describeError(error as Object)}`)
    }
  }

  private async noteUrl(noteId: string): Promise<string> {
    const config = await this.requireConfig()
    return PathUtils.joinRemoteFileUrl(config.baseUrl, config.notesDir, noteId)
  }

  private async requireConfig(): Promise<WebDAVConfig> {
    let config: WebDAVConfig | null = null
    for (let round = 0; round < 3; round += 1) {
      if (round > 0) {
        await new Promise<void>((resolve) => setTimeout(resolve, 450))
      }
      config = await this.loadConfig()
      if (config !== null && config.enabled) {
        return config
      }
    }
    const intent = await PreferencesService.getInstance().getQingyuCloudSyncIntent()
    if (intent === 'qingyu') {
      throw new Error('Qingyu WebDAV credentials unavailable')
    }
    throw new Error('WebDAV is not configured')
  }

  private async loadConfig(): Promise<WebDAVConfig | null> {
    return await PreferencesService.getInstance().getWebDAVConfig()
  }

  private async buildHeaders(extraHeaders?: HeaderOverrides, authConfig?: WebDAVConfig): Promise<RequestHeaders> {
    let config: WebDAVConfig
    if (authConfig !== undefined) {
      if (!authConfig.enabled) {
        throw new Error('WebDAV is not configured')
      }
      config = authConfig
    } else {
      config = await this.requireConfig()
    }
    const authorization = await this.resolveAuthorizationHeader(config)
    const headers: RequestHeaders = {
      Authorization: authorization,
      Accept: 'application/xml,text/plain,text/html,application/json,*/*'
    }
    if (extraHeaders?.contentType) {
      headers.Contentx2dType = extraHeaders.contentType
    }
    if (extraHeaders?.modifiedAt) {
      headers.Xx2dQingyux2dModified = extraHeaders.modifiedAt
    }
    if (extraHeaders?.depth) {
      headers.Depth = extraHeaders.depth
    }
    return headers
  }

  private async sendRequest(url: string, method: http.RequestMethod | string, extraData?: string,
    extraHeaders?: HeaderOverrides, authConfig?: WebDAVConfig): Promise<http.HttpResponse> {
    const request = http.createHttp()
    const safeUrl = this.sanitizeUrl(url)
    const methodLabel = this.requestMethodLabel(method)
    Logger.info('WebDAVClient',
      `sendRequest start: method=${methodLabel}, url=${safeUrl}, hasExtraData=${extraData !== undefined}, readTimeout=15000, connectTimeout=10000`)
    try {
      const headers = await this.buildHeaders(extraHeaders, authConfig)
      Logger.info('WebDAVClient',
        `sendRequest headers ready: method=${methodLabel}, url=${safeUrl}, headerKeys=${this.describeHeaderKeys(headers)}`)
      const requestOptions: http.HttpRequestOptions = {
        method: method as http.RequestMethod,
        header: headers,
        expectDataType: extraHeaders?.expectArrayBuffer ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING,
        readTimeout: 15000,
        connectTimeout: 10000
      }
      // Harmony NetStack rejects empty string payloads as invalid request parameters.
      if (extraData !== undefined && extraData.length > 0) {
        requestOptions.extraData = extraData
      }
      // Support binary upload
      if (extraHeaders?.rawData) {
        requestOptions.extraData = extraHeaders.rawData
      }
      const response = await request.request(url, requestOptions)
      Logger.info('WebDAVClient',
        `sendRequest success: method=${methodLabel}, url=${safeUrl}, responseCode=${response.responseCode}`)
      return response
    } catch (error) {
      if (this.isCredentialDecryptFailure(error)) {
        Logger.warn('WebDAVClient',
          `sendRequest authorization failed before request dispatch: method=${methodLabel}, url=${safeUrl}, ${this.describeError(error)}`)
        throw this.toRuntimeError(error)
      }
      Logger.warn('WebDAVClient',
        `sendRequest failed: method=${methodLabel}, url=${safeUrl}, ${this.describeError(error)}`)
      throw this.toRuntimeError(error)
    } finally {
      request.destroy()
      Logger.info('WebDAVClient', `sendRequest destroy: method=${methodLabel}, url=${safeUrl}`)
    }
  }

  private pickHeader(headers: Object, key: string): string {
    const headerRecord = headers as Record<string, Object | string | number | boolean | undefined>
    const normalizedKey = key.toLowerCase()
    for (const headerKey of Object.keys(headerRecord)) {
      if (headerKey.toLowerCase() !== normalizedKey) {
        continue
      }
      const value = headerRecord[headerKey]
      if (typeof value === 'string') {
        return value
      }
      if (typeof value === 'number' || typeof value === 'boolean') {
        return `${value}`
      }
      if (Array.isArray(value) && value.length > 0) {
        return `${value[0]}`
      }
      if (value !== undefined && value !== null) {
        return `${value}`
      }
    }
    return ''
  }

  private parseNoteIdsFromText(body: string): string[] {
    const results = new Set<string>()
    const regex = /([a-f0-9-]{36})\.md/gi
    let match: RegExpExecArray | null = regex.exec(body)
    while (match) {
      if (match[1].length > 0) {
        results.add(match[1])
      }
      match = regex.exec(body)
    }
    return Array.from(results)
  }

  private responseBodyToText(result: Object | string | number | boolean): string {
    if (typeof result === 'string') {
      return result
    }
    return JSON.stringify(result)
  }

  private async remoteIndexUrl(): Promise<string> {
    const config = await this.requireConfig()
    const directoryUrl = PathUtils.joinRemoteDirectoryUrl(config.baseUrl, config.notesDir)
    return `${directoryUrl}${encodeURIComponent(WebDAVClient._remoteIndexFileName)}`
  }

  private async remoteNoteSettingsUrl(): Promise<string> {
    const config = await this.requireConfig()
    return PathUtils.joinRemotePathFileUrl(
      config.baseUrl,
      config.notesDir,
      SyncConstants.noteSettingsFile
    )
  }

  /** GET 远端笔记设置；404 返回 `null`。 */
  async fetchNoteSettingsDocument(): Promise<NoteSettingsDocument | null> {
    const response = await this.sendRequest(
      await this.remoteNoteSettingsUrl(),
      http.RequestMethod.GET
    )
    if (response.responseCode === 404) {
      return null
    }
    if (response.responseCode >= 400) {
      throw new Error(`Note settings download failed with status ${response.responseCode}`)
    }
    const rawBody = this.responseBodyToText(response.result).trim()
    if (rawBody.length === 0) {
      return null
    }
    const decoded = JSON.parse(rawBody) as Record<string, Object>
    return NoteSettingsDocument.fromJsonRecord(decoded)
  }

  async uploadNoteSettingsDocument(doc: NoteSettingsDocument): Promise<void> {
    const response = await this.sendRequest(
      await this.remoteNoteSettingsUrl(),
      http.RequestMethod.PUT,
      JSON.stringify(doc.toJsonRecord()),
      { contentType: 'application/json; charset=utf-8' }
    )
    if (response.responseCode >= 400) {
      throw new Error(`Note settings upload failed with status ${response.responseCode}`)
    }
  }

  /** 索引 GET 失败时返回空快照（不抛），供列表合并与全量同步容错。 */
  private async fetchRemoteIndexSnapshotBestEffort(): Promise<RemoteIndexSnapshot> {
    try {
      return await this.fetchRemoteIndexSnapshotStrict()
    } catch (error) {
      Logger.warn('WebDAVClient',
        `fetchRemoteIndexSnapshotBestEffort degraded: ${this.describeError(error as Object)}`)
      return {
        noteEntries: new Map<string, RemoteIndexEntry>(),
        permanentlyDeletedNoteIds: new Set<string>(),
        updatedAt: 0
      }
    }
  }

  private async fetchRemoteIndexSnapshotStrict(): Promise<RemoteIndexSnapshot> {
    const permanentDeletes = new Set<string>()
    const response = await this.sendRequest(await this.remoteIndexUrl(), http.RequestMethod.GET)
    if (response.responseCode === 404) {
      return {
        noteEntries: new Map<string, RemoteIndexEntry>(),
        permanentlyDeletedNoteIds: permanentDeletes,
        updatedAt: 0
      }
    }
    if (response.responseCode >= 400) {
      throw new Error(`Index download failed with status ${response.responseCode}`)
    }
    const rawBody = this.responseBodyToText(response.result).trim()
    if (rawBody.length === 0) {
      return {
        noteEntries: new Map<string, RemoteIndexEntry>(),
        permanentlyDeletedNoteIds: permanentDeletes,
        updatedAt: 0
      }
    }
    const decoded = JSON.parse(rawBody) as Object
    const results: Map<string, RemoteIndexEntry> = new Map()
    if (typeof decoded !== 'object' || decoded === null || Array.isArray(decoded)) {
      return { noteEntries: results, permanentlyDeletedNoteIds: permanentDeletes, updatedAt: 0 }
    }
    const payload = decoded as Record<string, Object | undefined>
    let updatedAt = 0
    const rawUa = payload.updatedAt
    if (typeof rawUa === 'number' && Number.isFinite(rawUa)) {
      updatedAt = rawUa
    } else if (typeof rawUa === 'string') {
      const p = Number.parseInt(rawUa, 10)
      if (Number.isFinite(p)) {
        updatedAt = p
      }
    }
    const permRaw = payload[SyncConstants.remoteIndexFieldPermanentlyDeletedNoteIds]
    if (Array.isArray(permRaw)) {
      permRaw.forEach((item: Object) => {
        if (typeof item === 'string' && item.length > 0) {
          permanentDeletes.add(item)
        }
      })
    }
    const rawNoteIds = payload.noteIds
    if (Array.isArray(rawNoteIds)) {
      rawNoteIds.forEach((item: Object) => {
        if (typeof item === 'string' && item.length > 0) {
          if (!results.has(item)) {
            results.set(item, this.defaultRemoteIndexEntry())
          }
        }
      })
    } else if (rawNoteIds !== undefined && rawNoteIds !== null && typeof rawNoteIds === 'object') {
      const noteIdRecord = rawNoteIds as Record<string, Object | undefined>
      Object.keys(noteIdRecord).forEach((noteId: string) => {
        if (noteId.length === 0) {
          return
        }
        const rawEntry = noteIdRecord[noteId]
        const entryRecord = (rawEntry ?? {}) as Record<string, Object | undefined>
        results.set(noteId, {
          remoteModified: this.normalizeIndexNumber(entryRecord.remoteModified),
          deletedTime: this.normalizeIndexNumber(entryRecord.deletedTime),
          contentLength: this.normalizeIndexNumber(entryRecord.contentLength)
        })
      })
    }
    return { noteEntries: results, permanentlyDeletedNoteIds: permanentDeletes, updatedAt }
  }

  private async writeRemoteIndexEntries(noteEntries: Map<string, RemoteIndexEntry>,
    permanentlyDeletedNoteIds: Set<string>): Promise<void> {
    const sortedNoteIds = Array.from(noteEntries.keys()).sort()
    const noteIds: Record<string, RemoteIndexEntry> = {}
    sortedNoteIds.forEach((noteId: string) => {
      const entry = noteEntries.get(noteId) ?? this.defaultRemoteIndexEntry()
      noteIds[noteId] = {
        remoteModified: this.normalizeIndexNumber(entry.remoteModified),
        deletedTime: this.normalizeIndexNumber(entry.deletedTime),
        contentLength: this.normalizeIndexNumber(entry.contentLength)
      }
    })
    const sortedPermanent = Array.from(permanentlyDeletedNoteIds).filter((id: string) => id.length > 0).sort()
    const payload: RemoteIndexWritePayload = {
      version: 2,
      updatedAt: Date.now(),
      noteIds,
      permanentlyDeletedNoteIds: sortedPermanent
    }
    const response = await this.sendRequest(
      await this.remoteIndexUrl(),
      http.RequestMethod.PUT,
      JSON.stringify(payload),
      {
        contentType: 'application/json; charset=utf-8'
      }
    )
    if (response.responseCode >= 400) {
      throw new Error(`Index upload failed with status ${response.responseCode}`)
    }
  }

  private async addNoteToRemoteIndex(noteId: string, entry?: Partial<RemoteIndexEntry>): Promise<void> {
    let snapshot: RemoteIndexSnapshot
    try {
      snapshot = await this.fetchRemoteIndexSnapshotStrict()
    } catch (error) {
      Logger.warn('WebDAVClient',
        `addNoteToRemoteIndex skipped (index GET failed): ${this.describeError(error as Object)}`)
      return
    }
    const noteEntries = snapshot.noteEntries
    const previous = noteEntries.get(noteId) ?? this.defaultRemoteIndexEntry()
    const merged: RemoteIndexEntry = {
      remoteModified: this.normalizeIndexNumber(entry?.remoteModified ?? previous.remoteModified),
      deletedTime: this.normalizeIndexNumber(entry?.deletedTime ?? previous.deletedTime),
      contentLength: this.normalizeIndexNumber(entry?.contentLength ?? previous.contentLength)
    }
    if (noteEntries.has(noteId) &&
      previous.remoteModified === merged.remoteModified &&
      previous.deletedTime === merged.deletedTime &&
      previous.contentLength === merged.contentLength) {
      return
    }
    noteEntries.set(noteId, merged)
    await this.writeRemoteIndexEntries(noteEntries, snapshot.permanentlyDeletedNoteIds)
  }

  private async removeNoteFromRemoteIndex(noteId: string): Promise<void> {
    let snapshot: RemoteIndexSnapshot
    try {
      snapshot = await this.fetchRemoteIndexSnapshotStrict()
    } catch (error) {
      Logger.warn('WebDAVClient',
        `removeNoteFromRemoteIndex skipped (index GET failed): ${this.describeError(error as Object)}`)
      return
    }
    const noteEntries = snapshot.noteEntries
    if (!noteEntries.delete(noteId)) {
      return
    }
    await this.writeRemoteIndexEntries(noteEntries, snapshot.permanentlyDeletedNoteIds)
  }

  private defaultRemoteIndexEntry(): RemoteIndexEntry {
    return {
      remoteModified: 0,
      deletedTime: 0,
      contentLength: 0
    }
  }

  private normalizeIndexNumber(value: Object | number | undefined): number {
    if (typeof value === 'number') {
      return Number.isFinite(value) ? value : 0
    }
    if (typeof value === 'string') {
      const parsed = Number.parseInt(value, 10)
      return Number.isFinite(parsed) ? parsed : 0
    }
    return 0
  }

  private async resolveAuthorizationHeader(config: WebDAVConfig): Promise<string> {
    const signature = `${config.username}\u0000${config.encryptedPassword}`
    const cacheHit = this.cachedAuthSignature === signature && this.cachedAuthorizationHeader.length > 0
    Logger.info('WebDAVClient',
      `resolveAuthorizationHeader start: cacheHit=${cacheHit}, usernameLength=${config.username.length}, encryptedPasswordLength=${config.encryptedPassword.length}`)
    if (cacheHit) {
      Logger.info('WebDAVClient', 'resolveAuthorizationHeader cache hit')
      return this.cachedAuthorizationHeader
    }
    try {
      const password = await CryptoService.getInstance().decryptText(config.encryptedPassword)
      Logger.info('WebDAVClient', `resolveAuthorizationHeader password decrypted: passwordLength=${password.length}`)
      const authValue = this.base64.encodeToStringSync(new util.TextEncoder().encodeInto(`${config.username}:${password}`))
      this.cachedAuthSignature = signature
      this.cachedAuthorizationHeader = `Basic ${authValue}`
      Logger.info('WebDAVClient', 'resolveAuthorizationHeader generated authorization header')
      return this.cachedAuthorizationHeader
    } catch (error) {
      const wrappedError = new Error(`WebDAV credential decrypt failed: ${this.describeError(error)}`)
      Logger.warn('WebDAVClient', `resolveAuthorizationHeader failed: ${wrappedError.message}`)
      throw wrappedError
    }
  }

  private sanitizeUrl(url: string): string {
    return url.replace(/\/\/([^/@]+)@/, '//***@')
  }

  private requestMethodLabel(method: http.RequestMethod | string): string {
    if (typeof method === 'string') {
      return method
    }
    if (method === http.RequestMethod.GET) {
      return 'GET'
    }
    if (method === http.RequestMethod.HEAD) {
      return 'HEAD'
    }
    if (method === http.RequestMethod.PUT) {
      return 'PUT'
    }
    if (method === http.RequestMethod.DELETE) {
      return 'DELETE'
    }
    return `${method}`
  }

  private isReachableDirectoryResponse(responseCode: number): boolean {
    return (responseCode >= 200 && responseCode < 400) || responseCode === 405
  }

  private isCredentialDecryptFailure(error: Object): boolean {
    const detail = error as ErrorLike
    return (detail.message ?? `${error}`).includes('WebDAV credential decrypt failed')
  }

  private describeHeaderKeys(headers: RequestHeaders): string {
    return Object.keys(headers).join(',')
  }

  private describeError(error: Object): string {
    const detail = error as ErrorLike
    const raw = JSON.stringify(error)
    const fallbackRaw = raw.length > 0 ? raw : `${error}`
    return `code=${detail.code ?? 'n/a'}, name=${detail.name ?? 'n/a'}, message=${detail.message ?? 'n/a'}, raw=${fallbackRaw}`
  }

  private toRuntimeError(error: Object): Error {
    return new Error(this.describeError(error))
  }
}
