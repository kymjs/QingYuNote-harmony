import type { MarkdownBlock } from '../common/utils/MarkdownUtils'
import type { ProfileBody } from '../services/NoteApiClient'
import { Logger } from '../common/utils/Logger'
import { NoteEditMarkdownBlocksView } from '../pages/NoteEditMarkdownBlocksView'
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

export const SHARE_SLOGAN: string = '记录本身，就是意义。'
export const SHARE_INTRO: string =
  '轻羽云笔记同时支持手机与电脑全平台，无论你正在使用哪台设备，笔记都在手边。'
export const SHARE_HEADER_TO_CONTENT_GAP: number = 30
export const SHARE_AVATAR_SIZE: number = 48
export const SHARE_QR_SIZE: number = 72
export const SHARE_FOOTER_QR_GAP: number = 12

@Component
export struct NoteShareExportCard {
  @Prop theme: ShareCardTheme = ShareCardTheme.CLASSIC
  @Prop tone: ShareCardTone = ShareCardTone.DARK
  /** 含 captureKey，主题/色调切换时强制 Markdown 块重建。 */
  @Prop styleKey: string = ''
  @Prop title: string = ''
  @Prop content: string = ''
  @Prop previewBlocks: MarkdownBlock[] = []
  @Prop filesDirCache: string = ''
  @Prop noteCreatedAt: number = 0
  @Prop shareProfile: ProfileBody | null = null
  @State shareAvatarNetworkFailed: boolean = false
  onLinkToast: (href: string) => void = (_href: string) => {
  }
  onAreaHeight: (heightVp: number) => void = (_h: number) => {
  }

  aboutToAppear(): void {
    this.logBuild('aboutToAppear')
  }

  aboutToReuse(): void {
    this.shareAvatarNetworkFailed = false
    this.logBuild('aboutToReuse')
  }

  private logBuild(stage: string): void {
    const p = this.palette()
    Logger.info('NoteShareExportCard',
      `${stage} styleKey=${this.styleKey} theme=${this.theme} tone=${this.tone} ` +
      `bg=${p.background} text=${p.textPrimary} gradient=${p.backgroundGradient?.join('->') ?? 'none'}`)
  }

  private palette(): ShareThemePalette {
    return ShareThemeColors.resolve(this.theme, this.tone)
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
        this.theme === ShareCardTheme.CALENDAR)
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
      .fontSize(this.theme === ShareCardTheme.QINGYU ? 11 : 12)
      .fontColor(p.textSecondary)
      .lineHeight(18)
      .width('100%')
  }

  @Builder
  private buildQrCode(p: ShareThemePalette) {
    if (this.useTransparentQr()) {
      Image($r('app.media.website_qrcode'))
        .width(SHARE_QR_SIZE)
        .height(SHARE_QR_SIZE)
        .objectFit(ImageFit.Contain)
    } else {
      Stack() {
        Column()
          .width(SHARE_QR_SIZE)
          .height(SHARE_QR_SIZE)
          .backgroundColor(p.textPrimary)
        Image($r('app.media.website_qrcode'))
          .width(SHARE_QR_SIZE)
          .height(SHARE_QR_SIZE)
          .objectFit(ImageFit.Contain)
      }
      .width(SHARE_QR_SIZE)
      .height(SHARE_QR_SIZE)
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
  private buildJinshuBody(p: ShareThemePalette) {
    JinshuUnderlineText({
      text: ShareThemeColors.stripMarkdown(this.content),
      accent: p.accent ?? '#FF39FF14',
      fontSize: 15,
      lineHeight: 22,
      fontColor: p.textPrimary
    })
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
  private buildJinshuCard(p: ShareThemePalette) {
    Column({ space: 0 }) {
      if (p.showJinshuDecor) {
        Text('+++')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(p.accent ?? '#FF39FF14')
          .letterSpacing(2)
          .width('100%')
          .margin({ bottom: 16 })
      }
      this.buildJinshuBody(p)
      this.buildClassicFooter(p, true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
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
    .borderRadius(16)
    .backgroundColor(p.jinshuBackground ?? p.background)
    .alignItems(HorizontalAlign.Start)
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
