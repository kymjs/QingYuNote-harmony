import type { FlowchartShapeType } from '../model/FlowchartGraph'

export class FlowchartShapeDrawer {
  static drawShape(
    ctx: CanvasRenderingContext2D,
    shape: FlowchartShapeType,
    x: number,
    y: number,
    w: number,
    h: number,
    fill: string,
    stroke: string,
    strokeWidth: number = 1.5
  ): void {
    ctx.fillStyle = fill
    ctx.strokeStyle = stroke
    ctx.lineWidth = strokeWidth
  ctx.beginPath()
    switch (shape) {
      case 'roundedRect':
        FlowchartShapeDrawer.roundRect(ctx, x, y, w, h, 12)
        break
      case 'pill':
        FlowchartShapeDrawer.roundRect(ctx, x, y, w, h, h / 2)
        break
      case 'diamond':
        ctx.moveTo(x + w / 2, y)
        ctx.lineTo(x + w, y + h / 2)
        ctx.lineTo(x + w / 2, y + h)
        ctx.lineTo(x, y + h / 2)
        ctx.closePath()
        break
      case 'rectangle':
        ctx.rect(x, y, w, h)
        break
      case 'circle':
        ctx.ellipse(x + w / 2, y + h / 2, w / 2, h / 2, 0, 0, Math.PI * 2)
        break
      case 'cylinder':
        FlowchartShapeDrawer.cylinder(ctx, x, y, w, h)
        break
      case 'chevron':
        FlowchartShapeDrawer.chevron(ctx, x, y, w, h)
        break
      case 'home':
        FlowchartShapeDrawer.home(ctx, x, y, w, h)
        break
      case 'parallelogram':
        FlowchartShapeDrawer.parallelogram(ctx, x, y, w, h)
        break
      case 'trapezoid':
        FlowchartShapeDrawer.trapezoid(ctx, x, y, w, h)
        break
      case 'speechBubble':
        FlowchartShapeDrawer.speechBubble(ctx, x, y, w, h, true)
        break
      case 'rectSpeechBubble':
        FlowchartShapeDrawer.speechBubble(ctx, x, y, w, h, false)
        break
      case 'triangle':
        ctx.moveTo(x, y + h)
        ctx.lineTo(x + w, y + h)
        ctx.lineTo(x, y)
        ctx.closePath()
        break
      case 'equilateralTriangle':
        ctx.moveTo(x + w / 2, y)
        ctx.lineTo(x + w, y + h)
        ctx.lineTo(x, y + h)
        ctx.closePath()
        break
      case 'star':
        FlowchartShapeDrawer.star(ctx, x + w / 2, y + h / 2, Math.min(w, h) / 2, 5)
        break
      case 'hexagon':
        FlowchartShapeDrawer.polygon(ctx, x + w / 2, y + h / 2, Math.min(w, h) / 2, 6)
        break
      case 'pentagon':
        FlowchartShapeDrawer.polygon(ctx, x + w / 2, y + h / 2, Math.min(w, h) / 2, 5)
        break
      case 'octagon':
        FlowchartShapeDrawer.polygon(ctx, x + w / 2, y + h / 2, Math.min(w, h) / 2, 8)
        break
      case 'arrowLeft':
        FlowchartShapeDrawer.blockArrow(ctx, x, y, w, h, false)
        break
      case 'arrowRight':
        FlowchartShapeDrawer.blockArrow(ctx, x, y, w, h, true)
        break
      case 'doubleArrow':
        FlowchartShapeDrawer.doubleArrow(ctx, x, y, w, h)
        break
      case 'cloud':
        FlowchartShapeDrawer.cloud(ctx, x, y, w, h)
        break
      case 'braceLeft':
        FlowchartShapeDrawer.brace(ctx, x, y, w, h, true)
        break
      case 'braceRight':
        FlowchartShapeDrawer.brace(ctx, x, y, w, h, false)
        break
      case 'plus':
        FlowchartShapeDrawer.plus(ctx, x, y, w, h)
        break
      case 'arc3Quarter':
        ctx.moveTo(x + w / 2, y + h / 2)
        ctx.arc(x + w / 2, y + h / 2, w / 2, -Math.PI / 2, Math.PI)
        ctx.closePath()
        break
      case 'pie':
        ctx.moveTo(x + w / 2, y + h / 2)
        ctx.arc(x + w / 2, y + h / 2, w / 2, -Math.PI / 4, Math.PI / 4)
        ctx.closePath()
        break
      case 'cube':
        FlowchartShapeDrawer.cube(ctx, x, y, w, h)
        break
      default:
        FlowchartShapeDrawer.roundRect(ctx, x, y, w, h, 12)
        break
    }
    ctx.fill()
    ctx.stroke()
  }

  /** 在 Canvas 上沿任意方向绘制块状箭头（tail → head）。 */
  static drawBlockArrowBetween(
    ctx: CanvasRenderingContext2D,
    fromX: number,
    fromY: number,
    toX: number,
    toY: number,
    fill: string,
    stroke: string,
    strokeWidth: number = 1.5
  ): void {
    const dx = toX - fromX
    const dy = toY - fromY
    const len = Math.sqrt(dx * dx + dy * dy)
    if (len < 8) {
      return
    }
    const angle = Math.atan2(dy, dx)
    const shaftH = Math.max(20, Math.min(56, len * 0.35))
    ctx.save()
    ctx.translate(fromX, fromY)
    ctx.rotate(angle)
    FlowchartShapeDrawer.drawShape(
      ctx,
      'arrowRight',
      0,
      -shaftH / 2,
      len,
      shaftH,
      fill,
      stroke,
      strokeWidth)
    ctx.restore()
  }

  static drawLineSegment(
    ctx: CanvasRenderingContext2D,
    x1: number,
    y1: number,
    x2: number,
    y2: number,
    lineType: string,
    stroke: string,
    strokeWidth: number = 1.8,
    arrowHeadSize: number = 9
  ): void {
    ctx.strokeStyle = stroke
    ctx.fillStyle = stroke
    ctx.lineWidth = strokeWidth
    ctx.lineCap = 'round'
    ctx.beginPath()
    ctx.moveTo(x1, y1)
    ctx.lineTo(x2, y2)
    ctx.stroke()
    if (lineType === 'arrow' || lineType === 'doubleArrow') {
      FlowchartShapeDrawer.fillArrowHead(ctx, x2, y2, x1, y1, arrowHeadSize)
    }
    if (lineType === 'doubleArrow') {
      FlowchartShapeDrawer.fillArrowHead(ctx, x1, y1, x2, y2, arrowHeadSize)
    }
  }

  private static fillArrowHead(ctx: CanvasRenderingContext2D, tipX: number, tipY: number,
    fromX: number, fromY: number, size: number): void {
    const angle = Math.atan2(tipY - fromY, tipX - fromX)
    const ax1 = tipX - size * Math.cos(angle - Math.PI / 6)
    const ay1 = tipY - size * Math.sin(angle - Math.PI / 6)
    const ax2 = tipX - size * Math.cos(angle + Math.PI / 6)
    const ay2 = tipY - size * Math.sin(angle + Math.PI / 6)
    ctx.beginPath()
    ctx.moveTo(tipX, tipY)
    ctx.lineTo(ax1, ay1)
    ctx.lineTo(ax2, ay2)
    ctx.closePath()
    ctx.fill()
  }

  private static roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number,
    r: number): void {
    const radius = Math.min(r, w / 2, h / 2)
    ctx.moveTo(x + radius, y)
    ctx.lineTo(x + w - radius, y)
    ctx.quadraticCurveTo(x + w, y, x + w, y + radius)
    ctx.lineTo(x + w, y + h - radius)
    ctx.quadraticCurveTo(x + w, y + h, x + w - radius, y + h)
    ctx.lineTo(x + radius, y + h)
    ctx.quadraticCurveTo(x, y + h, x, y + h - radius)
    ctx.lineTo(x, y + radius)
    ctx.quadraticCurveTo(x, y, x + radius, y)
    ctx.closePath()
  }

  private static cylinder(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number): void {
    const ry = h * 0.12
    ctx.ellipse(x + w / 2, y + ry, w / 2, ry, 0, 0, Math.PI * 2)
    ctx.rect(x, y + ry, w, h - ry)
  }

  private static chevron(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number): void {
    ctx.moveTo(x, y)
    ctx.lineTo(x + w * 0.65, y)
    ctx.lineTo(x + w, y + h / 2)
    ctx.lineTo(x + w * 0.65, y + h)
    ctx.lineTo(x, y + h)
    ctx.closePath()
  }

  private static home(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number): void {
    ctx.moveTo(x + w / 2, y)
    ctx.lineTo(x + w, y + h * 0.35)
    ctx.lineTo(x + w, y + h)
    ctx.lineTo(x, y + h)
    ctx.lineTo(x, y + h * 0.35)
    ctx.closePath()
  }

  private static parallelogram(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number): void {
    const skew = w * 0.18
    ctx.moveTo(x + skew, y)
    ctx.lineTo(x + w, y)
    ctx.lineTo(x + w - skew, y + h)
    ctx.lineTo(x, y + h)
    ctx.closePath()
  }

  private static trapezoid(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number): void {
    const inset = w * 0.15
    ctx.moveTo(x + inset, y)
    ctx.lineTo(x + w - inset, y)
    ctx.lineTo(x + w, y + h)
    ctx.lineTo(x, y + h)
    ctx.closePath()
  }

  private static speechBubble(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number,
    rounded: boolean): void {
    const tailH = h * 0.18
    const bodyH = h - tailH
    if (rounded) {
      FlowchartShapeDrawer.roundRect(ctx, x, y, w, bodyH, 10)
    } else {
      ctx.rect(x, y, w, bodyH)
    }
    ctx.moveTo(x + w * 0.25, y + bodyH)
    ctx.lineTo(x + w * 0.18, y + h)
    ctx.lineTo(x + w * 0.38, y + bodyH)
    ctx.closePath()
  }

  private static polygon(ctx: CanvasRenderingContext2D, cx: number, cy: number, r: number, sides: number): void {
    for (let i = 0; i < sides; i++) {
      const angle = -Math.PI / 2 + i * 2 * Math.PI / sides
      const px = cx + r * Math.cos(angle)
      const py = cy + r * Math.sin(angle)
      if (i === 0) {
        ctx.moveTo(px, py)
      } else {
        ctx.lineTo(px, py)
      }
    }
    ctx.closePath()
  }

  private static star(ctx: CanvasRenderingContext2D, cx: number, cy: number, outer: number, points: number): void {
    const inner = outer * 0.45
    const total = points * 2
    for (let i = 0; i < total; i++) {
      const angle = -Math.PI / 2 + i * Math.PI / points
      const r = i % 2 === 0 ? outer : inner
      const px = cx + r * Math.cos(angle)
      const py = cy + r * Math.sin(angle)
      if (i === 0) {
        ctx.moveTo(px, py)
      } else {
        ctx.lineTo(px, py)
      }
    }
    ctx.closePath()
  }

  private static blockArrow(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number,
    toRight: boolean): void {
    const head = w * 0.35
    if (toRight) {
      ctx.moveTo(x, y + h * 0.25)
      ctx.lineTo(x + w - head, y + h * 0.25)
      ctx.lineTo(x + w - head, y)
      ctx.lineTo(x + w, y + h / 2)
      ctx.lineTo(x + w - head, y + h)
      ctx.lineTo(x + w - head, y + h * 0.75)
      ctx.lineTo(x, y + h * 0.75)
    } else {
      ctx.moveTo(x + w, y + h * 0.25)
      ctx.lineTo(x + head, y + h * 0.25)
      ctx.lineTo(x + head, y)
      ctx.lineTo(x, y + h / 2)
      ctx.lineTo(x + head, y + h)
      ctx.lineTo(x + head, y + h * 0.75)
      ctx.lineTo(x + w, y + h * 0.75)
    }
    ctx.closePath()
  }

  private static doubleArrow(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number): void {
    const head = w * 0.2
    ctx.moveTo(x + head, y + h * 0.3)
    ctx.lineTo(x, y + h / 2)
    ctx.lineTo(x + head, y + h * 0.7)
    ctx.lineTo(x + head, y + h * 0.55)
    ctx.lineTo(x + w - head, y + h * 0.55)
    ctx.lineTo(x + w - head, y + h * 0.7)
    ctx.lineTo(x + w, y + h / 2)
    ctx.lineTo(x + w - head, y + h * 0.3)
    ctx.lineTo(x + w - head, y + h * 0.45)
    ctx.lineTo(x + head, y + h * 0.45)
    ctx.closePath()
  }

  private static cloud(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number): void {
    ctx.ellipse(x + w * 0.22, y + h * 0.52, w * 0.22, h * 0.28, 0, 0, Math.PI * 2)
    ctx.ellipse(x + w * 0.47, y + h * 0.32, w * 0.25, h * 0.32, 0, 0, Math.PI * 2)
    ctx.ellipse(x + w * 0.7, y + h * 0.5, w * 0.25, h * 0.28, 0, 0, Math.PI * 2)
  }

  private static brace(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number,
    left: boolean): void {
    const cx = left ? x + w : x
    const dir = left ? -1 : 1
    const mid = y + h / 2
    ctx.moveTo(cx, y)
    ctx.quadraticCurveTo(cx + dir * w * 0.35, y, cx + dir * w * 0.35, mid - h * 0.15)
    ctx.quadraticCurveTo(cx + dir * w * 0.35, mid, cx + dir * w * 0.15, mid)
    ctx.quadraticCurveTo(cx + dir * w * 0.35, mid, cx + dir * w * 0.35, mid + h * 0.15)
    ctx.quadraticCurveTo(cx + dir * w * 0.35, y + h, cx, y + h)
  }

  private static plus(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number): void {
    const t = Math.min(w, h) * 0.22
    ctx.rect(x + (w - t) / 2, y + h * 0.125, t, h * 0.75)
    ctx.rect(x + w * 0.125, y + (h - t) / 2, w * 0.75, t)
  }

  private static cube(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number): void {
    const d = w * 0.22
    ctx.moveTo(x + d, y + d)
    ctx.lineTo(x + w - d * 0.5, y + d)
    ctx.lineTo(x + w, y + d * 2)
    ctx.lineTo(x + w - d * 0.5, y + h - d)
    ctx.lineTo(x + d, y + h - d)
    ctx.lineTo(x, y + d * 0.5)
    ctx.closePath()
    ctx.moveTo(x + d, y + d)
    ctx.lineTo(x, y + d * 0.5)
    ctx.lineTo(x + w - d * 0.5, y + d * 0.5)
    ctx.lineTo(x + w - d * 0.5, y + d)
  }
}
