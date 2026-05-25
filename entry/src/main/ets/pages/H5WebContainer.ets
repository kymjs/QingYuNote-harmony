import { webview } from '@kit.ArkWeb'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'

interface H5WebContainerParams {
  title?: string
  url?: string
}

@Entry
@Component
struct H5WebContainer {
  @State pageTitle: string = ''
  @State webUrl: string = 'about:blank'
  @State isLoading: boolean = false
  private webController: webview.WebviewController = new webview.WebviewController()
  private closeGuard = new PageCloseGuard()

  private shouldShowLoadingOverlay(): boolean {
    return this.isLoading &&
      (this.webUrl.startsWith('http://') || this.webUrl.startsWith('https://'))
  }

  aboutToAppear(): void {
    this.closeGuard.reset()
    try {
      const params = this.getUIContext().getRouter().getParams() as H5WebContainerParams
      const titleRaw = params?.title
      this.pageTitle =
        typeof titleRaw === 'string' && titleRaw.trim().length > 0 ? titleRaw.trim() : '网页'
      const urlRaw = params?.url
      const urlStr = typeof urlRaw === 'string' ? urlRaw.trim() : ''
      if (urlStr.length > 0 && (urlStr.startsWith('https://') || urlStr.startsWith('http://'))) {
        this.webUrl = urlStr
        this.isLoading = true
      } else {
        this.webUrl = 'about:blank'
        this.isLoading = false
        try {
          this.getUIContext().getPromptAction().showToast({
            message: '无效的链接',
            duration: 2000
          })
        } catch (_) {
          console.error('H5WebContainer invalid url toast failed')
        }
      }
    } catch (e) {
      console.error(`H5WebContainer aboutToAppear: ${JSON.stringify(e)}`)
      this.pageTitle = '网页'
      this.webUrl = 'about:blank'
      this.isLoading = false
    }
  }

  private handleToolbarBack(): void {
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'H5WebContainer')
  }

  onBackPress(): boolean {
    this.handleToolbarBack()
    return true
  }

  build() {
    Column() {
      Row() {
        Row() {
          Image($r('app.media.ic_back'))
            .width($r('app.float.toolbar_back_icon_size'))
            .height($r('app.float.toolbar_back_icon_size'))
            .objectFit(ImageFit.Contain)
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
          Text(this.pageTitle)
            .fontSize($r('app.float.title_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16 })

      Stack() {
        Web({ src: this.webUrl, controller: this.webController })
          .width('100%')
          .height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onPageBegin(() => {
            this.isLoading = true
          })
          .onPageEnd(() => {
            this.isLoading = false
          })
          .onErrorReceive(() => {
            this.isLoading = false
          })
          .onHttpErrorReceive(() => {
            this.isLoading = false
          })

        if (this.shouldShowLoadingOverlay()) {
          Column({ space: 16 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color($r('app.color.accent'))
            Text('加载中…')
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.secondary_text'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.app_background'))
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.app_background'))
  }
}
