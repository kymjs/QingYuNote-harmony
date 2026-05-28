/** combineBlocksForKatex 所需的最小 block 字段。 */
export interface MarkdownBlockLike {
  type: string
  content: string
  items?: MarkdownInlineLike[][]
  tableHeaders?: MarkdownInlineLike[][]
  tableRows?: MarkdownInlineLike[][][]
}

export interface MarkdownInlineLike {
  type: string
  content: string
}

/** KaTeX 本地预览 HTML（rawfile/katex，不依赖 MathJax / 外网 CDN）。 */
export class KatexUtils {
  /** loadData 的 baseUrl，需与 rawfile/katex 下资源路径一致。 */
  static readonly KATEX_BASE: string = 'resource://rawfile/katex/'

  /** 将含 $...$ / $$...$$ / \\(...\\) 的原文转为可渲染 HTML。 */
  static buildPreviewHtml(source: string, textColor: string, backgroundColor: string): string {
    const body = KatexUtils.escapeHtml(source)
    const safeColor = textColor.length > 0 ? textColor : '#1D1D1F'
    const safeBg = backgroundColor.length > 0 ? backgroundColor : 'transparent'
    return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
<link rel="stylesheet" type="text/css" href="${KatexUtils.KATEX_BASE}katex.min.css">
<script src="${KatexUtils.KATEX_BASE}katex.min.js"></script>
<script src="${KatexUtils.KATEX_BASE}auto-render.min.js"></script>
<style>
  html, body {
    margin: 0;
    padding: 6px 4px;
    background: ${safeBg};
    color: ${safeColor};
    font-size: 16px;
    line-height: 1.65;
    overflow-x: auto;
  }
  #content { word-wrap: break-word; white-space: pre-wrap; }
  .katex-display { margin: 0.5em 0; overflow-x: auto; }
</style>
</head>
<body>
<div id="content">${body}</div>
<script>
(function () {
  function report(msg) {
    try { HeightChannel.postMessage(String(msg)); } catch (e) {}
    try { console.log('[FormulaPreview] ' + msg); } catch (e) {}
  }
  try {
    if (typeof katex === 'undefined') {
      report('error:katex-undefined');
    } else if (typeof renderMathInElement !== 'function') {
      report('error:renderMathInElement-undefined');
    } else {
      renderMathInElement(document.getElementById('content'), {
        delimiters: [
          { left: '$$', right: '$$', display: true },
          { left: '$', right: '$', display: false },
          { left: '\\\\(', right: '\\\\)', display: false },
          { left: '\\\\[', right: '\\\\]', display: true }
        ],
        throwOnError: false,
        strict: false,
        trust: true,
        errorColor: '#cc0000'
      });
      report('ok:' + document.documentElement.scrollHeight);
    }
  } catch (e) {
    report('error:' + (e && e.message ? e.message : String(e)));
  }
})();
</script>
</body>
</html>`
  }

  /** 块级公式：content 为 $$ 内部 LaTeX。 */
  static wrapDisplaySource(content: string): string {
    const trimmed = content.trim()
    if (trimmed.startsWith('$$') && trimmed.endsWith('$$')) {
      return trimmed
    }
    return `$$\n${trimmed}\n$$`
  }

  /** 将预览 blocks 合并为一段 KaTeX 可渲染的 Markdown 文本。 */
  static combineBlocksForKatex(blocks: MarkdownBlockLike[]): string {
    const parts: string[] = []
    for (const block of blocks) {
      if (block.type === 'math_display') {
        parts.push(KatexUtils.wrapDisplaySource(block.content))
        continue
      }
      if (block.type === 'image' || block.type === 'divider') {
        continue
      }
      if (block.type === 'heading1') {
        parts.push(`# ${block.content}`)
        continue
      }
      if (block.type === 'heading2') {
        parts.push(`## ${block.content}`)
        continue
      }
      if (block.type === 'heading3') {
        parts.push(`### ${block.content}`)
        continue
      }
      if (block.type === 'code') {
        parts.push('```\n' + block.content + '\n```')
        continue
      }
      if (block.type === 'quote') {
        parts.push(block.content.split('\n').map((line: string) => `> ${line}`).join('\n'))
        continue
      }
      if (block.type === 'unordered_list' || block.type === 'ordered_list') {
        const items = block.items ?? []
        const lines: string[] = []
        for (let i = 0; i < items.length; i++) {
          const prefix = block.type === 'ordered_list' ? `${i + 1}. ` : '- '
          lines.push(prefix + KatexUtils.inlineSource(items[i]))
        }
        if (lines.length > 0) {
          parts.push(lines.join('\n'))
        }
        continue
      }
      if (block.type === 'table') {
        const headers = block.tableHeaders ?? []
        const rows = block.tableRows ?? []
        const tableLines: string[] = []
        if (headers.length > 0) {
          tableLines.push(`| ${headers.map((cell: MarkdownInlineLike[]) => KatexUtils.inlineSource(cell)).join(' | ')} |`)
          tableLines.push(`| ${headers.map((_cell: MarkdownInlineLike[]) => '---').join(' | ')} |`)
        }
        for (const row of rows) {
          tableLines.push(`| ${row.map((cell: MarkdownInlineLike[]) => KatexUtils.inlineSource(cell)).join(' | ')} |`)
        }
        if (tableLines.length > 0) {
          parts.push(tableLines.join('\n'))
        }
        continue
      }
      if (block.content.trim().length > 0) {
        parts.push(block.content)
      }
    }
    return parts.join('\n\n')
  }

  static escapeHtml(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
  }

  private static inlineSource(inlines: MarkdownInlineLike[]): string {
    let buf = ''
    for (const inline of inlines) {
      if (inline.type === 'math_inline') {
        buf += `$${inline.content}$`
      } else {
        buf += inline.content
      }
    }
    return buf
  }
}
