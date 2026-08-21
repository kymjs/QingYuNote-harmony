import type { EditorInsertResult } from './EditorMarkdownInsert'

/** Mermaid 代码围栏模板（与 Flutter `mermaid_templates.dart` 对齐）。 */
export class MermaidTemplates {
  static readonly DEFAULT_KIND: string = 'flowchart'

  static readonly KINDS: string[] = [
    'flowchart',
    'sequence',
    'class',
    'state',
    'er',
    'gantt'
  ]

  static labelFor(kind: string): string {
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
    if (kind === 'er') {
      return 'ER 图'
    }
    if (kind === 'gantt') {
      return '甘特图'
    }
    return kind
  }

  static skeleton(kind: string): string {
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
    return 'flowchart TD\n    A[Start] --> B{Decision}\n    B -->|Yes| C[OK]\n    B -->|No| D[Retry]'
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
