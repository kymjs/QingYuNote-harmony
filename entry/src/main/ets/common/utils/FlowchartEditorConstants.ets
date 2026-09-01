/** 流程图编辑器内置颜色（节点 / 连线）。 */
export const FLOWCHART_EDITOR_COLORS: string[] = [
  '#4CAF50',
  '#2196F3',
  '#FF9800',
  '#9C27B0',
  '#009688',
  '#607D8B',
  '#E53935',
  '#FFF8E1',
  '#E3F2FD',
  '#E8F5E9',
  '#F3E5F5',
  '#FFEBEE',
  '#FFF3E0',
  '#212121'
]

export const FLOWCHART_EDGE_COLOR_KEY = 'strokeColor'
export const FLOWCHART_MERMAID_TEMPLATE_KIND_KEY = 'mermaidTemplateKind'

export type FlowchartEditorChartKind =
  | 'pie'
  | 'flowchart'
  | 'sequence'
  | 'state'
  | 'gantt'
  | 'class'
  | 'journey'
  | 'gitgraph'
  | 'mindmap'
  | 'timeline'

export const FLOWCHART_EDITOR_CHART_KINDS: FlowchartEditorChartKind[] = [
  'flowchart',
  'state',
  'sequence',
  'class',
  'mindmap',
  'pie',
  'gitgraph',
  'journey',
  'timeline'
]

export function flowchartEditorChartLabel(kind: FlowchartEditorChartKind): string {
  switch (kind) {
    case 'pie':
      return '饼形图'
    case 'flowchart':
      return '流程图'
    case 'sequence':
      return '时序图'
    case 'state':
      return '知识图谱'
    case 'gantt':
      return '甘特图'
    case 'class':
      return '类图'
    case 'journey':
      return '用户旅程图'
    case 'gitgraph':
      return '分支图'
    case 'mindmap':
      return '思维导图'
    case 'timeline':
      return '时间线'
    default:
      return kind
  }
}

export function isCanvasEditableChartKind(kind: FlowchartEditorChartKind): boolean {
  return kind === 'flowchart' || kind === 'state' || kind === 'mindmap'
}

export function isMermaidPreviewOnlyChartKind(kind: FlowchartEditorChartKind): boolean {
  return !isCanvasEditableChartKind(kind)
}

/**
 * 从 Mermaid 正文首行声明推断样式面板类型。
 * 交互式思维导图笔记编码也是 mindmap；若当前不是样式「思维导图」则归为可交互流程图画布。
 */
export function chartKindFromMermaidBody(
  body: string,
  current?: FlowchartEditorChartKind
): FlowchartEditorChartKind | undefined {
  const lines = body.split('\n')
  let first = ''
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i].trim()
    if (t.length > 0) {
      first = t
      break
    }
  }
  const lower = first.toLowerCase()
  if (lower.startsWith('pie')) {
    return 'pie'
  }
  if (lower.startsWith('sequencediagram')) {
    return 'sequence'
  }
  if (lower.startsWith('statediagram')) {
    return 'state'
  }
  if (lower.startsWith('gantt')) {
    return 'gantt'
  }
  if (lower.startsWith('classdiagram')) {
    return 'class'
  }
  if (lower.startsWith('journey')) {
    return 'journey'
  }
  if (lower.startsWith('gitgraph')) {
    return 'gitgraph'
  }
  if (lower.startsWith('timeline')) {
    return 'timeline'
  }
  if (lower.startsWith('mindmap')) {
    if (current === 'mindmap') {
      return 'mindmap'
    }
    return 'flowchart'
  }
  if (lower.startsWith('flowchart') || lower.startsWith('graph')) {
    return 'flowchart'
  }
  return undefined
}

export type FlowchartAddNodeOption =
  | 'rectangle'
  | 'circle'
  | 'diamond'
  | 'sharpRect'
  | 'classBox'
  | 'mindmap'
  | 'pieSlice'
  | 'gitBranch'
  | 'gitCommit'
  | 'gitTag'

/** 流程图 / 状态图默认四项（兼容旧调用）。 */
export const FLOWCHART_ADD_NODE_OPTIONS: FlowchartAddNodeOption[] = [
  'rectangle',
  'circle',
  'diamond',
  'sharpRect'
]

/** 按当前图表样式过滤「添加节点」选项。 */
export function flowchartAddNodeOptionsFor(
  kind: FlowchartEditorChartKind
): FlowchartAddNodeOption[] {
  if (kind === 'flowchart' || kind === 'state' || kind === 'gantt') {
    return ['rectangle', 'circle', 'diamond', 'sharpRect']
  }
  if (kind === 'sequence' || kind === 'journey' || kind === 'timeline') {
    return ['sharpRect']
  }
  if (kind === 'class') {
    return ['classBox']
  }
  if (kind === 'mindmap') {
    return ['mindmap']
  }
  if (kind === 'pie') {
    return ['pieSlice']
  }
  if (kind === 'gitgraph') {
    return ['gitBranch', 'gitCommit', 'gitTag']
  }
  return ['rectangle', 'circle', 'diamond', 'sharpRect']
}

export function flowchartAddNodeLabel(option: FlowchartAddNodeOption): string {
  switch (option) {
    case 'rectangle':
      return '圆角矩形'
    case 'circle':
      return '圆形'
    case 'diamond':
      return '菱形'
    case 'sharpRect':
      return '矩形'
    case 'classBox':
      return '类'
    case 'mindmap':
      return '思维导图'
    case 'pieSlice':
      return '扇形'
    case 'gitBranch':
      return '分支'
    case 'gitCommit':
      return '事件'
    case 'gitTag':
      return '标签'
    default:
      return option
  }
}
