/** 语音笔记可视化：菱形竖条 + 三圈涟漪（Canvas 绘制）。 */
@Component
export struct VoiceNoteVisual {
  @Prop amplitudes: number[] = []
  /** 0=idle 1=recording 2=stopped */
  @Prop phase: number = 0
  @Prop @Watch('onVisualTick') rippleProgress: number = 0
  /** 父组件递增以强制 Canvas 重绘（Harmony Canvas 不保证 @Prop 数组变更刷屏）。 */
  @Prop @Watch('onVisualTick') visualTick: number = 0
  @Prop accentColor: string = '#0DAA4A'
  @Prop visualWidth: number = 260
  @Prop visualHeight: number = 220

  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)
  private canvasReady: boolean = false

  private readonly barCount: number = 17
  private readonly barWidth: number = 5
  private readonly barGap: number = 5
  private readonly maxBarHeight: number = 88
  private readonly idleShape: number[] = [
    0.22, 0.32, 0.48, 0.62, 0.78, 0.92, 0.78, 0.95, 1.0,
    0.95, 0.78, 0.92, 0.78, 0.62, 0.48, 0.32, 0.22
  ]

  aboutToUpdate(): void {
    this.redraw()
  }

  onVisualTick(): void {
    this.redraw()
  }

  private redraw(): void {
    if (!this.canvasReady) {
      return
    }
    const w = this.visualWidth
    const h = this.visualHeight
    if (w <= 0 || h <= 0) {
      return
    }
    const ctx = this.context
    ctx.clearRect(0, 0, w, h)
    const cx = w / 2
    const cy = h / 2
    this.paintRipples(ctx, cx, cy)
    this.paintBars(ctx, cx, cy, w)
  }

  private paintRipples(ctx: CanvasRenderingContext2D, cx: number, cy: number): void {
    const baseRadius = Math.min(cx, cy) * 0.42
    const maxExpand = Math.min(cx, cy) * 0.48
    const isRecording = this.phase === 1
    const freezeFrame = this.phase === 2
    ctx.lineWidth = 1.2
    for (let i = 0; i < 3; i += 1) {
      const phase = (this.rippleProgress + i / 3) % 1.0
      const t = (isRecording || freezeFrame) ? phase : (0.18 + i * 0.22)
      const radius = baseRadius + t * maxExpand
      let opacity = 0.2
      if (isRecording || freezeFrame) {
        opacity = (1.0 - t) * 0.45
      } else {
        opacity = Math.max(0.08, 0.28 - i * 0.06)
      }
      ctx.strokeStyle = this.colorWithAlpha(this.accentColor, opacity)
      ctx.beginPath()
      ctx.arc(cx, cy, radius, 0, Math.PI * 2)
      ctx.stroke()
    }
  }

  private paintBars(ctx: CanvasRenderingContext2D, cx: number, cy: number, w: number): void {
    const totalWidth = this.barCount * this.barWidth + (this.barCount - 1) * this.barGap
    let startX = (w - totalWidth) / 2
    if (startX < 0) {
      startX = 0
    }
    ctx.strokeStyle = this.accentColor
    ctx.lineWidth = this.barWidth
    ctx.lineCap = 'round'
    for (let i = 0; i < this.barCount; i += 1) {
      const shape = this.idleShape[i]
      const heightFactor = this.heightFactorForBar(i, shape)
      const height = Math.max(8, heightFactor * this.maxBarHeight)
      const x = startX + i * (this.barWidth + this.barGap) + this.barWidth / 2
      ctx.beginPath()
      ctx.moveTo(x, cy - height / 2)
      ctx.lineTo(x, cy + height / 2)
      ctx.stroke()
    }
  }

  private heightFactorForBar(index: number, shape: number): number {
    if (this.phase === 0) {
      return shape
    }
    const amp = this.amplitudeForBar(index)
    const v = shape * (0.35 + amp * 0.65)
    if (v < 0.12) {
      return 0.12
    }
    if (v > 1) {
      return 1
    }
    return v
  }

  private amplitudeForBar(index: number): number {
    if (this.amplitudes.length === 0) {
      return 0.2
    }
    if (this.amplitudes.length >= this.barCount) {
      const start = this.amplitudes.length - this.barCount
      const raw = this.amplitudes[start + index]
      if (raw < 0.05) {
        return 0.05
      }
      if (raw > 1) {
        return 1
      }
      return raw
    }
    const latest = this.amplitudes[this.amplitudes.length - 1]
    let base = latest
    if (base < 0.05) {
      base = 0.05
    }
    if (base > 1) {
      base = 1
    }
    const wave = 0.85 + 0.15 * Math.sin(index * 0.9)
    const mixed = base * wave
    if (mixed < 0.05) {
      return 0.05
    }
    if (mixed > 1) {
      return 1
    }
    return mixed
  }

  private colorWithAlpha(hex: string, alpha: number): string {
    const cleaned = hex.replace('#', '')
    let r = 13
    let g = 170
    let b = 74
    if (cleaned.length === 6) {
      r = Number.parseInt(cleaned.substring(0, 2), 16)
      g = Number.parseInt(cleaned.substring(2, 4), 16)
      b = Number.parseInt(cleaned.substring(4, 6), 16)
    } else if (cleaned.length === 8) {
      r = Number.parseInt(cleaned.substring(2, 4), 16)
      g = Number.parseInt(cleaned.substring(4, 6), 16)
      b = Number.parseInt(cleaned.substring(6, 8), 16)
    }
    const a = Math.max(0, Math.min(1, alpha))
    return `rgba(${r}, ${g}, ${b}, ${a})`
  }

  build() {
    Canvas(this.context)
      .width(this.visualWidth)
      .height(this.visualHeight)
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => {
        this.canvasReady = true
        this.redraw()
      })
  }
}
