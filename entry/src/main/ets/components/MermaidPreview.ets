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

export interface MermaidInteractionEvent {
  action: string
  kind: string
  id: string
  label: string
  targetId?: string
  targetLabel?: string
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
  /** 测量阶段先提供足够视口，避免 WebView 将首帧 scrollHeight 截为容器高度。 */
  private static readonly MEASURE_PLACEHOLDER_HEIGHT: number = 360
  private static readonly MIN_WEB_HEIGHT: number = 80
  private static readonly MAX_WEB_HEIGHT: number = 3200
  private static readonly EDITABLE_MIN_HEIGHT: number = 320

  @Prop @Watch('onSourceChanged') source: string = ''
  @Prop @Watch('onStyleChanged') textColor: string = '#1D1D1F'
  @Prop @Watch('onStyleChanged') previewBackgroundColor: string = 'transparent'
  @Prop @Watch('onStyleChanged') isDark: boolean = false
  @Prop interactive: boolean = true
  @Prop forShareExport: boolean = false
  /** 流程图编辑页预览模式：允许点选/双击，并由 shell 内 pan/zoom。 */
  @Prop @Watch('onEditableChanged') editable: boolean = false
  @Prop @Watch('onSelectionChanged') selectedKind: string = ''
  @Prop @Watch('onSelectionChanged') selectedId: string = ''
  @Prop @Watch('onColorsChanged') colorsJson: string = ''
  /** 语法错误标题；空则用默认「Mermaid 语法错误」。 */
  @Prop syntaxErrorTitle: string = ''
  onRenderSettled: () => void = () => {
  }
  onMermaidInteraction: (event: MermaidInteractionEvent) => void = (_: MermaidInteractionEvent) => {
  }

  @State private webHeight: number = MermaidPreview.MEASURE_PLACEHOLDER_HEIGHT
  /** 当前渲染周期内从 Web 侧观测到的最大内容高度，只增不减以避免截断。 */
  private maxContentHeightVp: number = 0
  @State private errorMessage: string = ''
  @State private scaleValue: number = 1
  @State private offsetX: number = 0
  @State private offsetY: number = 0
  private webController: webview.WebviewController = new webview.WebviewController()
  private heightBridge: MermaidChannelBridge = new MermaidChannelBridge()
  private errorBridge: MermaidChannelBridge = new MermaidChannelBridge()
  private readyBridge: MermaidChannelBridge = new MermaidChannelBridge()
  private interactionBridge: MermaidChannelBridge = new MermaidChannelBridge()
  private webAttached: boolean = false
  private shellReady: boolean = false
  private settled: boolean = false
  private debounceTimer: number = -1
  private registered: boolean = false

  aboutToAppear(): void {
    this.resetMeasuredHeight()
    this.registerBarrier()
    this.heightBridge.bind((message: string) => {
      this.onHeightMessage(message)
    })
    this.errorBridge.bind((message: string) => {
      this.onErrorMessage(message)
    })
    this.readyBridge.bind((_message: string) => {
      this.markSettled()
      this.syncSelectionToJs()
      this.syncColorsToJs()
    })
    this.interactionBridge.bind((message: string) => {
      this.onInteractionMessage(message)
    })
    WebViewSessionCleaner.registerController(this.webController)
  }

  aboutToDisappear(): void {
    this.clearDebounce()
    this.markSettled()
    WebViewSessionCleaner.unregisterController(this.webController)
  }

  onSourceChanged(): void {
    this.resetMeasuredHeight()
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

  onEditableChanged(): void {
    this.settled = false
    this.registerBarrier()
    this.scheduleInject(true)
  }

  onSelectionChanged(): void {
    this.syncSelectionToJs()
  }

  onColorsChanged(): void {
    this.syncColorsToJs()
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
      const minH = this.editable ? MermaidPreview.EDITABLE_MIN_HEIGHT : MermaidPreview.MIN_WEB_HEIGHT
      const maxH = this.editable ? 4000 : MermaidPreview.MAX_WEB_HEIGHT
      const next = Math.min(Math.max(cssPx, minH), maxH)
      if (next > this.maxContentHeightVp) {
        this.maxContentHeightVp = next
      }
      const target = Math.max(this.webHeight, this.maxContentHeightVp)
      if (target > this.webHeight + 0.5) {
        this.webHeight = target
      }
    }
  }

  private resetMeasuredHeight(): void {
    this.maxContentHeightVp = 0
    this.webHeight = this.editable
      ? MermaidPreview.EDITABLE_MIN_HEIGHT
      : MermaidPreview.MEASURE_PLACEHOLDER_HEIGHT
  }

  private syntaxErrorTitleText(): string {
    if (this.syntaxErrorTitle.length > 0) {
      return this.syntaxErrorTitle
    }
    return EditorUiStrings.loc('Mermaid 语法错误', 'Mermaid syntax error', 'Mermaid構文エラー')
  }

  private onErrorMessage(message: string): void {
    this.errorMessage = message.length > 0 ? message : this.syntaxErrorTitleText()
    this.maxContentHeightVp = 0
    this.webHeight = 96
  }

  private onInteractionMessage(message: string): void {
    if (!this.editable) {
      return
    }
    try {
      const parsed = JSON.parse(message) as Record<string, Object>
      const action = `${parsed['action'] ?? ''}`.trim()
      const kind = `${parsed['kind'] ?? ''}`.trim()
      if (action.length === 0 || kind.length === 0) {
        return
      }
      const event: MermaidInteractionEvent = {
        action: action,
        kind: kind,
        id: `${parsed['id'] ?? ''}`.trim(),
        label: `${parsed['label'] ?? ''}`.trim(),
        targetId: `${parsed['targetId'] ?? ''}`.trim(),
        targetLabel: `${parsed['targetLabel'] ?? ''}`.trim()
      }
      this.onMermaidInteraction(event)
    } catch (_) {
    }
  }

  private syncSelectionToJs(): void {
    if (!this.shellReady || !this.webAttached || !this.editable) {
      return
    }
    const kind = this.selectedKind
    const id = this.selectedId
    try {
      this.webController.runJavaScript(
        `typeof setMermaidSelection==="function"&&setMermaidSelection(${JSON.stringify(kind)},${JSON.stringify(id)});`
      )
    } catch (_) {
    }
  }

  private syncColorsToJs(): void {
    if (!this.shellReady || !this.webAttached || !this.editable) {
      return
    }
    const colors = this.colorsJson
    if (colors.length === 0) {
      return
    }
    try {
      this.webController.runJavaScript(
        `typeof applyMermaidColors==="function"&&applyMermaidColors(${JSON.stringify(colors)});`
      )
    } catch (_) {
    }
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
        `${JSON.stringify(this.textColor)},${JSON.stringify(this.previewBackgroundColor)},` +
        `${this.editable},${JSON.stringify(this.colorsJson)});`
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
      Text(this.syntaxErrorTitleText())
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
      .height(this.editable ? '100%' : this.webHeight)
      .layoutWeight(this.editable ? 1 : 0)
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
      .javaScriptProxy({
        object: this.interactionBridge,
        name: 'InteractionChannel',
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
    } else if (this.editable) {
      // shell 内负责 pan/zoom，外层铺满即可
      Column() {
        this.buildWeb()
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
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
