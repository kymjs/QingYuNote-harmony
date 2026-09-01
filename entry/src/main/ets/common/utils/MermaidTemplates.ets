import type { EditorInsertResult } from './EditorMarkdownInsert'
import type { FlowchartEdgeModel, FlowchartGraphModel, FlowchartNodeModel } from '../model/FlowchartGraph'

/** Mermaid 代码围栏模板（与 Flutter `mermaid_templates.dart` 对齐）。 */
export class MermaidTemplates {
  static readonly DEFAULT_KIND: string = 'flowchart'

  static readonly KINDS: string[] = [
    'pie',
    'flowchart',
    'sequence',
    'state',
    'gantt',
    'class',
    'journey',
    'er',
    'gitgraph',
    'mindmap',
    'timeline'
  ]

  /** 各样式对应的 Mermaid 声明关键字（源码首行）。 */
  static directiveKeyword(kind: string): string {
    if (kind === 'pie') {
      return 'pie'
    }
    if (kind === 'sequence') {
      return 'sequenceDiagram'
    }
    if (kind === 'state') {
      return 'stateDiagram-v2'
    }
    if (kind === 'gantt') {
      return 'gantt'
    }
    if (kind === 'class') {
      return 'classDiagram'
    }
    if (kind === 'journey') {
      return 'journey'
    }
    if (kind === 'er') {
      return 'erDiagram'
    }
    if (kind === 'gitgraph') {
      return 'gitGraph'
    }
    if (kind === 'mindmap') {
      return 'mindmap'
    }
    if (kind === 'timeline') {
      return 'timeline'
    }
    return 'flowchart'
  }

  static labelFor(kind: string): string {
    if (kind === 'pie') {
      return '饼形图'
    }
    if (kind === 'flowchart') {
      return '流程图'
    }
    if (kind === 'sequence') {
      return '时序图'
    }
    if (kind === 'class') {
      return '类图'
    }
    if (kind === 'state') {
      return '状态图'
    }
    if (kind === 'journey') {
      return '用户旅程图'
    }
    if (kind === 'er') {
      return 'ER 图'
    }
    if (kind === 'gantt') {
      return '甘特图'
    }
    if (kind === 'gitgraph') {
      return '分支图'
    }
    if (kind === 'mindmap') {
      return '思维导图'
    }
    if (kind === 'timeline') {
      return '时间线'
    }
    return kind
  }

  static skeleton(kind: string): string {
    if (kind === 'pie') {
      return 'pie title 示例\n    "A" : 45\n    "B" : 25\n    "C" : 30'
    }
    if (kind === 'journey') {
      return 'journey\n    title 用户旅程\n    section 发现\n      浏览首页: 5: 用户\n      搜索内容: 3: 用户\n    section 使用\n      创建笔记: 4: 用户\n      同步云端: 2: 用户'
    }
    if (kind === 'sequence') {
      return 'sequenceDiagram\n    participant A as Alice\n    participant B as Bob\n    A->>B: Hello\n    B-->>A: Hi'
    }
    if (kind === 'class') {
      return 'classDiagram\n    class Animal {\n        +String name\n        +eat()\n    }\n    class Dog {\n        +bark()\n    }\n    Animal <|-- Dog'
    }
    if (kind === 'state') {
      return 'stateDiagram-v2\n    [*] --> Idle\n    Idle --> Running: start\n    Running --> Idle: stop\n    Running --> [*]'
    }
    if (kind === 'er') {
      return 'erDiagram\n    USER ||--o{ ORDER : places\n    ORDER ||--|{ LINE-ITEM : contains'
    }
    if (kind === 'gantt') {
      return 'gantt\n    title Demo\n    dateFormat YYYY-MM-DD\n    section Plan\n    Task A :a1, 2026-01-01, 7d\n    Task B :after a1, 5d'
    }
    if (kind === 'gitgraph') {
      return 'gitGraph\n    commit id: "Init"\n    commit id: "Feature"\n    branch develop\n    checkout develop\n    commit id: "Work"\n    checkout main\n    merge develop'
    }
    if (kind === 'mindmap') {
      return 'mindmap\n  root((中心主题))\n    分支 A\n      细节 1\n    分支 B\n      细节 2'
    }
    if (kind === 'timeline') {
      return 'timeline\n    title 时间线\n    section 2024\n      启动 : 立项\n      设计 : 原型\n    section 2025\n      开发 : 迭代\n      发布 : 上线'
    }
    return 'flowchart TD\n    A[Start] --> B{Decision}\n    B -->|Yes| C[OK]\n    B -->|No| D[Retry]'
  }

  /** 用当前画布真实节点/连线生成对应样式的 Mermaid 正文（非假数据骨架）。 */
  static fromGraph(kind: string, graph: FlowchartGraphModel, title?: string): string {
    const nodes: FlowchartNodeModel[] = []
    for (const n of graph.nodes) {
      if (`${n.shape}` === 'line') {
        continue
      }
      nodes.push(n)
    }
    if (nodes.length === 0) {
      return MermaidTemplates.skeleton(kind)
    }
    if (kind === 'pie') {
      return MermaidTemplates.fromGraphPie(nodes, title)
    }
    if (kind === 'sequence') {
      return MermaidTemplates.fromGraphSequence(nodes, graph.edges)
    }
    if (kind === 'state') {
      return MermaidTemplates.fromGraphState(nodes, graph.edges)
    }
    if (kind === 'gantt') {
      return MermaidTemplates.fromGraphGantt(nodes, title)
    }
    if (kind === 'class') {
      return MermaidTemplates.fromGraphClass(nodes, graph.edges)
    }
    if (kind === 'journey') {
      return MermaidTemplates.fromGraphJourney(nodes, graph, title)
    }
    if (kind === 'er') {
      return MermaidTemplates.fromGraphEr(nodes, graph.edges)
    }
    if (kind === 'gitgraph') {
      return MermaidTemplates.fromGraphGit(nodes, graph)
    }
    if (kind === 'mindmap') {
      return MermaidTemplates.fromGraphMindmap(nodes, graph.edges)
    }
    if (kind === 'timeline') {
      return MermaidTemplates.fromGraphTimeline(nodes, title)
    }
    return ''
  }

  /** 与 fromGraph 一致的稳定 Mermaid 元素 id，供预览交互反向匹配节点。 */
  static mermaidSafeId(raw: string, index: number): string {
    const trimmed = raw.trim()
    let isNodeN = trimmed.length > 4
    if (isNodeN) {
      const lower = trimmed.toLowerCase()
      if (lower.startsWith('node')) {
        const numStr = trimmed.substring(4)
        for (let i = 0; i < numStr.length; i++) {
          const ch = numStr.charAt(i)
          if (ch < '0' || ch > '9') {
            isNodeN = false
            break
          }
        }
        if (numStr.length === 0) {
          isNodeN = false
        }
      } else {
        isNodeN = false
      }
    }
    if (isNodeN) {
      return trimmed.toLowerCase()
    }
    let cleaned = ''
    for (let i = 0; i < trimmed.length; i++) {
      const ch = trimmed.charAt(i)
      if ((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch === '_') {
        cleaned += ch
      }
    }
    if (cleaned.length === 0) {
      return `n${index}`
    }
    if (cleaned.charAt(0) >= '0' && cleaned.charAt(0) <= '9') {
      return `n${cleaned}`
    }
    return cleaned.length > 12 ? cleaned.substring(0, 12) : cleaned
  }

  /** 源码节点名原文（未 sanitize），供编辑弹窗回显。 */
  static rawMermaidName(node: FlowchartNodeModel): string {
    return `${node.properties['mermaidName'] ?? ''}`.trim()
  }

  /** 源码节点名：优先 properties.mermaidName。 */
  static nodeMermaidName(node: FlowchartNodeModel, index: number): string {
    const raw = MermaidTemplates.rawMermaidName(node)
    if (raw.length > 0) {
      return MermaidTemplates.mermaidSafeId(raw, index)
    }
    return MermaidTemplates.mermaidSafeId(node.id, index)
  }

  private static safeId(raw: string, index: number): string {
    return MermaidTemplates.mermaidSafeId(raw, index)
  }

  private static escape(raw: string): string {
    return raw.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, ' ')
  }

  private static nodeLabel(node: FlowchartNodeModel): string {
    const t = node.title.trim()
    return t.length > 0 ? t : '未命名'
  }

  private static fromGraphPie(nodes: FlowchartNodeModel[], title?: string): string {
    let out = 'pie'
    const t = (title ?? '').trim()
    if (t.length > 0) {
      out += ` title ${MermaidTemplates.escape(t)}`
    }
    out += '\n'
    const weight = Math.max(1, Math.floor(100 / nodes.length))
    let remain = 100
    for (let i = 0; i < nodes.length; i++) {
      const v = i === nodes.length - 1 ? remain : weight
      remain -= v
      out += `    "${MermaidTemplates.escape(MermaidTemplates.nodeLabel(nodes[i]))}" : ${v}\n`
    }
    return out.trimEnd()
  }

  private static fromGraphSequence(nodes: FlowchartNodeModel[], edges: FlowchartEdgeModel[]): string {
    let out = 'sequenceDiagram\n'
    const idMap: Record<string, string> = {}
    for (let i = 0; i < nodes.length; i++) {
      const id = MermaidTemplates.safeId(nodes[i].id, i)
      idMap[nodes[i].id] = id
      out += `    participant ${id} as ${MermaidTemplates.escape(MermaidTemplates.nodeLabel(nodes[i]))}\n`
    }
    for (const edge of edges) {
      const a = idMap[edge.source]
      const b = idMap[edge.target]
      if (a === undefined || b === undefined) {
        continue
      }
      const label = edge.label.trim().length === 0 ? '消息' : MermaidTemplates.escape(edge.label.trim())
      out += `    ${a}->>${b}: ${label}\n`
    }
    return out.trimEnd()
  }

  private static fromGraphState(nodes: FlowchartNodeModel[], edges: FlowchartEdgeModel[]): string {
    let out = 'stateDiagram-v2\n'
    const idMap: Record<string, string> = {}
    for (let i = 0; i < nodes.length; i++) {
      const id = MermaidTemplates.safeId(nodes[i].id, i)
      idMap[nodes[i].id] = id
      out += `    ${id} : ${MermaidTemplates.escape(MermaidTemplates.nodeLabel(nodes[i]))}\n`
    }
    if (edges.length === 0 && nodes.length > 0) {
      out += `    [*] --> ${idMap[nodes[0].id]}\n`
    }
    for (const edge of edges) {
      const a = idMap[edge.source]
      const b = idMap[edge.target]
      if (a === undefined || b === undefined) {
        continue
      }
      const label = edge.label.trim()
      if (label.length === 0) {
        out += `    ${a} --> ${b}\n`
      } else {
        out += `    ${a} --> ${b} : ${MermaidTemplates.escape(label)}\n`
      }
    }
    return out.trimEnd()
  }

  private static fromGraphGantt(nodes: FlowchartNodeModel[], title?: string): string {
    const t = (title ?? '').trim()
    let out = 'gantt\n'
    out += `    title ${t.length === 0 ? '计划' : MermaidTemplates.escape(t)}\n`
    out += '    dateFormat YYYY-MM-DD\n'
    out += '    section Tasks\n'
    for (let i = 0; i < nodes.length; i++) {
      const day = (i + 1).toString().padStart(2, '0')
      out += `    ${MermaidTemplates.escape(MermaidTemplates.nodeLabel(nodes[i]))} :t${i}, 2026-01-${day}, 3d\n`
    }
    return out.trimEnd()
  }

  private static fromGraphClass(nodes: FlowchartNodeModel[], edges: FlowchartEdgeModel[]): string {
    let out = 'classDiagram\n'
    const idMap: Record<string, string> = {}
    const used: Record<string, boolean> = {}
    for (let i = 0; i < nodes.length; i++) {
      let id = MermaidTemplates.nodeMermaidName(nodes[i], i)
      if (used[id] === true) {
        let n = 2
        while (used[`${id}_${n}`] === true) {
          n++
        }
        id = `${id}_${n}`
      }
      used[id] = true
      idMap[nodes[i].id] = id
      const raw = MermaidTemplates.rawMermaidName(nodes[i])
      if (raw.length > 0 && raw !== id) {
        out += `    class ${id}["${MermaidTemplates.escape(raw)}"] {\n`
      } else {
        out += `    class ${id} {\n`
      }
      out += `        ${MermaidTemplates.escape(MermaidTemplates.nodeLabel(nodes[i]))}\n`
      out += '    }\n'
    }
    for (const edge of edges) {
      const a = idMap[edge.source]
      const b = idMap[edge.target]
      if (a === undefined || b === undefined) {
        continue
      }
      const label = edge.label.trim()
      if (label.length === 0) {
        out += `    ${a} --> ${b}\n`
      } else {
        out += `    ${a} --> ${b} : ${MermaidTemplates.escape(label)}\n`
      }
    }
    for (let i = 0; i < nodes.length; i++) {
      const id = idMap[nodes[i].id]
      if (id === undefined) {
        continue
      }
      const color = nodes[i].color.trim()
      if (color.length > 0) {
        out += `    style ${id} fill:${color}\n`
      }
    }
    return out.trimEnd()
  }

  private static fromGraphJourney(
    nodes: FlowchartNodeModel[],
    graph: FlowchartGraphModel,
    title?: string
  ): string {
    const t = (title ?? '').trim()
    let out = 'journey\n'
    out += `    title ${t.length === 0 ? '用户旅程' : MermaidTemplates.escape(t)}\n`
    const sectionRaw = `${graph.metadata['journeySection'] ?? ''}`.trim()
    const section = sectionRaw.length > 0 ? sectionRaw : '流程'
    out += `    section ${MermaidTemplates.escape(section)}\n`
    for (const node of nodes) {
      const actor = node.description.trim().length === 0 ? '用户' : node.description.trim()
      out += `      ${MermaidTemplates.escape(MermaidTemplates.nodeLabel(node))}: 5: ${MermaidTemplates.escape(actor)}\n`
    }
    return out.trimEnd()
  }

  private static fromGraphEr(nodes: FlowchartNodeModel[], edges: FlowchartEdgeModel[]): string {
    let out = 'erDiagram\n'
    const idMap: Record<string, string> = {}
    for (let i = 0; i < nodes.length; i++) {
      const id = MermaidTemplates.safeId(nodes[i].id, i).toUpperCase()
      idMap[nodes[i].id] = id
      out += `    ${id} {\n`
      out += `        string name "${MermaidTemplates.escape(MermaidTemplates.nodeLabel(nodes[i]))}"\n`
      out += '    }\n'
    }
    for (const edge of edges) {
      const a = idMap[edge.source]
      const b = idMap[edge.target]
      if (a === undefined || b === undefined) {
        continue
      }
      const label = edge.label.trim().length === 0 ? 'rel' : MermaidTemplates.escape(edge.label.trim())
      out += `    ${a} ||--o{ ${b} : ${label}\n`
    }
    return out.trimEnd()
  }

  private static fromGraphGit(nodes: FlowchartNodeModel[], graph: FlowchartGraphModel): string {
    const edges = graph.edges
    let out = 'gitGraph\n'
    const idMap: Record<string, string> = {}
    for (let i = 0; i < nodes.length; i++) {
      const id = MermaidTemplates.nodeMermaidName(nodes[i], i)
      idMap[nodes[i].id] = id
      const tagRaw = `${nodes[i].properties['gitTag'] ?? ''}`.trim()
      const tag = tagRaw.length > 0 ? tagRaw : MermaidTemplates.nodeLabel(nodes[i])
      out += `    commit id: "${id}" tag: "${MermaidTemplates.escape(tag)}"\n`
    }
    if (edges.length > 0 && nodes.length >= 2) {
      const mid = idMap[nodes[Math.floor(nodes.length / 2)].id]
      const branchRaw = `${graph.metadata['gitBranchName'] ?? ''}`.trim()
      const branch = branchRaw.length > 0 ? MermaidTemplates.mermaidSafeId(branchRaw, 0) : 'develop'
      if (mid !== undefined) {
        out += `    branch ${branch}\n`
        out += `    checkout ${branch}\n`
        out += `    commit id: "dev_${mid}" tag: "分支"\n`
        out += '    checkout main\n'
        out += `    merge ${branch}\n`
      }
    }
    return out.trimEnd()
  }

  private static fromGraphMindmap(nodes: FlowchartNodeModel[], edges: FlowchartEdgeModel[]): string {
    const childrenOf: Record<string, string[]> = {}
    const targets: Record<string, boolean> = {}
    for (const edge of edges) {
      if (childrenOf[edge.source] === undefined) {
        childrenOf[edge.source] = []
      }
      childrenOf[edge.source].push(edge.target)
      targets[edge.target] = true
    }
    let root = nodes[0]
    for (const n of nodes) {
      if (targets[n.id] !== true) {
        root = n
        break
      }
    }
    const labelById: Record<string, string> = {}
    for (const n of nodes) {
      labelById[n.id] = MermaidTemplates.escape(MermaidTemplates.nodeLabel(n))
    }
    let out = 'mindmap\n'
    const walk = (id: string, depth: number): void => {
      const indent = '  '.repeat(depth + 1)
      const label = labelById[id] ?? id
      if (depth === 0) {
        out += `${indent}((${label}))\n`
      } else {
        out += `${indent}${label}\n`
      }
      const kids = childrenOf[id]
      if (kids === undefined) {
        return
      }
      for (const child of kids) {
        if (labelById[child] !== undefined) {
          walk(child, depth + 1)
        }
      }
    }
    walk(root.id, 0)
    if (edges.length === 0) {
      for (let i = 1; i < nodes.length; i++) {
        out += `    ${MermaidTemplates.escape(MermaidTemplates.nodeLabel(nodes[i]))}\n`
      }
    }
    return out.trimEnd()
  }

  private static fromGraphTimeline(nodes: FlowchartNodeModel[], title?: string): string {
    const t = (title ?? '').trim()
    let out = 'timeline\n'
    out += `    title ${t.length === 0 ? '时间线' : MermaidTemplates.escape(t)}\n`
    out += '    section 节点\n'
    for (const node of nodes) {
      out += `      ${MermaidTemplates.escape(MermaidTemplates.nodeLabel(node))} : 事件\n`
    }
    return out.trimEnd()
  }

  static fencedBlock(kind: string): string {
    const body = MermaidTemplates.skeleton(kind)
    return `\n\`\`\`mermaid\n${body}\n\`\`\`\n`
  }

  static insertTemplate(text: string, caret: number, kind: string = MermaidTemplates.DEFAULT_KIND): EditorInsertResult {
    const safeCaret = Math.max(0, Math.min(caret, text.length))
    const block = MermaidTemplates.fencedBlock(kind)
    const newText = text.substring(0, safeCaret) + block + text.substring(safeCaret)
    const newCaret = safeCaret + '\n```mermaid\n'.length
    return { text: newText, caret: newCaret }
  }
}
