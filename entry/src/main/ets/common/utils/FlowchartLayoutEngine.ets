import type {
  FlowchartAnchor,
  FlowchartEdgeModel,
  FlowchartGraphModel,
  FlowchartNodeModel,
  FlowchartNodePosition
} from '../model/FlowchartGraph'
import {
  FLOWCHART_LINE_NODE_SHAPE,
  FLOWCHART_ORTHOGONAL_ROUTING_KEY,
  FLOWCHART_LAYOUT_MODE_KEY,
  FLOWCHART_LAYOUT_MODE_MIND_MAP_LINEAR,
  FLOWCHART_MIND_MAP_ROOT_ID_KEY,
  FLOWCHART_MIND_MAP_SIDE_LEFT,
  FLOWCHART_MIND_MAP_SIDE_RIGHT,
  FLOWCHART_MIND_MAP_BLOCK_PROXY_ID,
  createFlowchartPosition
} from '../model/FlowchartGraph'
import { FlowchartMindMap } from './FlowchartMindMap'

interface LayoutEdge {
  source: string
  target: string
}

interface FlowchartSubtreeSize {
  w: number
  h: number
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
    if (FlowchartMindMap.isMindMapMode(graph)) {
      const rootId = FlowchartMindMap.rootId(graph)
      if (rootId.length > 0 && graph.nodes.some((n) => n.id === rootId)) {
        return FlowchartLayoutEngine.applyAlignedLayoutPreservingMindMap(graph, preferVertical, rootId)
      }
    }
    return FlowchartLayoutEngine.applyAlignedLayoutCore(graph, preferVertical)
  }

  static applyAlignedLayoutPreservingMindMap(
    graph: FlowchartGraphModel,
    preferVertical: boolean,
    rootId: string
  ): FlowchartGraphModel {
    const mindMapIds = FlowchartMindMap.collectSubtreeIds(graph, rootId)
    graph = FlowchartLayoutEngine.applyMindMapLinearLayout(graph, false, rootId)

    let minX = Number.MAX_VALUE
    let minY = Number.MAX_VALUE
    let maxX = Number.MIN_VALUE
    let maxY = Number.MIN_VALUE
    for (const node of graph.nodes) {
      if (!mindMapIds.has(node.id)) {
        continue
      }
      minX = Math.min(minX, node.position.x)
      minY = Math.min(minY, node.position.y)
      maxX = Math.max(maxX, node.position.x + node.width)
      maxY = Math.max(maxY, node.position.y + node.height)
    }
    const bboxOrigin = createFlowchartPosition(minX, minY)
    const blockW = Math.max(1, maxX - minX)
    const blockH = Math.max(1, maxY - minY)
    const proxyId = FLOWCHART_MIND_MAP_BLOCK_PROXY_ID
    const proxy: FlowchartNodeModel = {
      id: proxyId,
      title: '',
      description: '',
      color: '',
      shape: 'roundedRect',
      position: bboxOrigin,
      width: blockW,
      height: blockH,
      rotation: 0,
      properties: {}
    }

    const lineNodes: FlowchartNodeModel[] = []
    const layoutShapeNodes: FlowchartNodeModel[] = [proxy]
    for (const node of graph.nodes) {
      if (node.shape === FLOWCHART_LINE_NODE_SHAPE) {
        lineNodes.push(node)
      } else if (!mindMapIds.has(node.id)) {
        layoutShapeNodes.push(node)
      }
    }

    const layoutEdgeKeys = new Set<string>()
    const layoutEdges: LayoutEdge[] = []
    const addLayoutEdge = (source: string, target: string): void => {
      const key = source <= target ? `${source}|${target}` : `${target}|${source}`
      if (!layoutEdgeKeys.has(key)) {
        layoutEdgeKeys.add(key)
        layoutEdges.push({ source, target })
      }
    }
    const layoutShapeIds: Record<string, boolean> = {}
    for (const node of layoutShapeNodes) {
      layoutShapeIds[node.id] = true
    }
    for (const edge of graph.edges) {
      const srcInMind = mindMapIds.has(edge.source)
      const tgtInMind = mindMapIds.has(edge.target)
      if (srcInMind && tgtInMind) {
        continue
      }
      if (!srcInMind && !tgtInMind) {
        if (layoutShapeIds[edge.source] && layoutShapeIds[edge.target]) {
          addLayoutEdge(edge.source, edge.target)
        }
        continue
      }
      const externalId = srcInMind ? edge.target : edge.source
      if (layoutShapeIds[externalId]) {
        addLayoutEdge(proxyId, externalId)
      }
    }

    const positions = FlowchartLayoutEngine.layoutShapeNodes(
      layoutShapeNodes, layoutEdges, preferVertical
    )
    const proxyPos = positions[proxyId] ?? bboxOrigin
    const deltaX = proxyPos.x - bboxOrigin.x
    const deltaY = proxyPos.y - bboxOrigin.y

    const nodes = graph.nodes.map((node: FlowchartNodeModel): FlowchartNodeModel => {
      if (mindMapIds.has(node.id)) {
        return {
          id: node.id,
          title: node.title,
          description: node.description,
          color: node.color,
          shape: node.shape,
          position: createFlowchartPosition(node.position.x + deltaX, node.position.y + deltaY),
          width: node.width,
          height: node.height,
          rotation: node.rotation,
          properties: node.properties
        }
      }
      const pos = positions[node.id]
      if (pos !== undefined) {
        return {
          id: node.id,
          title: node.title,
          description: node.description,
          color: node.color,
          shape: node.shape,
          position: pos,
          width: node.width,
          height: node.height,
          rotation: node.rotation,
          properties: node.properties
        }
      }
      return node
    })

    const nodeById: Record<string, FlowchartNodeModel> = {}
    for (const node of nodes) {
      nodeById[node.id] = node
    }
    const rootForAnchors = nodeById[rootId]
    const edges = graph.edges.map((edge: FlowchartEdgeModel): FlowchartEdgeModel => {
      if (mindMapIds.has(edge.source) && mindMapIds.has(edge.target)) {
        return edge
      }
      const source = nodeById[edge.source]
      const target = nodeById[edge.target]
      if (source === undefined || target === undefined || rootForAnchors === undefined) {
        return edge
      }
      const layoutSource = mindMapIds.has(edge.source) ? rootForAnchors : source
      const layoutTarget = mindMapIds.has(edge.target) ? rootForAnchors : target
      const anchors = FlowchartLayoutEngine.layoutAnchors(layoutSource, layoutTarget, preferVertical)
      return {
        id: edge.id,
        source: edge.source,
        target: edge.target,
        label: edge.label,
        directed: edge.directed,
        lineType: edge.lineType,
        sourceAnchor: anchors[0],
        targetAnchor: anchors[1],
        properties: edge.properties
      }
    })

    const metadata: Record<string, Object> = {}
    for (const key of Object.keys(graph.metadata)) {
      metadata[key] = graph.metadata[key]
    }
    metadata[FLOWCHART_ORTHOGONAL_ROUTING_KEY] = true
    return {
      version: graph.version,
      metadata,
      nodes,
      edges
    }
  }

  static layoutShapeNodes(
    shapeNodes: FlowchartNodeModel[],
    layoutEdges: LayoutEdge[],
    preferVertical: boolean
  ): Record<string, FlowchartNodePosition> {
    if (shapeNodes.length === 0) {
      return {}
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
    const positions: Record<string, FlowchartNodePosition> = {}
    if (layoutEdges.length === 0) {
      FlowchartLayoutEngine.applyGridPositions(shapeNodes, positions, preferVertical, cellW, cellH, 0, 0)
      return positions
    }
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
    return positions
  }

  static applyAlignedLayoutCore(graph: FlowchartGraphModel, preferVertical: boolean = false): FlowchartGraphModel {
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
    const nodeById: Record<string, FlowchartNodeModel> = {}
    for (const node of nodes) {
      nodeById[node.id] = node
    }
    const edges = graph.edges.map((edge: FlowchartEdgeModel) => {
      const source = nodeById[edge.source]
      const target = nodeById[edge.target]
      if (source === undefined || target === undefined) {
        return edge
      }
      const anchors = FlowchartLayoutEngine.layoutAnchors(source, target, preferVertical)
      return {
        id: edge.id,
        source: edge.source,
        target: edge.target,
        label: edge.label,
        directed: edge.directed,
        lineType: edge.lineType,
        sourceAnchor: anchors[0],
        targetAnchor: anchors[1],
        properties: edge.properties
      } as FlowchartEdgeModel
    })
    const metadata: Record<string, Object> = {}
    for (const key of Object.keys(graph.metadata)) {
      metadata[key] = graph.metadata[key]
    }
    metadata[FLOWCHART_ORTHOGONAL_ROUTING_KEY] = true
    return {
      version: graph.version,
      metadata,
      nodes,
      edges
    }
  }

  static applyMindMapLinearLayout(graph: FlowchartGraphModel, preferVertical: boolean = false,
    rootId?: string, preserveRootPosition: boolean = false): FlowchartGraphModel {
    if (graph.nodes.length === 0) {
      return graph
    }
    const metadataRoot = graph.metadata[FLOWCHART_MIND_MAP_ROOT_ID_KEY]
    let resolvedRootId = rootId ?? (typeof metadataRoot === 'string' ? metadataRoot : '')
    if (resolvedRootId.length === 0) {
      resolvedRootId = graph.nodes[0].id
    }
    graph = FlowchartMindMap.normalizeMindMapNodeSizes(graph, resolvedRootId)
    const nodeById: Record<string, FlowchartNodeModel> = {}
    for (const node of graph.nodes) {
      nodeById[node.id] = node
    }
    if (nodeById[resolvedRootId] === undefined) {
      return graph
    }
    const previousRootPosition = preserveRootPosition
      ? nodeById[resolvedRootId].position
      : undefined

    const siblingGap = 32
    const levelGap = 80
    const origin = 48
    const positions: Record<string, FlowchartNodePosition> = {}
    const subtreeSizes: Record<string, FlowchartSubtreeSize> = {}

    const measureOnSide = (id: string, side: string): FlowchartSubtreeSize => {
      const cacheKey = `${id}:${side}`
      const cached = subtreeSizes[cacheKey]
      if (cached !== undefined) {
        return cached
      }
      const node = nodeById[id]
      const kids = FlowchartMindMap.childrenOnSide(graph, id, side)
      if (kids.length === 0) {
        const size: FlowchartSubtreeSize = { w: node.width, h: node.height }
        subtreeSizes[cacheKey] = size
        return size
      }
      let totalH = 0
      let maxChildW = 0
      for (let i = 0; i < kids.length; i++) {
        const childSize = measureOnSide(kids[i], side)
        totalH += childSize.h
        if (i < kids.length - 1) {
          totalH += siblingGap
        }
        maxChildW = Math.max(maxChildW, childSize.w)
      }
      const size: FlowchartSubtreeSize = {
        w: node.width + levelGap + maxChildW,
        h: Math.max(node.height, totalH)
      }
      subtreeSizes[cacheKey] = size
      return size
    }

    const measureSideExtent = (parentId: string, side: string): FlowchartSubtreeSize => {
      const kids = FlowchartMindMap.childrenOnSide(graph, parentId, side)
      if (kids.length === 0) {
        return { w: 0, h: 0 }
      }
      let totalH = 0
      let maxW = 0
      for (let i = 0; i < kids.length; i++) {
        const childSize = measureOnSide(kids[i], side)
        totalH += childSize.h
        if (i < kids.length - 1) {
          totalH += siblingGap
        }
        maxW = Math.max(maxW, childSize.w)
      }
      return { w: maxW, h: totalH }
    }

    const placeOnSide = (id: string, side: string, anchorX: number, anchorY: number): void => {
      const node = nodeById[id]
      const kids = FlowchartMindMap.childrenOnSide(graph, id, side)
      const box = measureOnSide(id, side)
      if (side === FLOWCHART_MIND_MAP_SIDE_RIGHT) {
        positions[id] = createFlowchartPosition(anchorX, anchorY + (box.h - node.height) / 2)
        if (kids.length === 0) {
          return
        }
        let cursorY = anchorY
        const childX = anchorX + node.width + levelGap
        for (const childId of kids) {
          const childBox = measureOnSide(childId, side)
          placeOnSide(childId, side, childX, cursorY)
          cursorY += childBox.h + siblingGap
        }
      } else {
        const nodeX = anchorX - node.width
        positions[id] = createFlowchartPosition(nodeX, anchorY + (box.h - node.height) / 2)
        if (kids.length === 0) {
          return
        }
        let cursorY = anchorY
        for (const childId of kids) {
          const childBox = measureOnSide(childId, side)
          const childAnchorX = nodeX - levelGap
          placeOnSide(childId, side, childAnchorX, cursorY)
          cursorY += childBox.h + siblingGap
        }
      }
    }

    const root = nodeById[resolvedRootId]
    const leftExtent = measureSideExtent(resolvedRootId, FLOWCHART_MIND_MAP_SIDE_LEFT)
    const rightExtent = measureSideExtent(resolvedRootId, FLOWCHART_MIND_MAP_SIDE_RIGHT)
    const rootBoxRight = measureOnSide(resolvedRootId, FLOWCHART_MIND_MAP_SIDE_RIGHT)
    const rootBoxLeft = measureOnSide(resolvedRootId, FLOWCHART_MIND_MAP_SIDE_LEFT)
    const sideBlockH = Math.max(leftExtent.h, rightExtent.h)
    const rootH = Math.max(
      root.height,
      Math.max(sideBlockH, Math.max(rootBoxRight.h, rootBoxLeft.h))
    )
    const rootX = origin + leftExtent.w
    const rootY = origin + (rootH - root.height) / 2
    positions[resolvedRootId] = createFlowchartPosition(rootX, rootY)

    if (leftExtent.w > 0) {
      let cursorY = origin + (sideBlockH - leftExtent.h) / 2
      for (const childId of FlowchartMindMap.childrenOnSide(graph, resolvedRootId, FLOWCHART_MIND_MAP_SIDE_LEFT)) {
        const childBox = measureOnSide(childId, FLOWCHART_MIND_MAP_SIDE_LEFT)
        placeOnSide(childId, FLOWCHART_MIND_MAP_SIDE_LEFT, rootX - levelGap, cursorY)
        cursorY += childBox.h + siblingGap
      }
    }
    if (rightExtent.w > 0) {
      let cursorY = origin + (sideBlockH - rightExtent.h) / 2
      for (const childId of FlowchartMindMap.childrenOnSide(graph, resolvedRootId, FLOWCHART_MIND_MAP_SIDE_RIGHT)) {
        const childBox = measureOnSide(childId, FLOWCHART_MIND_MAP_SIDE_RIGHT)
        placeOnSide(childId, FLOWCHART_MIND_MAP_SIDE_RIGHT, rootX + root.width + levelGap, cursorY)
        cursorY += childBox.h + siblingGap
      }
    }

    if (previousRootPosition !== undefined) {
      const laidRoot = positions[resolvedRootId]
      if (laidRoot !== undefined) {
        const dx = previousRootPosition.x - laidRoot.x
        const dy = previousRootPosition.y - laidRoot.y
        if (dx !== 0 || dy !== 0) {
          for (const id of Object.keys(positions)) {
            const pos = positions[id]
            positions[id] = createFlowchartPosition(pos.x + dx, pos.y + dy)
          }
        }
      }
    }

    const nodes = graph.nodes.map((node: FlowchartNodeModel): FlowchartNodeModel => {
      const pos = positions[node.id]
      return {
        id: node.id,
        title: node.title,
        description: node.description,
        color: node.color,
        shape: node.shape,
        position: pos ?? node.position,
        width: node.width,
        height: node.height,
        rotation: node.rotation,
        properties: node.properties
      }
    })
    const metadata: Record<string, Object> = {}
    for (const key of Object.keys(graph.metadata)) {
      metadata[key] = graph.metadata[key]
    }
    metadata[FLOWCHART_LAYOUT_MODE_KEY] = FLOWCHART_LAYOUT_MODE_MIND_MAP_LINEAR
    metadata[FLOWCHART_MIND_MAP_ROOT_ID_KEY] = resolvedRootId
    metadata[FLOWCHART_ORTHOGONAL_ROUTING_KEY] = true
    return {
      version: graph.version,
      metadata,
      nodes,
      edges: [...graph.edges]
    }
  }

  static nodeDegrees(edges: FlowchartEdgeModel[]): Record<string, number> {
    const degrees: Record<string, number> = {}
    for (const edge of edges) {
      degrees[edge.source] = (degrees[edge.source] ?? 0) + 1
      degrees[edge.target] = (degrees[edge.target] ?? 0) + 1
    }
    return degrees
  }

  static layoutAnchors(source: FlowchartNodeModel, target: FlowchartNodeModel,
    preferVertical: boolean): [FlowchartAnchor, FlowchartAnchor] {
    const scx = source.position.x + source.width / 2
    const scy = source.position.y + source.height / 2
    const tcx = target.position.x + target.width / 2
    const tcy = target.position.y + target.height / 2
    const dx = tcx - scx
    const dy = tcy - scy
    if (preferVertical) {
      if (Math.abs(dy) >= Math.abs(dx)) {
        return dy >= 0 ? ['bottom', 'top'] : ['top', 'bottom']
      }
    } else if (Math.abs(dx) >= Math.abs(dy)) {
      return dx >= 0 ? ['right', 'left'] : ['left', 'right']
    }
    if (Math.abs(dx) > Math.abs(dy)) {
      return dx >= 0 ? ['right', 'left'] : ['left', 'right']
    }
    return dy >= 0 ? ['bottom', 'top'] : ['top', 'bottom']
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
