import { webview } from '@kit.ArkWeb'
import { WebViewSessionCleaner } from '../common/utils/WebViewSessionCleaner'
import { EditorUiStrings } from '../common/utils/EditorUiStrings'
import { MermaidSourceSanitize } from '../common/utils/MermaidSourceSanitize'

/** 单通道 postMessage，与 preview_shell.html 的 Channel.postMessage 对齐。 */
class MermaidChannelBridge {
  private onMessage: (message: string) => void = (_: string) => {
  }

  bind(onMessage: (message: string) => void): void {
    this.onMessage = onMessage
  }

  postMessage(message: string): void {
    this.onMessage(message)
  }
}

/**
 * 分享截图等待：所有 MermaidPreview 定稿后再截。
 * 与 Flutter MermaidRenderBarrier 语义对齐。
 */
export class MermaidRenderBarrier {
  private static pending: number = 0

  static register(): void {
    MermaidRenderBarrier.pending += 1
  }

  static settle(): void {
    if (MermaidRenderBarrier.pending > 0) {
      MermaidRenderBarrier.pending -= 1
    }
  }

  static async waitUntilEmpty(timeoutMs: number = 8000): Promise<void> {
    const deadline = Date.now() + timeoutMs
    while (MermaidRenderBarrier.pending > 0 && Date.now() < deadline) {
      await new Promise<void>((resolve) => setTimeout(resolve, 50))
    }
    MermaidRenderBarrier.pending = 0
  }
}

@Component
export struct MermaidPreview {
  @Prop @Watch('onSourceChanged') source: string = ''
  @Prop @Watch('onStyleChanged') textColor: string = '#1D1D1F'
  @Prop @Watch('onStyleChanged') previewBackgroundColor: string = 'transparent'
  @Prop @Watch('onStyleChanged') isDark: boolean = false
  @Prop interactive: boolean = true
  @Prop forShareExport: boolean = false
  onRenderSettled: () => void = () => {
  }

  @State private webHeight: number = 120
  @State private errorMessage: string = ''
  @State private scaleValue: number = 1
  @State private offsetX: number = 0
  @State private offsetY: number = 0
  private webController: webview.WebviewController = new webview.WebviewController()
  private heightBridge: MermaidChannelBridge = new MermaidChannelBridge()
  private errorBridge: MermaidChannelBridge = new MermaidChannelBridge()
  private readyBridge: MermaidChannelBridge = new MermaidChannelBridge()
  private webAttached: boolean = false
  private shellReady: boolean = false
  private settled: boolean = false
  private debounceTimer: number = -1
  private registered: boolean = false

  aboutToAppear(): void {
    this.registerBarrier()
    this.heightBridge.bind((message: string) => {
      this.onHeightMessage(message)
    })
    this.errorBridge.bind((message: string) => {
      this.onErrorMessage(message)
    })
    this.readyBridge.bind((_message: string) => {
      this.markSettled()
    })
    WebViewSessionCleaner.registerController(this.webController)
  }

  aboutToDisappear(): void {
    this.clearDebounce()
    this.markSettled()
    WebViewSessionCleaner.unregisterController(this.webController)
  }

  onSourceChanged(): void {
    this.settled = false
    this.errorMessage = ''
    this.registerBarrier()
    this.scheduleInject(this.forShareExport)
  }

  onStyleChanged(): void {
    this.settled = false
    this.registerBarrier()
    this.scheduleInject(this.forShareExport)
  }

  private registerBarrier(): void {
    if (!this.registered) {
      MermaidRenderBarrier.register()
      this.registered = true
    }
  }

  private markSettled(): void {
    if (this.settled) {
      return
    }
    this.settled = true
    if (this.registered) {
      MermaidRenderBarrier.settle()
      this.registered = false
    }
    this.onRenderSettled()
  }

  private clearDebounce(): void {
    if (this.debounceTimer >= 0) {
      clearTimeout(this.debounceTimer)
      this.debounceTimer = -1
    }
  }

  private scheduleInject(immediate: boolean): void {
    this.clearDebounce()
    if (immediate || this.forShareExport) {
      this.injectContent()
      return
    }
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = -1
      this.injectContent()
    }, 300) as number
  }

  private onHeightMessage(message: string): void {
    if (!message.startsWith('ok:')) {
      return
    }
    const cssPx = parseFloat(message.substring(3))
    if (!isNaN(cssPx) && cssPx > 0) {
      const next = Math.min(Math.max(cssPx, 80), 1600)
      if (next > this.webHeight + 0.5) {
        this.webHeight = next
      }
    }
  }

  private onErrorMessage(message: string): void {
    this.errorMessage = message.length > 0 ? message :
      EditorUiStrings.loc('Mermaid 语法错误', 'Mermaid syntax error', 'Mermaid構文エラー')
    this.webHeight = 96
  }

  private injectContent(): void {
    if (!this.shellReady || !this.webAttached) {
      return
    }
    const trimmed = MermaidSourceSanitize.sanitize(this.source).trim()
    if (trimmed.length === 0) {
      this.markSettled()
      return
    }
    const theme = this.isDark ? 'dark' : 'default'
    const script =
      `renderMermaidPreview(${JSON.stringify(trimmed)},${JSON.stringify(theme)},` +
        `${JSON.stringify(this.textColor)},${JSON.stringify(this.previewBackgroundColor)});`
    try {
      this.webController.runJavaScript(script)
    } catch (_) {
      this.errorMessage = EditorUiStrings.loc('图表加载失败', 'Failed to load diagram', '図の読み込みに失敗しました')
      this.webHeight = 96
      this.markSettled()
    }
  }

  private resetTransform(): void {
    this.scaleValue = 1
    this.offsetX = 0
    this.offsetY = 0
  }

  @Builder
  private buildErrorCard() {
    Column({ space: 6 }) {
      Text(EditorUiStrings.loc('Mermaid 语法错误', 'Mermaid syntax error', 'Mermaid構文エラー'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#B91C1C')
        .width('100%')
      Text(this.errorMessage)
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
        .maxLines(6)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#14DC2626')
    .borderRadius(12)
    .border({ width: 1, color: '#59DC2626' })
  }

  @Builder
  private buildWeb() {
    Web({ src: $rawfile('mermaid/preview_shell.html'), controller: this.webController })
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
      .onlineImageAccess(false)
      .mixedMode(MixedMode.All)
      .cacheMode(CacheMode.None)
      .javaScriptProxy({
        object: this.heightBridge,
        name: 'HeightChannel',
        methodList: ['postMessage'],
        controller: this.webController
      })
      .javaScriptProxy({
        object: this.errorBridge,
        name: 'ErrorChannel',
        methodList: ['postMessage'],
        controller: this.webController
      })
      .javaScriptProxy({
        object: this.readyBridge,
        name: 'ReadyChannel',
        methodList: ['postMessage'],
        controller: this.webController
      })
      .onControllerAttached(() => {
        this.webAttached = true
      })
      .onPageEnd((event) => {
        const url = event?.url ?? ''
        if (url.indexOf('preview_shell.html') >= 0) {
          this.shellReady = true
          this.scheduleInject(true)
        }
      })
  }

  build() {
    if (this.source.trim().length === 0) {
      Column()
    } else if (this.errorMessage.length > 0) {
      this.buildErrorCard()
    } else {
      Column() {
        this.buildWeb()
      }
      .width('100%')
      .scale({ x: this.scaleValue, y: this.scaleValue })
      .translate({ x: this.offsetX, y: this.offsetY })
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          PinchGesture({ fingers: 2 })
            .onActionUpdate((event: GestureEvent) => {
              if (!this.interactive || this.forShareExport) {
                return
              }
              const next = Math.min(4, Math.max(1, event.scale))
              this.scaleValue = next
              if (next <= 1.01) {
                this.resetTransform()
              }
            }),
          PanGesture({ fingers: 1 })
            .onActionUpdate((event: GestureEvent) => {
              if (!this.interactive || this.forShareExport || this.scaleValue <= 1.01) {
                return
              }
              this.offsetX += event.offsetX
              this.offsetY += event.offsetY
            })
        )
      )
    }
  }
}
