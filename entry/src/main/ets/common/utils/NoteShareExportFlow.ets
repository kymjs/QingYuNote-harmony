import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { componentSnapshot } from '@kit.ArkUI'
import type { MarkdownBlock } from './MarkdownUtils'
import { ShareThemeColors, ShareCardTheme, ShareCardTone } from '../../share/ShareTheme'
import {
  buildJinshuLightSegmentCaptureIds,
  NOTE_SHARE_EXPORT_SNAPSHOT_ID
} from '../../share/NoteShareExportCard'
import type { ProfileBody } from '../../services/NoteApiClient'
import { Logger } from './Logger'
import {
  NOTE_EDIT_SHARE_SCROLL_ID,
  NOTE_EDIT_SHARE_SNAPSHOT_MAX_FULL_CARD_VP,
  noteEditDelayMs,
  shareExportBodyHasImages,
  shareExportContentHasImages,
  shareExportMountDelayMs,
  shareExportMountKey
} from './NoteEditShareHelper'
import {
  mergeSharePixelMapsVertical,
  normalizeAllShareSlicesForMerge,
  packSharePixelMapToPng,
  trimShareTransparentVerticalEdges
} from './NoteEditShareSnapshot'

/** Host page state/callbacks for off-screen share card snapshot export. */
export interface ShareExportDelegate {
  logTag: string
  getUIContext: () => UIContext
  obtainUiAbilityContext: () => common.UIAbilityContext | undefined
  getPageWidth: () => number
  getPageHeight: () => number
  getShareScroller: () => Scroller
  getShareBody: () => string
  getShareTitle: () => string
  getNoteCreatedAt: () => number
  getFilesDirCache: () => string
  getShareProfile: () => ProfileBody | null
  getPreviewBlocks: () => MarkdownBlock[]
  refreshPreviewBlocks: (content: string) => void
  getShareTheme: () => ShareCardTheme
  setShareTheme: (v: ShareCardTheme) => void
  getShareTone: () => ShareCardTone
  setShareTone: (v: ShareCardTone) => void
  getShareExportTheme: () => ShareCardTheme
  setShareExportTheme: (v: ShareCardTheme) => void
  getShareExportTone: () => ShareCardTone
  setShareExportTone: (v: ShareCardTone) => void
  getShareExportSnapshotCompatMode: () => boolean
  setShareExportSnapshotCompatMode: (v: boolean) => void
  getShareExportSnapshotSkipQr: () => boolean
  setShareExportSnapshotSkipQr: (v: boolean) => void
  getShareShowAppIcon: () => boolean
  getShareExportActive: () => boolean
  setShareExportActive: (v: boolean) => void
  getShareExportScrollBg: () => string
  setShareExportScrollBg: (v: string) => void
  getShareExportColumnVp: () => number
  setShareExportColumnVp: (v: number) => void
  getShareCardHeight: () => number
  setShareCardHeight: (v: number) => void
  getShareCardCaptureKey: () => number
  bumpShareCardCaptureKey: () => void
}

/** Snapshot pipeline extracted from NoteEdit for reuse on voice note detail share. */
export class NoteShareExportFlow {
  private static readonly SHARE_CARD_ID: string = NOTE_SHARE_EXPORT_SNAPSHOT_ID
  private static readonly SHARE_SNAPSHOT_MAX_FULL_CARD_VP: number = NOTE_EDIT_SHARE_SNAPSHOT_MAX_FULL_CARD_VP

  private delegate: ShareExportDelegate

  constructor(delegate: ShareExportDelegate) {
    this.delegate = delegate
  }

  shareExportMountKey(): string {
    return shareExportMountKey(
      this.delegate.getShareCardCaptureKey(),
      this.delegate.getShareExportTheme(),
      this.delegate.getShareExportTone(),
      this.delegate.getShareExportSnapshotCompatMode(),
      this.delegate.getShareExportSnapshotSkipQr(),
      this.delegate.getShareShowAppIcon()
    )
  }

  private shareAvatarUrlTrim(): string {
    return (this.delegate.getShareProfile()?.avatar_url ?? '').trim()
  }

  private shareExportBodyHasImages(): boolean {
    return shareExportBodyHasImages(this.delegate.getPreviewBlocks())
  }

  private shareExportContentHasImages(): boolean {
    return shareExportContentHasImages(
      this.delegate.getPreviewBlocks(),
      this.shareAvatarUrlTrim()
    )
  }

  private shareSnapshotPreferScrollViewport(): boolean {
    const columnVp = this.delegate.getShareExportColumnVp()
    if (columnVp <= 0) {
      return this.delegate.getPageHeight() > 0
    }
    const viewportVp = Math.max(this.delegate.getPageHeight(), this.delegate.getShareCardHeight(), 800)
    return columnVp > NoteShareExportFlow.SHARE_SNAPSHOT_MAX_FULL_CARD_VP ||
      columnVp > viewportVp * 0.92
  }

  private shareSnapshotWaitOpts(): componentSnapshot.SnapshotOptions {
    return { waitUntilRenderFinished: true }
  }

  private isJinshuLightExport(): boolean {
    return this.delegate.getShareExportTheme() === ShareCardTheme.JINSHU &&
      this.delegate.getShareExportTone() === ShareCardTone.LIGHT
  }

  private jinshuLightExportTextLen(): number {
    return ShareThemeColors.stripMarkdown(this.delegate.getShareBody()).length
  }

  private async trimShareSlice(pm: image.PixelMap): Promise<image.PixelMap | null> {
    const ui = this.delegate.getUIContext()
    const contentPx = this.delegate.getShareExportColumnVp() > 0
      ? Math.max(1, Math.round(ui.vp2px(this.delegate.getShareExportColumnVp())))
      : 0
    return trimShareTransparentVerticalEdges(pm, contentPx)
  }

  async mountShareExportCard(
    theme: ShareCardTheme,
    tone: ShareCardTone,
    snapshotCompatMode: boolean = false,
    snapshotSkipQr: boolean = false
  ): Promise<void> {
    if (this.delegate.getShareExportActive()) {
      this.delegate.setShareExportActive(false)
      await noteEditDelayMs(48)
    }
    this.delegate.bumpShareCardCaptureKey()
    const palette = ShareThemeColors.resolve(theme, tone)
    this.delegate.setShareExportTheme(theme)
    this.delegate.setShareExportTone(tone)
    this.delegate.setShareExportSnapshotCompatMode(snapshotCompatMode)
    this.delegate.setShareExportSnapshotSkipQr(snapshotSkipQr)
    this.delegate.setShareExportScrollBg(palette.backgroundGradient?.[0] ?? palette.background)
    this.delegate.setShareExportColumnVp(0)
    this.delegate.setShareCardHeight(0)
    this.delegate.setShareExportActive(true)
    Logger.info(this.delegate.logTag,
      `mountShareExportCard key=${this.delegate.getShareCardCaptureKey()} theme=${theme} tone=${tone} ` +
      `compat=${snapshotCompatMode} skipQr=${snapshotSkipQr}`)
    this.delegate.getShareScroller().scrollTo({ xOffset: 0, yOffset: 0, animation: false })
    const mountDelayMs = shareExportMountDelayMs(
      theme,
      tone,
      this.shareExportContentHasImages()
    )
    await noteEditDelayMs(mountDelayMs)
  }

  async exportShareImageToCache(
    theme: ShareCardTheme = this.delegate.getShareTheme(),
    tone: ShareCardTone = this.delegate.getShareTone()
  ): Promise<string | null> {
    if (this.delegate.getShareTheme() !== theme) {
      this.delegate.setShareTheme(theme)
    }
    if (this.delegate.getShareTone() !== tone) {
      this.delegate.setShareTone(tone)
    }
    this.delegate.refreshPreviewBlocks(this.delegate.getShareBody())
    const jinshuLight = theme === ShareCardTheme.JINSHU && tone === ShareCardTone.LIGHT
    await this.mountShareExportCard(theme, tone, false, false)
    try {
      let path = await this.offlineSnapshotCapture()
      if (!path && jinshuLight && !this.delegate.getShareExportSnapshotCompatMode()) {
        await this.mountShareExportCard(theme, tone, true, false)
        path = await this.offlineSnapshotCapture()
      }
      if (!path && jinshuLight && !this.delegate.getShareExportSnapshotSkipQr()) {
        await this.mountShareExportCard(theme, tone, true, true)
        path = await this.offlineSnapshotCapture()
      }
      if (!path && !this.delegate.getShareExportSnapshotSkipQr()) {
        await this.mountShareExportCard(theme, tone, this.delegate.getShareExportSnapshotCompatMode(), true)
        path = await this.offlineSnapshotCapture()
      }
      return path
    } catch (error) {
      Logger.error(this.delegate.logTag, `exportShareImageToCache failed: ${JSON.stringify(error)}`)
      return null
    } finally {
      this.delegate.setShareExportActive(false)
    }
  }

  private async offlineSnapshotCapture(): Promise<string | null> {
    const context = this.delegate.obtainUiAbilityContext()
    if (context === undefined) {
      return null
    }
    this.delegate.refreshPreviewBlocks(this.delegate.getShareBody())
    await new Promise<void>((resolve) => setTimeout(() => resolve(), 100))
    try {
      const pngBuf = await this.captureScrollingCardToImage()
      if (!pngBuf || pngBuf.byteLength === 0) {
        return null
      }
      const filePath: string = `${context.cacheDir}/note_share_${Date.now()}.png`
      const f: fileIo.File =
        fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(f.fd, pngBuf)
      fileIo.closeSync(f)
      return filePath
    } catch (err) {
      Logger.error(this.delegate.logTag, `offlineSnapshotCapture failed: ${JSON.stringify(err)}`)
      return null
    }
  }

  private async captureScrollingCardToImage(): Promise<ArrayBuffer | null> {
    await noteEditDelayMs(240)
    return await this.captureScrollingCardToImageCore()
  }

  private async getShareSnapshotWithCandidates(
    opts: componentSnapshot.SnapshotOptions,
    phase: string
  ): Promise<image.PixelMap | null> {
    const snap = this.delegate.getUIContext().getComponentSnapshot()
    const preferScroll = this.shareSnapshotPreferScrollViewport()
    const candidates: string[] = preferScroll
      ? [NOTE_EDIT_SHARE_SCROLL_ID, NoteShareExportFlow.SHARE_CARD_ID]
      : [NoteShareExportFlow.SHARE_CARD_ID, NOTE_EDIT_SHARE_SCROLL_ID]
    for (const candidate of candidates) {
      if (preferScroll && candidate === NoteShareExportFlow.SHARE_CARD_ID &&
        this.delegate.getShareExportColumnVp() > NoteShareExportFlow.SHARE_SNAPSHOT_MAX_FULL_CARD_VP) {
        continue
      }
      try {
        const pm = await snap.get(candidate, opts)
        return pm
      } catch (error) {
        Logger.warn(this.delegate.logTag,
          `snapshot failed phase=${phase} candidate=${candidate}: ${JSON.stringify(error)}`)
      }
    }
    return null
  }

  private async snapshotShareNodeById(
    nodeId: string,
    opts: componentSnapshot.SnapshotOptions
  ): Promise<image.PixelMap | null> {
    const snap = this.delegate.getUIContext().getComponentSnapshot()
    try {
      return await snap.get(nodeId, opts)
    } catch (error) {
      Logger.warn(this.delegate.logTag, `segment snapshot failed id=${nodeId}: ${JSON.stringify(error)}`)
      return null
    }
  }

  private async captureJinshuLightSegmented(): Promise<ArrayBuffer | null> {
    const waitOpts = this.shareSnapshotWaitOpts()
    const textLen = this.jinshuLightExportTextLen()
    const includeQuote = !this.delegate.getShareExportSnapshotCompatMode()
    const segmentIds = buildJinshuLightSegmentCaptureIds(textLen, includeQuote)
    const slices: image.PixelMap[] = []
    for (const nodeId of segmentIds) {
      const pm = await this.snapshotShareNodeById(nodeId, waitOpts)
      if (!pm) {
        for (const s of slices) {
          await s.release()
        }
        return null
      }
      slices.push(pm)
    }
    if (slices.length === 0) {
      return null
    }
    if (slices.length === 1) {
      const trimmed = await this.trimShareSlice(slices[0])
      await slices[0].release()
      if (!trimmed) {
        return null
      }
      const buf = await packSharePixelMapToPng(trimmed)
      await trimmed.release()
      return buf
    }
    let widthPx = 0
    let totalHeightPx = 0
    for (const s of slices) {
      const info = s.getImageInfoSync()
      widthPx = Math.max(widthPx, info.size.width)
      totalHeightPx += info.size.height
    }
    const sliceSkipTopPx: number[] = new Array(slices.length).fill(0)
    const normalized = await normalizeAllShareSlicesForMerge(slices)
    for (const s of slices) {
      await s.release()
    }
    if (!normalized) {
      return null
    }
    let normHeightPx = 0
    for (const n of normalized) {
      normHeightPx += n.getImageInfoSync().size.height
    }
    const merged = await mergeSharePixelMapsVertical(normalized, widthPx, normHeightPx, 0, sliceSkipTopPx)
    if (!merged) {
      return null
    }
    const buf = await packSharePixelMapToPng(merged)
    await merged.release()
    return buf
  }

  private async flushShareCardRenderSnapshot(): Promise<void> {
    const waitOpts = this.shareSnapshotWaitOpts()
    const scroller = this.delegate.getShareScroller()
    for (let round = 0; round < 2; round++) {
      scroller.scrollEdge(Edge.Bottom)
      await noteEditDelayMs(160)
      scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
      await noteEditDelayMs(160)
      try {
        const warmPm = await this.getShareSnapshotWithCandidates(waitOpts, `flush_round_${round}`)
        if (warmPm) {
          await warmPm.release()
        }
      } catch (_) {
      }
    }
    await noteEditDelayMs(120)
  }

  private async captureScrollingCardToImageCore(): Promise<ArrayBuffer | null> {
    const waitOpts = this.shareSnapshotWaitOpts()
    const ui = this.delegate.getUIContext()
    const scroller = this.delegate.getShareScroller()
    const vpEps = 0.5
    const offsetWarnVp = 2.0

    scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
    await noteEditDelayMs(100)
    await this.flushShareCardRenderSnapshot()

    const jinshuLongBody =
      this.isJinshuLightExport() &&
      !this.shareExportBodyHasImages() &&
      this.jinshuLightExportTextLen() > ShareThemeColors.JINSHU_LIGHT_BODY_CHARS_PER_CHUNK
    if (jinshuLongBody) {
      return await this.captureJinshuLightSegmented()
    }

    scroller.scrollEdge(Edge.Bottom)
    await noteEditDelayMs(120)
    const bottomOff = scroller.currentOffset()
    const maxScrollVp = Math.max(0, bottomOff.yOffset)
    scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
    await noteEditDelayMs(100)

    let firstPm: image.PixelMap | null = null
    try {
      firstPm = await this.getShareSnapshotWithCandidates(waitOpts, 'first_frame')
    } catch (_) {
      return null
    }
    if (!firstPm) {
      if (this.isJinshuLightExport()) {
        return await this.captureJinshuLightSegmented()
      }
      return null
    }

    let firstInfo: image.ImageInfo
    try {
      firstInfo = firstPm.getImageInfoSync()
    } catch (_) {
      await firstPm.release()
      return null
    }
    const widthPx = firstInfo.size.width
    const viewportPx = firstInfo.size.height
    const stepVp = ui.px2vp(viewportPx)
    const rowStepPx = Math.max(1, Math.round(ui.vp2px(stepVp)))
    const columnFromArea = this.delegate.getShareExportColumnVp() > 0 ? this.delegate.getShareExportColumnVp() : 0
    const columnTailVp = columnFromArea > 0 ? Math.max(0, columnFromArea - stepVp) : 0
    const scrollRangeVp = Math.max(maxScrollVp, columnTailVp)
    const extentVp = scrollRangeVp + stepVp
    const columnVp = Math.max(columnFromArea, extentVp, stepVp)
    const totalVp = Math.max(columnVp, stepVp)
    const totalPx = Math.max(Math.ceil(ui.vp2px(totalVp)), viewportPx)
    const extentPx = Math.ceil(ui.vp2px(extentVp))
    const mergeHeightPx = Math.min(totalPx, Math.max(viewportPx, extentPx))
    const snapshotCoversContent =
      columnFromArea > 0 && stepVp >= columnFromArea - vpEps
    const singleScreen = totalVp <= stepVp + vpEps

    if (singleScreen || snapshotCoversContent) {
      const trimmed = await this.trimShareSlice(firstPm)
      if (!trimmed) {
        return null
      }
      return await packSharePixelMapToPng(trimmed)
    }

    const slices: image.PixelMap[] = [firstPm]
    const sliceScrollYVp: number[] = [scroller.currentOffset().yOffset]
    let yVp = 0
    while (true) {
      const nextYVp = Math.min(yVp + stepVp, scrollRangeVp)
      if (nextYVp <= yVp + vpEps) {
        break
      }
      if (nextYVp > maxScrollVp + vpEps) {
        scroller.scrollEdge(Edge.Bottom)
        await noteEditDelayMs(100)
      }
      scroller.scrollTo({ xOffset: 0, yOffset: nextYVp, animation: false })
      await noteEditDelayMs(150)
      let actualY = scroller.currentOffset().yOffset
      if (Math.abs(actualY - nextYVp) > offsetWarnVp) {
        scroller.scrollTo({ xOffset: 0, yOffset: nextYVp, animation: false })
        await noteEditDelayMs(80)
        actualY = scroller.currentOffset().yOffset
      }
      let nudgeGuard = 0
      while (actualY < nextYVp - vpEps && nudgeGuard < 16) {
        const remainVp = nextYVp - actualY
        const stepNudge = Math.min(64, Math.max(1, remainVp))
        scroller.scrollBy(0, stepNudge)
        await noteEditDelayMs(45)
        const tryY = scroller.currentOffset().yOffset
        if (tryY <= actualY + 0.25) {
          break
        }
        actualY = tryY
        nudgeGuard++
      }
      let next: image.PixelMap | null = null
      try {
        next = await this.getShareSnapshotWithCandidates(waitOpts, `slice_target_${Math.round(nextYVp)}`)
      } catch (_) {
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
        sliceSkipTopPx.push(Math.max(0, viewportPx - deltaPx))
      }
    }
    if (slices.length === 1) {
      const trimmed = await this.trimShareSlice(slices[0])
      if (!trimmed) {
        return null
      }
      return await packSharePixelMapToPng(trimmed)
    }
    const normalized = await normalizeAllShareSlicesForMerge(slices)
    if (!normalized) {
      return null
    }
    const merged =
      await mergeSharePixelMapsVertical(normalized, widthPx, mergeHeightPx, rowStepPx, sliceSkipTopPx)
    if (!merged) {
      return null
    }
    return await packSharePixelMapToPng(merged)
  }
}
