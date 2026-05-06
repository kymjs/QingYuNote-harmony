import http from '@ohos.net.http'
import { util } from '@kit.ArkTS'
import type { RemoteNoteStat, WebDAVConfig } from '../common/model/Note'
import { PreferencesService } from './PreferencesService'
import { CryptoService } from './CryptoService'
import { PathUtils } from '../common/utils/PathUtils'
import { TimeUtils } from '../common/utils/TimeUtils'
import { Logger } from '../common/utils/Logger'

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
  notes: Record<string, RemoteIndexEntry>
}

export class WebDAVClient {
  private static instance: WebDAVClient = new WebDAVClient()
  private static readonly REMOTE_INDEX_FILE_NAME: string = '.qingyu-index.json'
  static readonly IMAGE_DIR_NAME: string = 'qingyu-note-image'
  private static readonly REMOTE_INDEX_VERSION: number = 2
  private static readonly PROPFIND_REQUEST_BODY: string =
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
      Logger.info('WebDAVClient', `testConnection response received: responseCode=${response.responseCode}`)
      return this.isReachableDirectoryResponse(response.responseCode)
    } catch (error) {
      if (this.isCredentialDecryptFailure(error)) {
        Logger.warn('WebDAVClient', `testConnection failed before request dispatch: phase=${phase}, ${this.describeError(error)}`)
        throw this.toRuntimeError(error)
      }
      Logger.warn('WebDAVClient', `testConnection failed: phase=${phase}, ${this.describeError(error)}`)
      return false
    }
  }

  async ensureNotesDirectory(): Promise<void> {
    const config = await this.requireConfig()
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

  private async ensureImageDirectory(config: WebDAVConfig): Promise<void> {
    const directoryUrl = PathUtils.joinRemoteDirectoryUrl(config.baseUrl, config.notesDir)
    const imageUrl = `${directoryUrl}${WebDAVClient.IMAGE_DIR_NAME}/`
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
    await this.addNoteToRemoteIndex(noteId, {
      remoteModified,
      deletedTime: indexHint?.deletedTime ?? 0,
      contentLength: indexHint?.contentLength ?? content.length
    })
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
    await this.removeNoteFromRemoteIndex(noteId)
  }

  async uploadImage(fileName: string, bytes: ArrayBuffer): Promise<void> {
    const config = await this.requireConfig()
    const directoryUrl = PathUtils.joinRemoteDirectoryUrl(config.baseUrl, config.notesDir)
    const imageUrl = `${directoryUrl}${WebDAVClient.IMAGE_DIR_NAME}/${encodeURIComponent(fileName)}`
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
    const imageUrl = `${directoryUrl}${WebDAVClient.IMAGE_DIR_NAME}/${encodeURIComponent(fileName)}`
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
    const imageUrl = `${directoryUrl}${WebDAVClient.IMAGE_DIR_NAME}/${encodeURIComponent(fileName)}`
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
      const response = await this.sendRequest(targetUrl, 'PROPFIND', WebDAVClient.PROPFIND_REQUEST_BODY, {
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
      const indexEntries = await this.readRemoteIndexEntries()
      indexEntries.forEach((_: RemoteIndexEntry, noteId: string) => results.add(noteId))
    } catch (error) {
      Logger.warn('WebDAVClient', `listRemoteNotes index fallback exception: ${this.describeError(error as Object)}`)
    }
    Logger.info('WebDAVClient', `listRemoteNotes success: parsedCount=${results.size}`)
    return Array.from(results)
  }

  async reconcileRemoteIndex(noteIds: string[], deletedNoteIds: string[]): Promise<void> {
    const mergedEntries = await this.readRemoteIndexEntries()
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
    await this.writeRemoteIndexEntries(mergedEntries)
  }

  async getRemoteIndexEntries(): Promise<Map<string, RemoteIndexEntry>> {
    return await this.readRemoteIndexEntries()
  }

  private async noteUrl(noteId: string): Promise<string> {
    const config = await this.requireConfig()
    return PathUtils.joinRemoteFileUrl(config.baseUrl, config.notesDir, noteId)
  }

  private async requireConfig(): Promise<WebDAVConfig> {
    const config = await this.loadConfig()
    if (!config || !config.enabled) {
      throw new Error('WebDAV is not configured')
    }
    return config
  }

  private async loadConfig(): Promise<WebDAVConfig | null> {
    return await PreferencesService.getInstance().getWebDAVConfig()
  }

  private async buildHeaders(extraHeaders?: HeaderOverrides): Promise<RequestHeaders> {
    const config = await this.requireConfig()
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
    extraHeaders?: HeaderOverrides): Promise<http.HttpResponse> {
    const request = http.createHttp()
    const safeUrl = this.sanitizeUrl(url)
    const methodLabel = this.requestMethodLabel(method)
    Logger.info('WebDAVClient',
      `sendRequest start: method=${methodLabel}, url=${safeUrl}, hasExtraData=${extraData !== undefined}, readTimeout=15000, connectTimeout=10000`)
    try {
      const headers = await this.buildHeaders(extraHeaders)
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
    return `${directoryUrl}${encodeURIComponent(WebDAVClient.REMOTE_INDEX_FILE_NAME)}`
  }

  private async readRemoteIndexEntries(): Promise<Map<string, RemoteIndexEntry>> {
    try {
      const response = await this.sendRequest(await this.remoteIndexUrl(), http.RequestMethod.GET)
      if (response.responseCode === 404) {
        return new Map<string, RemoteIndexEntry>()
      }
      if (response.responseCode >= 400) {
        throw new Error(`Index download failed with status ${response.responseCode}`)
      }
      const rawBody = this.responseBodyToText(response.result).trim()
      if (rawBody.length === 0) {
        return new Map<string, RemoteIndexEntry>()
      }
      const decoded = JSON.parse(rawBody) as Object
      const results: Map<string, RemoteIndexEntry> = new Map()
      if (Array.isArray(decoded)) {
        decoded.forEach((item: Object) => {
          if (typeof item === 'string' && item.length > 0) {
            results.set(item, this.defaultRemoteIndexEntry())
          }
        })
        return results
      }
      const payload = decoded as Record<string, Object | undefined>
      const notes = payload.notes as Record<string, Object | undefined> | undefined
      if (notes && typeof notes === 'object') {
        Object.keys(notes).forEach((noteId: string) => {
          if (noteId.length === 0) {
            return
          }
          const rawEntry = notes[noteId]
          const entryRecord = (rawEntry ?? {}) as Record<string, Object | undefined>
          results.set(noteId, {
            remoteModified: this.normalizeIndexNumber(entryRecord.remoteModified),
            deletedTime: this.normalizeIndexNumber(entryRecord.deletedTime),
            contentLength: this.normalizeIndexNumber(entryRecord.contentLength)
          })
        })
      }
      const noteIds = payload.noteIds
      if (Array.isArray(noteIds)) {
        noteIds.forEach((item: Object) => {
          if (typeof item === 'string' && item.length > 0) {
            if (!results.has(item)) {
              results.set(item, this.defaultRemoteIndexEntry())
            }
          }
        })
      }
      return results
    } catch (error) {
      if ((error as ErrorLike).message?.includes('Index download failed')) {
        throw error as Error
      }
      Logger.warn('WebDAVClient', `readRemoteIndexEntries parse fallback: ${this.describeError(error as Object)}`)
      return new Map<string, RemoteIndexEntry>()
    }
  }

  private async writeRemoteIndexEntries(noteEntries: Map<string, RemoteIndexEntry>): Promise<void> {
    const sortedNoteIds = Array.from(noteEntries.keys()).sort()
    const notes: Record<string, RemoteIndexEntry> = {}
    sortedNoteIds.forEach((noteId: string) => {
      const entry = noteEntries.get(noteId) ?? this.defaultRemoteIndexEntry()
      notes[noteId] = {
        remoteModified: this.normalizeIndexNumber(entry.remoteModified),
        deletedTime: this.normalizeIndexNumber(entry.deletedTime),
        contentLength: this.normalizeIndexNumber(entry.contentLength)
      }
    })
    const payload: RemoteIndexPayloadV2 = {
      version: WebDAVClient.REMOTE_INDEX_VERSION,
      updatedAt: Date.now(),
      notes
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
    const noteEntries = await this.readRemoteIndexEntries()
    const previous = noteEntries.get(noteId) ?? this.defaultRemoteIndexEntry()
    noteEntries.set(noteId, {
      remoteModified: this.normalizeIndexNumber(entry?.remoteModified ?? previous.remoteModified),
      deletedTime: this.normalizeIndexNumber(entry?.deletedTime ?? previous.deletedTime),
      contentLength: this.normalizeIndexNumber(entry?.contentLength ?? previous.contentLength)
    })
    await this.writeRemoteIndexEntries(noteEntries)
  }

  private async removeNoteFromRemoteIndex(noteId: string): Promise<void> {
    const noteEntries = await this.readRemoteIndexEntries()
    if (!noteEntries.delete(noteId)) {
      return
    }
    await this.writeRemoteIndexEntries(noteEntries)
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
