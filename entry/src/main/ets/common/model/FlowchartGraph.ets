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

export type FlowchartAnchor = 'top' | 'right' | 'bottom' | 'left'

export interface FlowchartAnchorHit {
  nodeId: string
  anchor: FlowchartAnchor
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
  return titles.length > 0 ? titles.join(' · ') : '流程图'
}

export function createFlowchartPosition(x: number, y: number): FlowchartNodePosition {
  const position: FlowchartNodePosition = { x: x, y: y }
  return position
}

export function emptyFlowchartProperties(): Record<string, Object> {
  const properties: Record<string, Object> = {}
  return properties
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
