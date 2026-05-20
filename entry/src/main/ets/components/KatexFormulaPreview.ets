import { webview } from '@kit.ArkWeb'
import { FormulaPreviewLog } from '../common/utils/FormulaPreviewLog'
import { KatexHeightBridge } from '../common/utils/KatexHeightBridge'
/** 本地 KaTeX：先加载 preview_shell.html，再 runJavaScript 注入正文（避免 loadData 被 src 导航 abort）。 */
@Component
export struct KatexFormulaPreview {
  @Prop @Watch('onSourceChanged') source: string = ''
  @Prop @Watch('onStyleChanged') textColor: string = '#1D1D1F'
  @Prop @Watch('onStyleChanged') previewBackgroundColor: string = 'transparent'
  @Prop displayBlock: boolean = false
  /** 测量阶段占位高度（vp），须大于最终内容，避免 scrollHeight 被视口截断。 */
  @State private webHeight: number = 360
  /** JS 已测得的内容高度（vp），禁止被 getPageHeight 等错误换算压小。 */
  private maxContentHeightVp: number = 0
  private webController: webview.WebviewController = new webview.WebviewController()
  private heightBridge: KatexHeightBridge = new KatexHeightBridge()
  private webAttached: boolean = false
  private shellReady: boolean = false

  aboutToAppear(): void {
    this.resetHeight()
    this.heightBridge.bind((message: string) => {
      this.onHeightMessage(message)
    })
    FormulaPreviewLog.info(`appear displayBlock=${this.displayBlock} len=${this.source.length}`)
  }

  onSourceChanged(): void {
    this.resetHeight()
    FormulaPreviewLog.info(`source changed len=${this.source.length}`)
    if (this.shellReady && this.webAttached) {
      this.injectContent()
    }
  }

  onStyleChanged(): void {
    if (this.shellReady && this.webAttached) {
      this.injectContent()
    }
  }

  private resetHeight(): void {
    this.maxContentHeightVp = 0
    this.webHeight = this.displayBlock ? 360 : 280
  }

  private onHeightMessage(message: string): void {
    if (message.startsWith('ok:')) {
      const cssPx = parseFloat(message.substring(3))
      if (!isNaN(cssPx) && cssPx > 0) {
        this.applyHeightFromJs(cssPx)
      }
      return
    }
    if (message.startsWith('error:')) {
      FormulaPreviewLog.error(`katex js ${message}`)
    }
  }

  /** Web 内 JS 的 scrollHeight 与 vp 近似 1:1；只增不减，避免后续被错误 native 高度压扁。 */
  private applyHeightFromJs(cssPx: number): void {
    const minH = this.displayBlock ? 56 : 48
    const next = Math.min(Math.max(cssPx, minH), 1600)
    if (next > this.maxContentHeightVp) {
      this.maxContentHeightVp = next
    }
    const target = Math.max(this.webHeight, this.maxContentHeightVp)
    if (target > this.webHeight + 0.5) {
      this.webHeight = target
      FormulaPreviewLog.info(`height(js)=${target} cssPx=${cssPx}`)
    }
  }

  private injectContent(): void {
    const trimmed = this.source.trim()
    if (trimmed.length === 0) {
      return
    }
    const script =
      `renderKatexPreview(${JSON.stringify(trimmed)},${JSON.stringify(this.textColor)},${JSON.stringify(this.previewBackgroundColor)});`
    FormulaPreviewLog.info(`runJavaScript len=${trimmed.length}`)
    try {
      this.webController.runJavaScript(script)
    } catch (e) {
      FormulaPreviewLog.error(`runJavaScript failed: ${JSON.stringify(e)}`)
    }
  }

  build() {
    if (this.source.trim().length === 0) {
      Column()
    } else {
      Column() {
        Web({ src: $rawfile('katex/preview_shell.html'), controller: this.webController })
          .width('100%')
          .height(this.webHeight)
          .overScrollMode(OverScrollMode.NEVER)
          .nestedScroll({
            scrollForward: NestedScrollMode.PARENT_FIRST,
            scrollBackward: NestedScrollMode.PARENT_FIRST
          })
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
            FormulaPreviewLog.info('Web controller attached')
          })
          .onPageEnd((event) => {
            const url = event?.url ?? ''
            FormulaPreviewLog.info(`Web page end url=${url}`)
            if (url.indexOf('preview_shell.html') >= 0) {
              this.shellReady = true
              this.injectContent()
            }
          })
          .onErrorReceive((event) => {
            FormulaPreviewLog.error(`Web error: ${JSON.stringify(event)}`)
          })
      }
      .width('100%')
      .constraintSize({ minHeight: this.displayBlock ? 56 : 48 })
    }
  }
}
