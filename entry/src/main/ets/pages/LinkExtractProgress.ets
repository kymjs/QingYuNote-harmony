import { AppContextHolder } from '../services/AppContextHolder'
import { PreferencesService } from '../services/PreferencesService'
import { LinkExtractHistoryService } from '../services/LinkExtractHistoryService'
import { AiNoteBackgroundTaskService } from '../services/AiNoteBackgroundTaskService'
import { NoteRepository } from '../services/NoteRepository'
import { LinkExtractClient } from '../services/LinkExtractClient'
import { EditorUiStrings } from '../common/utils/EditorUiStrings'
import { APP_LOCALE_REVISION_KEY } from '../services/LocaleService'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'
import { PageLifecycle } from '../common/utils/PageLifecycle'
import {
  isExtractStatusPending,
  type Note,
  type UpdateExtractInfo
} from '../common/model/Note'

interface LinkExtractProgressParams {
  noteId?: string
  kind?: string
  url?: string
}

@Entry
@Component
struct LinkExtractProgress {
  @StorageProp(APP_LOCALE_REVISION_KEY) localeRevision: number = 0
  @State uiState: string = 'processing'
  @State stepPhase: number = 0
  @State retrying: boolean = false
  private closeGuard = new PageCloseGuard()
  private lifecycle = new PageLifecycle()
  private noteId: string = ''
  private kind: string = 'linkExtract'
  private url: string = ''
  private stepTimer: number = -1
  private pollTimer: number = -1
  private navigatingAway: boolean = false
  private readonly placeholderTitleZh: string = 'AI提取链接中'
  private readonly placeholderContentZh: string = '已提交链接摘要，提取完成后会自动更新笔记'

  aboutToAppear(): void {
    this.lifecycle.appear()
    this.closeGuard.reset()
    try {
      const params = this.getUIContext().getRouter().getParams() as LinkExtractProgressParams
      this.noteId = `${params.noteId ?? ''}`.trim()
      this.kind = `${params.kind ?? 'linkExtract'}`.trim()
      this.url = `${params.url ?? ''}`.trim()
    } catch (_) {
      // ignore
    }
    void this.bootstrap()
  }

  aboutToDisappear(): void {
    this.clearTimers()
    this.lifecycle.disappear()
  }

  private loc(zh: string, en: string, ja: string = en): string {
    return EditorUiStrings.loc(zh, en, ja)
  }

  private clearTimers(): void {
    if (this.stepTimer !== -1) {
      clearInterval(this.stepTimer)
      this.stepTimer = -1
    }
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer)
      this.pollTimer = -1
    }
  }

  private handleToolbarBack(): void {
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'LinkExtractProgress')
  }

  onBackPress(): boolean {
    this.handleToolbarBack()
    return true
  }

  private async bootstrap(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    const note = await NoteRepository.getInstance().getNote(this.noteId)
    if (!this.lifecycle.isActive()) {
      return
    }
    if (note === null) {
      this.uiState = 'failed'
      return
    }
    if (this.url.length === 0 && note.sourceUrl.trim().length > 0) {
      this.url = note.sourceUrl.trim()
    }
    if (this.isFailedNote(note)) {
      this.uiState = 'failed'
      return
    }
    if (this.isSucceededNote(note)) {
      await this.openNoteAndClose(note)
      return
    }
    this.uiState = 'processing'
    this.startStepAnimation()
    this.startPolling()
  }

  private isFailedNote(note: Note): boolean {
    if (this.kind === 'linkExtract') {
      return note.extractStatus === 'failed'
    }
    return note.voiceTranscribeStatus === 'failed' || note.extractStatus === 'failed'
  }

  private isSucceededNote(note: Note): boolean {
    if (this.kind === 'linkExtract') {
      return note.extractStatus === 'succeeded' || note.extractStatus === 'partial'
    }
    if (isExtractStatusPending(note.extractStatus)) {
      return false
    }
    return note.voiceTranscribeStatus === 'succeeded' ||
      (note.content.trim().length > 0 &&
        note.voiceTranscribeStatus !== 'running' &&
        note.voiceTranscribeStatus !== 'failed' &&
        !isExtractStatusPending(note.extractStatus))
  }

  private startStepAnimation(): void {
    if (this.stepTimer !== -1) {
      clearInterval(this.stepTimer)
    }
    this.stepPhase = 0
    this.stepTimer = setInterval(() => {
      if (!this.lifecycle.isActive() || this.uiState !== 'processing') {
        return
      }
      this.stepPhase = (this.stepPhase + 1) % 5
    }, 1000)
  }

  private startPolling(): void {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer)
    }
    void this.pollOnce()
    this.pollTimer = setInterval(() => {
      void this.pollOnce()
    }, 2000)
  }

  private async pollOnce(): Promise<void> {
    if (!this.lifecycle.isActive() || this.navigatingAway) {
      return
    }
    let note = await NoteRepository.getInstance().getNote(this.noteId)
    if (note !== null && isExtractStatusPending(note.extractStatus)) {
      note = await NoteRepository.getInstance().refreshExtractJobForNote(this.noteId)
    }
    note = note ?? await NoteRepository.getInstance().getNote(this.noteId)
    if (!this.lifecycle.isActive() || note === null || this.navigatingAway) {
      return
    }
    if (this.isSucceededNote(note)) {
      await this.openNoteAndClose(note)
      return
    }
    if (this.isFailedNote(note)) {
      this.clearTimers()
      this.uiState = 'failed'
    }
  }

  private async openNoteAndClose(note: Note): Promise<void> {
    if (this.navigatingAway || !this.lifecycle.isActive()) {
      return
    }
    this.navigatingAway = true
    this.clearTimers()
    if (this.kind === 'linkExtract') {
      const title = note.title.trim().length > 0 ? note.title.trim() : this.fallbackHistoryTitle(note)
      const url = this.url.length > 0 ? this.url : note.sourceUrl.trim()
      if (url.length > 0) {
        await LinkExtractHistoryService.getInstance().addSuccess(
          note.id,
          url,
          title,
          note.createdAt > 0 ? note.createdAt : Date.now()
        )
      }
    }
    const hasAudio = `${note.audioId ?? ''}`.trim().length > 0
    const noteId = note.id
    const openWithPreview = note.content.trim().length > 0
    try {
      this.getUIContext().getRouter().back()
      if (hasAudio) {
        await this.getUIContext().getRouter().pushUrl({
          url: 'pages/VoiceNoteDetail',
          params: { noteId: noteId }
        })
      } else {
        await this.getUIContext().getRouter().pushUrl({
          url: 'pages/NoteEdit',
          params: { noteId: noteId, openWithPreview: openWithPreview }
        })
      }
    } catch (error) {
      console.error(`openNoteAndClose: ${JSON.stringify(error)}`)
    }
  }

  private fallbackHistoryTitle(note: Note): string {
    const ms = note.createdAt > 0 ? note.createdAt : Date.now()
    const dt = new Date(ms)
    const m = `${dt.getMonth() + 1}`.padStart(2, '0')
    const d = `${dt.getDate()}`.padStart(2, '0')
    const h = `${dt.getHours()}`.padStart(2, '0')
    const min = `${dt.getMinutes()}`.padStart(2, '0')
    return `${m}-${d} ${h}:${min}`
  }

  private isPlaceholderNote(note: Note): boolean {
    const title = note.title.trim()
    const content = note.content.trim()
    const titleLoc = this.loc(this.placeholderTitleZh, 'AI is extracting the link', 'AIリンク抽出中')
    const titleMatch = title === this.placeholderTitleZh || title === titleLoc
    if (!titleMatch) {
      return title.length === 0 && content.length === 0
    }
    const contentLoc = this.loc(
      this.placeholderContentZh,
      'Submitted; the note will update when extraction finishes.',
      '送信しました。抽出が完了するとノートが自動的に更新されます。'
    )
    return content.length === 0 ||
      content === this.placeholderContentZh ||
      content === contentLoc ||
      content.indexOf('已提交链接') >= 0
  }

  private async onCancel(): Promise<void> {
    if (this.kind !== 'linkExtract') {
      return
    }
    const note = await NoteRepository.getInstance().getNote(this.noteId)
    if (note !== null) {
      if (this.isPlaceholderNote(note)) {
        await NoteRepository.getInstance().deleteNote(note.id, Date.now())
      } else {
        await NoteRepository.getInstance().cancelPendingExtractJob(note)
        if (isExtractStatusPending(note.extractStatus)) {
          const patch: UpdateExtractInfo = {
            noteId: note.id,
            status: 'none',
            jobId: '',
            error: ''
          }
          await NoteRepository.getInstance().updateExtractInfo(patch)
        }
      }
    }
    this.popToHome()
  }

  private popToHome(): void {
    this.navigatingAway = true
    this.clearTimers()
    try {
      void this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' })
    } catch (_) {
      this.getUIContext().getRouter().back()
    }
  }

  private async onRetry(): Promise<void> {
    if (this.retrying) {
      return
    }
    this.retrying = true
    this.uiState = 'processing'
    this.startStepAnimation()
    this.startPolling()
    const svc = AiNoteBackgroundTaskService.getInstance()
    let ok = false
    if (this.kind === 'linkExtract') {
      if (this.url.trim().length === 0 || !svc.ensureIdleOrNotifyBusy()) {
        this.retrying = false
        this.uiState = 'failed'
        this.clearTimers()
        return
      }
      ok = await svc.runExtractLink(this.noteId, this.url, 0)
    } else {
      const note = await NoteRepository.getInstance().getNote(this.noteId)
      if (note !== null && isExtractStatusPending(note.extractStatus)) {
        ok = true
      } else if (note !== null && note.extractStatus === 'failed' && this.url.length > 0) {
        ok = await svc.runExtractLink(this.noteId, this.url, 0)
      }
    }
    this.retrying = false
    if (!ok) {
      this.uiState = 'failed'
      this.clearTimers()
    }
  }

  private async onFeedback(): Promise<void> {
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/H5WebContainer',
        params: {
          title: this.loc('用户反馈', 'Feedback', 'フィードバック'),
          url: 'https://vcnedpub4ekz.feishu.cn/share/base/form/shrcnexjZUlhIkZ4eD9BjcDfdkb'
        }
      })
    } catch (error) {
      console.error(`feedback: ${JSON.stringify(error)}`)
    }
  }

  private stepLabels(): string[] {
    const isPureVoice = this.kind === 'voiceTranscribe' &&
      !LinkExtractClient.isVideoPlatformUrl(this.url)
    if (isPureVoice) {
      return [
        this.loc('解析音频', 'Parse audio', '音声解析'),
        this.loc('提取正文', 'Extract text', '本文抽出'),
        this.loc('优化语气词', 'Clean fillers', 'フィラー除去'),
        this.loc('生成摘要', 'Generate summary', '要約生成')
      ]
    }
    if (LinkExtractClient.isVideoPlatformUrl(this.url)) {
      return [
        this.loc('解析网页', 'Parse page', 'ページ解析'),
        this.loc('提取视频', 'Extract video', '動画抽出'),
        this.loc('创建笔记', 'Create note', 'ノート作成'),
        this.loc('生成摘要', 'Generate summary', '要約生成')
      ]
    }
    return [
      this.loc('解析网页', 'Parse page', 'ページ解析'),
      this.loc('提取正文', 'Extract text', '本文抽出'),
      this.loc('提取图片', 'Extract images', '画像抽出'),
      this.loc('生成摘要', 'Generate summary', '要約生成')
    ]
  }

  private isVoiceFailureCopy(): boolean {
    return this.kind === 'voiceTranscribe' && !LinkExtractClient.isVideoPlatformUrl(this.url)
  }

  @Builder
  private platformFooter() {
    Column({ space: 12 }) {
      Text(this.loc(
        '支持提取文章、视频、图文等网页内容',
        'Supports articles, videos, image posts, and more',
        '記事・動画・画像投稿などのウェブ内容に対応'
      ))
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
      Row({ space: 2 }) {
        Image($r('app.media.ic_link_platform_douyin')).width(40).height(40).borderRadius(10)
        Image($r('app.media.ic_link_platform_xiaohongshu')).width(40).height(40).borderRadius(10)
        Image($r('app.media.ic_link_platform_bilibili')).width(40).height(40).borderRadius(10)
        Image($r('app.media.ic_link_platform_wechat')).width(40).height(40).borderRadius(10)
        Image($r('app.media.ic_link_platform_zhihu')).width(40).height(40).borderRadius(10)
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private processingBody() {
    Column() {
      Blank().layoutWeight(2)
      Image($r('app.media.illust_link_extracting'))
        .width(160)
        .height(160)
        .objectFit(ImageFit.Contain)
      Text(this.loc('AI处理中…', 'AI processing…', 'AI処理中…'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .margin({ top: 24, bottom: 8 })
      Text(this.loc(
        '关闭页面可在后台继续执行',
        'You can close this page and let it continue in background',
        'このページを閉じてもバックグラウンドで続行されます'
      ))
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
        .margin({ bottom: 28 })
      ForEach(this.stepLabels(), (label: string, index: number) => {
        Row({ space: 10 }) {
          Text(index < (this.stepPhase >= 4 ? 0 : this.stepPhase + 1) ? '◆' : '○')
            .fontSize(12)
            .fontColor(index < (this.stepPhase >= 4 ? 0 : this.stepPhase + 1)
              ? $r('app.color.accent')
              : $r('app.color.secondary_text'))
          Text(label)
            .fontSize(16)
            .fontColor(index < (this.stepPhase >= 4 ? 0 : this.stepPhase + 1)
              ? $r('app.color.accent')
              : $r('app.color.secondary_text'))
            .fontWeight(index < (this.stepPhase >= 4 ? 0 : this.stepPhase + 1)
              ? FontWeight.Medium
              : FontWeight.Normal)
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .margin({ top: 6, bottom: 6 })
      }, (label: string, index: number) => `${label}_${index}`)
      Blank().layoutWeight(3)
      if (this.kind === 'linkExtract') {
        Text(this.loc('取消', 'Cancel', 'キャンセル'))
          .fontSize(16)
          .fontColor($r('app.color.accent'))
          .fontWeight(FontWeight.Medium)
          .onClick(() => {
            void this.onCancel()
          })
          .margin({ bottom: 32 })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private failedBody() {
    Scroll() {
      Column({ space: 12 }) {
        Image($r('app.media.illust_link_extract_failed'))
          .width(160)
          .height(160)
          .objectFit(ImageFit.Contain)
          .margin({ top: 24 })
        Text(this.loc('提取失败', 'Extraction failed', '抽出失敗'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Text(this.isVoiceFailureCopy()
          ? this.loc('无法提取该音频的内容', 'Could not extract this audio', 'この音声の内容を抽出できません')
          : this.loc('无法提取该链接的内容', 'Could not extract this link', 'このリンクの内容を抽出できません'))
          .fontSize(14)
          .fontColor($r('app.color.secondary_text'))
          .margin({ bottom: 8 })

        Column({ space: 8 }) {
          Text(this.loc('可能的原因', 'Possible reasons', '考えられる原因'))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
            .textAlign(TextAlign.Start)
          if (this.isVoiceFailureCopy()) {
            Text(`•  ${this.loc('音频嘈杂声太多', 'Audio is too noisy', 'ノイズが多すぎます')}`)
              .fontSize(13).fontColor($r('app.color.secondary_text')).width('100%')
            Text(`•  ${this.loc('音频过长解析超时', 'Audio too long; timed out', '音声が長すぎてタイムアウトしました')}`)
              .fontSize(13).fontColor($r('app.color.secondary_text')).width('100%')
            Text(`•  ${this.loc('录音内容请使用普通话', 'Please record in Mandarin', '普通話で録音してください')}`)
              .fontSize(13).fontColor($r('app.color.secondary_text')).width('100%')
            Text(`•  ${this.loc('音频中没有文字', 'No speech detected in audio', '音声に文字がありません')}`)
              .fontSize(13).fontColor($r('app.color.secondary_text')).width('100%')
          } else {
            Text(`•  ${this.loc('链接不存在或已被删除', 'Link missing or deleted', 'リンクが存在しないか削除されています')}`)
              .fontSize(13).fontColor($r('app.color.secondary_text')).width('100%')
            Text(`•  ${this.loc('链接已失效或无法访问', 'Link expired or unreachable', 'リンクの期限切れまたはアクセス不可')}`)
              .fontSize(13).fontColor($r('app.color.secondary_text')).width('100%')
            Text(`•  ${this.loc('该网站不支持内容提取', 'Site does not support extraction', 'このサイトは抽出に非対応です')}`)
              .fontSize(13).fontColor($r('app.color.secondary_text')).width('100%')
            Text(`•  ${this.loc('内容需要登录或权限限制', 'Login or permission required', 'ログインまたは権限が必要です')}`)
              .fontSize(13).fontColor($r('app.color.secondary_text')).width('100%')
          }
        }
        .width('100%')
        .padding(14)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(12)
        .alignItems(HorizontalAlign.Start)

        Button(this.loc('重新提取', 'Retry', '再抽出'))
          .width('100%')
          .height(48)
          .enabled(!this.retrying)
          .backgroundColor($r('app.color.accent'))
          .fontColor($r('app.color.on_accent'))
          .borderRadius(12)
          .onClick(() => {
            void this.onRetry()
          })

        Button(this.loc('关闭', 'Close', '閉じる'))
          .width('100%')
          .height(48)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.accent'))
          .border({ width: 1, color: $r('app.color.accent') })
          .borderRadius(12)
          .onClick(() => {
            this.handleToolbarBack()
          })

        Row({ space: 6 }) {
          Text(this.loc('需要帮助？', 'Need help?', 'ヘルプが必要ですか？'))
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
          Text(this.loc('反馈问题', 'Send feedback', 'フィードバック'))
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .fontWeight(FontWeight.Medium)
            .onClick(() => {
              void this.onFeedback()
            })
        }
        .justifyContent(FlexAlign.Center)
        .margin({ top: 8, bottom: 16 })

        this.platformFooter()
      }
      .padding({ left: 16, right: 16, bottom: 24 })
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .layoutWeight(1)
  }

  build() {
    Column() {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(18)
            .fontColor([$r('app.color.primary_text')])
        }
        .height('100%')
        .padding({
          left: $r('app.float.toolbar_icon_button_padding_h'),
          right: $r('app.float.toolbar_icon_button_padding_h')
        })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.pill_radius'))
        .onClick(() => {
          this.handleToolbarBack()
        })

        Row() {
          Text(this.loc('链接提取', 'Link extract', 'リンク抽出'))
            .fontSize($r('app.float.title_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)

        Row().width(72)
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .alignItems(VerticalAlign.Center)

      if (this.uiState === 'processing') {
        Column() {
          this.processingBody()
        }
        .layoutWeight(1)
        .width('100%')
        .constraintSize({ maxWidth: 450 })
      } else {
        this.failedBody()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }
}
