import { Want } from '@kit.AbilityKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { AppContextHolder } from '../services/AppContextHolder'
import { PageLifecycle } from '../common/utils/PageLifecycle'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'
import { bookImportStatusText } from '../common/utils/ImportProgressStatusText'
import {
  pollSystemClipboardToken,
  takePendingApiKeyFromAppStorage
} from '../common/utils/ImportClipboardHelper'
import { PreferencesService } from '../services/PreferencesService'
import {
  WereadImportException,
  WereadImportProgress,
  WereadImportService
} from '../services/WereadImportService'

const WEREAD_API_KEY_URL = 'https://weread.qq.com/r/weread-skills'
const WEREAD_API_KEY_PREFIX = 'wrk-'

@Entry
@Component
struct WereadImport {
  @State token: string = ''
  @State importing: boolean = false
  @State statusText: string = ''
  @State loadingToken: boolean = true

  private lifecycle = new PageLifecycle()
  private closeGuard = new PageCloseGuard()
  private progressTimer: number = -1
  // 标记「点过获取 API Key」，下一次 onPageShow 时再读取剪贴板（与 Flutter _tryImportFromClipboard 行为对齐）
  private awaitingApiKeyReturn: boolean = false
  // 防抖：记录上次成功粘贴的 API Key，避免 onPageShow 反复触发同一导入
  private lastImportedKey: string = ''

  aboutToAppear(): void {
    this.lifecycle.appear()
    this.closeGuard.reset()
    void this.loadToken()
    this.syncImportUi()
    this.startProgressPolling()
  }

  aboutToDisappear(): void {
    this.lifecycle.disappear()
    this.stopProgressPolling()
  }

  onPageShow(): void {
    if (this.awaitingApiKeyReturn) {
      this.awaitingApiKeyReturn = false
      void this.tryImportFromClipboard()
    }
  }

  onBackPress(): boolean {
    this.handleToolbarBack()
    return true
  }

  private startProgressPolling(): void {
    this.stopProgressPolling()
    this.progressTimer = setInterval(() => {
      if (!this.lifecycle.isActive()) {
        return
      }
      this.syncImportUi()
    }, 400)
  }

  private stopProgressPolling(): void {
    if (this.progressTimer >= 0) {
      clearInterval(this.progressTimer)
      this.progressTimer = -1
    }
  }

  private syncImportUi(): void {
    const service = WereadImportService.getInstance()
    this.importing = service.isImportRunning()
    this.statusText = this.statusTextFromProgress(service.getProgress(), this.importing)
  }

  private statusTextFromProgress(
    progress: WereadImportProgress | null,
    running: boolean
  ): string {
    if (progress === null) {
      return bookImportStatusText(null, running)
    }
    return bookImportStatusText({
      processedBooks: progress.processedBooks,
      totalBooks: progress.totalBooks,
      currentBookTitle: progress.currentBookTitle
    }, running)
  }

  private async loadToken(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    if (!this.lifecycle.isActive()) {
      return
    }
    this.token = PreferencesService.getInstance().getWereadApiKey()
    this.loadingToken = false
  }

  private handleToolbarBack(): void {
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'WereadImport')
  }

  private isPcDevice(): boolean {
    return deviceInfo.deviceType === '2in1'
  }

  private openApiKeyPageInSystemBrowser(): void {
    const context = AppContextHolder.tryGetContext()
    if (context === undefined) {
      return
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: WEREAD_API_KEY_URL
    }
    context.startAbility(want).catch((err: Error) => {
      console.error(`openWereadApiKeyPage: ${JSON.stringify(err)}`)
    })
  }

  private openApiKeyPageInAppBrowser(): void {
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/H5WebContainer',
        params: {
          title: '获取 API Key',
          url: WEREAD_API_KEY_URL
        }
      }).catch((err: Error) => {
        console.error(`openWereadApiKeyPageInApp: ${JSON.stringify(err)}`)
      })
    } catch (error) {
      console.error(`openWereadApiKeyPageInApp: ${JSON.stringify(error)}`)
    }
  }

  private openApiKeyPage(): void {
    this.awaitingApiKeyReturn = true
    if (this.isPcDevice()) {
      this.openApiKeyPageInSystemBrowser()
      return
    }
    this.openApiKeyPageInAppBrowser()
  }

  private showToast(message: string): void {
    if (message.trim().length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message: message })
    } catch (_) {
    }
  }

  private onConfirm(): void {
    if (WereadImportService.getInstance().isImportRunning()) {
      return
    }
    const trimmed = this.token.trim()
    if (trimmed.length === 0) {
      this.showToast('请输入微信读书 API Key')
      return
    }
    this.lastImportedKey = trimmed

    void WereadImportService.getInstance().importAllNotes(trimmed).catch((error: Object) => {
      if (error instanceof WereadImportException) {
        return
      }
    })
    this.syncImportUi()
  }

  /** WebView 关闭后被调用:优先取 H5WebContainer 通过 AppStorage 传过来的 wrk- key;读不到再读系统剪贴板兜底。 */
  private async tryImportFromClipboard(): Promise<void> {
    if (!this.lifecycle.isActive()) {
      return
    }
    if (WereadImportService.getInstance().isImportRunning()) {
      return
    }

    const stored = takePendingApiKeyFromAppStorage('pendingWereadApiKey')
    if (stored.length > 0 && stored.startsWith(WEREAD_API_KEY_PREFIX)) {
      this.startImportWithKey(stored)
      return
    }

    const trimmed = await pollSystemClipboardToken(WEREAD_API_KEY_PREFIX)
    if (trimmed.length === 0) {
      return
    }
    this.startImportWithKey(trimmed)
  }

  private startImportWithKey(trimmed: string): void {
    if (trimmed === this.lastImportedKey) {
      // 同一 Key 已经在本次会话导入过，避免重复触发
      return
    }
    if (!this.lifecycle.isActive()) {
      return
    }
    this.token = trimmed
    this.lastImportedKey = trimmed
    this.showToast('已识别 API Key，正在开始导入…')
    this.onConfirm()
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
          Text($r('app.string.weread_import_title'))
            .fontSize($r('app.float.title_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .alignItems(VerticalAlign.Center)

      Column() {
        Column({ space: 12 }) {
            Text($r('app.string.weread_import_hint'))
              .fontSize(14)
              .fontColor($r('app.color.secondary_text'))
              .lineHeight(22)

            Button($r('app.string.weread_import_get_api_key'))
              .type(ButtonType.Capsule)
              .enabled(!this.importing)
              .backgroundColor($r('app.color.editor_background'))
              .fontColor($r('app.color.accent'))
              .border({ width: 1, color: $r('app.color.accent') })
              .width('100%')
              .onClick(() => {
                if (!this.importing) {
                  this.openApiKeyPage()
                }
              })

            Row({ space: 10 }) {
              // 与首页顶部搜索框 `Index.buildHomeHeader` 对齐：
              // 边框/背景/圆角放在外层 Row 上，TextInput 透明无边框，
              // 清空按钮作为子项嵌入「输入框」内部右侧。
              Row() {
                TextInput({ text: this.token, placeholder: 'wrk-xxxxxxxx' })
                  .layoutWeight(1)
                  .enabled(!this.importing && !this.loadingToken)
                  .fontSize($r('app.float.body_font_size'))
                  .fontColor($r('app.color.primary_text'))
                  .placeholderColor($r('app.color.tertiary_text'))
                  .backgroundColor(Color.Transparent)
                  .border({ width: 0 })
                  .padding({ left: 14, right: 4, top: 0, bottom: 0 })
                  .onChange((value: string) => {
                    this.token = value
                  })

                if (this.token.length > 0 && !this.importing && !this.loadingToken) {
                  Row() {
                    SymbolGlyph($r('sys.symbol.xmark'))
                      .fontSize(16)
                      .fontColor([$r('app.color.secondary_text')])
                  }
                  .padding({ left: 6, right: 10, top: 10, bottom: 10 })
                  .onClick(() => {
                    this.token = ''
                  })
                }
              }
              .layoutWeight(1)
              .height(44)
              .alignItems(VerticalAlign.Center)
              .backgroundColor($r('app.color.editor_background'))
              .borderRadius(12)
              .border({ width: 1, color: $r('app.color.card_border') })

              Button('导入')
                .type(ButtonType.Capsule)
                .enabled(!this.importing && !this.loadingToken)
                .backgroundColor($r('app.color.accent'))
                .fontColor(Color.White)
                .padding({ left: 18, right: 18 })
                .onClick(() => {
                  this.onConfirm()
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)

            if (this.importing && this.statusText.length > 0) {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color($r('app.color.accent'))
                Text(this.statusText)
                  .fontSize(13)
                  .fontColor($r('app.color.secondary_text'))
                  .layoutWeight(1)
              }
              .width('100%')
            }
          }
          .padding(20)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({ width: 1, color: $r('app.color.card_border') })
          .shadow({
            radius: 20,
            color: $r('app.color.shadow_color'),
            offsetX: 0,
            offsetY: 4
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 15, bottom: 32 })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }
}
