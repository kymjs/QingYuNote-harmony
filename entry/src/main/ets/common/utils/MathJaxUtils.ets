/** MathJax 预览 HTML 与 Markdown 分段（与 Flutter `mathjax_utils.dart` 对齐）。 */
export interface MarkdownPreviewSegment {
  isMath: boolean
  display: boolean
  content: string
}

export class MathJaxUtils {
  /** 与 loadData baseUrl 一致；优先使用应用内 rawfile，离线可用。 */
  static readonly MATHJAX_BASE: string = 'resource://rawfile/mathjax/'
  private static readonly MATHJAX_SCRIPT: string = 'tex-mml-chtml.js'
  private static readonly MATHJAX_FALLBACK: string =
    'https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js'

  static splitMarkdownSegments(content: string): MarkdownPreviewSegment[] {
    if (content.length === 0) {
      return [{ isMath: false, display: false, content: '' }]
    }
    const segments: MarkdownPreviewSegment[] = []
    let buffer = ''
    let index = 0
    let inCodeFence = false

    const flushMarkdown = (): void => {
      if (buffer.length === 0) {
        return
      }
      segments.push({ isMath: false, display: false, content: buffer })
      buffer = ''
    }

    while (index < content.length) {
      if (content.startsWith('```', index)) {
        inCodeFence = !inCodeFence
        buffer += '```'
        index += 3
        continue
      }
      if (inCodeFence) {
        buffer += content.charAt(index)
        index++
        continue
      }

      if (!MathJaxUtils.isEscaped(content, index) && content.startsWith('\\[', index)) {
        const close = MathJaxUtils.indexOfUnescaped(content, '\\]', index + 2)
        if (close !== -1) {
          flushMarkdown()
          segments.push({
            isMath: true,
            display: true,
            content: content.slice(index + 2, close).trim()
          })
          index = close + 2
          continue
        }
      }

      if (!MathJaxUtils.isEscaped(content, index) && content.startsWith('\\(', index)) {
        const close = MathJaxUtils.indexOfUnescaped(content, '\\)', index + 2)
        if (close !== -1) {
          flushMarkdown()
          segments.push({
            isMath: true,
            display: false,
            content: content.slice(index + 2, close).trim()
          })
          index = close + 2
          continue
        }
      }

      if (!MathJaxUtils.isEscaped(content, index) && content.startsWith('$$', index)) {
        const close = content.indexOf('$$', index + 2)
        if (close !== -1) {
          flushMarkdown()
          segments.push({
            isMath: true,
            display: true,
            content: content.slice(index + 2, close).trim()
          })
          index = close + 2
          continue
        }
      }

      if (!MathJaxUtils.isEscaped(content, index) &&
        content.charAt(index) === '$' &&
        (index + 1 >= content.length || content.charAt(index + 1) !== '$')) {
        const close = MathJaxUtils.findClosingInlineDollar(content, index + 1)
        if (close !== -1) {
          flushMarkdown()
          segments.push({
            isMath: true,
            display: false,
            content: content.slice(index + 1, close).trim()
          })
          index = close + 1
          continue
        }
      }

      buffer += content.charAt(index)
      index++
    }

    flushMarkdown()
    if (segments.length === 0) {
      return [{ isMath: false, display: false, content: '' }]
    }
    return segments
  }

  static buildPreviewHtml(latex: string, display: boolean, textColor: string, backgroundColor: string): string {
    const body = display ? `\\[${latex}\\]` : `\\(${latex}\\)`
    const escapedBody = MathJaxUtils.escapeHtml(body)
    const align = display ? 'center' : 'left'
    return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
<script>
window.MathJax = {
  tex: { inlineMath: [['\\\\(','\\\\)']], displayMath: [['\\\\[','\\\\]']], processEscapes: true },
  startup: {
    pageReady: () => MathJax.startup.defaultPageReady().then(() => {
      const h = document.documentElement.scrollHeight;
      if (window.HeightChannel) { HeightChannel.postMessage(String(h)); }
    })
  }
};
</script>
<script async src="${MathJaxUtils.MATHJAX_SCRIPT}" onerror="this.onerror=null;this.src='${MathJaxUtils.MATHJAX_FALLBACK}'"></script>
<style>
  html, body { margin: 0; padding: 0; background: ${backgroundColor}; overflow: hidden; }
  body { color: ${textColor}; font-size: 16px; line-height: 1.4; padding: 2px 0; }
  #math { text-align: ${align}; }
</style>
</head>
<body><div id="math">${escapedBody}</div></body>
</html>`
  }

  private static isEscaped(content: string, index: number): boolean {
    return index > 0 && content.charAt(index - 1) === '\\'
  }

  private static indexOfUnescaped(content: string, token: string, from: number): number {
    let i = from
    while (i < content.length) {
      const found = content.indexOf(token, i)
      if (found === -1) {
        return -1
      }
      if (!MathJaxUtils.isEscaped(content, found)) {
        return found
      }
      i = found + token.length
    }
    return -1
  }

  private static findClosingInlineDollar(content: string, from: number): number {
    for (let i = from; i < content.length; i++) {
      if (content.charAt(i) === '$' && !MathJaxUtils.isEscaped(content, i)) {
        return i
      }
      if (content.charAt(i) === '\n') {
        return -1
      }
    }
    return -1
  }

  private static escapeHtml(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
  }
}
