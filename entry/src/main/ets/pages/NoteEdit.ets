import type { MarkdownBlock } from '../common/utils/MarkdownUtils'
import { MarkdownUtils } from '../common/utils/MarkdownUtils'
import type { Note } from '../common/model/Note'
import { NoteRepository } from '../services/NoteRepository'
import { PreferencesService } from '../services/PreferencesService'
import { AppContextHolder } from '../services/AppContextHolder'
import { TimeUtils } from '../common/utils/TimeUtils'
import { Logger } from '../common/utils/Logger'
import componentSnapshot from '@ohos.arkui.componentSnapshot'
import { image } from '@kit.ImageKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import picker from '@ohos.file.picker'
import { NoteEditEditorPane } from './NoteEditEditorPane'
import { NoteEditPreviewPane } from './NoteEditPreviewPane'
import { NoteEditMarkdownBlocksView } from './NoteEditMarkdownBlocksView'

interface NoteEditParams {
  noteId?: string
  /** 从首页点入且正文非空时置为 true，与 Flutter `openWithPreview` 对齐。 */
  openWithPreview?: boolean
}

/** 仅当标题和正文至少有一个非空时为 true（与 Flutter `_hasEditorTitleOrBody` 对齐）。 */
function hasEditorTitleOrBody(title: string, content: string): boolean {
  return title.trim().length > 0 || content.trim().length > 0
}

@Entry
@Component
struct NoteEdit {
  @State noteId: string = ''
  @State title: string = ''
  @State content: string = ''
  @State saveStatus: string = '未保存'
  @State previewMode: string = 'split'
  @State pageWidth: number = 360
  @State lastSavedAt: number = 0
  @State previewBlocksState: MarkdownBlock[] = []
  @State previewSource: string = ''
  @State noteTags: string[] = []
  @State tagPool: string[] = []
  @State tagMenuVisible: boolean = false
  @State tagBarX: number = 0
  @State tagBarY: number = 0
  @State tagBarInitialized: boolean = false
  @State tagBarWidth: number = 120
  @State tagBarHeight: number = 32
  @State lastPanOffsetX: number = 0
  @State lastPanOffsetY: number = 0
  private textAreaController: TextAreaController = new TextAreaController()
  private shareScroller: Scroller = new Scroller()
  /** 分享卡片内 Column 总高度（vp），用于长截图分段滚动。 */
  @State shareExportColumnVp: number = 0
  /**
   * 长图生成时为 true：将分享用 Scroll 摆在屏内透明绘制。
   * 置于屏幕外（如 x=-8000）时部分机型上滚动偏移不生效，componentSnapshot 反复截到同一帧，拼接重复。
   */
  @State shareExportCaptureOnScreen: boolean = false
  private saveTimer: number = -1
  private previewTimer: number = -1
  private previewDirty: boolean = true
  private preferPreviewOnOpen: boolean = false
  private shareCardHeight: number = 0
  /** 缓存 ability `filesDir`，避免预览中多张图片重复 `getContext`。 */
  private filesDirCache: string = ''
  private static readonly SHARE_CARD_ID: string = 'note_share_export_card'
  private static readonly SHARE_SLOGAN: string = '记录本身，就是意义。   ——轻羽云笔记'
  private static readonly SHARE_INTRO: string =
    '轻羽云笔记是一款云笔记应用，同时支持手机与电脑全平台，无论你正在使用哪台设备，笔记都在手边。'

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext
    this.filesDirCache = ctx.filesDir
    const params = this.getUIContext().getRouter().getParams() as NoteEditParams
    this.noteId = params?.noteId ?? ''
    this.preferPreviewOnOpen = params?.openWithPreview === true
    void this.loadNote()
  }

  private async ensurePreferencesInitialized(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
  }

  private async refreshTagPool(): Promise<void> {
    await this.ensurePreferencesInitialized()
    const stored = await PreferencesService.getInstance().getNoteTags()
    const allNotes = await NoteRepository.getInstance().listNotes()
    const fromNotes: string[] = []
    for (const n of allNotes) {
      fromNotes.push(...n.tags)
    }
    this.tagPool = this.normalizeTags([...fromNotes, ...stored, ...this.noteTags])
  }

  private normalizeTags(tags: string[]): string[] {
    const seen: Set<string> = new Set()
    const normalized: string[] = []
    for (const rawTag of tags) {
      const tag = `${rawTag ?? ''}`.trim()
      if (tag.length === 0 || seen.has(tag)) {
        continue
      }
      seen.add(tag)
      normalized.push(tag)
    }
    normalized.sort((left: string, right: string) => left.localeCompare(right, 'zh-Hans-CN'))
    return normalized
  }

  private async onTagChecked(tag: string, selected: boolean): Promise<void> {
    const next: string[] = [...this.noteTags]
    if (selected) {
      if (!next.includes(tag)) {
        next.push(tag)
      }
    } else {
      const idx = next.indexOf(tag)
      if (idx >= 0) {
        next.splice(idx, 1)
      }
    }
    this.noteTags = this.normalizeTags(next)
    if (this.noteId.length === 0) {
      this.scheduleSave()
      return
    }
    await this.persistTagsToRepository()
  }

  private async persistTagsToRepository(): Promise<void> {
    try {
      const note = await NoteRepository.getInstance().saveDraft(this.noteId, {
        title: this.title,
        content: this.content,
        tags: this.noteTags
      })
      this.lastSavedAt = note.updatedAt
      this.saveStatus = '已保存'
    } catch (error) {
      this.saveStatus = '保存失败'
      Logger.error('NoteEdit', `persistTagsToRepository failed: ${JSON.stringify(error)}`)
    }
  }

  private async openTagManage(): Promise<void> {
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/TagManage',
        params: {}
      })
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showPreviewMessage('打开标签管理失败')
    }
  }

  aboutToDisappear(): void {
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer)
      this.saveTimer = -1
    }
    if (this.previewTimer !== -1) {
      clearTimeout(this.previewTimer)
      this.previewTimer = -1
    }
  }

  private async loadNote(): Promise<void> {
    await NoteRepository.getInstance().init()
    if (!this.noteId) {
      this.previewMode = this.pageWidth >= 600 ? 'split' : 'edit'
      this.preparePreviewForCurrentMode(this.content)
      return
    }
    const note = await NoteRepository.getInstance().getNote(this.noteId)
    if (!note) {
      this.preparePreviewForCurrentMode(this.content)
      return
    }
    this.title = note.title
    this.content = note.content
    this.lastSavedAt = note.updatedAt
    this.saveStatus = '已保存'
    this.noteTags = this.normalizeTags(note.tags)
    const hasBody = note.content.trim().length > 0
    if (this.preferPreviewOnOpen && hasBody) {
      this.previewMode = this.isSplitMode() ? 'split' : 'preview'
    } else {
      this.previewMode = this.isSplitMode() ? 'split' : 'edit'
    }
    this.preparePreviewForCurrentMode(note.content)
  }

  private scheduleSave(): void {
    if (this.title.trim().length === 0 && this.content.trim().length === 0) {
      if (this.saveTimer !== -1) {
        clearTimeout(this.saveTimer)
        this.saveTimer = -1
      }
      this.saveStatus = '未保存'
      return
    }
    this.saveStatus = '保存中...'
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer)
    }
    this.saveTimer = setTimeout(() => {
      void this.handleAutoSave()
    }, 2000)
  }

  private schedulePreviewRefresh(): void {
    if (!this.shouldRenderPreview()) {
      this.previewDirty = true
      if (this.previewTimer !== -1) {
        clearTimeout(this.previewTimer)
        this.previewTimer = -1
      }
      return
    }
    if (this.previewTimer !== -1) {
      clearTimeout(this.previewTimer)
    }
    this.previewDirty = true
    this.previewTimer = setTimeout(() => {
      this.previewTimer = -1
      this.refreshPreviewBlocks(this.content)
    }, 260)
  }

  private refreshPreviewBlocks(content: string): void {
    if (!this.previewDirty && this.previewSource === content && this.previewBlocksState.length > 0) {
      return
    }
    this.previewSource = content
    this.previewBlocksState = MarkdownUtils.parseBlocks(content)
    this.previewDirty = false
  }

  private async handleAutoSave(): Promise<void> {
    try {
      Logger.info('NoteEdit',
        `handleAutoSave start: noteId=${this.noteId || 'new'}, titleLength=${this.title.length}, contentLength=${this.content.length}`)
      if (this.title.trim().length === 0 && this.content.trim().length === 0) {
        this.saveStatus = '未保存'
        Logger.info('NoteEdit', 'handleAutoSave skipped: title and content are empty')
        return
      }
      let note: Note | null = null
      if (!this.noteId) {
        note = await NoteRepository.getInstance().createNote({
          title: this.title,
          content: this.content,
          tags: this.normalizeTags(this.noteTags)
        })
        this.noteId = note.id
      } else {
        note = await NoteRepository.getInstance().saveDraft(this.noteId, {
          title: this.title,
          content: this.content,
          tags: this.normalizeTags(this.noteTags)
        })
      }
      this.title = note.title
      this.noteTags = this.normalizeTags(note.tags)
      this.lastSavedAt = note.updatedAt
      this.saveStatus = '已保存'
      Logger.info('NoteEdit',
        `handleAutoSave success: noteId=${this.noteId}, titleLength=${this.title.length}, contentLength=${this.content.length}`)
    } catch (error) {
      this.saveStatus = '保存失败'
      Logger.error('NoteEdit', `handleAutoSave failed: ${JSON.stringify(error)}`)
      console.error(JSON.stringify(error))
    }
  }

  private async handleBack(): Promise<void> {
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer)
      this.saveTimer = -1
    }
    // Let the latest input event flush into bound state before saving.
    await new Promise<void>((resolve: () => void) => setTimeout(() => resolve(), 0))
    await this.handleAutoSave()
    this.getUIContext().getRouter().back()
  }

  private isSplitMode(): boolean {
    return this.pageWidth >= 600
  }

  /** 顶部保存状态 + 预览/编辑模式（与 Flutter `_saveStatusDisplay` 对齐）；中间为「空格减号空格」。 */
  private saveStatusDisplay(): string {
    const modeLabel = this.previewMode === 'preview' ? '预览模式' : '编辑模式'
    return `${this.saveStatus} - ${modeLabel}`
  }

  private switchMode(mode: string): void {
    if (this.previewMode === mode) {
      if (mode === 'preview') {
        this.preparePreviewForCurrentMode(this.content, true)
      }
      return
    }
    this.previewMode = mode
    if (mode === 'preview') {
      this.preparePreviewForCurrentMode(this.content, true)
    }
  }

  private shouldRenderPreview(): boolean {
    return this.isSplitMode() || this.previewMode === 'preview'
  }

  private preparePreviewForCurrentMode(content: string, forceRefresh: boolean = false): void {
    if (!this.shouldRenderPreview() && !forceRefresh) {
      this.previewDirty = true
      return
    }
    if (forceRefresh) {
      this.previewDirty = true
    }
    this.refreshPreviewBlocks(content)
  }

  private showPreviewMessage(message: string): void {
    if (message.trim().length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message,
        duration: 1600
      })
    } catch (error) {
      console.error(`showToast failed: ${JSON.stringify(error)}`)
    }
  }

  private resolveImageSrc(src: string): string {
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return src
    }
    if (src.startsWith('file://')) {
      return src
    }
    if (src.startsWith('/')) {
      return fileUri.getUriFromPath(src)
    }
    const base =
      this.filesDirCache.length > 0 ? this.filesDirCache : (getContext(this) as common.UIAbilityContext).filesDir
    const absPath = `${base}/${src}`
    return fileUri.getUriFromPath(absPath)
  }

  private async insertImage(): Promise<void> {
    try {
      const photoSelectOptions: picker.PhotoSelectOptions = new picker.PhotoSelectOptions()
      photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE
      photoSelectOptions.maxSelectNumber = 1
      const photoPicker: picker.PhotoViewPicker = new picker.PhotoViewPicker()
      const result: picker.PhotoSelectResult = await photoPicker.select(photoSelectOptions)
      const uri: string = result.photoUris[0] ?? ''
      if (uri.length === 0) {
        return
      }
      const base =
        this.filesDirCache.length > 0 ? this.filesDirCache : (getContext(this) as common.UIAbilityContext).filesDir
      const imagesDir = `${base}/qingyu-note-image`
      if (!fileIo.accessSync(imagesDir)) {
        fileIo.mkdirSync(imagesDir, true)
      }
      const randomStr = Math.random().toString(36).slice(2, 8)
      const ext = '.png'
      const fileName = `${Date.now()}_${randomStr}${ext}`
      const destPath = `${imagesDir}/${fileName}`
      const srcFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const destFile = fileIo.openSync(destPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      await fileIo.copyFile(srcFile.fd, destFile.fd)
      fileIo.closeSync(srcFile)
      fileIo.closeSync(destFile)
      const relativePath = `qingyu-note-image/${fileName}`
      const imageMarkdown = `![图片](${relativePath})`
      const text = this.content
      if (text.length > 0 && !text.endsWith('\n')) {
        this.content = `${text}\n${imageMarkdown}\n`
      } else {
        this.content = `${text}${imageMarkdown}\n`
      }
      this.textAreaController.caretPosition(this.content.length)
      this.scheduleSave()
      if (this.shouldRenderPreview()) {
        this.schedulePreviewRefresh()
      } else {
        this.previewDirty = true
      }
    } catch (error) {
      Logger.error('NoteEdit', `insertImage failed: ${JSON.stringify(error)}`)
      this.showPreviewMessage('插入图片失败')
    }
  }

  private async saveCachePngToGallery(cachePath: string): Promise<boolean> {
    const context = getContext(this) as common.UIAbilityContext
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context)
      const srcFileUris: Array<string> = [fileUri.getUriFromPath(cachePath)]
      const photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [
        {
          title: `note_share_${Date.now()}`,
          fileNameExtension: 'png',
          photoType: photoAccessHelper.PhotoType.IMAGE,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT
        }
      ]
      const destUris: Array<string> = await helper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs)
      if (destUris.length === 0) {
        return false
      }
      const src = fileIo.openSync(cachePath, fileIo.OpenMode.READ_ONLY)
      const dest = await fileIo.open(destUris[0], fileIo.OpenMode.WRITE_ONLY)
      await fileIo.copyFile(src.fd, dest.fd)
      fileIo.closeSync(src)
      fileIo.closeSync(dest)
      return true
    } catch (error) {
      Logger.error('NoteEdit', `saveCachePngToGallery failed: ${JSON.stringify(error)}`)
      return false
    }
  }

  private async exportShareImageToCache(): Promise<string | null> {
    this.refreshPreviewBlocks(this.content)
    await new Promise<void>((resolve) => setTimeout(() => resolve(), 100))
    try {
      return await this.offlineSnapshotCapture()
    } catch (error) {
      Logger.error('NoteEdit', `exportShareImageToCache failed: ${JSON.stringify(error)}`)
      return null
    }
  }

  private async offlineSnapshotCapture(): Promise<string | null> {
    const context = getContext(this) as common.UIAbilityContext
    this.refreshPreviewBlocks(this.content)
    await new Promise<void>((resolve) => setTimeout(() => resolve(), 100))
    try {
      const pngBuf = await this.captureScrollingCardToImage()
      if (!pngBuf || pngBuf.byteLength === 0) {
        return null
      }
      const filePath: string = `${context.cacheDir}/note_share_${Date.now()}.png`
      const f: fileIo.File = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(f.fd, pngBuf)
      fileIo.closeSync(f)
      Logger.info('NoteEdit', `saved long image to ${filePath}, size: ${pngBuf.byteLength}`)
      return filePath
    } catch (err) {
      Logger.error('NoteEdit', `offlineSnapshotCapture failed: ${JSON.stringify(err)}`)
      return null
    }
  }

  private static delayMs(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms))
  }

  /**
   * 与单屏分享一致：先 ImagePacker(SDR) 再解码，使每张滚动截图的 PixelMap 与 PNG 编解码管线对齐，
   * 避免 RS 离屏截图直接 readPixels + 手工合并时的 HDR/通道解读与相册「正常图」不一致。
   */
  private async normalizeSliceViaSdrPngRoundTrip(pm: image.PixelMap): Promise<image.PixelMap | null> {
    const packer = image.createImagePacker()
    let inputReleased = false
    try {
      try {
        await pm.convertPixelFormat(image.PixelMapFormat.RGBA_8888)
      } catch (_) {
        // 部分 RS 截图 convert 失败仍可走 packing
      }
      const pngBuf = await packer.packing(pm, {
        format: 'image/png',
        quality: 100,
        desiredDynamicRange: image.PackingDynamicRange.SDR
      })
      await pm.release()
      inputReleased = true
      const src = image.createImageSource(pngBuf)
      try {
        return await src.createPixelMap({
          desiredDynamicRange: image.DecodingDynamicRange.SDR,
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888
        })
      } finally {
        await src.release()
      }
    } catch (e) {
      Logger.error('NoteEdit', `normalizeSliceViaSdrPngRoundTrip failed: ${JSON.stringify(e)}`)
      if (!inputReleased) {
        try {
          await pm.release()
        } catch (_) {
        }
      }
      return null
    }
  }

  /** 全部转为「SDR PNG 往返」后的 PixelMap；失败时释放已分配资源与剩余原始切片。 */
  private async normalizeAllSlicesForMerge(slices: image.PixelMap[]): Promise<image.PixelMap[] | null> {
    const out: image.PixelMap[] = []
    for (let i = 0; i < slices.length; i++) {
      const n = await this.normalizeSliceViaSdrPngRoundTrip(slices[i])
      if (!n) {
        for (const p of out) {
          await p.release()
        }
        for (let j = i + 1; j < slices.length; j++) {
          await slices[j].release()
        }
        return null
      }
      out.push(n)
    }
    return out
  }

  private async packPixelMapToPng(pm: image.PixelMap): Promise<ArrayBuffer | null> {
    const packer = image.createImagePacker()
    try {
      try {
        await pm.convertPixelFormat(image.PixelMapFormat.RGBA_8888)
      } catch (_) {
        // 部分 PixelMap 与 convert 不兼容时仍可 packing
      }
      const buf = await packer.packing(pm, {
        format: 'image/png',
        quality: 100,
        desiredDynamicRange: image.PackingDynamicRange.SDR
      })
      await pm.release()
      return buf
    } catch (err) {
      Logger.error('NoteEdit', `packPixelMapToPng failed: ${JSON.stringify(err)}`)
      await pm.release()
      return null
    }
  }

  /**
   * 将多张纵向分段截图合并为一张 PixelMap。
   * - rowStepPx：单屏在物理像素上的高度上限，用于裁掉比视口「更高」的截图底部。
   * - sliceSkipTopPx：每张切片从像素矩阵顶部跳过的行数；除首张外一般为「视口高度 − 与上一张之间的滚动增量(px)」，
   *   用于去掉相邻截图在纵向的重叠（若滚动增量小于视口高度，下一张顶部会与上一张底部重复）。
   * - 调用方应在拼接前经 normalizeAllSlicesForMerge，使每张切片与单屏导出同源（SDR PNG 往返后的 RGBA）。
   * - readPixelsToBufferSync 在本机为 **BGRA** 字节序（与 readPixelsSync 的 RGBA 语义差一次 R/B 交换）。
   *   逐像素 **BGRA→RGBA** 写入合并缓冲，再以 **RGBA_8888** 建 PixelMap，与单屏 snapshot 直打包路径一致。
   *   仅用 BGRA 建 PixelMap 再 ImagePacker 仍可能偏色。
   */
  private async mergePixelMapsVertical(slices: image.PixelMap[], widthPx: number,
    totalHeightPx: number, rowStepPx: number, sliceSkipTopPx: number[]): Promise<image.PixelMap | null> {
    if (slices.length === 0 || totalHeightPx <= 0 || sliceSkipTopPx.length !== slices.length) {
      Logger.warn('NoteEdit',
        `mergePixelMapsVertical: bad args slices=${slices.length} totalH=${totalHeightPx} skipLen=${sliceSkipTopPx.length}`)
      return null
    }
    const headInfo = slices[0].getImageInfoSync()
    const headAlpha = headInfo.alphaType
    const mergeAlphaType =
      headAlpha === image.AlphaType.UNKNOWN ? image.AlphaType.PREMUL : headAlpha
    const mergeBufferPixelFormat = image.PixelMapFormat.RGBA_8888
    const rowBytes = widthPx * 4
    const dstBuf = new ArrayBuffer(rowBytes * totalHeightPx)
    const dstView = new Uint8Array(dstBuf)
    let dstRowTop = 0
    try {
      for (let s = 0; s < slices.length && dstRowTop < totalHeightPx; s++) {
        const pm = slices[s]
        const info = pm.getImageInfoSync()
        const srcStride = info.stride
        const srcH = info.size.height
        const srcBuf = new ArrayBuffer(pm.getPixelBytesNumber())
        pm.readPixelsToBufferSync(srcBuf)
        const srcView = new Uint8Array(srcBuf)
        let skipTop = Math.max(0, Math.floor(sliceSkipTopPx[s]))
        if (skipTop >= srcH) {
          Logger.warn('NoteEdit', `mergePixelMapsVertical: slice[${s}] skipped skipTop=${skipTop}>=srcH=${srcH}`)
          continue
        }
        const availAfterSkip = srcH - skipTop
        const cap = rowStepPx > 0 ? Math.min(availAfterSkip, rowStepPx) : availAfterSkip
        const rowsToCopy = Math.min(cap, totalHeightPx - dstRowTop)
        for (let r = 0; r < rowsToCopy; r++) {
          const srcRow = skipTop + r
          const srcLineStart = srcRow * srcStride
          const dstLineStart = (dstRowTop + r) * rowBytes
          if (srcLineStart + rowBytes > srcView.byteLength) {
            Logger.warn('NoteEdit',
              `mergePixelMapsVertical: slice[${s}] row=${r} src overflow srcLineStart=${srcLineStart}`)
            break
          }
          for (let x = 0; x < widthPx; x++) {
            const si = srcLineStart + x * 4
            const di = dstLineStart + x * 4
            dstView[di] = srcView[si + 2]
            dstView[di + 1] = srcView[si + 1]
            dstView[di + 2] = srcView[si]
            dstView[di + 3] = srcView[si + 3]
          }
        }
        dstRowTop += rowsToCopy
      }
      const actualHeight = Math.max(1, Math.min(dstRowTop, totalHeightPx))
      const trimmedBuf =
        actualHeight === totalHeightPx ? dstBuf : dstBuf.slice(0, rowBytes * actualHeight)
      const mergedPm = await image.createPixelMap(trimmedBuf, {
        size: { width: widthPx, height: actualHeight },
        pixelFormat: mergeBufferPixelFormat,
        alphaType: mergeAlphaType
      })
      return mergedPm
    } catch (err) {
      Logger.error('NoteEdit', `mergePixelMapsVertical failed: ${JSON.stringify(err)}`)
      return null
    } finally {
      for (const pm of slices) {
        await pm.release()
      }
    }
  }

  /**
   * 对已挂载的 Scroll（SHARE_CARD_ID）分段截图并纵向拼接。
   * 不使用 createFromBuilder，避免 Builder 在隔离上下文中缺少 observeComponentCreation2。
   */
  private async captureScrollingCardToImage(): Promise<ArrayBuffer | null> {
    this.shareExportCaptureOnScreen = true
    await NoteEdit.delayMs(160)
    try {
      return await this.captureScrollingCardToImageCore()
    } finally {
      this.shareExportCaptureOnScreen = false
    }
  }

  private async captureScrollingCardToImageCore(): Promise<ArrayBuffer | null> {
    const snap = this.getUIContext().getComponentSnapshot()
    const id = NoteEdit.SHARE_CARD_ID
    const waitOpts: componentSnapshot.SnapshotOptions = { waitUntilRenderFinished: true }
    const ui = this.getUIContext()
    const vpEps = 0.5
    const offsetWarnVp = 2.0

    this.shareScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
    await NoteEdit.delayMs(100)

    // 长内容下 Column.onAreaChange 可能偏小；用 Scroller 最大偏移推算可滚范围（界面会先滚到底再回到顶部）。
    this.shareScroller.scrollEdge(Edge.Bottom)
    await NoteEdit.delayMs(120)
    const bottomOff = this.shareScroller.currentOffset()
    const maxScrollVp = Math.max(0, bottomOff.yOffset)

    this.shareScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
    await NoteEdit.delayMs(100)

    let firstPm: image.PixelMap | null = null
    try {
      firstPm = await snap.get(id, waitOpts)
    } catch (err) {
      Logger.error('NoteEdit', `snapshot get failed: ${JSON.stringify(err)}`)
      return null
    }
    if (!firstPm) {
      return null
    }

    const firstInfo = firstPm.getImageInfoSync()
    const widthPx = firstInfo.size.width
    const viewportPx = firstInfo.size.height
    // 视口高度（vp）：优先布局高度，与 Scroll 实际可滚区域一致；用于总长与每屏裁切像素 rowStepPx。
    const stepVp = this.shareCardHeight > 0 ? this.shareCardHeight : ui.px2vp(viewportPx)
    const rowStepPx = Math.max(1, Math.round(ui.vp2px(stepVp)))

    // Column.onAreaChange 得到的总高常以「内容真实高度」为准；Scroller.currentOffset 最大值有时偏小，
    // 若仅用 measured maxScrollVp，底部一段（常为 slogan+APP 说明）永远进不了视口。用布局推算的最小滚动行程兜底。
    const columnFromArea = this.shareExportColumnVp > 0 ? this.shareExportColumnVp : 0
    const columnTailVp = columnFromArea > 0 ? Math.max(0, columnFromArea - stepVp) : 0
    const scrollRangeVp = Math.max(maxScrollVp, columnTailVp)
    const extentVp = scrollRangeVp + stepVp
    const columnVp = Math.max(columnFromArea, extentVp, stepVp)
    const totalVp = Math.max(columnVp, stepVp)
    const totalPx = Math.max(Math.ceil(ui.vp2px(totalVp)), viewportPx)
    const extentPx = Math.ceil(ui.vp2px(extentVp))
    const mergeHeightPx = Math.min(totalPx, Math.max(viewportPx, extentPx))

    const singleScreen = totalVp <= stepVp + vpEps

    if (singleScreen) {
      return await this.packPixelMapToPng(firstPm)
    }

    const slices: image.PixelMap[] = [firstPm]
    /** 每张截图对应的真实滚动偏移（vp），用于拼接去重；必须用 actualY，勿用目标 nextYVp（滚动可能被钳制）。 */
    const sliceScrollYVp: number[] = [this.shareScroller.currentOffset().yOffset]
    let yVp = 0
    while (true) {
      const nextYVp = Math.min(yVp + stepVp, scrollRangeVp)
      if (nextYVp <= yVp + vpEps) {
        break
      }
      // 目标超过 Scroller 初次测量的最大偏移时，先顶一次底再 scrollTo，便于引擎刷新可滚区域，露出末尾文案。
      if (nextYVp > maxScrollVp + vpEps) {
        this.shareScroller.scrollEdge(Edge.Bottom)
        await NoteEdit.delayMs(100)
      }
      this.shareScroller.scrollTo({ xOffset: 0, yOffset: nextYVp, animation: false })
      await NoteEdit.delayMs(150)
      let actualY = this.shareScroller.currentOffset().yOffset
      if (Math.abs(actualY - nextYVp) > offsetWarnVp) {
        this.shareScroller.scrollTo({ xOffset: 0, yOffset: nextYVp, animation: false })
        await NoteEdit.delayMs(80)
        actualY = this.shareScroller.currentOffset().yOffset
      }
      // scrollTo 可能被钳制，用小步 scrollBy 逼近目标，便于末尾 slogan 区域进入视口。
      let nudgeGuard = 0
      while (actualY < nextYVp - vpEps && nudgeGuard < 16) {
        const remainVp = nextYVp - actualY
        const stepNudge = Math.min(64, Math.max(1, remainVp))
        this.shareScroller.scrollBy(0, stepNudge)
        await NoteEdit.delayMs(45)
        const tryY = this.shareScroller.currentOffset().yOffset
        if (tryY <= actualY + 0.25) {
          break
        }
        actualY = tryY
        nudgeGuard++
      }
      let next: image.PixelMap | null = null
      try {
        next = await snap.get(id, waitOpts)
      } catch (err) {
        Logger.error('NoteEdit', `snapshot get failed at targetYVp=${nextYVp}: ${JSON.stringify(err)}`)
        break
      }
      if (!next) {
        break
      }
      slices.push(next)
      sliceScrollYVp.push(actualY)
      yVp = nextYVp
    }

    const sliceSkipTopPx: number[] = []
    for (let i = 0; i < slices.length; i++) {
      if (i === 0) {
        sliceSkipTopPx.push(0)
      } else {
        const deltaVp = sliceScrollYVp[i] - sliceScrollYVp[i - 1]
        const deltaPx = Math.max(0, Math.round(ui.vp2px(deltaVp)))
        const skipTop = Math.max(0, viewportPx - deltaPx)
        sliceSkipTopPx.push(skipTop)
      }
    }
    if (slices.length === 1) {
      return await this.packPixelMapToPng(slices[0])
    }

    const normalized = await this.normalizeAllSlicesForMerge(slices)
    if (!normalized) {
      Logger.error('NoteEdit', 'shareLongImage: normalizeAllSlicesForMerge failed')
      return null
    }
    const merged =
      await this.mergePixelMapsVertical(normalized, widthPx, mergeHeightPx, rowStepPx, sliceSkipTopPx)
    if (!merged) {
      Logger.error('NoteEdit', 'shareLongImage: mergePixelMapsVertical returned null')
      return null
    }
    return await this.packPixelMapToPng(merged)
  }

  /** 通过弹窗授权保存长图到相册（无需 WRITE_IMAGEVIDEO 权限）。 */
  private async runSaveLongImageToGallery(): Promise<void> {
    this.showPreviewMessage('正在生成长图…')
    const path = await this.exportShareImageToCache()
    if (!path || path.length === 0) {
      this.showPreviewMessage('生成长图失败')
      return
    }
    const ok = await this.saveCachePngToGallery(path)
    this.showPreviewMessage(ok ? '已保存到相册' : '保存到相册失败')
  }

  @Builder
  private buildShareExportCard() {
    Column({ space: 14 }) {
      Text(this.title.trim().length > 0 ? this.title : '无标题')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      NoteEditMarkdownBlocksView({
        blocks: this.previewBlocksState,
        filesDirCache: this.filesDirCache,
        onLinkToast: (href: string): void => {
          this.showPreviewMessage(href)
        }
      })
      Column({ space: 10 }) {
        Text(NoteEdit.SHARE_SLOGAN)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .lineHeight(22)
          .width('100%')
        Text(NoteEdit.SHARE_INTRO)
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
          .lineHeight(18)
          .width('100%')
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(18)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.preview_background'))
    .onAreaChange((_: Area, area: Area) => {
      const h = Number.parseFloat(`${area.height}`)
      if (h > 0) {
        this.shareExportColumnVp = h
      }
    })
  }

  @Builder
  private buildTagChip(tag: string) {
    Stack(){
      Text(tag)
        .fontSize(12)
        .fontColor(0X00FFFFFF)
        .padding({ left: 8, right: 8, top: 3, bottom: 4 })
        .backgroundColor($r('app.color.tag_text_accent'))
        .opacity(0.12)
        .borderRadius(10)
      Text(tag)
        .fontSize(12)
        .fontColor($r('app.color.primary_text'))
        .padding({ left: 8, right: 8, top: 3, bottom: 4 })
        .borderRadius(10)
    }
  }

  @Builder
  private buildTagDropdown() {
    Column() {
      if (this.tagPool.length === 0) {
        Text('暂无可用标签')
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('app.color.tertiary_text'))
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      } else {
        ForEach(this.tagPool, (tag: string) => {
          Row() {
            Checkbox()
              .select(this.noteTags.includes(tag))
              .selectedColor($r('app.color.accent'))
              .onChange((value: boolean) => {
                void this.onTagChecked(tag, value)
              })
            Text(tag)
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .onClick(() => {
            const selected = !this.noteTags.includes(tag)
            void this.onTagChecked(tag, selected)
          })
        }, (tag: string) => `tag_item_${tag}`)
      }
      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'))
        .margin({ top: 4, bottom: 4 })
      Row() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(16)
          .fontColor([$r('app.color.accent')])
        Text('添加标签')
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.accent'))
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .onClick(() => {
        this.tagMenuVisible = false
        void this.openTagManage()
      })
    }
    .width(110)
    .constraintSize({ maxHeight: 320 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.card_border') })
    .shadow({
      radius: 12,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 4
    })
  }

  /**
   * 移动端预览模式下的标签栏 Builder：
   * - 标签图标 + 下拉箭头 + 当前标签 Chips（无标签时显示"标签"）
   * - 仅当 `hasEditorTitleOrBody` 为 true 时展示
   * - 悬浮窗形式，支持手指拖动到屏幕任意位置
   */
  @Builder
  buildMobileTagBarWidget() {
    Row({ space: 4 }) {
      Row() {
        Row({ space: 4 }) {
          Text('#')
            .fontSize(14)
            .fontColor($r('app.color.secondary_text'))
            .fontWeight(FontWeight.Medium)
          if (this.noteTags.length === 0) {
            Text('标签')
              .fontSize(12)
              .fontColor($r('app.color.secondary_text'))
          } else {
            Scroll() {
              Row({ space: 4 }) {
                ForEach(this.noteTags, (tag: string) => {
                  this.buildTagChip(tag)
                }, (tag: string) => `mobile_tag_chip_${tag}`)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
          }
        }
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(14)
          .fontColor([$r('app.color.secondary_text')])
      }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor($r('app.color.surface_muted'))
      .borderRadius(18)
      .onClick(() => {
        void this.refreshTagPool()
        this.tagMenuVisible = !this.tagMenuVisible
      })
    }
    .shadow({
      radius: 8,
      color: '#20000000',
      offsetX: 0,
      offsetY: 2
    })
  }

  @Builder
  buildDraggableTagBar() {
    Stack() {
      // 内联构建移动端标签栏，避免链式调用问题
      Row({ space: 4 }) {
        Row() {
          Row({ space: 4 }) {
            Text('#')
              .fontSize(14)
              .fontColor($r('app.color.secondary_text'))
              .fontWeight(FontWeight.Medium)
            if (this.noteTags.length === 0) {
              Text('标签')
                .fontSize(12)
                .fontColor($r('app.color.secondary_text'))
            } else {
              Scroll() {
                Row({ space: 4 }) {
                  ForEach(this.noteTags, (tag: string) => {
                    this.buildTagChip(tag)
                  }, (tag: string) => `mobile_tag_chip_${tag}`)
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
            }
          }
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(14)
            .fontColor([$r('app.color.secondary_text')])
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(18)
        .onClick(() => {
          void this.refreshTagPool()
          this.tagMenuVisible = !this.tagMenuVisible
        })
        .shadow({
          radius: 18,
          color: '#2A000000',
          offsetX: 0,
          offsetY: 3
        })
      }

      .onAreaChange((_, currentArea: Area) => {
        this.tagBarWidth = Number.parseFloat(`${currentArea.width}`) || 120
        this.tagBarHeight = Number.parseFloat(`${currentArea.height}`) || 32
        if (!this.tagBarInitialized) {
          const cardPadding = 18
          const toolbarHeight = 69
          const safeAreaTop = 44
          const defaultRight = 8
          this.tagBarX = this.pageWidth - this.tagBarWidth - cardPadding - defaultRight
          this.tagBarY = toolbarHeight + safeAreaTop
          this.tagBarInitialized = true
        }
      })
      .position({ x: this.tagBarX, y: this.tagBarY })
      .gesture(
        PanGesture()
          .onActionStart((event: GestureEvent) => {
            this.lastPanOffsetX = event.offsetX
            this.lastPanOffsetY = event.offsetY
          })
          .onActionUpdate((event: GestureEvent) => {
            const safeAreaTop = 44
            const safeAreaBottom = 34
            const screenHeight = 780
            // 计算增量：当前偏移 - 上次偏移
            const deltaX = event.offsetX - this.lastPanOffsetX
            const deltaY = event.offsetY - this.lastPanOffsetY
            this.lastPanOffsetX = event.offsetX
            this.lastPanOffsetY = event.offsetY
            let newX = this.tagBarX + deltaX
            let newY = this.tagBarY + deltaY
            if (newX < 0) {
              newX = 0
            }
            if (newX > this.pageWidth - this.tagBarWidth) {
              newX = this.pageWidth - this.tagBarWidth
            }
            if (newY < safeAreaTop) {
              newY = safeAreaTop
            }
            if (newY > screenHeight - this.tagBarHeight - safeAreaBottom) {
              newY = screenHeight - this.tagBarHeight - safeAreaBottom
            }
            this.tagBarX = newX
            this.tagBarY = newY
          })
          .onActionEnd((_: GestureEvent) => {
            this.lastPanOffsetX = 0
            this.lastPanOffsetY = 0
          })
      )
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: $r('app.float.toolbar_spacing_content') }) {
        Row() {
          Row() {
            Image($r('app.media.ic_back'))
              .width($r('app.float.note_edit_back_icon_size'))
              .height($r('app.float.note_edit_back_icon_size'))
              .objectFit(ImageFit.Contain)
          }
          .height('100%')
          .constraintSize({ minWidth: 48 })
          .padding({
            top: 8,
            bottom: 8,
            left: 14,
            right: 14
          })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.pill_radius'))
          .onClick(() => {
            void this.handleBack()
          })

          Column({ space: 4 }) {
            Text(this.saveStatusDisplay())
              .fontSize($r('app.float.caption_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor(
                this.saveStatus === '已保存' ? $r('app.color.success') :
                  (this.saveStatus === '保存失败' ? $r('app.color.danger') : $r('app.color.secondary_text'))
              )
              .textAlign(TextAlign.Start)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            if (this.lastSavedAt > 0) {
              Text(TimeUtils.format(this.lastSavedAt))
                .fontSize(12)
                .fontColor($r('app.color.tertiary_text'))
                .textAlign(TextAlign.Start)
                .width('100%')
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 8, right: 8 })

          if (this.isSplitMode()) {
            Row() {
              Text('图')
                .fontSize(16)
                .fontColor(Color.White)
                .width(30)
                .height(30)
                .textAlign(TextAlign.Center)
                .margin({ right: 5 })
                .onClick(() => {
                  void this.insertImage()
                })
            }
          }

          if (!this.isSplitMode()) {
            Row({ space: 6 }) {
              if (this.previewMode === 'preview') {
                Button('编辑')
                  .fontSize($r('app.float.caption_font_size'))
                  .fontWeight(FontWeight.Medium)
                  .height(30)
                  .padding({ left: 12, right: 12 })
                  .borderRadius(18)
                  .backgroundColor(Color.Transparent)
                  .fontColor($r('app.color.accent'))
                  .border({ width: 1, color: $r('app.color.accent') })
                  .onClick(() => {
                    this.switchMode('edit')
                  })
              } else {
                Button('预览')
                  .fontSize($r('app.float.caption_font_size'))
                  .fontWeight(FontWeight.Medium)
                  .height(30)
                  .padding({ left: 12, right: 12 })
                  .borderRadius(18)
                  .backgroundColor($r('app.color.accent'))
                  .fontColor(Color.White)
                  .onClick(() => {
                    this.switchMode('preview')
                  })
                Image($r('app.media.ic_image'))
                  .width(30)
                  .height(30)
                  .margin({ right: 5, left: 5 })
                  .padding(3)
                  .fillColor(Color.White)
                  .onClick(() => {
                    void this.insertImage()
                  })
              }
              Image($r('app.media.ic_share'))
                .width(30)
                .height(30)
                .margin({ right: 5, left: 5 })
                .padding(3)
                .fillColor(Color.White)
                .onClick(() => {
                  void this.runSaveLongImageToGallery()
                })
            }
            .alignItems(VerticalAlign.Center)
          }
        }
        .width('100%')
        .height($r('app.float.edit_note_toolbar_height'))
        .alignItems(VerticalAlign.Center)

        if (this.isSplitMode()) {
          Row({ space: 14 }) {
            NoteEditEditorPane({
              title: $title,
              content: $content,
              textAreaController: this.textAreaController,
              onTitleChange: (): void => {
                this.scheduleSave()
              },
              onContentChange: (): void => {
                if (this.shouldRenderPreview()) {
                  this.schedulePreviewRefresh()
                } else {
                  this.previewDirty = true
                }
                this.scheduleSave()
              }
            })
            NoteEditPreviewPane({
              title: this.title,
              splitMode: this.isSplitMode(),
              showSplitTagRow: hasEditorTitleOrBody(this.title, this.content),
              previewBlocks: this.previewBlocksState,
              filesDirCache: this.filesDirCache,
              onBackgroundTap: (): void => {
                if (this.tagMenuVisible) {
                  this.tagMenuVisible = false
                }
              },
              onLinkToast: (href: string): void => {
                this.showPreviewMessage(href)
              },
              tagBarSlot: this.buildMobileTagBarWidget
            })
          }
          .layoutWeight(1)
          .width('100%')
        } else if (this.previewMode === 'preview') {
          NoteEditPreviewPane({
            title: this.title,
            splitMode: this.isSplitMode(),
            showSplitTagRow: hasEditorTitleOrBody(this.title, this.content),
            previewBlocks: this.previewBlocksState,
            filesDirCache: this.filesDirCache,
            onBackgroundTap: (): void => {
              if (this.tagMenuVisible) {
                this.tagMenuVisible = false
              }
            },
            onLinkToast: (href: string): void => {
              this.showPreviewMessage(href)
            },
            tagBarSlot: this.buildMobileTagBarWidget
          })
        } else {
          NoteEditEditorPane({
            title: $title,
            content: $content,
            textAreaController: this.textAreaController,
            onTitleChange: (): void => {
              this.scheduleSave()
            },
            onContentChange: (): void => {
              if (this.shouldRenderPreview()) {
                this.schedulePreviewRefresh()
              } else {
                this.previewDirty = true
              }
              this.scheduleSave()
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .padding({
        top: $r('app.float.toolbar_editor_page_padding_top'),
        left: this.pageWidth >= 600 ? 24 : 6,
        right: this.pageWidth >= 600 ? 24 : 6
      })
      .backgroundColor($r('app.color.app_background'))

      if (this.tagMenuVisible) {
        Column() {
          this.buildTagDropdown()
        }
        .position({ x: this.pageWidth - 130, y: 69 })
        .zIndex(999)
      }

      // 移动端预览模式下的可拖动悬浮标签栏
      if (!this.isSplitMode() && hasEditorTitleOrBody(this.title, this.content)) {
        Stack() {
          this.buildDraggableTagBar()
        }
          .position({ x: 0, y: 0 })
          .zIndex(998)
      }

      Scroll(this.shareScroller) {
        this.buildShareExportCard()
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .width('100%')
      .constraintSize({ minHeight: 800 })
      .onAreaChange((_, value) => {
        this.shareCardHeight = Number.parseFloat(`${value.height}`) || 0
      })
      .position(this.shareExportCaptureOnScreen ? { x: 0, y: 0 } : { x: -8000, y: 0 })
      // 截屏时必须正常不透明并叠在最上层：过低 opacity 或 zIndex 在底层会被主编缉区盖住，合成结果为空/黑屏。
      .opacity(1)
      .hitTestBehavior(this.shareExportCaptureOnScreen ? HitTestMode.None : HitTestMode.Default)
      .zIndex(this.shareExportCaptureOnScreen ? 10001 : 0)
      .id(NoteEdit.SHARE_CARD_ID)
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      if (this.tagMenuVisible) {
        this.tagMenuVisible = false
      }
    })
    .onAreaChange((_, value) => {
      const nextWidth = Number.parseFloat(`${value.width}`) || 360
      const wasSplitMode = this.isSplitMode()
      if (Math.abs(this.pageWidth - nextWidth) >= 1) {
        this.pageWidth = nextWidth
      }
      const nextSplitMode = this.isSplitMode()
      const nextPreviewMode = nextSplitMode ? 'split' : (this.previewMode === 'preview' ? 'preview' : 'edit')
      if (this.previewMode !== nextPreviewMode) {
        this.previewMode = nextPreviewMode
      }
      if ((!wasSplitMode && nextSplitMode) || this.shouldRenderPreview()) {
        this.preparePreviewForCurrentMode(this.content, true)
      }
    })
  }
}
