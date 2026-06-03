import type { MarkdownBlock } from '../common/utils/MarkdownUtils'
import type { ProfileBody } from '../services/NoteApiClient'
import { fileUri } from '@kit.CoreFileKit'
import { Logger } from '../common/utils/Logger'
import { NoteEditMarkdownBlocksView } from '../pages/NoteEditMarkdownBlocksView'
import { FileService } from '../services/FileService'
import {
  DEFAULT_SHARE_CONTENT_PADDING,
  ShareCardTheme,
  ShareCardTone,
  ShareThemeColors,
  type ShareThemePalette
} from './ShareTheme'
import { JinshuUnderlineText } from './JinshuUnderlineText'

export interface NoteShareExportCardParams {
  theme: ShareCardTheme
  tone: ShareCardTone
  snapshotCompatMode?: boolean
  /** 导出快照跳过 footer 二维码 Image，规避 checkImage 失败。 */
  snapshotSkipQr?: boolean
  styleKey?: string
  title: string
  content: string
  previewBlocks: MarkdownBlock[]
  filesDirCache: string
  noteCreatedAt: number
  shareProfile: ProfileBody | null
  onLinkToast: (href: string) => void
  onAreaHeight?: (heightVp: number) => void
}

export const NOTE_SHARE_EXPORT_SNAPSHOT_ID: string = 'note_share_export_card'

/** 锦书浅色导出节点 id（供 ComponentSnapshot 分段探测）。 */
export const JINSHU_LIGHT_SHELL_ID: string = 'jinshu_light_shell'
export const JINSHU_LIGHT_CARD_INNER_ID: string = 'jinshu_light_card_inner'
export const JINSHU_LIGHT_QUOTE_ID: string = 'jinshu_light_quote'
export const JINSHU_LIGHT_BODY_ID: string = 'jinshu_light_body'
export const JINSHU_LIGHT_FOOTER_ID: string = 'jinshu_light_footer'
export const JINSHU_LIGHT_DIVIDER_ID: string = 'jinshu_light_divider'
export const JINSHU_LIGHT_SLOGAN_ID: string = 'jinshu_light_slogan'
export const JINSHU_LIGHT_QR_ID: string = 'jinshu_light_qr'
export const JINSHU_LIGHT_QUOTE_FONT_SIZE: number = 116
export const JINSHU_LIGHT_QUOTE_EDGE: number = 30
export const JINSHU_LIGHT_BODY_H_PADDING: number = 30
export const JINSHU_LIGHT_BODY_FONT_SIZE: number = 21
export const JINSHU_LIGHT_BODY_LINE_HEIGHT: number = 33
export const JINSHU_LIGHT_BODY_TOP_GAP: number = 0
export const JINSHU_LIGHT_FOOTER_EDGE: number = 15
export const JINSHU_LIGHT_FOOTER_TOP_GAP: number = 28

/** 锦书浅色分段导出节点顺序（quote 可选 + body 分块 + footer）。 */
export function buildJinshuLightSegmentCaptureIds(textLen: number, includeQuote: boolean): string[] {
  const ids: string[] = []
  if (includeQuote) {
    ids.push(JINSHU_LIGHT_QUOTE_ID)
  }
  const chunkCount = ShareThemeColors.jinshuLightBodyChunkCount(textLen)
  for (let i = 0; i < chunkCount; i++) {
    ids.push(ShareThemeColors.jinshuLightBodyChunkId(i))
  }
  ids.push(JINSHU_LIGHT_DIVIDER_ID)
  return ids
}

export const SHARE_SLOGAN: string = '轻羽云笔记：记录本身，就是意义'
export const SHARE_INTRO: string = '手机与电脑全平台云笔记，无论你正在使用哪台设备，笔记都在手边。'
export const SHARE_HEADER_TO_CONTENT_GAP: number = 30
export const SHARE_AVATAR_SIZE: number = 48
export const SHARE_QR_SIZE: number = 72
export const SHARE_FOOTER_QR_GAP: number = 12

@Component
export struct NoteShareExportCard {
  @Prop theme: ShareCardTheme = ShareCardTheme.CLASSIC
  @Prop tone: ShareCardTone = ShareCardTone.DARK
  /** 导出快照兼容模式：用于规避特定组件在 ComponentSnapshot 下偶发失败。 */
  @Prop snapshotCompatMode: boolean = false
  /** 导出快照跳过 footer 二维码 Image。 */
  @Prop snapshotSkipQr: boolean = false
  /** 含 captureKey，主题/色调切换时强制 Markdown 块重建。 */
  @Prop styleKey: string = ''
  @Prop title: string = ''
  @Prop content: string = ''
  @Prop previewBlocks: MarkdownBlock[] = []
  @Prop filesDirCache: string = ''
  @Prop noteCreatedAt: number = 0
  @Prop shareProfile: ProfileBody | null = null
  @State shareAvatarNetworkFailed: boolean = false
  @State jinshuBodyChunks: string[] = []
  onLinkToast: (href: string) => void = (_href: string) => {
  }
  onAreaHeight: (heightVp: number) => void = (_h: number) => {
  }

  aboutToAppear(): void {
    this.logBuild('aboutToAppear')
    if (this.isJinshuLight()) {
      this.jinshuBodyChunks = ShareThemeColors.splitJinshuLightBodyChunks(this.jinshuDisplayText())
    }
  }

  aboutToReuse(): void {
    this.shareAvatarNetworkFailed = false
    if (this.isJinshuLight()) {
      this.jinshuBodyChunks = ShareThemeColors.splitJinshuLightBodyChunks(this.jinshuDisplayText())
    }
    this.logBuild('aboutToReuse')
  }

  private logBuild(stage: string): void {
    const p = this.palette()
    Logger.info('NoteShareExportCard',
      `${stage} styleKey=${this.styleKey} theme=${this.theme} tone=${this.tone} ` +
      `compat=${this.snapshotCompatMode} skipQr=${this.snapshotSkipQr} bg=${p.background} text=${p.textPrimary} ` +
      `gradient=${p.backgroundGradient?.join('->') ?? 'none'}`)
  }

  private palette(): ShareThemePalette {
    return ShareThemeColors.resolve(this.theme, this.tone)
  }

  private isJinshuLight(): boolean {
    return this.theme === ShareCardTheme.JINSHU && this.tone === ShareCardTone.LIGHT
  }

  private displayName(): string {
    const name = (this.shareProfile?.username ?? '').trim()
    return name.length > 0 ? name : '轻羽云笔记用户'
  }

  private avatarUrl(): string {
    return (this.shareProfile?.avatar_url ?? '').trim()
  }

  private formatCreatedAt(): string {
    const ms = this.noteCreatedAt > 0 ? this.noteCreatedAt : Date.now()
    const date = new Date(ms)
    return `创作于${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()}`
  }

  private titleText(): string {
    return this.title.trim().length > 0 ? this.title.trim() : '无标题'
  }

  private jinshuDisplayText(): string {
    const plain = ShareThemeColors.stripMarkdown(this.content)
    return plain.length > 0 ? plain : '开始写作后，这里会实时显示预览。'
  }

  private hasBodyImages(): boolean {
    for (const block of this.previewBlocks) {
      if (block.type === 'image') {
        return true
      }
    }
    return false
  }

  private jinshuBlockPlainText(block: MarkdownBlock): string {
    if (block.type === 'unordered_list' || block.type === 'ordered_list') {
      const lines: string[] = []
      for (const item of block.items) {
        let line = ''
        for (const inline of item) {
          line += inline.content
        }
        const trimmed = line.trim()
        if (trimmed.length > 0) {
          lines.push(trimmed)
        }
      }
      return ShareThemeColors.stripMarkdown(lines.join('\n'))
    }
    if (block.type === 'checkbox_list') {
      const lines: string[] = []
      for (const item of block.checkboxItems ?? []) {
        let line = ''
        for (const inline of item.inlines) {
          line += inline.content
        }
        const trimmed = line.trim()
        if (trimmed.length > 0) {
          lines.push(trimmed)
        }
      }
      return ShareThemeColors.stripMarkdown(lines.join('\n'))
    }
    if (block.type === 'divider' || block.type === 'image') {
      return ''
    }
    return ShareThemeColors.stripMarkdown(block.content)
  }

  private resolveLocalImageAbsPath(src: string): string {
    if (src.startsWith('file://')) {
      return src.replace('file://', '')
    }
    if (src.startsWith('/')) {
      return src
    }
    return `${this.filesDirCache}/${src}`
  }

  private resolveImageSrc(src: string): string {
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return src
    }
    return fileUri.getUriFromPath(this.resolveLocalImageAbsPath(src))
  }

  private isLocalNoteImageSrc(src: string): boolean {
    return src.includes('qingyu-note-image')
  }

  private localNoteImageExists(src: string): boolean {
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return true
    }
    return FileService.fileExists(this.resolveLocalImageAbsPath(src))
  }

  @Builder
  private buildAvatar() {
    if (this.avatarUrl().length > 0 && !this.shareAvatarNetworkFailed) {
      Image(this.avatarUrl())
        .width(SHARE_AVATAR_SIZE)
        .height(SHARE_AVATAR_SIZE)
        .borderRadius(SHARE_AVATAR_SIZE / 2)
        .objectFit(ImageFit.Cover)
        .onError(() => {
          this.shareAvatarNetworkFailed = true
        })
    } else {
      Image($r('app.media.icon_app'))
        .width(SHARE_AVATAR_SIZE)
        .height(SHARE_AVATAR_SIZE)
        .borderRadius(SHARE_AVATAR_SIZE / 2)
        .objectFit(ImageFit.Cover)
    }
  }

  @Builder
  private buildClassicFooter(p: ShareThemePalette, qrOnLeft: boolean = true) {
    Divider()
      .strokeWidth(1)
      .color(p.divider)
      .margin({ top: 24, bottom: 16 })
    if (qrOnLeft) {
      Row({ space: SHARE_FOOTER_QR_GAP }) {
        this.buildQrCode(p)
        Column({ space: 10 }) {
          this.buildSloganTexts(p)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    } else {
      Row({ space: SHARE_FOOTER_QR_GAP }) {
        Column({ space: 10 }) {
          this.buildSloganTexts(p)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        this.buildQrCode(p)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    }
  }

  private useTransparentQr(): boolean {
    return this.tone === ShareCardTone.LIGHT &&
      (this.theme === ShareCardTheme.CLASSIC ||
        this.theme === ShareCardTheme.QINGYU ||
        this.theme === ShareCardTheme.CALENDAR ||
        this.theme === ShareCardTheme.JINSHU)
  }

  private qrSize(): number {
    if (this.theme === ShareCardTheme.JINSHU && this.tone === ShareCardTone.DARK) {
      return SHARE_QR_SIZE * 0.8
    }
    return SHARE_QR_SIZE
  }

  @Builder
  private buildSloganTexts(p: ShareThemePalette) {
    Text(SHARE_SLOGAN)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(p.textPrimary)
      .lineHeight(20)
      .width('100%')
    Text(SHARE_INTRO)
      .fontSize(this.theme === ShareCardTheme.QINGYU || this.isJinshuLight() ? 11 : 12)
      .fontColor(p.textSecondary)
      .lineHeight(18)
      .width('100%')
  }

  @Builder
  private buildQrCode(p: ShareThemePalette) {
    if (this.snapshotSkipQr) {
      Column()
        .width(this.qrSize())
        .height(this.qrSize())
    } else if (this.useTransparentQr()) {
      Image($r('app.media.website_qrcode'))
        .width(this.qrSize())
        .height(this.qrSize())
        .objectFit(ImageFit.Contain)
    } else {
      Stack() {
        Column()
          .width(this.qrSize())
          .height(this.qrSize())
          .backgroundColor(p.textPrimary)
        Image($r('app.media.website_qrcode'))
          .width(this.qrSize())
          .height(this.qrSize())
          .objectFit(ImageFit.Contain)
      }
      .width(this.qrSize())
      .height(this.qrSize())
    }
  }

  @Builder
  private buildMarkdownBody(p: ShareThemePalette, center: boolean = false) {
    NoteEditMarkdownBlocksView({
      blocks: this.previewBlocks,
      filesDirCache: this.filesDirCache,
      forShareExport: true,
      shareTextOverride: p.textPrimary,
      shareCodeBgOverride: p.codeBackground,
      shareDividerOverride: p.divider,
      shareBackgroundOverride: p.background,
      shareStyleKey: this.styleKey.length > 0 ? this.styleKey : `${this.theme}_${this.tone}`,
      onLinkToast: this.onLinkToast
    })
    .key(this.styleKey.length > 0 ? this.styleKey : `${this.theme}_${this.tone}`)
    .width('100%')
    .align(center ? Alignment.Center : Alignment.Start)
  }

  @Builder
  private buildJinshuBodyContent(p: ShareThemePalette, bodyText: string) {
    if (this.isJinshuLight() && this.snapshotCompatMode) {
      Text(bodyText)
        .fontSize(JINSHU_LIGHT_BODY_FONT_SIZE)
        .lineHeight(JINSHU_LIGHT_BODY_LINE_HEIGHT)
        .fontWeight(FontWeight.Medium)
        .fontColor(p.textPrimary)
        .width('100%')
    } else {
      JinshuUnderlineText({
        text: bodyText,
        accent: p.accent ?? '#FF39FF14',
        fontSize: this.isJinshuLight() ? JINSHU_LIGHT_BODY_FONT_SIZE : 15,
        lineHeight: this.isJinshuLight() ? JINSHU_LIGHT_BODY_LINE_HEIGHT : 22,
        fontColor: p.textPrimary,
        useSolidUnderline: this.isJinshuLight(),
        highlightOnly: this.isJinshuLight()
      })
    }
  }

  @Builder
  private buildJinshuShareImage(block: MarkdownBlock) {
    if (this.isLocalNoteImageSrc(block.language) && !this.localNoteImageExists(block.language)) {
      Column({ space: 10 }) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color(this.palette().accent ?? '#FF39FF14')
        Text(block.content.length > 0 ? block.content : '图片同步中…')
          .fontSize(12)
          .fontColor(this.palette().textSecondary)
      }
      .width('100%')
      .padding({ top: 28, bottom: 28 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.palette().codeBackground)
      .borderRadius(12)
    } else {
      Image(this.resolveImageSrc(block.language))
        .width('100%')
        .objectFit(ImageFit.Cover)
        .borderRadius(12)
        .alt(block.content)
    }
  }

  @Builder
  private buildJinshuMixedBody(p: ShareThemePalette) {
    Column({ space: 14 }) {
      ForEach(this.previewBlocks, (block: MarkdownBlock, index: number) => {
        if (block.type === 'image') {
          this.buildJinshuShareImage(block)
        } else if (block.type !== 'divider') {
          if (this.jinshuBlockPlainText(block).length > 0) {
            this.buildJinshuBodyContent(p, this.jinshuBlockPlainText(block))
          }
        }
      }, (block: MarkdownBlock, index: number) =>
        `${this.styleKey}_jinshu_mixed_${block.type}_${index}_${block.content.length}`)
    }
    .width('100%')
  }

  @Builder
  private buildJinshuBody(p: ShareThemePalette) {
    if (this.hasBodyImages()) {
      this.buildJinshuMixedBody(p)
    } else {
      this.buildJinshuBodyContent(p, this.jinshuDisplayText())
    }
  }

  @Builder
  private buildJinshuBodyChunkWrap(p: ShareThemePalette, chunkText: string, chunkIndex: number) {
    Column() {
      this.buildJinshuBodyContent(p, chunkText)
    }
    .width('100%')
    .padding({
      left: JINSHU_LIGHT_BODY_H_PADDING,
      right: JINSHU_LIGHT_BODY_H_PADDING
    })
    .backgroundColor(p.jinshuBackground ?? p.background)
    .id(ShareThemeColors.jinshuLightBodyChunkId(chunkIndex))
  }

  @Builder
  private buildJinshuBodyLight(p: ShareThemePalette) {
    if (this.hasBodyImages()) {
      Column() {
        this.buildJinshuMixedBody(p)
      }
      .width('100%')
      .padding({
        left: JINSHU_LIGHT_BODY_H_PADDING,
        right: JINSHU_LIGHT_BODY_H_PADDING
      })
      .backgroundColor(p.jinshuBackground ?? p.background)
      .id(JINSHU_LIGHT_BODY_ID)
    } else if (this.isJinshuLight() && this.jinshuBodyChunks.length > 1) {
      Column({ space: 0 }) {
        ForEach(this.jinshuBodyChunks, (chunkText: string, chunkIndex: number) => {
          this.buildJinshuBodyChunkWrap(p, chunkText, chunkIndex)
        }, (chunkText: string, chunkIndex: number) =>
          `${this.styleKey}_jinshu_body_chunk_${chunkIndex}_${chunkText.length}`)
      }
      .width('100%')
    } else {
      Column() {
        this.buildJinshuBody(p)
      }
      .width('100%')
      .padding({
        left: JINSHU_LIGHT_BODY_H_PADDING,
        right: JINSHU_LIGHT_BODY_H_PADDING
      })
      .backgroundColor(p.jinshuBackground ?? p.background)
      .id(JINSHU_LIGHT_BODY_ID)
    }
  }

  @Builder
  private buildClassicCard(p: ShareThemePalette) {
    Column({ space: 0 }) {
      this.buildAvatar()
      Text(this.displayName())
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(p.textPrimary)
        .lineHeight(22)
        .width('100%')
        .margin({ top: 10 })
      Text(this.formatCreatedAt())
        .fontSize(13)
        .fontColor(p.textSecondary)
        .lineHeight(18)
        .width('100%')
        .margin({ top: 4 })
      Column({ space: 14 }) {
        Text(this.titleText())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(p.textPrimary)
          .fontFamily('serif')
          .width('100%')
        this.buildMarkdownBody(p)
      }
      .width('100%')
      .margin({ top: SHARE_HEADER_TO_CONTENT_GAP })
      this.buildClassicFooter(p, true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildQingyuCard(p: ShareThemePalette) {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        this.buildAvatar()
        Column({ space: 4 }) {
          Text(this.displayName())
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(p.textPrimary)
            .lineHeight(22)
            .width('100%')
          Text(this.formatCreatedAt())
            .fontSize(13)
            .fontColor(p.textSecondary)
            .lineHeight(18)
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      Divider()
        .strokeWidth(1)
        .color(p.divider)
        .margin({ top: 16, bottom: 16 })
      this.buildMarkdownBody(p)
      Text(this.titleText())
        .fontSize(14)
        .fontColor(p.textSecondary)
        .fontFamily('serif')
        .lineHeight(20)
        .width('100%')
        .margin({ top: 20 })
      this.buildClassicFooter(p, false)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private calendarDate(): Date {
    const ms = this.noteCreatedAt > 0 ? this.noteCreatedAt : Date.now()
    return new Date(ms)
  }

  @Builder
  private buildCalendarCard(p: ShareThemePalette) {
    Column({ space: 0 }) {
      Text(`${this.calendarDate().getDate()}`)
        .fontSize(72)
        .fontWeight(FontWeight.Bold)
        .fontColor(p.textPrimary)
        .fontFamily('serif')
        .textAlign(TextAlign.Center)
        .width('100%')
      Text(`${ShareThemeColors.MONTH_ENGLISH[this.calendarDate().getMonth()]} ${this.calendarDate().getFullYear()}`)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(p.textPrimary)
        .letterSpacing(1.2)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 4 })
      Text(ShareThemeColors.weekdayChinese(this.calendarDate()))
        .fontSize(14)
        .fontColor(p.textSecondary)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 6 })
      Column()
        .width(48)
        .height(1)
        .backgroundColor(p.divider)
        .margin({ top: 24, bottom: 24 })
      this.buildMarkdownBody(p, true)
      Text(`《${this.titleText()}》`)
        .fontSize(14)
        .fontColor(p.textSecondary)
        .lineHeight(20)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 20 })
      Text(this.displayName())
        .fontSize(13)
        .fontColor(p.textSecondary)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 8 })
      this.buildClassicFooter(p, true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildJinshuLightQuote(p: ShareThemePalette) {
    Row() {
      Text('“')
        .fontSize(JINSHU_LIGHT_QUOTE_FONT_SIZE)
        .fontWeight(FontWeight.Bold)
        .lineHeight(JINSHU_LIGHT_QUOTE_FONT_SIZE)
        .fontColor('#FFFFCFE0')
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .padding({
      top: JINSHU_LIGHT_QUOTE_EDGE,
      left: JINSHU_LIGHT_QUOTE_EDGE
    })
    .margin({ bottom: JINSHU_LIGHT_BODY_TOP_GAP })
    .backgroundColor(p.jinshuBackground ?? p.background)
    .id(JINSHU_LIGHT_QUOTE_ID)
  }

  @Builder
  private buildJinshuLightFooter(p: ShareThemePalette) {
    Column() {
      Divider()
        .strokeWidth(1)
        .color(p.divider)
        .margin({ top: JINSHU_LIGHT_FOOTER_TOP_GAP, bottom: 16 })
      Row({ space: SHARE_FOOTER_QR_GAP }) {
        Column({ space: 10 }) {
          this.buildSloganTexts(p)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .id(JINSHU_LIGHT_SLOGAN_ID)
        Column() {
          this.buildQrCode(p)
        }
        .id(JINSHU_LIGHT_QR_ID)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .id(JINSHU_LIGHT_FOOTER_ID)
    }
    .width('100%')
    .padding({
      left: JINSHU_LIGHT_FOOTER_EDGE,
      right: JINSHU_LIGHT_FOOTER_EDGE,
      bottom: JINSHU_LIGHT_FOOTER_EDGE
    })
    .backgroundColor(p.jinshuBackground ?? p.background)
    .id(JINSHU_LIGHT_DIVIDER_ID)
  }

  @Builder
  private buildJinshuCard(p: ShareThemePalette) {
    Column({ space: 0 }) {
      if (this.isJinshuLight() && !this.snapshotCompatMode) {
        this.buildJinshuLightQuote(p)
      }
      if (p.showJinshuDecor) {
        Text('+++')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(p.accent ?? '#FF39FF14')
          .letterSpacing(2)
          .width('100%')
          .margin({ bottom: 16 })
      }
      if (this.isJinshuLight()) {
        this.buildJinshuBodyLight(p)
      } else {
        this.buildJinshuBody(p)
      }
      if (this.isJinshuLight()) {
        this.buildJinshuLightFooter(p)
      } else {
        this.buildClassicFooter(p, true)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .id(JINSHU_LIGHT_CARD_INNER_ID)
  }

  @Builder
  private buildCardInner(p: ShareThemePalette) {
    if (this.theme === ShareCardTheme.QINGYU) {
      this.buildQingyuCard(p)
    } else if (this.theme === ShareCardTheme.CALENDAR) {
      this.buildCalendarCard(p)
    } else if (this.theme === ShareCardTheme.JINSHU) {
      this.buildJinshuCard(p)
    } else {
      this.buildClassicCard(p)
    }
  }

  @Builder
  private buildJinshuShell(p: ShareThemePalette) {
    Column() {
      this.buildCardInner(p)
    }
    .width('100%')
    .padding(p.contentPadding ?? DEFAULT_SHARE_CONTENT_PADDING)
    .borderRadius(this.isJinshuLight() ? 0 : 16)
    .backgroundColor(p.jinshuBackground ?? p.background)
    .alignItems(HorizontalAlign.Start)
    .id(JINSHU_LIGHT_SHELL_ID)
    .onAreaChange((_: Area, area: Area) => {
      const h = Number.parseFloat(`${area.height}`)
      if (h > 0) {
        this.onAreaHeight(h)
      }
    })
  }

  @Builder
  private buildDoubleBorderShell(p: ShareThemePalette) {
    Column() {
      Column() {
        this.buildCardInner(p)
      }
      .width('100%')
      .padding(18)
      .border({ width: 1, color: p.borderColor ?? p.divider })
      .linearGradient(p.backgroundGradient !== undefined ? {
        angle: 135,
        colors: [[p.backgroundGradient[0], 0], [p.backgroundGradient[1], 1]]
      } : undefined)
      .backgroundColor(p.backgroundGradient === undefined ? p.background : '#00000000')
    }
    .width('100%')
    .padding(3)
    .border({ width: 1, color: p.borderColor ?? p.divider })
    .onAreaChange((_: Area, area: Area) => {
      const h = Number.parseFloat(`${area.height}`)
      if (h > 0) {
        this.onAreaHeight(h)
      }
    })
  }

  @Builder
  private buildDefaultShell(p: ShareThemePalette) {
    Column() {
      this.buildCardInner(p)
    }
    .width('100%')
    .padding(18)
    .linearGradient(p.backgroundGradient !== undefined ? {
      angle: 135,
      colors: [[p.backgroundGradient[0], 0], [p.backgroundGradient[1], 1]]
    } : undefined)
    .backgroundColor(p.backgroundGradient === undefined ? p.background : '#00000000')
    .alignItems(HorizontalAlign.Start)
    .onAreaChange((_: Area, area: Area) => {
      const h = Number.parseFloat(`${area.height}`)
      if (h > 0) {
        this.onAreaHeight(h)
      }
    })
  }

  @Builder
  private buildCardShell() {
    if (this.theme === ShareCardTheme.JINSHU) {
      this.buildJinshuShell(this.palette())
    } else {
      this.buildStandardShell(this.palette())
    }
  }

  @Builder
  private buildStandardShell(p: ShareThemePalette) {
    if (p.showDoubleBorder && p.borderColor !== undefined) {
      this.buildDoubleBorderShell(p)
    } else {
      this.buildDefaultShell(p)
    }
  }

  build() {
    Column() {
      this.buildCardShell()
    }
    .width('100%')
    .id(NOTE_SHARE_EXPORT_SNAPSHOT_ID)
    .onAppear(() => {
      this.logBuild('build')
    })
  }
}
