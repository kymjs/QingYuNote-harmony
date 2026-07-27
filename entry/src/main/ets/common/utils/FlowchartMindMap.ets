import type {
  FlowchartAnchor,
  FlowchartEdgeModel,
  FlowchartGraphModel,
  FlowchartNodeModel
} from '../model/FlowchartGraph'
import {
  cloneFlowchartRecord,
  FLOWCHART_LAYOUT_MODE_KEY,
  FLOWCHART_LAYOUT_MODE_MIND_MAP_LINEAR,
  FLOWCHART_MIND_MAP_BRANCH_TEXT_COLOR,
  FLOWCHART_MIND_MAP_DEFAULT_CHILD_COUNT,
  FLOWCHART_MIND_MAP_ROLE_BRANCH,
  FLOWCHART_MIND_MAP_ROLE_KEY,
  FLOWCHART_MIND_MAP_ROLE_ROOT,
  FLOWCHART_MIND_MAP_ROOT_COLOR,
  FLOWCHART_MIND_MAP_ROOT_ID_KEY,
  FLOWCHART_MIND_MAP_SIDE_LEFT,
  FLOWCHART_MIND_MAP_SIDE_RIGHT,
  FLOWCHART_ORTHOGONAL_ROUTING_KEY
} from '../model/FlowchartGraph'

export interface FlowchartLabelSize {
  w: number
  h: number
}

export interface FlowchartBranchLabelLayout {
  lines: string[]
  maxLines: number
  w: number
  h: number
}

export const FLOWCHART_MIND_MAP_BRANCH_FONT_SIZE = 14
// ArkUI 的 .lineHeight() 接收 vp 数值，不是 multiplier；该值需与 FontSize 14 配套
// （≈ fontSize × 1.43），否则多行 Text 的实际行高不足以容纳 CJK 字形，会叠在一起。
export const FLOWCHART_MIND_MAP_BRANCH_LINE_HEIGHT = 20
export const FLOWCHART_MIND_MAP_BRANCH_SELECTION_PAD_H = 8
export const FLOWCHART_MIND_MAP_BRANCH_SELECTION_PAD_V = 4

// 分支框每行最大字符数（与节流阈值保持一致）。
export const FLOWCHART_MIND_MAP_BRANCH_MAX_CHARS_PER_LINE = 8
// 分支框最小宽度对应的字符数。仅作为「单字/空标题」的视觉底线，避免 box 退化到几乎不可见；
// 不应再用它硬撑一整行 CJK，否则会让短标题的选框被过度撑大（视觉上文字只占一小块）。
// 该值要明显小于 [FLOWCHART_MIND_MAP_BRANCH_MAX_CHARS_PER_LINE]。
export const FLOWCHART_MIND_MAP_BRANCH_MIN_CHARS_PER_LINE = 1

// 半角字符相对 CJK 的字宽比，用于宽度估算。
export const FLOWCHART_MIND_MAP_BRANCH_LATIN_WIDTH_RATIO = 0.55
// 其他字符（emoji、控制符等）相对 CJK 的字宽比。
export const FLOWCHART_MIND_MAP_BRANCH_HALF_WIDTH_RATIO = 0.7
// CJK 字形相对 fontSize 的真实渲染倍率。HarmonyOS / Android 的 Noto Sans CJK 等系统
// 字体下，CJK glyph 实际渲染宽度 ≈ fontSize × 1.2–1.25（含 leading/字形 padding），
// 比简单的 `fontSize × 1.0` 估算明显宽。用 1.0 会让 box 内框被 padding 抠得太紧，
// 用 1.1 仍会在某些机型上让 8 个汉字末尾被 `…` 替换。1.25 让 branchW 留出 ~12 px 的
// 安全 buffer，确保选中态边框下文字尾部不被 ellipsize。
export const FLOWCHART_MIND_MAP_BRANCH_CJK_GLYPH_RATIO = 1.13
// 分支文本框最大渲染宽度（vp）。
export const FLOWCHART_MIND_MAP_BRANCH_MAX_LINE_WIDTH = 160

const FLOWCHART_MIND_MAP_PLACEHOLDER_TITLES: string[] = [
  '输入文本',  // legacy：历史数据兼容
  'Enter text',
  'テキストを入力',
  '輸入文本',
  '双击编辑'  // 当前默认占位文案
]

export class FlowchartMindMap {
  static isDefaultMindMapNodeTitle(title: string, localizedDefault?: string): boolean {
    const trimmed = title.trim()
    if (trimmed.length === 0) {
      return true
    }
    if (FLOWCHART_MIND_MAP_PLACEHOLDER_TITLES.includes(trimmed)) {
      return true
    }
    if (localizedDefault !== undefined && trimmed === localizedDefault.trim()) {
      return true
    }
    return false
  }

  static resolveMindMapNodeTitle(title: string, localizedDefault?: string): string {
    if (FlowchartMindMap.isDefaultMindMapNodeTitle(title, localizedDefault)) {
      return '双击编辑'
    }
    return title.trim()
  }

  static mindMapTitleForEdit(title: string, localizedDefault: string): string {
    const normalized = FlowchartMindMap.normalizeSavedMindMapTitle(title, localizedDefault)
    if (FlowchartMindMap.isDefaultMindMapNodeTitle(normalized, localizedDefault)) {
      return ''
    }
    return normalized
  }

  static normalizeSavedMindMapTitle(title: string, localizedDefault: string): string {
    let trimmed = title.trim()
    if (trimmed.length === 0) {
      // 用户在编辑框里什么都没填就保存，等同于「未编辑」，记为双击编辑占位。
      return '双击编辑'
    }
    if (FlowchartMindMap.isDefaultMindMapNodeTitle(trimmed, localizedDefault)) {
      // 用户填了其它本地化文案（`Enter text` 等历史占位），统一收敛到当前的「双击编辑」占位。
      return '双击编辑'
    }
    const prefixes = new Set<string>([localizedDefault.trim(), ...FLOWCHART_MIND_MAP_PLACEHOLDER_TITLES])
    for (const prefix of prefixes) {
      if (prefix.length === 0) {
        continue
      }
      if (trimmed.startsWith(prefix) && trimmed.length > prefix.length) {
        trimmed = trimmed.substring(prefix.length).trim()
        break
      }
    }
    return trimmed.length === 0 ? '双击编辑' : trimmed
  }

  static parentOf(graph: FlowchartGraphModel, nodeId: string): string {
    for (const edge of graph.edges) {
      if (edge.target === nodeId) {
        return edge.source
      }
    }
    return ''
  }

  static isMindMapMode(graph: FlowchartGraphModel): boolean {
    return graph.metadata[FLOWCHART_LAYOUT_MODE_KEY] === FLOWCHART_LAYOUT_MODE_MIND_MAP_LINEAR
  }

  static rootId(graph: FlowchartGraphModel): string {
    const raw = graph.metadata[FLOWCHART_MIND_MAP_ROOT_ID_KEY]
    return typeof raw === 'string' ? raw : ''
  }

  static roleOf(node: FlowchartNodeModel): string {
    const raw = node.properties[FLOWCHART_MIND_MAP_ROLE_KEY]
    return typeof raw === 'string' ? raw : ''
  }

  static isRoot(graph: FlowchartGraphModel, node: FlowchartNodeModel): boolean {
    if (!FlowchartMindMap.isMindMapMode(graph)) {
      return false
    }
    if (FlowchartMindMap.roleOf(node) === FLOWCHART_MIND_MAP_ROLE_ROOT) {
      return true
    }
    return node.id === FlowchartMindMap.rootId(graph)
  }

  static isTextOnlyBranch(graph: FlowchartGraphModel, node: FlowchartNodeModel): boolean {
    return FlowchartMindMap.isMindMapMode(graph) && FlowchartMindMap.isBranch(graph, node)
  }

  /** 沿父边向上找到该节点所属思维导图树根。 */
  static treeRootId(graph: FlowchartGraphModel, nodeId: string): string {
    let current = nodeId
    const seen: Record<string, boolean> = {}
    while (!seen[current]) {
      seen[current] = true
      const parent = FlowchartMindMap.parentOf(graph, current)
      if (parent.length === 0) {
        return current
      }
      current = parent
    }
    return ''
  }

  /** 是否属于思维导图树内节点（根或分支；支持画布上多套导图）。 */
  static isTreeNode(graph: FlowchartGraphModel, node: FlowchartNodeModel): boolean {
    if (!FlowchartMindMap.isMindMapMode(graph)) {
      return false
    }
    const role = FlowchartMindMap.roleOf(node)
    if (role === FLOWCHART_MIND_MAP_ROLE_ROOT || role === FLOWCHART_MIND_MAP_ROLE_BRANCH) {
      return true
    }
    const root = FlowchartMindMap.rootId(graph)
    if (root.length === 0) {
      return false
    }
    return FlowchartMindMap.collectSubtreeIds(graph, root).has(node.id)
  }

  /** 是否思维导图内部连线（两端均属同一棵导图树）。 */
  static isMindMapEdge(graph: FlowchartGraphModel, edge: FlowchartEdgeModel): boolean {
    if (!FlowchartMindMap.isMindMapMode(graph)) {
      return false
    }
    let source: FlowchartNodeModel | undefined = undefined
    let target: FlowchartNodeModel | undefined = undefined
    for (const node of graph.nodes) {
      if (node.id === edge.source) {
        source = node
      }
      if (node.id === edge.target) {
        target = node
      }
    }
    if (source === undefined || target === undefined ||
      !FlowchartMindMap.isTreeNode(graph, source) ||
      !FlowchartMindMap.isTreeNode(graph, target)) {
      return false
    }
    return FlowchartMindMap.treeRootId(graph, edge.source) ===
      FlowchartMindMap.treeRootId(graph, edge.target)
  }

  static canInitiateConnection(graph: FlowchartGraphModel, node: FlowchartNodeModel): boolean {
    if (!FlowchartMindMap.isMindMapMode(graph)) {
      return true
    }
    if (!FlowchartMindMap.isTreeNode(graph, node)) {
      return true
    }
    return FlowchartMindMap.isRoot(graph, node)
  }

  static shouldShowConnectionAnchors(graph: FlowchartGraphModel, node: FlowchartNodeModel): boolean {
    if (FlowchartMindMap.isMindMapMode(graph)) {
      return !FlowchartMindMap.isBranch(graph, node)
    }
    return true
  }

  static shouldShowResizeHandle(graph: FlowchartGraphModel, node: FlowchartNodeModel): boolean {
    if (!FlowchartMindMap.isMindMapMode(graph)) {
      return true
    }
    return !FlowchartMindMap.isBranch(graph, node)
  }

  static exitMode(graph: FlowchartGraphModel): FlowchartGraphModel {
    if (!FlowchartMindMap.isMindMapMode(graph)) {
      return graph
    }
    const metadata: Record<string, Object> = {}
    for (const key of Object.keys(graph.metadata)) {
      if (key === FLOWCHART_LAYOUT_MODE_KEY ||
        key === FLOWCHART_MIND_MAP_ROOT_ID_KEY ||
        key === FLOWCHART_ORTHOGONAL_ROUTING_KEY) {
        continue
      }
      metadata[key] = graph.metadata[key]
    }
    return {
      version: graph.version,
      metadata,
      nodes: [...graph.nodes],
      edges: [...graph.edges]
    }
  }

  static childrenOnSide(graph: FlowchartGraphModel, parentId: string, side: string): string[] {
    const result: string[] = []
    for (const edge of graph.edges) {
      if (edge.source !== parentId) {
        continue
      }
      const edgeSide = FlowchartMindMap.edgeSideFromAnchors(edge.sourceAnchor, edge.targetAnchor)
      if (edgeSide === side) {
        result.push(edge.target)
      }
    }
    result.sort()
    return result
  }

  static siblingCountOnSide(edges: FlowchartEdgeModel[], edge: FlowchartEdgeModel): number {
    const side = FlowchartMindMap.edgeSideFromAnchors(edge.sourceAnchor, edge.targetAnchor)
    if (side.length === 0) {
      return 0
    }
    let count = 0
    for (const e of edges) {
      if (e.source !== edge.source) {
        continue
      }
      if (FlowchartMindMap.edgeSideFromAnchors(e.sourceAnchor, e.targetAnchor) === side) {
        count++
      }
    }
    return count
  }

  static edgeSideFromAnchors(sourceAnchor: FlowchartAnchor, targetAnchor: FlowchartAnchor): string {
    if (sourceAnchor === 'right' && targetAnchor === 'left') {
      return FLOWCHART_MIND_MAP_SIDE_RIGHT
    }
    if (sourceAnchor === 'left' && targetAnchor === 'right') {
      return FLOWCHART_MIND_MAP_SIDE_LEFT
    }
    return ''
  }

  static expansionSide(graph: FlowchartGraphModel, nodeId: string): string {
    const node = graph.nodes.find((item) => item.id === nodeId)
    if (node === undefined || FlowchartMindMap.isRoot(graph, node) ||
      !FlowchartMindMap.isBranch(graph, node)) {
      return ''
    }
    for (const edge of graph.edges) {
      if (edge.target !== nodeId) {
        continue
      }
      if (edge.targetAnchor === 'left') {
        return FLOWCHART_MIND_MAP_SIDE_RIGHT
      }
      if (edge.targetAnchor === 'right') {
        return FLOWCHART_MIND_MAP_SIDE_LEFT
      }
    }
    return FLOWCHART_MIND_MAP_SIDE_RIGHT
  }

  static createDefaultTemplate(newId: () => string): FlowchartGraphModel {
    const rootId = newId()
    const childIds: string[] = []
    for (let i = 0; i < FLOWCHART_MIND_MAP_DEFAULT_CHILD_COUNT; i++) {
      childIds.push(newId())
    }
    const rootProperties: Record<string, Object> = {}
    rootProperties[FLOWCHART_MIND_MAP_ROLE_KEY] = FLOWCHART_MIND_MAP_ROLE_ROOT
    const root: FlowchartNodeModel = {
      id: rootId,
      title: '双击编辑',
      description: '',
      color: FLOWCHART_MIND_MAP_ROOT_COLOR,
      shape: 'roundedRect',
      position: { x: 0, y: 0 },
      width: 120,
      height: 72,
      rotation: 0,
      properties: rootProperties
    }
    const children = childIds.map((id): FlowchartNodeModel => {
      const properties: Record<string, Object> = {}
      properties[FLOWCHART_MIND_MAP_ROLE_KEY] = FLOWCHART_MIND_MAP_ROLE_BRANCH
      return {
        id,
        title: '双击编辑',
        description: '',
        color: '',
        shape: 'roundedRect',
        position: { x: 0, y: 0 },
        width: 40,
        height: 24,
        rotation: 0,
        properties
      }
    })
    const edges = childIds.map((childId): FlowchartEdgeModel => {
      return {
        id: newId(),
        source: rootId,
        target: childId,
        label: '',
        directed: false,
        lineType: 'solid',
        sourceAnchor: 'right',
        targetAnchor: 'left',
        properties: {}
      }
    })
    const metadata: Record<string, Object> = {}
    metadata[FLOWCHART_LAYOUT_MODE_KEY] = FLOWCHART_LAYOUT_MODE_MIND_MAP_LINEAR
    metadata[FLOWCHART_MIND_MAP_ROOT_ID_KEY] = rootId
    metadata[FLOWCHART_ORTHOGONAL_ROUTING_KEY] = true
    return {
      version: 1,
      metadata,
      nodes: [root, ...children],
      edges
    }
  }

  static addChildOnSide(
    graph: FlowchartGraphModel,
    parentId: string,
    side: string,
    child: FlowchartNodeModel,
    edgeId: string
  ): FlowchartGraphModel {
    const sourceAnchor: FlowchartAnchor = side === FLOWCHART_MIND_MAP_SIDE_LEFT ? 'left' : 'right'
    const targetAnchor: FlowchartAnchor = side === FLOWCHART_MIND_MAP_SIDE_LEFT ? 'right' : 'left'
    let result: FlowchartGraphModel = {
      version: graph.version,
      metadata: graph.metadata,
      nodes: [...graph.nodes, child],
      edges: [...graph.edges]
    }
    result = FlowchartMindMap.addChildEdge(result, parentId, child.id, edgeId, sourceAnchor, targetAnchor)
    return result
  }

  static childrenMap(graph: FlowchartGraphModel): Record<string, string[]> {
    const children: Record<string, string[]> = {}
    for (const edge of graph.edges) {
      if (children[edge.source] === undefined) {
        children[edge.source] = []
      }
      children[edge.source].push(edge.target)
    }
    for (const key of Object.keys(children)) {
      children[key].sort()
    }
    return children
  }

  static collectSubtreeIds(graph: FlowchartGraphModel, rootNodeId: string): Set<string> {
    const children = FlowchartMindMap.childrenMap(graph)
    const result = new Set<string>([rootNodeId])
    const stack: string[] = [rootNodeId]
    while (stack.length > 0) {
      const id = stack.pop() as string
      const kids = children[id] ?? []
      for (const child of kids) {
        if (!result.has(child)) {
          result.add(child)
          stack.push(child)
        }
      }
    }
    return result
  }

  static isBranch(graph: FlowchartGraphModel, node: FlowchartNodeModel): boolean {
    if (FlowchartMindMap.isRoot(graph, node)) {
      return false
    }
    if (!FlowchartMindMap.isMindMapMode(graph)) {
      return false
    }
    return FlowchartMindMap.roleOf(node) === FLOWCHART_MIND_MAP_ROLE_BRANCH ||
      FlowchartMindMap.parentOf(graph, node.id).length > 0
  }

  /**
   * 字形宽度单位：1 CJK = 1 unit；1 ASCII 字母数字 = 0.5 unit（即 1 CJK ≈ 2 ASCII）；
   * emoji / 全角符号 / 其他 = 0.7 unit。用于把「行容量 8」换成「单位容量 8」（width-aware 切行）。
   */
  static charUnitWeight(ch: string): number {
    if (ch.length === 0) {
      return 0
    }
    const code = ch.charCodeAt(0)
    if ((code >= 0x4E00 && code <= 0x9FFF) ||
      (code >= 0x3400 && code <= 0x4DBF) ||
      (code >= 0x20000 && code <= 0x2A6DF) ||
      (code >= 0x3000 && code <= 0x303F) ||
      (code >= 0xFF00 && code <= 0xFFEF) ||
      (code >= 0x2E80 && code <= 0x2EFF) ||
      (code >= 0xF900 && code <= 0xFAFF) ||
      (code >= 0x2F00 && code <= 0x2FDF)) {
      return 1.0
    }
    if ((code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A)) {
      return 0.5
    }
    return 0.7
  }

  /** 整段文字的总单位（weight）值。 */
  static textUnits(text: string): number {
    let units = 0
    for (let i = 0; i < text.length; i++) {
      units += FlowchartMindMap.charUnitWeight(text[i])
    }
    return units
  }

  /** 在不超过 [maxUnits] 单位的前提下，从 [text] 头取最多字符。 */
  static takeCharsByUnits(text: string, maxUnits: number): string {
    let units = 0
    let result = ''
    for (let i = 0; i < text.length; i++) {
      const w = FlowchartMindMap.charUnitWeight(text[i])
      if (units + w > maxUnits) {
        break
      }
      result += text[i]
      units += w
    }
    return result
  }

  /**
   * 把 [text] 切成 [lineCount] 行，每行宽度单位不超过 [maxUnitsPerLine]。
   * 实现要点：
   * 1. 字符宽度非均匀：CJK = 1 unit，ASCII = 0.5 unit，其它 = 0.7 unit；
   * 2. 行容量 = [maxUnitsPerLine]，逐字符贪心填入，超过容量就在下一行继续；
   * 3. 最后一行吃掉所有剩余字符（不再 wrap）。
   */
  static splitBranchLines(text: string, lineCount: number, maxUnitsPerLine: number): string[] {
    if (lineCount <= 1) {
      return [text]
    }
    if (text.length === 0) {
      return ['']
    }
    const totalUnits = FlowchartMindMap.textUnits(text)
    const idealUnitsPerLine = totalUnits / lineCount
    const lines: string[] = []
    let currentLine = ''
    let currentUnits = 0
    let lineIdx = 0
    for (let i = 0; i < text.length; i++) {
      const ch = text[i]
      const w = FlowchartMindMap.charUnitWeight(ch)
      const isLastLine = lineIdx === lineCount - 1
      currentLine += ch
      currentUnits += w
      if (!isLastLine && i < text.length - 1) {
        const wouldExceed = currentUnits > maxUnitsPerLine
        const reachedIdeal = currentUnits >= idealUnitsPerLine - 0.001
        if (wouldExceed || reachedIdeal) {
          lines.push(currentLine)
          currentLine = ''
          currentUnits = 0
          lineIdx++
        }
      }
    }
    if (currentLine.length > 0) {
      lines.push(currentLine)
    }
    while (lines.length < lineCount) {
      lines.push('')
    }
    return lines
  }

  /**
   * 估算一行文字的渲染宽度（vp）。
   * - CJK / 全角标点按 [FLOWCHART_MIND_MAP_BRANCH_FONT_SIZE] *
   *   [FLOWCHART_MIND_MAP_BRANCH_CJK_GLYPH_RATIO] 估算
   * - 半角字母数字按 [FLOWCHART_MIND_MAP_BRANCH_LATIN_WIDTH_RATIO] 倍字宽
   * - 其他（emoji、控制符等）按 [FLOWCHART_MIND_MAP_BRANCH_HALF_WIDTH_RATIO] 倍字宽
   */
  static estimateBranchLineWidth(line: string): number {
    let width = 0
    for (let i = 0; i < line.length; i++) {
      const code = line.charCodeAt(i)
      // CJK 统一表意 / 扩展 A-F / 全角标点 / 半角片假名 → fontSize
      const isCjk = (code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF) ||
        (code >= 0x20000 && code <= 0x3FFFD) ||
        (code >= 0x3000 && code <= 0x303F) ||
        (code >= 0xFF00 && code <= 0xFFEF) ||
        (code >= 0x2E80 && code <= 0x2EFF) ||
        (code >= 0xF900 && code <= 0xFAFF)
      // 半角字母数字
      const isAsciiAlphaNum = (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A)
      if (isCjk) {
        width += FLOWCHART_MIND_MAP_BRANCH_FONT_SIZE *
          FLOWCHART_MIND_MAP_BRANCH_CJK_GLYPH_RATIO
      } else if (isAsciiAlphaNum) {
        width += FLOWCHART_MIND_MAP_BRANCH_FONT_SIZE *
          FLOWCHART_MIND_MAP_BRANCH_LATIN_WIDTH_RATIO
      } else {
        width += FLOWCHART_MIND_MAP_BRANCH_FONT_SIZE *
          FLOWCHART_MIND_MAP_BRANCH_HALF_WIDTH_RATIO
      }
    }
    return width
  }

  static layoutBranchLabel(title: string): FlowchartBranchLabelLayout {
    const raw = FlowchartMindMap.resolveMindMapNodeTitle(title)
    // 用宽度单位（units）决定行数与是否截断：1 CJK = 1 unit，1 ASCII = 0.5 unit，
    // 这样 16 ASCII（= 8 units）和 8 CJK（= 8 units）都会被识别为 1 行。
    const units = FlowchartMindMap.textUnits(raw)
    const maxUnitsPerLine = FLOWCHART_MIND_MAP_BRANCH_MAX_CHARS_PER_LINE // 8 = 行容量（units）
    let text = raw
    let lineCount = 1
    if (units <= maxUnitsPerLine) {
      lineCount = 1
    } else if (units <= maxUnitsPerLine * 2) {
      lineCount = 2
    } else if (units <= maxUnitsPerLine * 3) {
      lineCount = 3
    } else {
      lineCount = 3
      // 超长：截断到 (maxUnitsPerLine × lineCount − 3) 单位 + "..." ≈ 24 单位
      // （「…」占 3 个 ASCII 字符 = 1.5 unit，留 buffer）。
      text = `${FlowchartMindMap.takeCharsByUnits(raw, maxUnitsPerLine * lineCount - 3)}...`
    }
    const lines = FlowchartMindMap.splitBranchLines(
      text,
      lineCount,
      maxUnitsPerLine
    )
    let maxW = 0
    for (const line of lines) {
      maxW = Math.max(maxW, FlowchartMindMap.estimateBranchLineWidth(line))
    }
    // 把单行估算宽度的上界钳制到「一整行 CJK 字符」宽（按真实字形倍率算），
    // 避免被极少数宽字符（emoji / 异常字形）撑得过大而破坏布局。
    const lineMaxWidth = FLOWCHART_MIND_MAP_BRANCH_FONT_SIZE *
      FLOWCHART_MIND_MAP_BRANCH_MAX_CHARS_PER_LINE *
      FLOWCHART_MIND_MAP_BRANCH_CJK_GLYPH_RATIO +
      FLOWCHART_MIND_MAP_BRANCH_SELECTION_PAD_H * 2
    const cappedLineWidth = Math.min(maxW, lineMaxWidth)
    const branchMinWidth = FLOWCHART_MIND_MAP_BRANCH_FONT_SIZE *
      FLOWCHART_MIND_MAP_BRANCH_MIN_CHARS_PER_LINE *
      FLOWCHART_MIND_MAP_BRANCH_CJK_GLYPH_RATIO +
      FLOWCHART_MIND_MAP_BRANCH_SELECTION_PAD_H * 2
    const lineBoxH = FLOWCHART_MIND_MAP_BRANCH_LINE_HEIGHT
    const textH = lineBoxH * lines.length
    return {
      lines,
      maxLines: lineCount,
      w: Math.max(branchMinWidth, cappedLineWidth + FLOWCHART_MIND_MAP_BRANCH_SELECTION_PAD_H * 2),
      h: Math.max(24, textH + FLOWCHART_MIND_MAP_BRANCH_SELECTION_PAD_V * 2 + 2)
    }
  }

  static measureBranchLabel(title: string): FlowchartLabelSize {
    const layout = FlowchartMindMap.layoutBranchLabel(title)
    return { w: layout.w, h: layout.h }
  }

  static effectiveBranchDisplaySize(
    graph: FlowchartGraphModel,
    node: FlowchartNodeModel
  ): FlowchartLabelSize {
    if (!FlowchartMindMap.isTextOnlyBranch(graph, node)) {
      return { w: node.width, h: node.height }
    }
    const layout = FlowchartMindMap.layoutBranchLabel(node.title)
    return {
      w: Math.max(node.width, layout.w),
      h: Math.max(node.height, layout.h)
    }
  }

  static measureRootLabel(title: string): FlowchartLabelSize {
    const display = title.trim().length > 0 ? title.trim() : '双击编辑'
    return {
      w: Math.max(96, display.length * 14 + 32),
      h: 48
    }
  }

  static normalizeMindMapNodeSizes(graph: FlowchartGraphModel, rootId: string): FlowchartGraphModel {
    const branchIds = FlowchartMindMap.collectSubtreeIds(graph, rootId)
    branchIds.delete(rootId)
    const nodes = graph.nodes.map((node: FlowchartNodeModel): FlowchartNodeModel => {
      if (node.id === rootId) {
        const size = FlowchartMindMap.measureRootLabel(node.title)
        const properties = cloneFlowchartRecord(node.properties)
        properties[FLOWCHART_MIND_MAP_ROLE_KEY] = FLOWCHART_MIND_MAP_ROLE_ROOT
        return {
          id: node.id,
          title: node.title,
          description: node.description,
          color: FLOWCHART_MIND_MAP_ROOT_COLOR,
          shape: 'roundedRect',
          position: node.position,
          width: size.w,
          height: size.h,
          rotation: node.rotation,
          properties
        }
      }
      if (branchIds.has(node.id)) {
        const size = FlowchartMindMap.measureBranchLabel(node.title)
        const properties = cloneFlowchartRecord(node.properties)
        properties[FLOWCHART_MIND_MAP_ROLE_KEY] = FLOWCHART_MIND_MAP_ROLE_BRANCH
        return {
          id: node.id,
          title: node.title,
          description: node.description,
          color: '',
          shape: 'roundedRect',
          position: node.position,
          width: size.w,
          height: size.h,
          rotation: node.rotation,
          properties
        }
      }
      return node
    })
    return {
      version: graph.version,
      metadata: graph.metadata,
      nodes,
      edges: [...graph.edges]
    }
  }

  static assignRoles(graph: FlowchartGraphModel, rootId: string): FlowchartGraphModel {
    const branchIds = FlowchartMindMap.collectSubtreeIds(graph, rootId)
    branchIds.delete(rootId)
    const nodes = graph.nodes.map((node: FlowchartNodeModel): FlowchartNodeModel => {
      if (node.id === rootId) {
        const properties = cloneFlowchartRecord(node.properties)
        properties[FLOWCHART_MIND_MAP_ROLE_KEY] = FLOWCHART_MIND_MAP_ROLE_ROOT
        return {
          id: node.id,
          title: node.title,
          description: node.description,
          color: node.color,
          shape: node.shape,
          position: node.position,
          width: node.width,
          height: node.height,
          rotation: node.rotation,
          properties
        }
      }
      if (branchIds.has(node.id)) {
        const properties = cloneFlowchartRecord(node.properties)
        properties[FLOWCHART_MIND_MAP_ROLE_KEY] = FLOWCHART_MIND_MAP_ROLE_BRANCH
        return {
          id: node.id,
          title: node.title,
          description: node.description,
          color: node.color,
          shape: node.shape,
          position: node.position,
          width: node.width,
          height: node.height,
          rotation: node.rotation,
          properties
        }
      }
      return node
    })
    const metadata = cloneFlowchartRecord(graph.metadata)
    metadata[FLOWCHART_LAYOUT_MODE_KEY] = FLOWCHART_LAYOUT_MODE_MIND_MAP_LINEAR
    metadata[FLOWCHART_MIND_MAP_ROOT_ID_KEY] = rootId
    return {
      version: graph.version,
      metadata,
      nodes,
      edges: [...graph.edges]
    }
  }

  static addChildEdge(
    graph: FlowchartGraphModel,
    parentId: string,
    childId: string,
    edgeId: string,
    sourceAnchor: FlowchartAnchor = 'right',
    targetAnchor: FlowchartAnchor = 'left'
  ): FlowchartGraphModel {
    const edges = graph.edges.filter((edge: FlowchartEdgeModel) => edge.target !== childId)
    const edge: FlowchartEdgeModel = {
      id: edgeId,
      source: parentId,
      target: childId,
      label: '',
      directed: false,
      lineType: 'solid',
      sourceAnchor,
      targetAnchor,
      properties: {}
    }
    return {
      version: graph.version,
      metadata: graph.metadata,
      nodes: [...graph.nodes],
      edges: [...edges, edge]
    }
  }

  static markBranch(node: FlowchartNodeModel): FlowchartNodeModel {
    const properties = cloneFlowchartRecord(node.properties)
    properties[FLOWCHART_MIND_MAP_ROLE_KEY] = FLOWCHART_MIND_MAP_ROLE_BRANCH
    return {
      id: node.id,
      title: node.title,
      description: node.description,
      color: node.color,
      shape: node.shape,
      position: node.position,
      width: node.width,
      height: node.height,
      rotation: node.rotation,
      properties
    }
  }

  static removeSubtree(graph: FlowchartGraphModel, nodeId: string): FlowchartGraphModel {
    const removeIds = FlowchartMindMap.collectSubtreeIds(graph, nodeId)
    const nodes = graph.nodes.filter((node: FlowchartNodeModel) => !removeIds.has(node.id))
    const edges = graph.edges.filter((edge: FlowchartEdgeModel) =>
      !removeIds.has(edge.source) && !removeIds.has(edge.target))
    const removingTrackedRoot = graph.metadata[FLOWCHART_MIND_MAP_ROOT_ID_KEY] === nodeId
    let nextRootId = ''
    if (nodes.length > 0 && removingTrackedRoot) {
      for (const node of nodes) {
        if (FlowchartMindMap.roleOf(node) === FLOWCHART_MIND_MAP_ROLE_ROOT) {
          nextRootId = node.id
          break
        }
      }
    }
    const shouldExitMindMap = nodes.length === 0 || (removingTrackedRoot && nextRootId.length === 0)
    const metadata: Record<string, Object> = {}
    for (const key of Object.keys(graph.metadata)) {
      if (shouldExitMindMap &&
        (key === FLOWCHART_MIND_MAP_ROOT_ID_KEY ||
          key === FLOWCHART_LAYOUT_MODE_KEY ||
          key === FLOWCHART_ORTHOGONAL_ROUTING_KEY)) {
        continue
      }
      metadata[key] = graph.metadata[key]
    }
    if (!shouldExitMindMap && removingTrackedRoot && nextRootId.length > 0) {
      metadata[FLOWCHART_MIND_MAP_ROOT_ID_KEY] = nextRootId
    }
    return {
      version: graph.version,
      metadata,
      nodes,
      edges
    }
  }
}
