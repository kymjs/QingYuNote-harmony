import type { FlowchartAnchor, FlowchartNodePosition } from '../model/FlowchartGraph'
import { FLOWCHART_MIND_MAP_BUS_GAP, FLOWCHART_MIND_MAP_DEGREE_THRESHOLD } from '../model/FlowchartGraph'

export class FlowchartEdgeRouting {
  static isHorizontalAnchor(anchor: FlowchartAnchor): boolean {
    return anchor === 'left' || anchor === 'right'
  }

  static shouldUseOrthogonalEdge(sourceId: string, targetId: string,
    nodeDegrees: Record<string, number>): boolean {
    const srcDeg = nodeDegrees[sourceId] ?? 0
    const tgtDeg = nodeDegrees[targetId] ?? 0
    return srcDeg <= FLOWCHART_MIND_MAP_DEGREE_THRESHOLD &&
      tgtDeg <= FLOWCHART_MIND_MAP_DEGREE_THRESHOLD
  }

  static orthogonalPath(fromX: number, fromY: number, toX: number, toY: number,
    sourceAnchor: FlowchartAnchor, targetAnchor: FlowchartAnchor): FlowchartNodePosition[] {
    const points: FlowchartNodePosition[] = [{ x: fromX, y: fromY }]
    const sourceHorizontal = FlowchartEdgeRouting.isHorizontalAnchor(sourceAnchor)
    const targetHorizontal = FlowchartEdgeRouting.isHorizontalAnchor(targetAnchor)

    if (sourceHorizontal && targetHorizontal) {
      if (Math.abs(fromY - toY) > 0.001) {
        const midX = (fromX + toX) / 2
        points.push({ x: midX, y: fromY })
        points.push({ x: midX, y: toY })
      }
    } else if (!sourceHorizontal && !targetHorizontal) {
      if (Math.abs(fromX - toX) > 0.001) {
        const midY = (fromY + toY) / 2
        points.push({ x: fromX, y: midY })
        points.push({ x: toX, y: midY })
      }
    } else if (sourceHorizontal) {
      points.push({ x: toX, y: fromY })
    } else {
      points.push({ x: fromX, y: toY })
    }

    const last = points[points.length - 1]
    if (Math.abs(last.x - toX) > 0.001 || Math.abs(last.y - toY) > 0.001) {
      points.push({ x: toX, y: toY })
    }
    return FlowchartEdgeRouting.simplifyPolyline(points)
  }

  static mindMapTreePath(fromX: number, fromY: number, toX: number, toY: number,
    sourceLeft: number, sourceRight: number, sourceAnchor: FlowchartAnchor): FlowchartNodePosition[] {
    const spineX = sourceAnchor === 'left'
      ? sourceLeft - FLOWCHART_MIND_MAP_BUS_GAP
      : sourceRight + FLOWCHART_MIND_MAP_BUS_GAP
    return FlowchartEdgeRouting.simplifyPolyline([
      { x: fromX, y: fromY },
      { x: spineX, y: fromY },
      { x: spineX, y: toY },
      { x: toX, y: toY }
    ])
  }

  static simplifyPolyline(points: FlowchartNodePosition[]): FlowchartNodePosition[] {
    if (points.length <= 2) {
      return points
    }
    const result: FlowchartNodePosition[] = [points[0]]
    for (let i = 1; i < points.length - 1; i++) {
      const prev = result[result.length - 1]
      const cur = points[i]
      const next = points[i + 1]
      const collinearH = Math.abs(prev.y - cur.y) < 0.001 && Math.abs(cur.y - next.y) < 0.001
      const collinearV = Math.abs(prev.x - cur.x) < 0.001 && Math.abs(cur.x - next.x) < 0.001
      if (!collinearH && !collinearV) {
        result.push(cur)
      }
    }
    result.push(points[points.length - 1])
    return result
  }

  static polylineMidpoint(points: FlowchartNodePosition[]): FlowchartNodePosition {
    if (points.length === 0) {
      return { x: 0, y: 0 }
    }
    if (points.length === 1) {
      return points[0]
    }
    let total = 0
    for (let i = 0; i < points.length - 1; i++) {
      const dx = points[i + 1].x - points[i].x
      const dy = points[i + 1].y - points[i].y
      total += Math.sqrt(dx * dx + dy * dy)
    }
    if (total < 0.001) {
      return points[0]
    }
    const half = total / 2
    let walked = 0
    for (let i = 0; i < points.length - 1; i++) {
      const ax = points[i].x
      const ay = points[i].y
      const bx = points[i + 1].x
      const by = points[i + 1].y
      const dx = bx - ax
      const dy = by - ay
      const segLen = Math.sqrt(dx * dx + dy * dy)
      if (walked + segLen >= half) {
        const t = segLen < 0.001 ? 0 : (half - walked) / segLen
        return { x: ax + dx * t, y: ay + dy * t }
      }
      walked += segLen
    }
    return points[points.length - 1]
  }

  static distanceToPolyline(px: number, py: number, points: FlowchartNodePosition[]): number {
    if (points.length < 2) {
      return Number.MAX_VALUE
    }
    let best = Number.MAX_VALUE
    for (let i = 0; i < points.length - 1; i++) {
      const dist = FlowchartEdgeRouting.distanceToSegment(
        px, py,
        points[i].x, points[i].y,
        points[i + 1].x, points[i + 1].y
      )
      if (dist < best) {
        best = dist
      }
    }
    return best
  }

  static distanceToSegment(px: number, py: number,
    ax: number, ay: number, bx: number, by: number): number {
    const abx = bx - ax
    const aby = by - ay
    const apx = px - ax
    const apy = py - ay
    const abLenSq = abx * abx + aby * aby
    if (abLenSq < 0.001) {
      const dx = px - ax
      const dy = py - ay
      return Math.sqrt(dx * dx + dy * dy)
    }
    let t = (apx * abx + apy * aby) / abLenSq
    if (t < 0) {
      t = 0
    } else if (t > 1) {
      t = 1
    }
    const cx = ax + abx * t
    const cy = ay + aby * t
    const dx = px - cx
    const dy = py - cy
    return Math.sqrt(dx * dx + dy * dy)
  }

  static pathCommandsFromPoints(points: FlowchartNodePosition[]): string {
    if (points.length === 0) {
      return ''
    }
    let commands = `M${points[0].x.toFixed(1)} ${points[0].y.toFixed(1)}`
    for (let i = 1; i < points.length; i++) {
      commands += ` L${points[i].x.toFixed(1)} ${points[i].y.toFixed(1)}`
    }
    return commands
  }
}
