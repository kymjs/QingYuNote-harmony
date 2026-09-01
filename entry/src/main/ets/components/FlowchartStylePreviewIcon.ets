/** 图表样式面板格子顶部示意配图（Canvas 矢量，与 Flutter 对齐）。 */
import { FlowchartEditorChartKind } from '../common/utils/FlowchartEditorConstants'

@Component
export struct FlowchartStylePreviewIcon {
  @Prop kind: FlowchartEditorChartKind = 'flowchart'
  @Prop color: string = '#333333'
  @Prop iconSize: number = 36

  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)
  private canvasReady: boolean = false

  aboutToUpdate(): void {
    this.redraw()
  }

  private redraw(): void {
    if (!this.canvasReady) {
      return
    }
    const w = this.iconSize
    const h = this.iconSize
    const ctx = this.context
    ctx.clearRect(0, 0, w, h)
    ctx.strokeStyle = this.color
    ctx.fillStyle = this.colorWithAlpha(this.color, 0.18)
    ctx.lineWidth = 1.4
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    switch (this.kind) {
      case 'flowchart':
        this.paintFlowchart(ctx, w, h)
        break
      case 'state':
        this.paintKnowledgeGraph(ctx, w, h)
        break
      case 'sequence':
        this.paintSequence(ctx, w, h)
        break
      case 'class':
        this.paintClass(ctx, w, h)
        break
      case 'mindmap':
        this.paintMindmap(ctx, w, h)
        break
      case 'pie':
        this.paintPie(ctx, w, h)
        break
      case 'gitgraph':
        this.paintGit(ctx, w, h)
        break
      case 'journey':
        this.paintJourney(ctx, w, h)
        break
      case 'timeline':
        this.paintTimeline(ctx, w, h)
        break
      default:
        this.paintFlowchart(ctx, w, h)
        break
    }
  }

  private colorWithAlpha(hex: string, alpha: number): string {
    const cleaned = hex.replace('#', '')
    let r = 51
    let g = 51
    let b = 51
    if (cleaned.length === 6) {
      r = Number.parseInt(cleaned.substring(0, 2), 16)
      g = Number.parseInt(cleaned.substring(2, 4), 16)
      b = Number.parseInt(cleaned.substring(4, 6), 16)
    }
    const a = Math.max(0, Math.min(1, alpha))
    return `rgba(${r}, ${g}, ${b}, ${a})`
  }

  private roundRect(
    ctx: CanvasRenderingContext2D,
    x: number,
    y: number,
    rw: number,
    rh: number,
    radius: number
  ): void {
    const r = Math.min(radius, rw / 2, rh / 2)
    ctx.beginPath()
    ctx.moveTo(x + r, y)
    ctx.arcTo(x + rw, y, x + rw, y + rh, r)
    ctx.arcTo(x + rw, y + rh, x, y + rh, r)
    ctx.arcTo(x, y + rh, x, y, r)
    ctx.arcTo(x, y, x + rw, y, r)
    ctx.closePath()
    ctx.fill()
    ctx.stroke()
  }

  private paintFlowchart(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    const scale = 0.5
    const topW = w * 0.56 * scale
    const topH = 10 * scale
    const sideW = 14 * scale
    const sideH = 10 * scale
    const ax = w * 0.5 - topW / 2
    const ay = 2 + (10 - topH) / 2
    const by = h * 0.42 + (10 - sideH) / 2
    const dy = h - 12 + (10 - topH) / 2
    const bx = 4 + (14 - sideW) / 2
    const cx = w - 18 + (14 - sideW) / 2
    this.roundRect(ctx, ax, ay, topW, topH, 1.5)
    this.roundRect(ctx, bx, by, sideW, sideH, 1.5)
    this.roundRect(ctx, cx, by, sideW, sideH, 1.5)
    this.roundRect(ctx, ax, dy, topW, topH, 1.5)
    const acx = ax + topW / 2
    const bcx = bx + sideW / 2
    const ccx = cx + sideW / 2
    ctx.beginPath()
    ctx.moveTo(acx, ay + topH)
    ctx.lineTo(acx, by)
    ctx.lineTo(bcx, by)
    ctx.moveTo(acx, by)
    ctx.lineTo(ccx, by)
    ctx.moveTo(bcx, by + sideH)
    ctx.lineTo(bcx, dy)
    ctx.moveTo(ccx, by + sideH)
    ctx.lineTo(ccx, dy)
    ctx.moveTo(bcx, dy)
    ctx.lineTo(ccx, dy)
    ctx.stroke()
  }

  private paintKnowledgeGraph(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    const nodes: number[][] = [
      [w * 0.5, h * 0.22],
      [w * 0.22, h * 0.72],
      [w * 0.78, h * 0.72],
      [w * 0.5, h * 0.55]
    ]
    ctx.beginPath()
    ctx.moveTo(nodes[0][0], nodes[0][1])
    ctx.lineTo(nodes[3][0], nodes[3][1])
    ctx.lineTo(nodes[1][0], nodes[1][1])
    ctx.moveTo(nodes[3][0], nodes[3][1])
    ctx.lineTo(nodes[2][0], nodes[2][1])
    ctx.moveTo(nodes[0][0], nodes[0][1])
    ctx.lineTo(nodes[2][0], nodes[2][1])
    ctx.stroke()
    for (let i = 0; i < nodes.length; i++) {
      ctx.beginPath()
      ctx.arc(nodes[i][0], nodes[i][1], 4.2, 0, Math.PI * 2)
      ctx.fill()
      ctx.stroke()
    }
  }

  private paintSequence(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    const left = w * 0.28
    const right = w * 0.72
    this.roundRect(ctx, left - 7, 3, 14, 8, 3)
    this.roundRect(ctx, right - 7, 3, 14, 8, 3)
    ctx.beginPath()
    ctx.moveTo(left, 11)
    ctx.lineTo(left, h - 4)
    ctx.moveTo(right, 11)
    ctx.lineTo(right, h - 4)
    const y1 = h * 0.4
    const y2 = h * 0.7
    ctx.moveTo(left, y1)
    ctx.lineTo(right, y1)
    ctx.moveTo(right - 4, y1 - 3)
    ctx.lineTo(right, y1)
    ctx.lineTo(right - 4, y1 + 3)
    ctx.moveTo(right, y2)
    ctx.lineTo(left, y2)
    ctx.moveTo(left + 4, y2 - 3)
    ctx.lineTo(left, y2)
    ctx.lineTo(left + 4, y2 + 3)
    ctx.stroke()
  }

  private paintClass(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    const x = 6
    const y = 4
    const rw = w - 12
    const rh = h - 8
    ctx.fillRect(x, y, rw, rh)
    ctx.strokeRect(x, y, rw, rh)
    const y1 = y + rh / 3
    const y2 = y + rh * 2 / 3
    ctx.beginPath()
    ctx.moveTo(x, y1)
    ctx.lineTo(x + rw, y1)
    ctx.moveTo(x, y2)
    ctx.lineTo(x + rw, y2)
    ctx.stroke()
  }

  private paintMindmap(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    const rx = w * 0.28
    const ry = h * 0.5
    const children: number[][] = [
      [w * 0.78, h * 0.22],
      [w * 0.78, h * 0.5],
      [w * 0.78, h * 0.78]
    ]
    const rootW = 16 * 0.5
    const rootH = 12 * 0.5
    // 根节点右缘 → 竖脊 → 子节点：正交折线
    const rootRight = rx + rootW / 2
    const spineX = (rootRight + children[0][0]) / 2
    ctx.beginPath()
    for (let i = 0; i < children.length; i++) {
      const cx = children[i][0]
      const cy = children[i][1]
      ctx.moveTo(rootRight, ry)
      ctx.lineTo(spineX, ry)
      ctx.lineTo(spineX, cy)
      ctx.lineTo(cx, cy)
    }
    ctx.stroke()
    this.roundRect(ctx, rx - rootW / 2, ry - rootH / 2, rootW, rootH, 2)
    for (let i = 0; i < children.length; i++) {
      ctx.beginPath()
      ctx.arc(children[i][0], children[i][1], 3.5, 0, Math.PI * 2)
      ctx.fill()
      ctx.stroke()
    }
  }

  private paintPie(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    const cx = w / 2
    const cy = h / 2
    const r = Math.min(w, h) / 2 - 4
    ctx.beginPath()
    ctx.arc(cx, cy, r, 0, Math.PI * 2)
    ctx.stroke()
    ctx.beginPath()
    ctx.moveTo(cx, cy)
    ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 0.55)
    ctx.closePath()
    ctx.fill()
    ctx.stroke()
    ctx.beginPath()
    ctx.moveTo(cx, cy)
    ctx.lineTo(cx, cy - r)
    ctx.moveTo(cx, cy)
    ctx.lineTo(cx + r * Math.cos(Math.PI * 0.05), cy + r * Math.sin(Math.PI * 0.05))
    ctx.stroke()
  }

  private paintGit(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    const yMain = h * 0.35
    const yBranch = h * 0.72
    ctx.beginPath()
    ctx.moveTo(4, yMain)
    ctx.lineTo(w - 4, yMain)
    ctx.moveTo(w * 0.35, yMain)
    ctx.lineTo(w * 0.55, yBranch)
    ctx.lineTo(w * 0.75, yBranch)
    ctx.lineTo(w * 0.88, yMain)
    ctx.stroke()
    const xs: number[] = [0.18, 0.42, 0.88]
    for (let i = 0; i < xs.length; i++) {
      ctx.beginPath()
      ctx.arc(w * xs[i], yMain, 3.2, 0, Math.PI * 2)
      ctx.fill()
      ctx.stroke()
    }
    ctx.beginPath()
    ctx.arc(w * 0.65, yBranch, 3.2, 0, Math.PI * 2)
    ctx.fill()
    ctx.stroke()
  }

  private paintJourney(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    const pts: number[][] = [
      [5, h * 0.7],
      [w * 0.28, h * 0.35],
      [w * 0.52, h * 0.55],
      [w * 0.75, h * 0.28],
      [w - 5, h * 0.45]
    ]
    ctx.beginPath()
    ctx.moveTo(pts[0][0], pts[0][1])
    for (let i = 1; i < pts.length; i++) {
      ctx.lineTo(pts[i][0], pts[i][1])
    }
    ctx.stroke()
    for (let i = 0; i < pts.length; i++) {
      ctx.beginPath()
      ctx.arc(pts[i][0], pts[i][1], 3, 0, Math.PI * 2)
      ctx.fill()
      ctx.stroke()
    }
  }

  private paintTimeline(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    const y = h * 0.55
    ctx.beginPath()
    ctx.moveTo(3, y)
    ctx.lineTo(w - 3, y)
    ctx.stroke()
    const xs: number[] = [0.18, 0.5, 0.82]
    const stemH = 10
    const boxH = 7
    const boxCy = y - stemH - boxH / 2
    for (let i = 0; i < xs.length; i++) {
      const x = w * xs[i]
      ctx.beginPath()
      ctx.moveTo(x, y)
      ctx.lineTo(x, y - stemH)
      ctx.stroke()
      ctx.beginPath()
      ctx.arc(x, y, 3.2, 0, Math.PI * 2)
      ctx.fill()
      ctx.stroke()
      this.roundRect(ctx, x - 5, boxCy - boxH / 2, 10, boxH, 2)
    }
  }

  build() {
    Canvas(this.context)
      .width(this.iconSize)
      .height(this.iconSize)
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => {
        this.canvasReady = true
        this.redraw()
      })
  }
}
