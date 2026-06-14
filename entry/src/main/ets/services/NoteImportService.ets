import picker from '@ohos.file.picker'
import { fileUri } from '@kit.CoreFileKit'
import fs from '@ohos.file.fs'
import type common from '@ohos.app.ability.common'
import util from '@ohos.util'
import { Logger } from '../common/utils/Logger'
import { HtmlToMarkdown } from '../common/utils/HtmlToMarkdown'
import { DocxReader } from '../common/utils/DocxReader'
import { ZipReader, ZipEntry } from '../common/utils/ZipReader'
import { NoteRepository } from './NoteRepository'

/** 与 Flutter `NoteImportResult` 字段对齐：成功数 / 名称 / 失败 / 跳过。 */
export class NoteImportResult {
  importedCount: number = 0
  importedNames: string[] = []
  failedFiles: string[] = []
  skippedFiles: string[] = []
}

/**
 * 从本地文件导入 md / html / docx / 图片为新笔记（与 Flutter `NoteImportService` 行为对齐）。
 * - 文件选择：`picker.DocumentViewPicker`，允许 docx / html / md / txt / 常见图片。
 * - 解析分发：按扩展名走 Markdown / TXT / HTML / DOCX / Image 五个分支。
 * - 图片重定向：相对路径 / data URI 都会被复制到 `${ctx.filesDir}/qingyu-note-image/{时间戳_随机}.{ext}`，
 *   笔记内引用统一替换为 `qingyu-note-image/...`，与 `NoteStateCodec.extractImageRefs` 正则匹配。
 * - 失败语义：旧版 .doc / 解析失败 → failedFiles；不支持的扩展名 → skippedFiles。
 *
 * 该服务在 UI 前台同步串行执行（与 Flutter `_importNotesFromFiles` 一致），调用方负责按钮防重入。
 */
export class NoteImportService {
  private static instance: NoteImportService = new NoteImportService()
  private static readonly IMAGES_DIR_NAME: string = 'qingyu-note-image'
  private static readonly FILE_SUFFIX_FILTERS: Array<string> = [
    '文档|md,markdown,txt,html,htm,docx,doc',
    '图片|png,jpg,jpeg,gif,webp,bmp'
  ]
  private static readonly MAX_SELECT_NUMBER: number = 50
  private static readonly ALLOWED_IMAGE_EXTS: Set<string> = new Set<string>([
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'
  ])

  static getInstance(): NoteImportService {
    return NoteImportService.instance
  }

  /**
   * 拉起 DocumentViewPicker 让用户选择文件，自动转成本地路径后串行导入。
   * picker 未选择时返回空的 NoteImportResult。
   */
  async pickAndImport(context: common.UIAbilityContext): Promise<NoteImportResult> {
    const result = new NoteImportResult()
    const uris = await NoteImportService.pickUris(context)
    if (uris.length === 0) {
      return result
    }
    return this.importFromUris(uris, context)
  }

  /** 从 URI 列表串行导入；context 用于拿到 filesDir 创建图片目录。 */
  async importFromUris(uris: string[], context: common.UIAbilityContext): Promise<NoteImportResult> {
    const result = new NoteImportResult()
    if (uris.length === 0) {
      return result
    }
    let imagesDir: string | null = null
    try {
      imagesDir = await this.ensureImagesDir(context)
    } catch (error) {
      Logger.warn('NoteImportService', `ensureImagesDir failed: ${JSON.stringify(error)}`)
    }
    for (const uri of uris) {
      try {
        const displayName = this.displayNameFromUri(uri)
        const ext = NoteImportService.extensionOf(displayName).toLowerCase()
        if (ext === 'md' || ext === 'markdown' || ext === 'txt') {
          await this.importMarkdownLike(uri, displayName, imagesDir, result)
        } else if (ext === 'html' || ext === 'htm') {
          await this.importHtml(uri, displayName, imagesDir, result)
        } else if (ext === 'docx') {
          await this.importDocx(uri, displayName, imagesDir, result)
        } else if (ext === 'doc') {
          result.failedFiles.push(`${displayName}：暂不支持旧版 .doc，请另存为 .docx 后重试`)
        } else if (NoteImportService.ALLOWED_IMAGE_EXTS.has(ext)) {
          if (imagesDir === null) {
            result.failedFiles.push(`${displayName}：图片目录不可用`)
            continue
          }
          await this.importImage(uri, displayName, ext, imagesDir, result)
        } else {
          result.skippedFiles.push(displayName)
        }
      } catch (error) {
        Logger.warn('NoteImportService', `import ${uri} failed: ${JSON.stringify(error)}`)
        const displayName = this.displayNameFromUri(uri)
        result.failedFiles.push(`${displayName}：导入失败`)
      }
    }
    return result
  }

  // ---------- 解析分支 ----------

  private async importMarkdownLike(
    uri: string,
    displayName: string,
    imagesDir: string | null,
    result: NoteImportResult
  ): Promise<void> {
    if (!NoteImportService.fileExists(uri)) {
      result.skippedFiles.push(displayName)
      return
    }
    const raw = await fs.readText(uri, { encoding: 'utf-8' })
    const baseDir = this.dirnameFromUri(uri)
    const markdown = imagesDir !== null
      ? await this.relocateMarkdownImages(raw, baseDir, imagesDir)
      : raw
    await this.createImportedNote(this.titleFromDisplayName(displayName), markdown, displayName, result)
  }

  private async importHtml(
    uri: string,
    displayName: string,
    imagesDir: string | null,
    result: NoteImportResult
  ): Promise<void> {
    if (!NoteImportService.fileExists(uri)) {
      result.skippedFiles.push(displayName)
      return
    }
    const html = await fs.readText(uri, { encoding: 'utf-8' })
    const baseDir = this.dirnameFromUri(uri)
    const preparedHtml = imagesDir !== null
      ? this.stripDataUriImagesFromHtml(html, imagesDir)
      : html
    let markdown = HtmlToMarkdown.convert(preparedHtml)
    if (imagesDir !== null) {
      markdown = await this.relocateMarkdownImages(markdown, baseDir, imagesDir)
    }
    await this.createImportedNote(this.titleFromDisplayName(displayName), markdown, displayName, result)
  }

  private async importDocx(
    uri: string,
    displayName: string,
    imagesDir: string | null,
    result: NoteImportResult
  ): Promise<void> {
    if (!NoteImportService.fileExists(uri)) {
      result.skippedFiles.push(displayName)
      return
    }
    const buffer = NoteImportService.readUriBytes(uri)
    const docx = DocxReader.extract(buffer)
    const mediaFiles: Map<string, string> = new Map()
    if (imagesDir !== null) {
      docx.mediaByRid.forEach((fileName: string, rid: string) => {
        const ext = NoteImportService.extensionOf(fileName).toLowerCase()
        if (ext.length === 0 || !NoteImportService.ALLOWED_IMAGE_EXTS.has(ext)) {
          return
        }
        try {
          const bytes = NoteImportService.findMediaBytes(buffer, fileName)
          if (bytes === null) {
            return
          }
          const relPath = this.writeImageBytesSync(bytes, '.' + ext, imagesDir)
          mediaFiles.set(rid, relPath)
        } catch (error) {
          Logger.warn('NoteImportService', `docx media ${fileName} extract failed: ${JSON.stringify(error)}`)
        }
      })
    }
    let html = docx.html
    // 把 [[docx-img:rid]] 占位符换成 <img src="...">
    mediaFiles.forEach((relPath: string, rid: string) => {
      const replacement = `<img src="${relPath}">`
      html = html.split(`[[docx-img:${rid}]]`).join(replacement)
    })
    // 残余占位符清理（无媒体的 rid）
    html = html.replace(/\[\[docx-img:[^\]]+\]\]/g, '')
    let markdown = HtmlToMarkdown.convert(html)
    if (imagesDir !== null) {
      markdown = await this.relocateMarkdownImages(markdown, '', imagesDir)
    }
    await this.createImportedNote(this.titleFromDisplayName(displayName), markdown, displayName, result)
  }

  private async importImage(
    uri: string,
    displayName: string,
    ext: string,
    imagesDir: string,
    result: NoteImportResult
  ): Promise<void> {
    if (!NoteImportService.fileExists(uri)) {
      result.skippedFiles.push(displayName)
      return
    }
    const bytes = NoteImportService.readUriBytes(uri)
    const relPath = await this.writeImageBytes(bytes, '.' + ext, imagesDir)
    const content = `![图片](${relPath})`
    await this.createImportedNote(this.titleFromDisplayName(displayName), content, displayName, result)
  }

  private async createImportedNote(
    title: string,
    content: string,
    displayName: string,
    result: NoteImportResult
  ): Promise<void> {
    await NoteRepository.getInstance().createNote({
      title,
      content,
      tags: [],
      skipTitleAutoFill: true
    })
    result.importedCount += 1
    result.importedNames.push(displayName)
  }

  // ---------- markdown / html 图片重定向 ----------

  private static readonly MARKDOWN_IMG_REGEX: RegExp = /!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g
  private static readonly HTML_DATA_URI_IMG_REGEX: RegExp = /<img\s+([^>]*?)\ssrc\s*=\s*(["'])(data:image\/([^;]+);base64,([^"']+))\2([^>]*)>/gi

  /** 重写 markdown 内 `![](src)` 引用的本地图片路径，data URI / 远程 URL 跳过。 */
  async relocateMarkdownImages(
    markdown: string,
    baseDir: string,
    imagesDir: string
  ): Promise<string> {
    if (markdown.length === 0) {
      return markdown
    }
    const matches: RegExpExecArray[] = []
    NoteImportService.MARKDOWN_IMG_REGEX.lastIndex = 0
    let m: RegExpExecArray | null = NoteImportService.MARKDOWN_IMG_REGEX.exec(markdown)
    while (m !== null) {
      matches.push(m)
      m = NoteImportService.MARKDOWN_IMG_REGEX.exec(markdown)
    }
    if (matches.length === 0) {
      return markdown
    }
    let output = markdown
    for (let i = matches.length - 1; i >= 0; i -= 1) {
      const match = matches[i]
      const alt = match[1] ?? ''
      const src = match[2] ?? ''
      if (src.length === 0) {
        continue
      }
      if (this.isRemoteImageUrl(src)) {
        continue
      }
      if (src.startsWith(NoteImportService.IMAGES_DIR_NAME + '/')) {
        continue
      }
      const relocated = await this.relocateImageSrc(src, baseDir, imagesDir)
      if (relocated === null || relocated === src) {
        continue
      }
      const replacement = `![${alt}](${relocated})`
      output = output.substring(0, match.index) + replacement + output.substring(match.index + match[0].length)
    }
    return output
  }

  private async relocateImageSrc(
    src: string,
    baseDir: string,
    imagesDir: string
  ): Promise<string | null> {
    const trimmed = src.trim()
    // data URI
    if (trimmed.toLowerCase().startsWith('data:image/')) {
      const match = /^data:image\/([^;]+);base64,(.+)$/i.exec(trimmed)
      if (match === null) {
        return null
      }
      const subtype = match[1] ?? 'png'
      const b64 = (match[2] ?? '').replace(/\s/g, '')
      try {
        const helper = new util.Base64Helper()
        const bytes = helper.decodeSync(b64)
        return await this.writeImageBytes(bytes, '.' + subtype, imagesDir)
      } catch (error) {
        Logger.warn('NoteImportService', `data URI decode failed: ${JSON.stringify(error)}`)
        return null
      }
    }
    // file:// URI
    if (trimmed.startsWith('file://')) {
      const path = NoteImportService.uriToPath(trimmed)
      if (path === null || !NoteImportService.fileExists(path)) {
        return null
      }
      const ext = NoteImportService.extensionOf(this.basenameFromPath(path))
      if (ext.length === 0) {
        return null
      }
      const bytes = NoteImportService.readUriBytes(path)
      return await this.writeImageBytes(bytes, '.' + ext, imagesDir)
    }
    // 绝对路径
    if (trimmed.startsWith('/')) {
      if (!NoteImportService.fileExists(trimmed)) {
        return null
      }
      const ext = NoteImportService.extensionOf(this.basenameFromPath(trimmed))
      if (ext.length === 0) {
        return null
      }
      const bytes = NoteImportService.readUriBytes(trimmed)
      return await this.writeImageBytes(bytes, '.' + ext, imagesDir)
    }
    // 相对路径：基于 baseDir 解析
    const normalized = trimmed.replace(/\\/g, '/')
    if (baseDir.length === 0) {
      return null
    }
    const joined = baseDir.endsWith('/') ? baseDir + normalized : baseDir + '/' + normalized
    if (!NoteImportService.fileExists(joined)) {
      return null
    }
    const ext = NoteImportService.extensionOf(this.basenameFromPath(joined))
    if (ext.length === 0) {
      return null
    }
    const bytes = NoteImportService.readUriBytes(joined)
    return await this.writeImageBytes(bytes, '.' + ext, imagesDir)
  }

  /** 把 HTML 中 data URI 图片落盘，并把 `<img src="data:...">` 改成相对路径。 */
  private stripDataUriImagesFromHtml(html: string, imagesDir: string): string {
    if (html.length === 0) {
      return html
    }
    const matches: RegExpExecArray[] = []
    NoteImportService.HTML_DATA_URI_IMG_REGEX.lastIndex = 0
    let m: RegExpExecArray | null = NoteImportService.HTML_DATA_URI_IMG_REGEX.exec(html)
    while (m !== null) {
      matches.push(m)
      m = NoteImportService.HTML_DATA_URI_IMG_REGEX.exec(html)
    }
    if (matches.length === 0) {
      return html
    }
    let output = html
    for (let i = matches.length - 1; i >= 0; i -= 1) {
      const match = matches[i]
      const before = match[1] ?? ''
      const quote = match[2] ?? '"'
      const subtype = match[4] ?? 'png'
      const b64 = (match[5] ?? '').replace(/\s/g, '')
      const after = match[6] ?? ''
      try {
        const helper = new util.Base64Helper()
        const bytes = helper.decodeSync(b64)
        const relPath = this.writeImageBytesSync(bytes, '.' + subtype, imagesDir)
        const newTag = `<img${before} src=${quote}${relPath}${quote}${after}>`
        output = output.substring(0, match.index) + newTag + output.substring(match.index + match[0].length)
      } catch (error) {
        Logger.warn('NoteImportService', `html data URI decode failed: ${JSON.stringify(error)}`)
      }
    }
    return output
  }

  // ---------- 图片目录 + 写入 ----------

  private async ensureImagesDir(context: common.UIAbilityContext): Promise<string> {
    const baseDir = context.filesDir ?? ''
    const dir = baseDir + '/' + NoteImportService.IMAGES_DIR_NAME
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true)
    }
    return dir
  }

  private async writeImageBytes(
    bytes: Uint8Array,
    ext: string,
    imagesDir: string
  ): Promise<string> {
    const fileName = this.randomImageFileName(ext)
    const path = imagesDir + '/' + fileName
    NoteImportService.writeFileBytes(path, bytes)
    return NoteImportService.IMAGES_DIR_NAME + '/' + fileName
  }

  /** 同步版本（用于 html 解析里的链式替换）。 */
  private writeImageBytesSync(bytes: Uint8Array, ext: string, imagesDir: string): string {
    const fileName = this.randomImageFileName(ext)
    const path = imagesDir + '/' + fileName
    NoteImportService.writeFileBytes(path, bytes)
    return NoteImportService.IMAGES_DIR_NAME + '/' + fileName
  }

  private randomImageFileName(ext: string): string {
    const safeExt = ext.startsWith('.') ? ext : '.' + ext
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789'
    let randomPart = ''
    for (let i = 0; i < 6; i += 1) {
      randomPart += alphabet.charAt(Math.floor(Math.random() * alphabet.length))
    }
    return `${Date.now()}_${randomPart}${safeExt}`
  }

  // ---------- docx 内部 zip 重复读取（仅取 media） ----------

  private static findMediaBytes(buffer: Uint8Array, mediaName: string): Uint8Array | null {
    try {
      const entries: ZipEntry[] = ZipReader.readEntries(buffer)
      const entry: ZipEntry | null = ZipReader.findEntry(entries, 'word/media/' + mediaName)
      return entry === null ? null : entry.data
    } catch (error) {
      Logger.warn('NoteImportService', `findMediaBytes failed: ${JSON.stringify(error)}`)
      return null
    }
  }

  // ---------- URI 工具 ----------

  private static async pickUris(context: common.UIAbilityContext): Promise<string[]> {
    try {
      const documentPicker = new picker.DocumentViewPicker(context)
      const options = new picker.DocumentSelectOptions()
      options.fileSuffixFilters = NoteImportService.FILE_SUFFIX_FILTERS
      options.maxSelectNumber = NoteImportService.MAX_SELECT_NUMBER
      const uris: string[] = await documentPicker.select(options)
      return Array.isArray(uris) ? uris : []
    } catch (error) {
      Logger.warn('NoteImportService', `DocumentViewPicker select failed: ${JSON.stringify(error)}`)
      return []
    }
  }

  private displayNameFromUri(uri: string): string {
    try {
      const u = new fileUri.FileUri(uri)
      return u.name
    } catch (_) {
      return this.basenameFromPath(uri)
    }
  }

  private dirnameFromUri(uri: string): string {
    const path = NoteImportService.uriToPath(uri)
    if (path === null) {
      return ''
    }
    const idx = path.lastIndexOf('/')
    return idx < 0 ? '' : path.substring(0, idx)
  }

  private titleFromDisplayName(displayName: string): string {
    const base = displayName.replace(/\.[^.]+$/, '').trim()
    return base.length === 0 ? '未命名笔记' : base
  }

  private isRemoteImageUrl(src: string): boolean {
    const lower = src.toLowerCase()
    return lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('//')
  }

  private basenameFromPath(path: string): string {
    const idx = path.lastIndexOf('/')
    return idx < 0 ? path : path.substring(idx + 1)
  }

  // ---------- 静态工具 ----------

  private static extensionOf(name: string): string {
    const lower = name.toLowerCase()
    const slash = Math.max(lower.lastIndexOf('/'), lower.lastIndexOf('\\'))
    const base = slash >= 0 ? lower.substring(slash + 1) : lower
    const dot = base.lastIndexOf('.')
    if (dot <= 0) {
      return ''
    }
    return base.substring(dot + 1)
  }

  private static fileExists(uri: string): boolean {
    try {
      return fs.accessSync(uri)
    } catch (_) {
      return false
    }
  }

  private static uriToPath(uri: string): string | null {
    try {
      if (!uri.startsWith('file://')) {
        return uri
      }
      const u = new fileUri.FileUri(uri)
      return u.path
    } catch (_) {
      return null
    }
  }

  private static readUriBytes(uri: string): Uint8Array {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY)
    try {
      const stat = fs.statSync(uri)
      const buffer = new ArrayBuffer(stat.size)
      fs.readSync(file.fd, buffer)
      return new Uint8Array(buffer)
    } finally {
      try {
        fs.closeSync(file)
      } catch (_) {
      }
    }
  }

  private static writeFileBytes(path: string, bytes: Uint8Array): void {
    const dir = path.substring(0, path.lastIndexOf('/'))
    if (dir.length > 0 && !fs.accessSync(dir)) {
      fs.mkdirSync(dir, true)
    }
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    try {
      fs.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength))
    } finally {
      try {
        fs.closeSync(file)
      } catch (_) {
      }
    }
  }
}
