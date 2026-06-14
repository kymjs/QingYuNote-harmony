import fs from '@ohos.file.fs'
import { Logger } from './Logger'
import { YoudaoNoteContentConverter } from './YoudaoNoteContentConverter'
import { YoudaoMcpToolResult } from '../../services/YoudaoMcpClient'
import { AppContextHolder } from '../../services/AppContextHolder'

const LOG_TAG = 'YoudaoImportExport'
const CHUNK_SIZE = 800
const DEBUG_DIR_NAME = 'youdao-import-debug'

export interface YoudaoContentAnalysis {
  length: number
  trimmedLength: number
  looksStructured: boolean
  startsWithJson: boolean
  startsWithHtml: boolean
  startsWithGzipB64: boolean
  hasJsonTableBlock: boolean
  hasJsonImageBlock: boolean
  hasJsonTodoBlock: boolean
  hasHtmlTable: boolean
  hasHtmlImg: boolean
  hasHtmlCheckbox: boolean
  hasMarkdownTable: boolean
  hasMarkdownImage: boolean
  hasMarkdownCheckbox: boolean
  preview200: string
}

/** 有道云 MCP 导出内容调试日志（完整纯文本 + 落盘）。 */
export class YoudaoImportExportLogger {
  static logMcpAttempt(
    fileId: string,
    noteTitle: string,
    attemptLabel: string,
    result: YoudaoMcpToolResult,
    parsedContent: string,
    rawFormat: string,
    isRaw: boolean
  ): void {
    const analysis = YoudaoImportExportLogger.analyzeContent(parsedContent)
    const payloadSummary = YoudaoImportExportLogger.mcpPayloadSummary(result)
    const mcpRawText = result.asText() ?? ''
    const header = YoudaoImportExportLogger.buildHeader(
      fileId,
      noteTitle,
      attemptLabel,
      rawFormat,
      isRaw,
      analysis,
      payloadSummary,
      parsedContent.length,
      mcpRawText.length
    )

    YoudaoImportExportLogger.logChunked('META', header)
    if (mcpRawText.length > 0) {
      YoudaoImportExportLogger.logChunked('MCP_asText', mcpRawText)
    } else {
      Logger.info(LOG_TAG, 'MCP_asText: (empty)')
    }
    YoudaoImportExportLogger.logChunked('PARSED_content', parsedContent)

    const fileBody = `${header}\n\n--- MCP asText() ---\n${mcpRawText}\n\n--- parsed content field ---\n${parsedContent}`
    YoudaoImportExportLogger.writeDebugFile(fileId, noteTitle, attemptLabel, fileBody)
  }

  static logConversion(
    fileId: string,
    noteTitle: string,
    rawContent: string,
    rawFormat: string,
    isRaw: boolean,
    convertedMarkdown: string
  ): void {
    const rawAnalysis = YoudaoImportExportLogger.analyzeContent(rawContent)
    const mdAnalysis = YoudaoImportExportLogger.analyzeContent(convertedMarkdown)
    const structured = YoudaoNoteContentConverter.tryConvert(rawContent)
    const header = [
      '=== Youdao Import Conversion ===',
      `fileId: ${fileId}`,
      `noteTitle: ${noteTitle}`,
      `rawFormat: ${rawFormat}`,
      `isRaw: ${isRaw}`,
      `rawAnalysis: ${JSON.stringify(rawAnalysis)}`,
      `markdownAnalysis: ${JSON.stringify(mdAnalysis)}`,
      `tryConvertHit: ${structured !== null && structured.length > 0}`,
      `tryConvertLength: ${structured?.length ?? 0}`,
      `convertedLength: ${convertedMarkdown.length}`
    ].join('\n')

    YoudaoImportExportLogger.logChunked('CONVERSION_META', header)
    YoudaoImportExportLogger.logChunked('SELECTED_RAW', rawContent)
    YoudaoImportExportLogger.logChunked('CONVERTED_MD', convertedMarkdown)

    const fileBody = `${header}\n\n--- selected raw export ---\n${rawContent}\n\n--- tryConvert output ---\n${structured ?? '(null)'}\n\n--- convertWithFallback output ---\n${convertedMarkdown}`
    YoudaoImportExportLogger.writeDebugFile(fileId, noteTitle, 'conversion', fileBody)
  }

  static analyzeContent(content: string): YoudaoContentAnalysis {
    const trimmed = content.trim()
    return {
      length: content.length,
      trimmedLength: trimmed.length,
      looksStructured: YoudaoNoteContentConverter.looksStructured(content),
      startsWithJson: trimmed.startsWith('{'),
      startsWithHtml: trimmed.startsWith('<'),
      startsWithGzipB64: trimmed.startsWith('H4sI'),
      hasJsonTableBlock: content.includes('"6":"t"') || content.includes('"6": "t"'),
      hasJsonImageBlock: content.includes('"6":"im"') || content.includes('"6": "im"'),
      hasJsonTodoBlock: content.includes('"6":"todo"') || content.includes('"6": "todo"'),
      hasHtmlTable: /<\s*table\b/i.test(content),
      hasHtmlImg: /<\s*img\b/i.test(content),
      hasHtmlCheckbox: /<\s*input\b[^>]*\btype\s*=\s*["']?checkbox/i.test(content),
      hasMarkdownTable: /^\s*\|.*\|\s*$/m.test(content),
      hasMarkdownImage: content.includes('!['),
      hasMarkdownCheckbox: /^\s*-\s*\[[ xX\-]\]/m.test(content),
      preview200: trimmed.length > 200 ? trimmed.slice(0, 200) : trimmed
    }
  }

  private static buildHeader(
    fileId: string,
    noteTitle: string,
    attemptLabel: string,
    rawFormat: string,
    isRaw: boolean,
    analysis: YoudaoContentAnalysis,
    payloadSummary: string,
    parsedLength: number,
    mcpRawTextLength: number
  ): string {
    return [
      '=== Youdao MCP Export Dump ===',
      `timestamp: ${new Date().toISOString()}`,
      `fileId: ${fileId}`,
      `noteTitle: ${noteTitle}`,
      `attempt: ${attemptLabel}`,
      `rawFormat: ${rawFormat}`,
      `isRaw: ${isRaw}`,
      `parsedContentLength: ${parsedLength}`,
      `mcpAsTextLength: ${mcpRawTextLength}`,
      `contentAnalysis: ${JSON.stringify(analysis)}`,
      `mcpPayloadSummary: ${payloadSummary}`
    ].join('\n')
  }

  private static mcpPayloadSummary(result: YoudaoMcpToolResult): string {
    const json = result.asJson()
    if (json !== null) {
      const keys = Object.keys(json).sort()
      const content = json['content']
      const contentLen = typeof content === 'string' ? content.length : 0
      return `type=Object keys=${keys.join(',')} title=${json['title']} isRaw=${json['isRaw']} rawFormat=${json['rawFormat']} contentFieldLen=${contentLen}`
    }
    const text = result.asText()
    return `type=null asTextLen=${text?.length ?? 0}`
  }

  private static logChunked(section: string, text: string): void {
    if (text.length === 0) {
      Logger.info(LOG_TAG, `[${section}] (empty)`)
      return
    }
    const total = Math.ceil(text.length / CHUNK_SIZE)
    for (let i = 0; i < total; i++) {
      const start = i * CHUNK_SIZE
      const end = Math.min(start + CHUNK_SIZE, text.length)
      Logger.info(LOG_TAG, `[${section}][${i}/${total}] ${text.slice(start, end)}`)
    }
  }

  private static writeDebugFile(fileId: string, noteTitle: string, attemptLabel: string, body: string): void {
    try {
      const ctx = AppContextHolder.tryGetContext()
      if (ctx === undefined) {
        Logger.warn(LOG_TAG, 'writeDebugFile: context unavailable')
        return
      }
      const baseDir = `${ctx.cacheDir}/${DEBUG_DIR_NAME}`
      try {
        if (!fs.accessSync(baseDir)) {
          fs.mkdirSync(baseDir, true)
        }
      } catch (_) {
        fs.mkdirSync(baseDir, true)
      }
      const fileName = `${YoudaoImportExportLogger.safeFileToken(noteTitle)}_${YoudaoImportExportLogger.safeFileToken(fileId)}_${YoudaoImportExportLogger.safeFileToken(attemptLabel)}.txt`
      const filePath = `${baseDir}/${fileName}`
      const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      try {
        fs.writeSync(file.fd, body)
      } finally {
        fs.closeSync(file)
      }
      Logger.info(LOG_TAG, `完整导出已写入: ${filePath} (${body.length} chars)`)
    } catch (error) {
      Logger.warn(LOG_TAG, `写入调试文件失败: ${JSON.stringify(error)}`)
    }
  }

  private static safeFileToken(raw: string): string {
    const trimmed = raw.trim()
    if (trimmed.length === 0) {
      return 'untitled'
    }
    const safe = trimmed.replace(/[\\/:*?"<>|\s]+/g, '_').replace(/_+/g, '_')
    return safe.length > 48 ? safe.slice(0, 48) : safe
  }
}
