export const NOTE_TYPE_MARKDOWN = 1
export const NOTE_TYPE_FLOWCHART = 2
export const FLOWCHART_FILE_SUFFIX = '.qy'

export type FlowchartShapeType =
  | 'roundedRect'
  | 'pill'
  | 'diamond'
  | 'rectangle'
  | 'circle'
  | 'cylinder'
  | 'chevron'
  | 'home'
  | 'parallelogram'
  | 'trapezoid'
  | 'speechBubble'
  | 'rectSpeechBubble'
  | 'triangle'
  | 'equilateralTriangle'
  | 'star'
  | 'hexagon'
  | 'pentagon'
  | 'octagon'
  | 'arrowLeft'
  | 'arrowRight'
  | 'doubleArrow'
  | 'cloud'
  | 'braceLeft'
  | 'braceRight'
  | 'plus'
  | 'arc3Quarter'
  | 'pie'
  | 'cube'
  | 'line'

export type FlowchartLineType = 'solid' | 'dashed' | 'arrow' | 'doubleArrow'

export const FLOWCHART_LINE_NODE_SHAPE: FlowchartShapeType = 'line'

export const FLOWCHART_LINE_PROP_TYPE = 'lineType'
export const FLOWCHART_LINE_PROP_FROM_X = 'fromX'
export const FLOWCHART_LINE_PROP_FROM_Y = 'fromY'
export const FLOWCHART_LINE_PROP_TO_X = 'toX'
export const FLOWCHART_LINE_PROP_TO_Y = 'toY'

/** 布局后启用正交连线（仅 0°/90° 折线）的 metadata 键。 */
export const FLOWCHART_ORTHOGONAL_ROUTING_KEY = 'orthogonalRouting'

/** 节点连接数超过该值视为思维导图中心，保留直线连接。 */
export const FLOWCHART_MIND_MAP_DEGREE_THRESHOLD = 4

/** 思维导图（线性树）模式 metadata / 节点属性键。 */
export const FLOWCHART_LAYOUT_MODE_KEY = 'layoutMode'
export const FLOWCHART_LAYOUT_MODE_MIND_MAP_LINEAR = 'mindMapLinear'
export const FLOWCHART_MIND_MAP_ROOT_ID_KEY = 'mindMapRootId'
export const FLOWCHART_MIND_MAP_ROLE_KEY = 'mindMapRole'
export const FLOWCHART_MIND_MAP_ROLE_ROOT = 'root'
export const FLOWCHART_MIND_MAP_ROLE_BRANCH = 'branch'

export const FLOWCHART_MIND_MAP_ROOT_COLOR = '#5B8DEF'
export const FLOWCHART_MIND_MAP_LINE_COLOR = '#5B8DEF'
export const FLOWCHART_MIND_MAP_BRANCH_TEXT_COLOR = '#95A3B8'
export const FLOWCHART_MIND_MAP_ROOT_TEXT_COLOR = '#EAF1FF'
export const FLOWCHART_MIND_MAP_BUS_GAP = 28

export const FLOWCHART_MIND_MAP_DEFAULT_CHILD_COUNT = 3
export const FLOWCHART_MIND_MAP_SIDE_LEFT = 'left'
export const FLOWCHART_MIND_MAP_SIDE_RIGHT = 'right'
export const FLOWCHART_MIND_MAP_BLOCK_PROXY_ID = '__flowchartMindMapBlock__'

export type FlowchartAnchor = 'top' | 'right' | 'bottom' | 'left'

export interface FlowchartAnchorHit {
  nodeId: string
  anchor: FlowchartAnchor
}

export interface FlowchartMindMapButtonRect {
  x: number
  y: number
  w: number
  h: number
}

export interface FlowchartMindMapAddHit {
  parentId: string
  side: string
}

export interface FlowchartNodePosition {
  x: number
  y: number
}

export interface FlowchartEdgeLineEndpoints {
  from: FlowchartNodePosition
  to: FlowchartNodePosition
}

export interface FlowchartNodeModel {
  id: string
  title: string
  description: string
  color: string
  shape: FlowchartShapeType
  position: FlowchartNodePosition
  width: number
  height: number
  rotation: number
  properties: Record<string, Object>
}

export interface FlowchartEdgeModel {
  id: string
  source: string
  target: string
  label: string
  directed: boolean
  lineType: FlowchartLineType
  sourceAnchor: FlowchartAnchor
  targetAnchor: FlowchartAnchor
  properties: Record<string, Object>
}

export interface FlowchartGraphModel {
  version: number
  metadata: Record<string, Object>
  nodes: FlowchartNodeModel[]
  edges: FlowchartEdgeModel[]
}

export const FLOWCHART_SHAPE_TYPES: FlowchartShapeType[] = [
  'roundedRect', 'pill', 'diamond', 'rectangle', 'arrowRight'
]

export const FLOWCHART_LINE_TYPES: FlowchartLineType[] = [
  'solid'
]

export function flowchartSearchableText(graph: FlowchartGraphModel): string {
  const parts: string[] = []
  for (const node of graph.nodes) {
    const title = node.title.trim()
    const desc = node.description.trim()
    if (title.length > 0) {
      parts.push(title)
    }
    if (desc.length > 0) {
      parts.push(desc)
    }
  }
  return parts.join('\n')
}

export function flowchartSearchSummary(graph: FlowchartGraphModel): string {
  const titles = graph.nodes.map((n) => n.title.trim()).filter((t) => t.length > 0).slice(0, 3)
  return titles.length > 0 ? titles.join(' · ') : '编辑标题'
}

export function createFlowchartPosition(x: number, y: number): FlowchartNodePosition {
  const position: FlowchartNodePosition = { x: x, y: y }
  return position
}

export function emptyFlowchartProperties(): Record<string, Object> {
  const properties: Record<string, Object> = {}
  return properties
}

export function cloneFlowchartRecord(source: Record<string, Object>): Record<string, Object> {
  const target: Record<string, Object> = {}
  for (const key of Object.keys(source)) {
    target[key] = source[key]
  }
  return target
}

export function flowchartFirstMatchingNodeId(graph: FlowchartGraphModel, query: string): string {
  const q = query.trim().toLowerCase()
  if (q.length === 0) {
    return ''
  }
  for (const node of graph.nodes) {
    if (node.title.toLowerCase().includes(q) || node.description.toLowerCase().includes(q)) {
      return node.id
    }
  }
  return ''
}

export function createEmptyFlowchartGraph(): FlowchartGraphModel {
  const metadata: Record<string, Object> = {}
  metadata['createdAt'] = new Date().toISOString()
  const graph: FlowchartGraphModel = {
    version: 1,
    metadata: metadata,
    nodes: [],
    edges: []
  }
  return graph
}

export function cloneFlowchartGraph(graph: FlowchartGraphModel): FlowchartGraphModel {
  const metadata: Record<string, Object> = {}
  for (const key of Object.keys(graph.metadata)) {
    metadata[key] = graph.metadata[key]
  }
  const nodes: FlowchartNodeModel[] = []
  for (const node of graph.nodes) {
    const props: Record<string, Object> = {}
    for (const key of Object.keys(node.properties)) {
      props[key] = node.properties[key]
    }
    nodes.push({
      id: node.id,
      title: node.title,
      description: node.description,
      color: node.color,
      shape: node.shape,
      position: createFlowchartPosition(node.position.x, node.position.y),
      width: node.width,
      height: node.height,
      rotation: node.rotation,
      properties: props
    })
  }
  const edges: FlowchartEdgeModel[] = []
  for (const edge of graph.edges) {
    const props: Record<string, Object> = {}
    for (const key of Object.keys(edge.properties)) {
      props[key] = edge.properties[key]
    }
    edges.push({
      id: edge.id,
      source: edge.source,
      target: edge.target,
      label: edge.label,
      directed: edge.directed,
      lineType: edge.lineType,
      sourceAnchor: edge.sourceAnchor,
      targetAnchor: edge.targetAnchor,
      properties: props
    })
  }
  return {
    version: graph.version,
    metadata: metadata,
    nodes: nodes,
    edges: edges
  }
}

export const FLOWCHART_DEFAULT_TITLE = '编辑标题'

/** 旧版占位图唯一节点标题（Flutter 历史 `emptyGraph` 行为）。 */
export const FLOWCHART_LEGACY_STARTER_NODE_TITLE = '开始'

export function isDefaultFlowchartTitle(title: string): boolean {
  const trimmed = title.trim()
  return trimmed.length === 0 || trimmed === FLOWCHART_DEFAULT_TITLE
}

export function isPlaceholderFlowchartGraph(graph: FlowchartGraphModel): boolean {
  if (graph.nodes.length === 0) {
    return true
  }
  if (graph.nodes.length === 1 && graph.edges.length === 0) {
    const node = graph.nodes[0]
    if (node.title.trim() === FLOWCHART_LEGACY_STARTER_NODE_TITLE) {
      return true
    }
  }
  return false
}

export function shouldShowFlowchartInHomeList(title: string, graph: FlowchartGraphModel): boolean {
  if (!isDefaultFlowchartTitle(title)) {
    return true
  }
  return !isPlaceholderFlowchartGraph(graph)
}
