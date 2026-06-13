import { webview } from '@kit.ArkWeb'
import { MathJaxHeightBridge } from '../common/utils/MathJaxHeightBridge'
import { MathJaxUtils } from '../common/utils/MathJaxUtils'
import { WebViewSessionCleaner } from '../common/utils/WebViewSessionCleaner'

/** 使用 MathJax 渲染单段 LaTeX（行内或块级）。 */
@Component
export struct MathJaxPreview {
  @Prop @Watch('onLatexChanged') latex: string = ''
  @Prop @Watch('onDisplayChanged') display: boolean = false
  @Prop @Watch('onStyleChanged') textColor: string = '#111111'
  @Prop @Watch('onStyleChanged') previewBackgroundColor: string = 'transparent'
  @State private webHeight: number = 32
  private webController: webview.WebviewController = new webview.WebviewController()
  private webAttached: boolean = false
  private heightBridge: MathJaxHeightBridge = new MathJaxHeightBridge()

  aboutToAppear(): void {
    this.resetWebHeight()
    this.heightBridge.bind((height: number) => {
      this.applyMeasuredHeight(height)
    })
    WebViewSessionCleaner.registerController(this.webController)
  }

  aboutToDisappear(): void {
    WebViewSessionCleaner.unregisterController(this.webController)
  }

  onLatexChanged(): void {
    this.resetWebHeight()
    if (this.webAttached) {
      this.pushHtml()
    }
  }

  onDisplayChanged(): void {
    this.resetWebHeight()
    if (this.webAttached) {
      this.pushHtml()
    }
  }

  onStyleChanged(): void {
    if (this.webAttached) {
      this.pushHtml()
    }
  }

  private resetWebHeight(): void {
    this.webHeight = this.display ? 56 : 32
  }

  private applyMeasuredHeight(rawHeight: number): void {
    const minH = this.display ? 40 : 28
    const next = Math.min(Math.max(rawHeight, minH), 480)
    if (Math.abs(next - this.webHeight) > 0.5) {
      this.webHeight = next
    }
  }

  private measureWebHeight(): void {
    try {
      const pageHeight = this.webController.getPageHeight()
      if (pageHeight > 0) {
        this.applyMeasuredHeight(px2vp(pageHeight))
      }
    } catch (e) {
      console.error(`MathJaxPreview measure height failed: ${JSON.stringify(e)}`)
    }
  }

  private pushHtml(): void {
    const trimmed = this.latex.trim()
    if (trimmed.length === 0) {
      return
    }
    const html = MathJaxUtils.buildPreviewHtml(
      trimmed,
      this.display,
      this.textColor,
      this.previewBackgroundColor
    )
    try {
      this.webController.loadData(
        html,
        'text/html',
        'UTF-8',
        MathJaxUtils.MATHJAX_BASE,
        MathJaxUtils.MATHJAX_BASE
      )
    } catch (e) {
      console.error(`MathJaxPreview loadData failed: ${JSON.stringify(e)}`)
    }
  }

  build() {
    if (this.latex.trim().length === 0) {
      Column()
    } else {
      Column() {
        Web({ src: 'about:blank', controller: this.webController })
          .height(this.webHeight)
          .width(this.display ? '100%' : undefined)
          .constraintSize(this.display ? {} : { maxWidth: '100%' })
          .overScrollMode(OverScrollMode.NEVER)
          .backgroundColor(Color.Transparent)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(true)
          .imageAccess(true)
          .onlineImageAccess(true)
          .mixedMode(MixedMode.All)
          .cacheMode(CacheMode.None)
          .javaScriptProxy({
            object: this.heightBridge,
            name: 'HeightChannel',
            methodList: ['postMessage'],
            controller: this.webController
          })
          .onControllerAttached(() => {
            this.webAttached = true
            this.pushHtml()
          })
          .onPageEnd(() => {
            this.measureWebHeight()
          })
          .onErrorReceive(() => {
            console.error('MathJaxPreview Web error')
          })
      }
      .width(this.display ? '100%' : undefined)
      .constraintSize(this.display ? { minHeight: 48 } : { minHeight: 28, maxWidth: '100%' })
    }
  }
}
