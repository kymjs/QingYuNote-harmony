import { AppContextHolder } from '../services/AppContextHolder'
import { PreferencesService } from '../services/PreferencesService'
import { LinkExtractHistoryService, type LinkExtractHistoryItem } from '../services/LinkExtractHistoryService'
import { AiNoteBackgroundTaskService } from '../services/AiNoteBackgroundTaskService'
import { NoteRepository } from '../services/NoteRepository'
import { LinkUrlUtils } from '../common/utils/LinkUrlUtils'
import { EditorUiStrings } from '../common/utils/EditorUiStrings'
import { APP_LOCALE_REVISION_KEY } from '../services/LocaleService'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'
import { ensureAiMembershipAccess } from '../common/utils/AiMembershipGateNavigation'
import { isExtractStatusPending, type Note } from '../common/model/Note'

interface LinkExtractParams {
  noteId?: string
  prefillUrl?: string
}

@Entry
@Component
struct LinkExtract {
  @StorageProp(APP_LOCALE_REVISION_KEY) localeRevision: number = 0
  @State urlDraft: string = ''
  @State history: LinkExtractHistoryItem[] = []
  @State submitting: boolean = false
  private closeGuard = new PageCloseGuard()
  private noteId: string = ''

  aboutToAppear(): void {
    this.closeGuard.reset()
    try {
      const params = this.getUIContext().getRouter().getParams() as LinkExtractParams
      this.noteId = `${params.noteId ?? ''}`.trim()
      const prefill = `${params.prefillUrl ?? ''}`.trim()
      if (prefill.length > 0) {
        this.urlDraft = prefill
      }
    } catch (_) {
      // ignore
    }
    void this.bootstrap()
  }

  private loc(zh: string, en: string, ja: string = en): string {
    return EditorUiStrings.loc(zh, en, ja)
  }

  private handleToolbarBack(): void {
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'LinkExtract')
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
    const loggedIn = await PreferencesService.getInstance().isUserLoggedIn()
    const guest = await PreferencesService.getInstance().isGuestMode()
    if (!loggedIn || guest) {
      try {
        await this.getUIContext().getRouter().pushUrl({ url: 'pages/Login' })
      } catch (_) {
        // ignore
      }
      const stillIn = await PreferencesService.getInstance().isUserLoggedIn()
      const stillGuest = await PreferencesService.getInstance().isGuestMode()
      if (!stillIn || stillGuest) {
        this.getUIContext().getRouter().back()
        return
      }
    }
    this.history = await LinkExtractHistoryService.getInstance().list()
  }

  private extractedUrl(): string | null {
    return LinkUrlUtils.extractFirstUrl(this.urlDraft)
  }

  private async onStartExtract(): Promise<void> {
    if (this.submitting) {
      return
    }
    const url = this.extractedUrl()
    if (url === null) {
      this.toast(this.loc('请粘贴有效的链接', 'Please paste a valid link', '有効なリンクを貼り付けてください'))
      return
    }
    if (!(await ensureAiMembershipAccess(this.getUIContext()))) {
      return
    }
    const svc = AiNoteBackgroundTaskService.getInstance()
    if (!svc.ensureIdleOrNotifyBusy()) {
      return
    }
    if (!(await svc.ensureNoPendingExtractOrNotify())) {
      return
    }
    this.submitting = true
    const started = await svc.runExtractLink(this.noteId, url, 0)
    this.submitting = false
    const resultId = `${svc.lastResult?.noteId ?? ''}`.trim()
    if (!started || resultId.length === 0) {
      return
    }
    try {
      await this.getUIContext().getRouter().replaceUrl({
        url: 'pages/LinkExtractProgress',
        params: {
          noteId: resultId,
          kind: 'linkExtract',
          url: url
        }
      })
    } catch (error) {
      console.error(`open progress: ${JSON.stringify(error)}`)
    }
  }

  private async onHistoryTap(item: LinkExtractHistoryItem): Promise<void> {
    const note = await NoteRepository.getInstance().getNote(item.noteId)
    if (note === null || note.deleted) {
      this.urlDraft = item.url
      return
    }
    if (isExtractStatusPending(note.extractStatus) ||
      note.extractStatus === 'failed' ||
      note.voiceTranscribeStatus === 'running' ||
      note.voiceTranscribeStatus === 'failed') {
      const kind = note.sourceUrl.trim().length === 0 &&
        note.extractStatus !== 'failed' &&
        !isExtractStatusPending(note.extractStatus)
        ? 'voiceTranscribe'
        : 'linkExtract'
      try {
        await this.getUIContext().getRouter().pushUrl({
          url: 'pages/LinkExtractProgress',
          params: {
            noteId: note.id,
            kind: kind,
            url: note.sourceUrl.trim().length > 0 ? note.sourceUrl.trim() : item.url
          }
        })
      } catch (error) {
        console.error(`history progress: ${JSON.stringify(error)}`)
      }
      return
    }
    await this.openNote(note)
  }

  private async openNote(note: Note): Promise<void> {
    try {
      if (`${note.audioId ?? ''}`.trim().length > 0) {
        await this.getUIContext().getRouter().pushUrl({
          url: 'pages/VoiceNoteDetail',
          params: { noteId: note.id }
        })
      } else {
        await this.getUIContext().getRouter().pushUrl({
          url: 'pages/NoteEdit',
          params: { noteId: note.id, openWithPreview: note.content.trim().length > 0 }
        })
      }
    } catch (error) {
      console.error(`openNote: ${JSON.stringify(error)}`)
    }
  }

  private formatHistoryDate(ms: number): string {
    if (ms <= 0) {
      return ''
    }
    const dt = new Date(ms)
    const m = `${dt.getMonth() + 1}`.padStart(2, '0')
    const d = `${dt.getDate()}`.padStart(2, '0')
    return `${m}-${d}`
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message, duration: 2000 })
    } catch (_) {
      // ignore
    }
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

      Scroll() {
        Column({ space: 16 }) {
          Text(this.loc('粘贴链接', 'Paste link', 'リンクを貼り付け'))
            .fontSize(13)
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
            .textAlign(TextAlign.Start)

          TextInput({
            text: this.urlDraft,
            placeholder: 'https://'
          })
            .width('100%')
            .onChange((v: string) => {
              this.urlDraft = v
            })

          Button(this.submitting
            ? this.loc('AI 提交中…', 'Submitting…', '送信中…')
            : this.loc('开始提取', 'Start extract', '抽出を開始'))
            .width('100%')
            .height(48)
            .enabled(this.extractedUrl() !== null && !this.submitting)
            .backgroundColor($r('app.color.accent'))
            .fontColor($r('app.color.on_accent'))
            .borderRadius(12)
            .onClick(() => {
              void this.onStartExtract()
            })

          if (this.history.length > 0) {
            Text(this.loc('历史记录', 'History', '履歴'))
              .fontSize(13)
              .fontColor($r('app.color.secondary_text'))
              .width('100%')
              .textAlign(TextAlign.Start)
              .margin({ top: 8 })

            ForEach(this.history, (item: LinkExtractHistoryItem) => {
              Row() {
                Column({ space: 4 }) {
                  Text(item.title.trim().length > 0
                    ? item.title
                    : this.formatHistoryDate(item.createdAtMs))
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.primary_text'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(item.url)
                    .fontSize(12)
                    .fontColor($r('app.color.secondary_text'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Text(this.formatHistoryDate(item.createdAtMs))
                  .fontSize(12)
                  .fontColor($r('app.color.secondary_text'))
                  .margin({ left: 8 })
              }
              .width('100%')
              .padding(14)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(12)
              .border({ width: 1, color: $r('app.color.card_border') })
              .onClick(() => {
                void this.onHistoryTap(item)
              })
            }, (item: LinkExtractHistoryItem) => `${item.noteId}_${item.createdAtMs}`)
          }
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 24 })
        .width('100%')
        .constraintSize({ maxWidth: 450 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      Column() {
        this.platformFooter()
      }
      .padding({ left: 16, right: 16, bottom: 28, top: 8 })
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }
}
