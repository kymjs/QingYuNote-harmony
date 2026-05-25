import type { FlowchartAnchor, FlowchartNodePosition, FlowchartShapeType } from '../model/FlowchartGraph'

/** 为 ArkUI Shape.Path 生成 SVG 风格 path 命令（局部坐标，原点为节点左上角）。 */
export class FlowchartShapePath {
  static shapeCommands(shape: FlowchartShapeType, w: number, h: number): string {
    switch (shape) {
      case 'diamond':
        return FlowchartShapePath.diamond(w, h)
      case 'arrowLeft':
        return FlowchartShapePath.blockArrow(w, h, false)
      case 'arrowRight':
        return FlowchartShapePath.blockArrow(w, h, true)
      case 'doubleArrow':
        return FlowchartShapePath.doubleArrow(w, h)
      default:
        return ''
    }
  }

  static isPathShape(shape: FlowchartShapeType): boolean {
    return shape === 'diamond' || shape === 'arrowLeft' || shape === 'arrowRight' ||
      shape === 'doubleArrow'
  }

  /** 节点局部坐标系下的连接锚点（与 Path 几何一致，原点在节点左上角）。 */
  static anchorLocal(shape: FlowchartShapeType, anchor: FlowchartAnchor, w: number, h: number):
    FlowchartNodePosition {
    if (shape === 'diamond') {
      switch (anchor) {
        case 'top':
          return { x: w / 2, y: 0 }
        case 'right':
          return { x: w, y: h / 2 }
        case 'bottom':
          return { x: w / 2, y: h }
        default:
          return { x: 0, y: h / 2 }
      }
    }
    switch (anchor) {
      case 'top':
        return { x: w / 2, y: 0 }
      case 'right':
        return { x: w, y: h / 2 }
      case 'bottom':
        return { x: w / 2, y: h }
      default:
        return { x: 0, y: h / 2 }
    }
  }

  /** 箭头类节点局部坐标系下的头尾端点。 */
  static endpointLocal(shape: FlowchartShapeType, index: number, w: number, h: number): FlowchartNodePosition {
    if (shape === 'arrowRight') {
      return index === 0 ?
        { x: 0, y: h / 2 } :
        { x: w, y: h / 2 }
    }
    if (shape === 'arrowLeft') {
      return index === 0 ?
        { x: w, y: h / 2 } :
        { x: 0, y: h / 2 }
    }
    if (shape === 'doubleArrow') {
      return index === 0 ?
        { x: 0, y: h / 2 } :
        { x: w, y: h / 2 }
    }
    return { x: w / 2, y: h / 2 }
  }

  static diamond(w: number, h: number): string {
    return `M${(w / 2).toFixed(1)} 0 L${w.toFixed(1)} ${(h / 2).toFixed(1)} L${(w / 2).toFixed(1)} ${h.toFixed(1)} L0 ${(h / 2).toFixed(1)} Z`
  }

  static blockArrow(w: number, h: number, toRight: boolean): string {
    const head = w * 0.35
    if (toRight) {
      return `M0 ${(h * 0.25).toFixed(1)} L${(w - head).toFixed(1)} ${(h * 0.25).toFixed(1)} ` +
        `L${(w - head).toFixed(1)} 0 L${w.toFixed(1)} ${(h / 2).toFixed(1)} ` +
        `L${(w - head).toFixed(1)} ${h.toFixed(1)} L${(w - head).toFixed(1)} ${(h * 0.75).toFixed(1)} ` +
        `L0 ${(h * 0.75).toFixed(1)} Z`
    }
    return `M${w.toFixed(1)} ${(h * 0.25).toFixed(1)} L${head.toFixed(1)} ${(h * 0.25).toFixed(1)} ` +
      `L${head.toFixed(1)} 0 L0 ${(h / 2).toFixed(1)} ` +
      `L${head.toFixed(1)} ${h.toFixed(1)} L${head.toFixed(1)} ${(h * 0.75).toFixed(1)} ` +
      `L${w.toFixed(1)} ${(h * 0.75).toFixed(1)} Z`
  }

  static doubleArrow(w: number, h: number): string {
    const head = w * 0.2
    return `M${head.toFixed(1)} ${(h * 0.3).toFixed(1)} L0 ${(h / 2).toFixed(1)} ` +
      `L${head.toFixed(1)} ${(h * 0.7).toFixed(1)} L${head.toFixed(1)} ${(h * 0.55).toFixed(1)} ` +
      `L${(w - head).toFixed(1)} ${(h * 0.55).toFixed(1)} L${(w - head).toFixed(1)} ${(h * 0.7).toFixed(1)} ` +
      `L${w.toFixed(1)} ${(h / 2).toFixed(1)} L${(w - head).toFixed(1)} ${(h * 0.3).toFixed(1)} ` +
      `L${(w - head).toFixed(1)} ${(h * 0.45).toFixed(1)} L${head.toFixed(1)} ${(h * 0.45).toFixed(1)} Z`
  }

  static lineSegment(x1: number, y1: number, x2: number, y2: number,
    lineType: string, arrowHeadSize: number = 9): string {
    let commands = `M${x1.toFixed(1)} ${y1.toFixed(1)} L${x2.toFixed(1)} ${y2.toFixed(1)}`
    if (lineType === 'arrow' || lineType === 'doubleArrow') {
      commands += ` ${FlowchartShapePath.arrowHead(x2, y2, x1, y1, arrowHeadSize)}`
    }
    if (lineType === 'doubleArrow') {
      commands += ` ${FlowchartShapePath.arrowHead(x1, y1, x2, y2, arrowHeadSize)}`
    }
    return commands
  }

  private static arrowHead(tipX: number, tipY: number, fromX: number, fromY: number, size: number): string {
    const angle = Math.atan2(tipY - fromY, tipX - fromX)
    const ax1 = tipX - size * Math.cos(angle - Math.PI / 6)
    const ay1 = tipY - size * Math.sin(angle - Math.PI / 6)
    const ax2 = tipX - size * Math.cos(angle + Math.PI / 6)
    const ay2 = tipY - size * Math.sin(angle + Math.PI / 6)
    return `M${tipX.toFixed(1)} ${tipY.toFixed(1)} L${ax1.toFixed(1)} ${ay1.toFixed(1)} L${ax2.toFixed(1)} ${ay2.toFixed(1)} Z`
  }
}
