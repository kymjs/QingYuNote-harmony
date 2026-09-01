import type {
  FlowchartAnchor,
  FlowchartEdgeModel,
  FlowchartGraphModel,
  FlowchartLineType,
  FlowchartNodeModel,
  FlowchartShapeType
} from '../model/FlowchartGraph'
import {
  cloneFlowchartRecord,
  createEmptyFlowchartGraph,
  createFlowchartPosition,
  emptyFlowchartProperties,
  FLOWCHART_DIAGRAM_KIND_KEY,
  FLOWCHART_LAYOUT_MODE_KEY,
  FLOWCHART_LAYOUT_MODE_MIND_MAP_LINEAR,
  FLOWCHART_MIND_MAP_ROLE_BRANCH,
  FLOWCHART_MIND_MAP_ROLE_KEY,
  FLOWCHART_MIND_MAP_ROLE_ROOT,
  FLOWCHART_MIND_MAP_ROOT_ID_KEY,
  FLOWCHART_MIND_MAP_SIDE_KEY
} from '../model/FlowchartGraph'
import { FlowchartMindMap } from './FlowchartMindMap'

export const FLOWCHART_EXT_VERSION = 1

export type FlowchartDiagramKind = 'graph' | 'mindmap' | 'flowchart'

export interface FlowchartEncodedGraph {
  mermaidBody: string
  flowchartExtJson: string
}

interface ParsedNodeLabel {
  title: string
  description: string
}

interface ParsedGraphEdge {
  source: string
  target: string
  label: string
}

interface MindmapContentLine {
  depth: number
  text: string
  isRoot: boolean
}

interface FlowchartExtPosition {
  x: number
  y: number
}

interface FlowchartExtNodeEntry {
  position: FlowchartExtPosition
  width: number
  height: number
  rotation: number
  color: string
  shape: FlowchartShapeType
  properties: Record<string, Object>
}

interface FlowchartExtEdgeEntry {
  source: string
  target: string
  lineType: FlowchartLineType
  sourceAnchor: FlowchartAnchor
  targetAnchor: FlowchartAnchor
  directed: boolean
  label: string
  properties: Record<string, Object>
}

interface FlowchartExtMindmapSection {
  rootId: string
  dfsOrder: string[]
  sides?: Record<string, string>
}

interface FlowchartExtDocument {
  version: number
  diagramKind: FlowchartDiagramKind
  direction: string
  metadata: Record<string, Object>
  nodes: Record<string, FlowchartExtNodeEntry>
  edges: Record<string, FlowchartExtEdgeEntry>
  mindmap?: FlowchartExtMindmapSection
}

export class FlowchartMermaidCodec {
  private static readonly FENCE_REGEX = /```mermaid\s*\r?\n([\s\S]*?)```/
  private static readonly GRAPH_EDGE_REGEX =
    /^\s*([A-Za-z0-9_]+)(?:\[[^\]]*\]|\([^\)]*\)|\{[^\}]*\})?\s*(-{1,2}>|-\.->|==>|---)\s*(?:\|([^|]*)\|\s*)?([A-Za-z0-9_]+)/

  static unwrapMermaidFence(content: string): string | undefined {
    const match = content.replace(/\r/g, '').match(FlowchartMermaidCodec.FENCE_REGEX)
    if (!match || match[1] === undefined) {
      return undefined
    }
    return match[1].trim()
  }

  static wrapMermaidFence(body: string): string {
    return `\`\`\`mermaid\n${body.trim()}\n\`\`\``
  }

  static detectKind(mermaidBody: string): FlowchartDiagramKind {
    const lines = mermaidBody.trim().split('\n')
    if (lines.length === 0) {
      return 'graph'
    }
    const first = lines[0].trim().toLowerCase()
    if (first.startsWith('mindmap')) {
      return 'mindmap'
    }
    if (first.startsWith('graph')) {
      return 'graph'
    }
    if (first.startsWith('flowchart')) {
      return 'flowchart'
    }
    return 'graph'
  }

  static detectDirection(mermaidBody: string): string {
    const first = mermaidBody.trim().split('\n')[0].trim()
    const parts = first.split(/\s+/)
    if (parts.length >= 2) {
      const dir = parts[parts.length - 1].toUpperCase()
      if (dir === 'TD' || dir === 'LR' || dir === 'BT' || dir === 'RL') {
        return dir
      }
    }
    return 'TD'
  }

  static isMindMapContent(content: string): boolean {
    const body = FlowchartMermaidCodec.unwrapMermaidFence(content)
    if (body === undefined || body.length === 0) {
      return false
    }
    return FlowchartMermaidCodec.detectKind(body) === 'mindmap'
  }

  static kindOfGraph(graph: FlowchartGraphModel): FlowchartDiagramKind {
    if (FlowchartMindMap.isMindMapMode(graph)) {
      return 'mindmap'
    }
    const raw = graph.metadata[FLOWCHART_DIAGRAM_KIND_KEY]
    if (typeof raw === 'string' && raw.length > 0) {
      return FlowchartMermaidCodec.diagramKindFromWire(raw)
    }
    return 'graph'
  }

  static extractSearchableText(mermaidBody: string): string {
    const kind = FlowchartMermaidCodec.detectKind(mermaidBody)
    if (kind === 'mindmap') {
      return FlowchartMermaidCodec.extractMindmapSearchText(mermaidBody)
    }
    return FlowchartMermaidCodec.extractGraphSearchText(mermaidBody)
  }

  static extractSearchableTextFromNote(content: string): string {
    const body = FlowchartMermaidCodec.unwrapMermaidFence(content)
    if (body === undefined || body.length === 0) {
      return ''
    }
    return FlowchartMermaidCodec.extractSearchableText(body)
  }

  static parseFromNote(content: string, flowchartExtJson: string | undefined): FlowchartGraphModel {
    const mermaidBody = FlowchartMermaidCodec.unwrapMermaidFence(content)
    if (mermaidBody === undefined || mermaidBody.length === 0) {
      return createEmptyFlowchartGraph()
    }
    let ext: Record<string, Object> | undefined = undefined
    const extRaw = (flowchartExtJson ?? '').trim()
    if (extRaw.length > 0) {
      try {
        ext = JSON.parse(extRaw) as Record<string, Object>
      } catch (_) {
        ext = undefined
      }
    }
    const kind = FlowchartMermaidCodec.detectKind(mermaidBody)
    if (kind === 'mindmap') {
      return FlowchartMermaidCodec.parseMindmap(mermaidBody, ext)
    }
    return FlowchartMermaidCodec.parseGraphLike(mermaidBody, ext, kind)
  }

  static encodeGraph(graph: FlowchartGraphModel): FlowchartEncodedGraph {
    const kind = FlowchartMermaidCodec.kindOfGraph(graph)
    const direction = FlowchartMermaidCodec.directionOfGraph(graph, kind)
    const mermaidBody = kind === 'mindmap'
      ? FlowchartMermaidCodec.encodeMindmap(graph)
      : FlowchartMermaidCodec.encodeGraphLike(graph, kind, direction)
    const ext = FlowchartMermaidCodec.buildFlowchartExt(graph, kind, direction)
    const result: FlowchartEncodedGraph = {
      mermaidBody: mermaidBody,
      flowchartExtJson: JSON.stringify(ext)
    }
    return result
  }

  static buildFlowchartExt(
    graph: FlowchartGraphModel,
    kind: FlowchartDiagramKind,
    direction: string
  ): FlowchartExtDocument {
    const nodes: Record<string, FlowchartExtNodeEntry> = {}
    for (const node of graph.nodes) {
      const position: FlowchartExtPosition = {
        x: node.position.x,
        y: node.position.y
      }
      const nodeEntry: FlowchartExtNodeEntry = {
        position: position,
        width: node.width,
        height: node.height,
        rotation: node.rotation,
        color: node.color,
        shape: node.shape,
        properties: node.properties
      }
      nodes[node.id] = nodeEntry
    }
    const edges: Record<string, FlowchartExtEdgeEntry> = {}
    for (const edge of graph.edges) {
      const edgeEntry: FlowchartExtEdgeEntry = {
        source: edge.source,
        target: edge.target,
        lineType: edge.lineType,
        sourceAnchor: edge.sourceAnchor,
        targetAnchor: edge.targetAnchor,
        directed: edge.directed,
        label: edge.label,
        properties: edge.properties
      }
      edges[edge.id] = edgeEntry
    }
    const ext: FlowchartExtDocument = {
      version: FLOWCHART_EXT_VERSION,
      diagramKind: kind,
      direction: direction,
      metadata: graph.metadata,
      nodes: nodes,
      edges: edges
    }
    if (kind === 'mindmap') {
      const rootId = FlowchartMindMap.rootId(graph) ?? ''
      const mindmap: FlowchartExtMindmapSection = {
        rootId: rootId,
        dfsOrder: FlowchartMermaidCodec.mindmapDfsOrder(graph)
      }
      const sides: Record<string, string> = {}
      for (const node of graph.nodes) {
        const side = node.properties[FLOWCHART_MIND_MAP_SIDE_KEY]
        if (typeof side === 'string' && side.length > 0) {
          sides[node.id] = side
        }
      }
      if (Object.keys(sides).length > 0) {
        mindmap.sides = sides
      }
      ext.mindmap = mindmap
    }
    return ext
  }

  static defaultSkeleton(kind: FlowchartDiagramKind, direction: string, rootTitle: string = '双击编辑'): string {
    switch (kind) {
      case 'mindmap':
        return `mindmap\n  ((${FlowchartMermaidCodec.escapeMindmapLine(rootTitle)}))`
      case 'flowchart':
        return `flowchart ${direction}\n  n1["${FlowchartMermaidCodec.escapeLabel(rootTitle)}"]`
      default:
        return `graph ${direction}\n  n1["${FlowchartMermaidCodec.escapeLabel(rootTitle)}"]`
    }
  }

  private static diagramKindFromWire(raw: string): FlowchartDiagramKind {
    switch (raw.trim().toLowerCase()) {
      case 'graph':
        return 'graph'
      case 'mindmap':
        return 'mindmap'
      case 'flowchart':
        return 'flowchart'
      default:
        return 'graph'
    }
  }

  private static directionOfGraph(graph: FlowchartGraphModel, kind: FlowchartDiagramKind): string {
    if (kind === 'mindmap') {
      return 'TD'
    }
    const raw = graph.metadata['direction']
    if (typeof raw === 'string' && raw.length > 0) {
      return raw.toUpperCase()
    }
    return 'TD'
  }

  private static mermaidId(nodeId: string): string {
    const trimmed = nodeId.trim()
    const lower = trimmed.toLowerCase()
    if (lower.startsWith('node') && lower.length > 4) {
      const numStr = trimmed.substring(4)
      let ok = numStr.length > 0
      for (let i = 0; i < numStr.length; i++) {
        const ch = numStr.charAt(i)
        if (ch < '0' || ch > '9') {
          ok = false
          break
        }
      }
      if (ok) {
        return lower
      }
    }
    return trimmed.replace(/-/g, '_')
  }

  private static uuidFromMermaidId(mermaidId: string, idMap: Record<string, string>): string {
    if (idMap[mermaidId] !== undefined) {
      return idMap[mermaidId]
    }
    return mermaidId.replace(/_/g, '-')
  }

  private static formatNodeLabel(node: FlowchartNodeModel): string {
    const title = node.title.trim()
    const desc = node.description.trim()
    if (desc.length === 0) {
      return FlowchartMermaidCodec.escapeLabel(title)
    }
    return FlowchartMermaidCodec.escapeLabel(`${title}<br/>${desc}`)
  }

  private static escapeLabel(raw: string): string {
    return raw
      .replace(/\\/g, '\\\\')
      .replace(/"/g, '#quot;')
      .replace(/\n/g, '<br/>')
      .replace(/\r/g, '')
  }

  private static unescapeLabel(raw: string): string {
    return raw
      .replace(/<br\/>/g, '\n')
      .replace(/<br>/g, '\n')
      .replace(/#quot;/g, '"')
      .replace(/\\n/g, '\n')
  }

  private static escapeMindmapLine(raw: string): string {
    return raw.replace(/\n/g, ' ').trim()
  }

  private static splitNodeLabel(label: string): ParsedNodeLabel {
    const unescaped = FlowchartMermaidCodec.unescapeLabel(label)
    const parts = unescaped.split('\n')
    if (parts.length <= 1) {
      const brParts = unescaped.split(/<br\s*\/?>/i)
      if (brParts.length <= 1) {
        return { title: unescaped.trim(), description: '' }
      }
      return {
        title: brParts[0].trim(),
        description: brParts.slice(1).join('\n').trim()
      }
    }
    return {
      title: parts[0].trim(),
      description: parts.slice(1).join('\n').trim()
    }
  }

  private static encodeGraphLike(
    graph: FlowchartGraphModel,
    kind: FlowchartDiagramKind,
    direction: string
  ): string {
    const keyword = kind === 'graph' ? 'graph' : 'flowchart'
    const lines: string[] = [`${keyword} ${direction}`]
    const idMap: Record<string, string> = {}
    for (const node of graph.nodes) {
      idMap[FlowchartMermaidCodec.mermaidId(node.id)] = node.id
    }
    const emittedEdges = new Set<string>()
    for (const edge of graph.edges) {
      if (FlowchartMindMap.isMindMapMode(graph) && !FlowchartMindMap.isMindMapEdge(graph, edge)) {
        continue
      }
      const source = FlowchartMermaidCodec.nodeById(graph, edge.source)
      const target = FlowchartMermaidCodec.nodeById(graph, edge.target)
      if (source === undefined || target === undefined) {
        continue
      }
      const sid = FlowchartMermaidCodec.mermaidId(edge.source)
      const tid = FlowchartMermaidCodec.mermaidId(edge.target)
      const label = edge.label.trim()
      const srcLabel = FlowchartMermaidCodec.formatNodeLabel(source)
      const tgtLabel = FlowchartMermaidCodec.formatNodeLabel(target)
      const edgeKey = `${sid}->${tid}|${label}`
      if (emittedEdges.has(edgeKey)) {
        continue
      }
      emittedEdges.add(edgeKey)
      if (label.length === 0) {
        lines.push(`  ${sid}["${srcLabel}"] --> ${tid}["${tgtLabel}"]`)
      } else {
        lines.push(`  ${sid}["${srcLabel}"] -->|${label}| ${tid}["${tgtLabel}"]`)
      }
    }
    for (const node of graph.nodes) {
      let hasEdge = false
      for (const edge of graph.edges) {
        if (edge.source === node.id || edge.target === node.id) {
          hasEdge = true
          break
        }
      }
      if (!hasEdge) {
        const sid = FlowchartMermaidCodec.mermaidId(node.id)
        lines.push(`  ${sid}["${FlowchartMermaidCodec.formatNodeLabel(node)}"]`)
      }
    }
    return lines.join('\n').replace(/\s+$/, '')
  }

  private static encodeMindmap(graph: FlowchartGraphModel): string {
    const lines: string[] = ['mindmap']
    const order = FlowchartMermaidCodec.mindmapDfsOrder(graph)
    if (order.length === 0) {
      return 'mindmap\n  ((双击编辑))'
    }
    const depthOf: Record<string, number> = {}
    const root = FlowchartMindMap.rootId(graph) ?? order[0]
    const measureDepth = (id: string, depth: number): void => {
      depthOf[id] = depth
      for (const child of FlowchartMermaidCodec.mindmapChildren(graph, id)) {
        measureDepth(child, depth + 1)
      }
    }
    measureDepth(root, 0)
    for (const id of order) {
      const node = FlowchartMermaidCodec.nodeById(graph, id)
      if (node === undefined) {
        continue
      }
      const depth = depthOf[id] ?? 0
      const pad = '  '.repeat(depth + 1)
      const text = FlowchartMermaidCodec.escapeMindmapLine(
        node.description.trim().length === 0
          ? node.title.trim()
          : `${node.title.trim()}  ${node.description.trim()}`
      )
      if (FlowchartMindMap.isRoot(graph, node)) {
        lines.push(`${pad}((${text}))`)
      } else {
        lines.push(`${pad}${text}`)
      }
    }
    return lines.join('\n').replace(/\s+$/, '')
  }

  private static mindmapChildren(graph: FlowchartGraphModel, parentId: string): string[] {
    const children: string[] = []
    for (const edge of graph.edges) {
      if (edge.source === parentId && FlowchartMindMap.isMindMapEdge(graph, edge)) {
        children.push(edge.target)
      }
    }
    children.sort()
    return children
  }

  private static mindmapDfsOrder(graph: FlowchartGraphModel): string[] {
    const root = FlowchartMindMap.rootId(graph)
    if (root === undefined || root.length === 0) {
      return graph.nodes.map((n) => n.id)
    }
    const order: string[] = []
    const walk = (id: string): void => {
      order.push(id)
      for (const child of FlowchartMermaidCodec.mindmapChildren(graph, id)) {
        walk(child)
      }
    }
    walk(root)
    for (const node of graph.nodes) {
      if (!order.includes(node.id)) {
        order.push(node.id)
      }
    }
    return order
  }

  private static parseGraphLike(
    mermaidBody: string,
    ext: Record<string, Object> | undefined,
    kind: FlowchartDiagramKind
  ): FlowchartGraphModel {
    const direction = FlowchartMermaidCodec.detectDirection(mermaidBody)
    const metadata = cloneFlowchartRecord(
      (ext?.['metadata'] as Record<string, Object> | undefined) ?? {}
    )
    metadata[FLOWCHART_DIAGRAM_KIND_KEY] = kind
    metadata['direction'] = direction

    const extNodes = (ext?.['nodes'] as Record<string, Object> | undefined) ?? {}
    const extEdges = (ext?.['edges'] as Record<string, Object> | undefined) ?? {}

    const parsedNodes: Record<string, ParsedNodeLabel> = {}
    const parsedEdges: ParsedGraphEdge[] = []

    for (const line of mermaidBody.split('\n')) {
      const trimmed = line.trim()
      if (trimmed.length === 0 ||
        trimmed.toLowerCase().startsWith('graph') ||
        trimmed.toLowerCase().startsWith('flowchart')) {
        continue
      }
      const match = trimmed.match(FlowchartMermaidCodec.GRAPH_EDGE_REGEX)
      if (match !== null && match[1] !== undefined && match[4] !== undefined) {
        const source = match[1]
        const target = match[4]
        const label = (match[3] ?? '').trim()
        parsedEdges.push({ source: source, target: target, label: label })
        const srcLabel = FlowchartMermaidCodec.extractBracketLabel(trimmed, source)
        const tgtLabel = FlowchartMermaidCodec.extractBracketLabel(trimmed, target)
        if (srcLabel !== undefined) {
          parsedNodes[source] = FlowchartMermaidCodec.splitNodeLabel(srcLabel)
        }
        if (tgtLabel !== undefined) {
          parsedNodes[target] = FlowchartMermaidCodec.splitNodeLabel(tgtLabel)
        }
        continue
      }
      const solo = trimmed.match(/^([A-Za-z0-9_]+)\["([^"]*)"\]/)
      if (solo !== null && solo[1] !== undefined && solo[2] !== undefined) {
        parsedNodes[solo[1]] = FlowchartMermaidCodec.splitNodeLabel(solo[2])
      }
    }

    const mermaidToUuid: Record<string, string> = {}
    for (const extId of Object.keys(extNodes)) {
      mermaidToUuid[FlowchartMermaidCodec.mermaidId(extId)] = extId
    }

    const nodeFromExt = (mermaidNodeId: string, parsed: ParsedNodeLabel | undefined): FlowchartNodeModel => {
      const uuid = FlowchartMermaidCodec.uuidFromMermaidId(mermaidNodeId, mermaidToUuid)
      const extNode = extNodes[uuid] as Record<string, Object> | undefined
      const parsedLabel = parsed ?? { title: '', description: '' }
      const pos = (extNode?.['position'] as Record<string, Object> | undefined) ?? {}
      const props = FlowchartMermaidCodec.copyProperties(extNode?.['properties'])
      return {
        id: uuid,
        title: parsedLabel.title.length > 0 ? parsedLabel.title : '双击编辑',
        description: parsedLabel.description,
        color: typeof extNode?.['color'] === 'string' ? `${extNode['color']}` : '#FFF8E1',
        shape: FlowchartMermaidCodec.shapeFromWire(extNode?.['shape']),
        position: createFlowchartPosition(
          typeof pos['x'] === 'number' ? pos['x'] as number : 0,
          typeof pos['y'] === 'number' ? pos['y'] as number : 0
        ),
        width: typeof extNode?.['width'] === 'number' ? extNode['width'] as number : 120,
        height: typeof extNode?.['height'] === 'number' ? extNode['height'] as number : 72,
        rotation: typeof extNode?.['rotation'] === 'number' ? extNode['rotation'] as number : 0,
        properties: props
      }
    }

    const nodes: FlowchartNodeModel[] = []
    for (const key of Object.keys(parsedNodes)) {
      nodes.push(nodeFromExt(key, parsedNodes[key]))
    }
    for (const extId of Object.keys(extNodes)) {
      if (!nodes.some((n) => n.id === extId)) {
        nodes.push(nodeFromExt(FlowchartMermaidCodec.mermaidId(extId), undefined))
      }
    }

    const edges: FlowchartEdgeModel[] = []
    for (const extEntryKey of Object.keys(extEdges)) {
      const edgeMap = extEdges[extEntryKey] as Record<string, Object>
      edges.push({
        id: extEntryKey,
        source: typeof edgeMap['source'] === 'string' ? `${edgeMap['source']}` : '',
        target: typeof edgeMap['target'] === 'string' ? `${edgeMap['target']}` : '',
        label: typeof edgeMap['label'] === 'string' ? `${edgeMap['label']}` : '',
        directed: edgeMap['directed'] === false ? false : true,
        lineType: FlowchartMermaidCodec.lineTypeFromWire(edgeMap['lineType']),
        sourceAnchor: FlowchartMermaidCodec.anchorFromWire(edgeMap['sourceAnchor']),
        targetAnchor: FlowchartMermaidCodec.anchorFromWire(edgeMap['targetAnchor']),
        properties: FlowchartMermaidCodec.copyProperties(edgeMap['properties'])
      })
    }
    for (const pe of parsedEdges) {
      const sourceUuid = FlowchartMermaidCodec.uuidFromMermaidId(pe.source, mermaidToUuid)
      const targetUuid = FlowchartMermaidCodec.uuidFromMermaidId(pe.target, mermaidToUuid)
      const exists = edges.some((e) => e.source === sourceUuid && e.target === targetUuid)
      if (!exists) {
        edges.push({
          id: `edge_${pe.source}_${pe.target}`,
          source: sourceUuid,
          target: targetUuid,
          label: pe.label,
          directed: true,
          lineType: 'solid',
          sourceAnchor: 'bottom',
          targetAnchor: 'top',
          properties: emptyFlowchartProperties()
        })
      }
    }

    return {
      version: 1,
      metadata: metadata,
      nodes: nodes,
      edges: edges
    }
  }

  private static extractBracketLabel(line: string, nodeId: string): string | undefined {
    const pattern = new RegExp(`${nodeId}\\["([^"]*)"\\]`)
    const match = line.match(pattern)
    return match?.[1]
  }

  private static parseMindmap(
    mermaidBody: string,
    ext: Record<string, Object> | undefined
  ): FlowchartGraphModel {
    const metadata = cloneFlowchartRecord(
      (ext?.['metadata'] as Record<string, Object> | undefined) ?? {}
    )
    metadata[FLOWCHART_LAYOUT_MODE_KEY] = FLOWCHART_LAYOUT_MODE_MIND_MAP_LINEAR
    metadata[FLOWCHART_DIAGRAM_KIND_KEY] = 'mindmap'

    const extNodes = (ext?.['nodes'] as Record<string, Object> | undefined) ?? {}
    const extEdges = (ext?.['edges'] as Record<string, Object> | undefined) ?? {}
    const mindmapExt = (ext?.['mindmap'] as Record<string, Object> | undefined) ?? {}
    const dfsRaw = mindmapExt['dfsOrder'] as Array<Object> | undefined
    const dfsOrder: string[] = []
    if (dfsRaw !== undefined) {
      for (let i = 0; i < dfsRaw.length; i++) {
        dfsOrder.push(`${dfsRaw[i]}`)
      }
    }
    const sides = (mindmapExt['sides'] as Record<string, Object> | undefined) ?? {}
    let rootId = typeof mindmapExt['rootId'] === 'string' ? `${mindmapExt['rootId']}` : ''

    const contentLines: MindmapContentLine[] = []
    for (const line of mermaidBody.split('\n')) {
      if (line.trim().length === 0 || line.trim().toLowerCase() === 'mindmap') {
        continue
      }
      const indent = line.length - line.trimStart().length
      const depth = Math.floor(indent / 2)
      const trimmed = line.trim()
      let isRoot = false
      let text = trimmed
      if (trimmed.startsWith('((') && trimmed.endsWith('))')) {
        isRoot = true
        text = trimmed.substring(2, trimmed.length - 2).trim()
      }
      contentLines.push({ depth: depth, text: text, isRoot: isRoot })
    }

    const nodes: FlowchartNodeModel[] = []
    const edges: FlowchartEdgeModel[] = []
    const stack: string[] = []

    for (let i = 0; i < contentLines.length; i++) {
      const line = contentLines[i]
      const nodeId = i < dfsOrder.length ? dfsOrder[i] : `mm_${i}`
      if (line.isRoot && rootId.length === 0) {
        rootId = nodeId
      }
      // depth 与栈深对齐：同级节点需先弹出上一兄弟（>=），再挂到共同父节点。
      while (stack.length >= line.depth) {
        stack.pop()
      }
      const parentId = stack.length === 0 ? undefined : stack[stack.length - 1]
      const extNode = extNodes[nodeId] as Record<string, Object> | undefined
      const pos = (extNode?.['position'] as Record<string, Object> | undefined) ?? {}
      const labelParts = line.text.split(/\s{2,}/)
      const title = FlowchartMermaidCodec.unescapeLabel(labelParts[0])
      const description = labelParts.length > 1 ? labelParts.slice(1).join(' ').trim() : ''
      const properties = FlowchartMermaidCodec.copyProperties(extNode?.['properties'])
      if (line.isRoot) {
        properties[FLOWCHART_MIND_MAP_ROLE_KEY] = FLOWCHART_MIND_MAP_ROLE_ROOT
      } else {
        properties[FLOWCHART_MIND_MAP_ROLE_KEY] = FLOWCHART_MIND_MAP_ROLE_BRANCH
      }
      const side = sides[nodeId]
      if (typeof side === 'string' && side.length > 0) {
        properties[FLOWCHART_MIND_MAP_SIDE_KEY] = side
      }
      nodes.push({
        id: nodeId,
        title: title.length === 0 ? '双击编辑' : title,
        description: description,
        color: typeof extNode?.['color'] === 'string' ? `${extNode['color']}` : '#FFF8E1',
        shape: FlowchartMermaidCodec.shapeFromWire(extNode?.['shape']),
        position: createFlowchartPosition(
          typeof pos['x'] === 'number' ? pos['x'] as number : 0,
          typeof pos['y'] === 'number' ? pos['y'] as number : 0
        ),
        width: typeof extNode?.['width'] === 'number' ? extNode['width'] as number : 120,
        height: typeof extNode?.['height'] === 'number' ? extNode['height'] as number : 72,
        rotation: typeof extNode?.['rotation'] === 'number' ? extNode['rotation'] as number : 0,
        properties: properties
      })
      if (parentId !== undefined) {
        let extEdge: Record<string, Object> | undefined = undefined
        let extEdgeId = ''
        for (const key of Object.keys(extEdges)) {
          const map = extEdges[key] as Record<string, Object>
          if (map['source'] === parentId && map['target'] === nodeId) {
            extEdge = map
            extEdgeId = key
            break
          }
        }
        edges.push({
          id: extEdge !== undefined && extEdgeId.length > 0 ? extEdgeId : `mm_edge_${parentId}_${nodeId}`,
          source: parentId,
          target: nodeId,
          label: typeof extEdge?.['label'] === 'string' ? `${extEdge['label']}` : '',
          directed: true,
          lineType: FlowchartMermaidCodec.lineTypeFromWire(extEdge?.['lineType']),
          sourceAnchor: FlowchartMermaidCodec.anchorFromWire(extEdge?.['sourceAnchor']),
          targetAnchor: FlowchartMermaidCodec.anchorFromWire(extEdge?.['targetAnchor']),
          properties: FlowchartMermaidCodec.copyProperties(extEdge?.['properties'])
        })
      }
      stack.push(nodeId)
    }

    if (rootId.length > 0) {
      metadata[FLOWCHART_MIND_MAP_ROOT_ID_KEY] = rootId
    }

    return {
      version: 1,
      metadata: metadata,
      nodes: nodes,
      edges: edges
    }
  }

  private static extractGraphSearchText(mermaidBody: string): string {
    const parts: string[] = []
    for (const line of mermaidBody.split('\n')) {
      const regex = /\["([^"]*)"\]/g
      let match: RegExpExecArray | null = regex.exec(line)
      while (match !== null) {
        if (match[1] !== undefined) {
          const split = FlowchartMermaidCodec.splitNodeLabel(match[1])
          if (split.title.length > 0) {
            parts.push(split.title)
          }
          if (split.description.length > 0) {
            parts.push(split.description)
          }
        }
        match = regex.exec(line)
      }
    }
    return parts.join('\n')
  }

  private static extractMindmapSearchText(mermaidBody: string): string {
    const parts: string[] = []
    for (const line of mermaidBody.split('\n')) {
      let trimmed = line.trim()
      if (trimmed.length === 0 || trimmed.toLowerCase() === 'mindmap') {
        continue
      }
      if (trimmed.startsWith('((') && trimmed.endsWith('))')) {
        trimmed = trimmed.substring(2, trimmed.length - 2).trim()
      }
      if (trimmed.length > 0) {
        parts.push(trimmed)
      }
    }
    return parts.join('\n')
  }

  private static nodeById(graph: FlowchartGraphModel, id: string): FlowchartNodeModel | undefined {
    for (const node of graph.nodes) {
      if (node.id === id) {
        return node
      }
    }
    return undefined
  }

  private static copyProperties(raw: Object | undefined): Record<string, Object> {
    if (raw === undefined || typeof raw !== 'object') {
      return emptyFlowchartProperties()
    }
    return cloneFlowchartRecord(raw as Record<string, Object>)
  }

  private static shapeFromWire(raw: Object | undefined): FlowchartShapeType {
    if (typeof raw !== 'string' || raw.length === 0) {
      return 'roundedRect'
    }
    return raw as FlowchartShapeType
  }

  private static lineTypeFromWire(raw: Object | undefined): FlowchartLineType {
    if (typeof raw !== 'string' || raw.length === 0) {
      return 'solid'
    }
    return raw as FlowchartLineType
  }

  private static anchorFromWire(raw: Object | undefined): FlowchartAnchor {
    if (typeof raw !== 'string' || raw.length === 0) {
      return 'bottom'
    }
    return raw as FlowchartAnchor
  }
}
