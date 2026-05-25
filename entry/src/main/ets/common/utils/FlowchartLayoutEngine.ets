import type {
  FlowchartEdgeModel,
  FlowchartGraphModel,
  FlowchartNodeModel,
  FlowchartNodePosition
} from '../model/FlowchartGraph'
import { FLOWCHART_LINE_NODE_SHAPE, createFlowchartPosition } from '../model/FlowchartGraph'

interface LayoutEdge {
  source: string
  target: string
}

export class FlowchartLayoutEngine {
  private static readonly GRID_ORIGIN = 48
  private static readonly GRID_GAP_X = 40
  private static readonly GRID_GAP_Y = 40
  private static readonly GRID_COLS = 4
  private static readonly COMPONENT_GAP = 64
  private static readonly DEFAULT_NODE_W = 120
  private static readonly DEFAULT_NODE_H = 72
  private static readonly OCCLUSION_MARGIN = 6
  private static readonly MAX_ORDER_SWEEPS = 6
  private static readonly MAX_NUDGE_PASSES = 8

  /**
   * 分层布局：优先减少连线交叉与穿过其它节点，其次保持网格对齐。
   * @param preferVertical 手机纵向（自上而下）；平板/PC 横向（自左而右）。
   */
  static applyAlignedLayout(graph: FlowchartGraphModel, preferVertical: boolean = false): FlowchartGraphModel {
    if (graph.nodes.length === 0) {
      return graph
    }
    const shapeNodes: FlowchartNodeModel[] = []
    const lineNodes: FlowchartNodeModel[] = []
    for (const node of graph.nodes) {
      if (node.shape === FLOWCHART_LINE_NODE_SHAPE) {
        lineNodes.push(node)
      } else {
        shapeNodes.push(node)
      }
    }
    if (shapeNodes.length === 0) {
      return graph
    }
    let maxW = FlowchartLayoutEngine.DEFAULT_NODE_W
    let maxH = FlowchartLayoutEngine.DEFAULT_NODE_H
    for (const node of shapeNodes) {
      if (node.width > maxW) {
        maxW = node.width
      }
      if (node.height > maxH) {
        maxH = node.height
      }
    }
    const cellW = maxW + FlowchartLayoutEngine.GRID_GAP_X
    const cellH = maxH + FlowchartLayoutEngine.GRID_GAP_Y
    const layoutEdges = FlowchartLayoutEngine.collectLayoutEdges(graph.edges, shapeNodes)
    const positions: Record<string, FlowchartNodePosition> = {}
    if (layoutEdges.length === 0) {
      FlowchartLayoutEngine.applyGridPositions(shapeNodes, positions, preferVertical, cellW, cellH, 0, 0)
    } else {
      const components = FlowchartLayoutEngine.findComponents(shapeNodes, layoutEdges)
      let offsetX = FlowchartLayoutEngine.GRID_ORIGIN
      let offsetY = FlowchartLayoutEngine.GRID_ORIGIN
      for (let ci = 0; ci < components.length; ci++) {
        const comp = components[ci]
        const compNodes: FlowchartNodeModel[] = []
        for (const id of comp) {
          const node = FlowchartLayoutEngine.nodeById(shapeNodes, id)
          if (node !== undefined) {
            compNodes.push(node)
          }
        }
        const compEdges = FlowchartLayoutEngine.edgesForComponent(layoutEdges, comp)
        const compPos = FlowchartLayoutEngine.layoutComponent(
          compNodes, compEdges, preferVertical, cellW, cellH
        )
        let compW = 0
        let compH = 0
        for (const id of comp) {
          const p = compPos[id]
          const node = FlowchartLayoutEngine.nodeById(compNodes, id)
          if (p === undefined || node === undefined) {
            continue
          }
          positions[id] = createFlowchartPosition(p.x + offsetX, p.y + offsetY)
          compW = Math.max(compW, p.x + node.width)
          compH = Math.max(compH, p.y + node.height)
        }
        if (preferVertical) {
          offsetY += compH + FlowchartLayoutEngine.COMPONENT_GAP
        } else {
          offsetX += compW + FlowchartLayoutEngine.COMPONENT_GAP
        }
      }
    }
    for (const node of lineNodes) {
      positions[node.id] = createFlowchartPosition(node.position.x, node.position.y)
    }
    const nodes = graph.nodes.map((n: FlowchartNodeModel) => {
      const p = positions[n.id]
      return {
        id: n.id,
        title: n.title,
        description: n.description,
        color: n.color,
        shape: n.shape,
        position: p !== undefined ? p : n.position,
        width: n.width,
        height: n.height,
        rotation: n.rotation,
        properties: n.properties
      } as FlowchartNodeModel
    })
    return {
      version: graph.version,
      metadata: graph.metadata,
      nodes,
      edges: graph.edges
    }
  }

  private static collectLayoutEdges(edges: FlowchartEdgeModel[],
    shapeNodes: FlowchartNodeModel[]): LayoutEdge[] {
    const ids: Record<string, boolean> = {}
    for (const node of shapeNodes) {
      ids[node.id] = true
    }
    const result: LayoutEdge[] = []
    for (const edge of edges) {
      if (ids[edge.source] === true && ids[edge.target] === true) {
        result.push({ source: edge.source, target: edge.target })
      }
    }
    return result
  }

  private static nodeById(nodes: FlowchartNodeModel[], id: string): FlowchartNodeModel | undefined {
    for (const node of nodes) {
      if (node.id === id) {
        return node
      }
    }
    return undefined
  }

  private static findComponents(nodes: FlowchartNodeModel[], edges: LayoutEdge[]): string[][] {
    const ids: string[] = nodes.map((n: FlowchartNodeModel) => n.id)
    const adj: Record<string, string[]> = {}
    for (const id of ids) {
      adj[id] = []
    }
    for (const edge of edges) {
      adj[edge.source].push(edge.target)
      adj[edge.target].push(edge.source)
    }
    const visited: Record<string, boolean> = {}
    const components: string[][] = []
    for (const id of ids) {
      if (visited[id] === true) {
        continue
      }
      const stack: string[] = [id]
      visited[id] = true
      const comp: string[] = []
      while (stack.length > 0) {
        const cur = stack.pop() as string
        comp.push(cur)
        const neighbors = adj[cur]
        for (let i = 0; i < neighbors.length; i++) {
          const next = neighbors[i]
          if (visited[next] !== true) {
            visited[next] = true
            stack.push(next)
          }
        }
      }
      components.push(comp)
    }
    return components
  }

  private static edgesForComponent(edges: LayoutEdge[], comp: string[]): LayoutEdge[] {
    const inComp: Record<string, boolean> = {}
    for (const id of comp) {
      inComp[id] = true
    }
    const result: LayoutEdge[] = []
    for (const edge of edges) {
      if (inComp[edge.source] === true && inComp[edge.target] === true) {
        result.push(edge)
      }
    }
    return result
  }

  private static layoutComponent(nodes: FlowchartNodeModel[], edges: LayoutEdge[],
    preferVertical: boolean, cellW: number, cellH: number): Record<string, FlowchartNodePosition> {
    const ranks: Record<string, number> = {}
    const layerOrder: Record<string, number> = {}
    for (const node of nodes) {
      ranks[node.id] = 0
      layerOrder[node.id] = 0
    }
    for (let iter = 0; iter < nodes.length; iter++) {
      for (const edge of edges) {
        const nextRank = ranks[edge.source] + 1
        if (ranks[edge.target] < nextRank) {
          ranks[edge.target] = nextRank
        }
      }
    }
    let maxRank = 0
    for (const node of nodes) {
      if (ranks[node.id] > maxRank) {
        maxRank = ranks[node.id]
      }
    }
    const layers: string[][] = []
    for (let r = 0; r <= maxRank; r++) {
      layers.push([])
    }
    for (const node of nodes) {
      layers[ranks[node.id]].push(node.id)
    }
    for (let r = 0; r <= maxRank; r++) {
      layers[r].sort((a: string, b: string) => a.localeCompare(b))
      for (let i = 0; i < layers[r].length; i++) {
        layerOrder[layers[r][i]] = i
      }
    }
    const preds: Record<string, string[]> = {}
    const succs: Record<string, string[]> = {}
    for (const node of nodes) {
      preds[node.id] = []
      succs[node.id] = []
    }
    for (const edge of edges) {
      preds[edge.target].push(edge.source)
      succs[edge.source].push(edge.target)
    }
    for (let sweep = 0; sweep < FlowchartLayoutEngine.MAX_ORDER_SWEEPS; sweep++) {
      for (let r = 1; r <= maxRank; r++) {
        FlowchartLayoutEngine.sortLayerByMedian(layers[r], preds, layerOrder)
      }
      for (let r = maxRank - 1; r >= 0; r--) {
        FlowchartLayoutEngine.sortLayerByMedian(layers[r], succs, layerOrder)
      }
    }
    for (let r = 0; r <= maxRank; r++) {
      for (let i = 0; i < layers[r].length; i++) {
        layerOrder[layers[r][i]] = i
      }
    }
    const positions: Record<string, FlowchartNodePosition> = {}
    FlowchartLayoutEngine.assignLayerCoordinates(nodes, layers, positions, preferVertical, cellW, cellH, 0, 0)
    FlowchartLayoutEngine.reduceOcclusions(nodes, edges, positions, preferVertical, cellH)
    return positions
  }

  private static sortLayerByMedian(layer: string[], neighborMap: Record<string, string[]>,
    orderRef: Record<string, number>): void {
    layer.sort((a: string, b: string) => {
      const ma = FlowchartLayoutEngine.medianNeighborOrder(a, neighborMap, orderRef)
      const mb = FlowchartLayoutEngine.medianNeighborOrder(b, neighborMap, orderRef)
      if (ma !== mb) {
        return ma - mb
      }
      return a.localeCompare(b)
    })
    for (let i = 0; i < layer.length; i++) {
      orderRef[layer[i]] = i
    }
  }

  private static medianNeighborOrder(nodeId: string, neighborMap: Record<string, string[]>,
    orderRef: Record<string, number>): number {
    const neighbors = neighborMap[nodeId]
    if (neighbors.length === 0) {
      return orderRef[nodeId]
    }
    const values: number[] = []
    for (const nid of neighbors) {
      values.push(orderRef[nid])
    }
    values.sort((a: number, b: number) => a - b)
    const mid = Math.floor(values.length / 2)
    if (values.length % 2 === 1) {
      return values[mid]
    }
    return (values[mid - 1] + values[mid]) / 2
  }

  private static assignLayerCoordinates(nodes: FlowchartNodeModel[], layers: string[][],
    positions: Record<string, FlowchartNodePosition>, preferVertical: boolean,
    cellW: number, cellH: number, offsetX: number, offsetY: number): void {
    for (let r = 0; r < layers.length; r++) {
      const layer = layers[r]
      const layerSpan = layer.length > 0 ? (layer.length - 1) * (preferVertical ? cellW : cellH) : 0
      for (let i = 0; i < layer.length; i++) {
        const node = FlowchartLayoutEngine.nodeById(nodes, layer[i])
        if (node === undefined) {
          continue
        }
        const centeredOffset = i * (preferVertical ? cellW : cellH) - layerSpan / 2
        let x = 0
        let y = 0
        if (preferVertical) {
          x = FlowchartLayoutEngine.GRID_ORIGIN + offsetX + centeredOffset
          y = FlowchartLayoutEngine.GRID_ORIGIN + offsetY + r * cellH
        } else {
          x = FlowchartLayoutEngine.GRID_ORIGIN + offsetX + r * cellW
          y = FlowchartLayoutEngine.GRID_ORIGIN + offsetY + centeredOffset
        }
        positions[node.id] = createFlowchartPosition(x, y)
      }
    }
  }

  private static reduceOcclusions(nodes: FlowchartNodeModel[], edges: LayoutEdge[],
    positions: Record<string, FlowchartNodePosition>, preferVertical: boolean, cellH: number): void {
    for (let pass = 0; pass < FlowchartLayoutEngine.MAX_NUDGE_PASSES; pass++) {
      let improved = false
      for (const edge of edges) {
        const source = FlowchartLayoutEngine.nodeById(nodes, edge.source)
        const target = FlowchartLayoutEngine.nodeById(nodes, edge.target)
        if (source === undefined || target === undefined) {
          continue
        }
        const sp = positions[source.id]
        const tp = positions[target.id]
        if (sp === undefined || tp === undefined) {
          continue
        }
        const fromX = sp.x + source.width / 2
        const fromY = sp.y + source.height / 2
        const toX = tp.x + target.width / 2
        const toY = tp.y + target.height / 2
        for (const blocker of nodes) {
          if (blocker.id === source.id || blocker.id === target.id) {
            continue
          }
          const bp = positions[blocker.id]
          if (bp === undefined) {
            continue
          }
          if (!FlowchartLayoutEngine.segmentHitsRect(fromX, fromY, toX, toY, bp.x, bp.y,
            blocker.width, blocker.height, FlowchartLayoutEngine.OCCLUSION_MARGIN)) {
            continue
          }
          const nudge = cellH * 0.5
          const nudgeX = preferVertical ? nudge : 0
          const nudgeY = preferVertical ? 0 : nudge
          const tryA = createFlowchartPosition(bp.x - nudgeX, bp.y - nudgeY)
          const tryB = createFlowchartPosition(bp.x + nudgeX, bp.y + nudgeY)
          const aOk = !FlowchartLayoutEngine.segmentHitsRect(fromX, fromY, toX, toY, tryA.x, tryA.y,
            blocker.width, blocker.height, FlowchartLayoutEngine.OCCLUSION_MARGIN)
          const bOk = !FlowchartLayoutEngine.segmentHitsRect(fromX, fromY, toX, toY, tryB.x, tryB.y,
            blocker.width, blocker.height, FlowchartLayoutEngine.OCCLUSION_MARGIN)
          if (aOk) {
            positions[blocker.id] = tryA
          } else if (bOk) {
            positions[blocker.id] = tryB
          }
          improved = true
        }
      }
      if (!improved) {
        break
      }
    }
  }

  private static segmentHitsRect(x1: number, y1: number, x2: number, y2: number,
    px: number, py: number, width: number, height: number, margin: number): boolean {
    const left = px - margin
    const right = px + width + margin
    const top = py - margin
    const bottom = py + height + margin
    return FlowchartLayoutEngine.segmentIntersectsRect(x1, y1, x2, y2, left, top, right, bottom)
  }

  private static segmentIntersectsRect(x1: number, y1: number, x2: number, y2: number,
    left: number, top: number, right: number, bottom: number): boolean {
    if (x1 >= left && x1 <= right && y1 >= top && y1 <= bottom) {
      return true
    }
    if (x2 >= left && x2 <= right && y2 >= top && y2 <= bottom) {
      return true
    }
    if (x1 < left && x2 < left) {
      return false
    }
    if (x1 > right && x2 > right) {
      return false
    }
    if (y1 < top && y2 < top) {
      return false
    }
    if (y1 > bottom && y2 > bottom) {
      return false
    }
    return FlowchartLayoutEngine.segmentsIntersect(x1, y1, x2, y2, left, top, right, bottom) ||
      FlowchartLayoutEngine.segmentsIntersect(x1, y1, x2, y2, right, top, right, bottom) ||
      FlowchartLayoutEngine.segmentsIntersect(x1, y1, x2, y2, right, bottom, left, bottom) ||
      FlowchartLayoutEngine.segmentsIntersect(x1, y1, x2, y2, left, bottom, left, top)
  }

  private static segmentsIntersect(ax: number, ay: number, bx: number, by: number,
    cx: number, cy: number, dx: number, dy: number): boolean {
    const orient = (px: number, py: number, qx: number, qy: number, rx: number, ry: number): number => {
      return (qy - py) * (rx - qx) - (qx - px) * (ry - qy)
    }
    const o1 = orient(ax, ay, bx, by, cx, cy)
    const o2 = orient(ax, ay, bx, by, dx, dy)
    const o3 = orient(cx, cy, dx, dy, ax, ay)
    const o4 = orient(cx, cy, dx, dy, bx, by)
    if (o1 * o2 < 0 && o3 * o4 < 0) {
      return true
    }
    return false
  }

  private static applyGridPositions(nodes: FlowchartNodeModel[],
    positions: Record<string, FlowchartNodePosition>, preferVertical: boolean,
    cellW: number, cellH: number, offsetX: number, offsetY: number): void {
    for (let index = 0; index < nodes.length; index++) {
      const node = nodes[index]
      let col = 0
      let row = 0
      if (preferVertical) {
        row = index
      } else {
        col = index % FlowchartLayoutEngine.GRID_COLS
        row = Math.floor(index / FlowchartLayoutEngine.GRID_COLS)
      }
      positions[node.id] = createFlowchartPosition(
        FlowchartLayoutEngine.GRID_ORIGIN + offsetX + col * cellW,
        FlowchartLayoutEngine.GRID_ORIGIN + offsetY + row * cellH
      )
    }
  }
}
