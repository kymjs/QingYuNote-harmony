import fs from '@ohos.file.fs'
import http from '@ohos.net.http'
import util from '@ohos.util'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { AppContextHolder } from './AppContextHolder'
import { Logger } from '../common/utils/Logger'

interface ImageCacheIndexEntry {
  url: string
  fileName: string
  size: number
  lastAccessMs: number
}

interface ImageCacheIndexFile {
  entries: Record<string, ImageCacheIndexEntry>
}

interface ImageCacheSortItem {
  key: string
  entry: ImageCacheIndexEntry
}

/** 网络图片磁盘缓存：按 URL 去重，上限 300MB，超出后按最久未使用（LRU）淘汰。 */
export class ImageCacheService {
  private static readonly MAX_CACHE_BYTES: number = 300 * 1024 * 1024
  private static readonly CACHE_DIR_NAME: string = 'url_image_cache'
  private static readonly INDEX_FILE_NAME: string = 'index.json'
  private static instance: ImageCacheService = new ImageCacheService()
  private cacheDir: string = ''
  private index: Record<string, ImageCacheIndexEntry> = {}
  private ready: boolean = false
  private inFlight: Map<string, Promise<string>> = new Map<string, Promise<string>>()
  private indexWriteChain: Promise<void> = Promise.resolve()
  private readonly textEncoder: util.TextEncoder = new util.TextEncoder()

  static getInstance(): ImageCacheService {
    return ImageCacheService.instance
  }

  static isNetworkImageUrl(url: string): boolean {
    const trimmed = url.trim()
    return trimmed.startsWith('http://') || trimmed.startsWith('https://')
  }

  /** 解析 URL 对应缓存文件绝对路径；未命中则下载后写入缓存。 */
  async resolve(url: string): Promise<string> {
    const normalized = url.trim()
    if (!ImageCacheService.isNetworkImageUrl(normalized)) {
      throw new Error('url must be http or https')
    }
    const existing = this.inFlight.get(normalized)
    if (existing !== undefined) {
      return existing
    }
    const task = this.resolveInternal(normalized)
    this.inFlight.set(normalized, task)
    try {
      return await task
    } finally {
      this.inFlight.delete(normalized)
    }
  }

  async precache(url: string): Promise<void> {
    if (!ImageCacheService.isNetworkImageUrl(url)) {
      return
    }
    try {
      await this.resolve(url)
    } catch (error) {
      Logger.warn('ImageCacheService', `precache failed for ${url}: ${JSON.stringify(error)}`)
    }
  }

  private async resolveInternal(url: string): Promise<string> {
    await this.ensureReady()
    const key = await this.cacheKey(url)
    const hit = this.index[key]
    if (hit !== undefined) {
      const filePath = `${this.cacheDir}/${hit.fileName}`
      if (FileServiceFileExists(filePath)) {
        await this.touchEntry(key, hit)
        return filePath
      }
      await this.removeEntry(key, hit)
    }
    return this.downloadAndStore(url, key)
  }

  private async ensureReady(): Promise<void> {
    if (this.ready) {
      return
    }
    const ctx = AppContextHolder.tryGetContext()
    if (!ctx) {
      throw new Error('Ability context has not been initialized')
    }
    this.cacheDir = `${ctx.cacheDir}/${ImageCacheService.CACHE_DIR_NAME}`
    try {
      if (!fs.accessSync(this.cacheDir)) {
        fs.mkdirSync(this.cacheDir, true)
      }
    } catch (_) {
      fs.mkdirSync(this.cacheDir, true)
    }
    this.index = await this.loadIndex()
    this.ready = true
  }

  private async loadIndex(): Promise<Record<string, ImageCacheIndexEntry>> {
    const indexPath = `${this.cacheDir}/${ImageCacheService.INDEX_FILE_NAME}`
    try {
      if (!fs.accessSync(indexPath)) {
        return {}
      }
      const raw = await fs.readText(indexPath, { encoding: 'utf-8' })
      const parsed = JSON.parse(raw) as ImageCacheIndexFile
      if (parsed === null || parsed.entries === undefined) {
        return {}
      }
      return parsed.entries
    } catch (error) {
      Logger.warn('ImageCacheService', `loadIndex failed: ${JSON.stringify(error)}`)
      return {}
    }
  }

  private async saveIndex(): Promise<void> {
    const previous = this.indexWriteChain
    let release: () => void = () => {
    }
    const gate = new Promise<void>((resolve) => {
      release = resolve
    })
    this.indexWriteChain = gate
    await previous
    try {
      const payload: ImageCacheIndexFile = { entries: this.index }
      const indexPath = `${this.cacheDir}/${ImageCacheService.INDEX_FILE_NAME}`
      const file = fs.openSync(indexPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      try {
        await fs.write(file.fd, JSON.stringify(payload), { encoding: 'utf-8' })
      } finally {
        fs.closeSync(file)
      }
    } finally {
      release()
    }
  }

  private async touchEntry(key: string, entry: ImageCacheIndexEntry): Promise<void> {
    entry.lastAccessMs = Date.now()
    this.index[key] = entry
    await this.saveIndex()
  }

  private async downloadAndStore(url: string, key: string): Promise<string> {
    const req = http.createHttp()
    try {
      const response = await req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 20000,
        readTimeout: 60000
      })
      if (response.responseCode < 200 || response.responseCode >= 400) {
        throw new Error(`image download failed with status ${response.responseCode}`)
      }
      if (!(response.result instanceof ArrayBuffer)) {
        throw new Error('unexpected image response type')
      }
      const bytes = response.result as ArrayBuffer
      if (bytes.byteLength <= 0) {
        throw new Error('empty image response')
      }
      const contentType = `${response.header?.['content-type'] ?? response.header?.['Content-Type'] ?? ''}`
      const extension = this.extensionFromContentType(contentType) ?? this.extensionFromUrl(url)
      const fileName = `${key}${extension}`
      const filePath = `${this.cacheDir}/${fileName}`
      const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      try {
        await fs.write(file.fd, bytes)
      } finally {
        fs.closeSync(file)
      }
      const entry: ImageCacheIndexEntry = {
        url: url,
        fileName: fileName,
        size: bytes.byteLength,
        lastAccessMs: Date.now()
      }
      this.index[key] = entry
      await this.evictIfNeeded()
      await this.saveIndex()
      return filePath
    } finally {
      req.destroy()
    }
  }

  private async evictIfNeeded(): Promise<void> {
    let total = 0
    const keys = Object.keys(this.index)
    for (let i = 0; i < keys.length; i++) {
      total += this.index[keys[i]].size
    }
    if (total <= ImageCacheService.MAX_CACHE_BYTES) {
      return
    }
    const sorted: ImageCacheSortItem[] = keys
      .map((key: string): ImageCacheSortItem => {
        const item: ImageCacheSortItem = { key: key, entry: this.index[key] }
        return item
      })
      .sort((a: ImageCacheSortItem, b: ImageCacheSortItem) => a.entry.lastAccessMs - b.entry.lastAccessMs)
    for (let i = 0; i < sorted.length; i++) {
      if (total <= ImageCacheService.MAX_CACHE_BYTES) {
        break
      }
      total -= sorted[i].entry.size
      await this.removeEntry(sorted[i].key, sorted[i].entry)
    }
  }

  private async removeEntry(key: string, entry: ImageCacheIndexEntry): Promise<void> {
    const nextIndex: Record<string, ImageCacheIndexEntry> = {}
    const allKeys = Object.keys(this.index)
    for (let i = 0; i < allKeys.length; i++) {
      const k = allKeys[i]
      if (k !== key) {
        nextIndex[k] = this.index[k]
      }
    }
    this.index = nextIndex
    const filePath = `${this.cacheDir}/${entry.fileName}`
    try {
      if (fs.accessSync(filePath)) {
        fs.unlinkSync(filePath)
      }
    } catch (error) {
      Logger.warn('ImageCacheService', `removeEntry failed: ${JSON.stringify(error)}`)
    }
  }

  private async cacheKey(url: string): Promise<string> {
    const md = cryptoFramework.createMd('SHA256')
    await md.update({ data: this.textEncoder.encodeInto(url) })
    const digest = await md.digest()
    const bytes = new Uint8Array(digest.data)
    let hex = ''
    for (let i = 0; i < bytes.length; i++) {
      hex += bytes[i].toString(16).padStart(2, '0')
    }
    return hex
  }

  private extensionFromContentType(contentType: string): string | null {
    const lower = contentType.toLowerCase()
    if (lower.includes('jpeg') || lower.includes('jpg')) {
      return '.jpg'
    }
    if (lower.includes('png')) {
      return '.png'
    }
    if (lower.includes('gif')) {
      return '.gif'
    }
    if (lower.includes('webp')) {
      return '.webp'
    }
    if (lower.includes('bmp')) {
      return '.bmp'
    }
    if (lower.includes('svg')) {
      return '.svg'
    }
    return null
  }

  private extensionFromUrl(url: string): string {
    const lower = url.toLowerCase()
    const exts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg']
    for (let i = 0; i < exts.length; i++) {
      const ext = exts[i]
      if (lower.endsWith(ext)) {
        return ext === '.jpeg' ? '.jpg' : ext
      }
    }
    return '.img'
  }
}

function FileServiceFileExists(filePath: string): boolean {
  try {
    return fs.accessSync(filePath)
  } catch (_) {
    return false
  }
}
