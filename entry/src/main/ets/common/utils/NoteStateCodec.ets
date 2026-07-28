import type { Note, NoteFilePayload, NoteStateBlock } from '../model/Note'
import { EXTRACT_STATUS_VALUES, ExtractStatus, VOICE_TRANSCRIBE_STATUS_VALUES, VoiceTranscribeStatus } from '../model/Note'
import { MarkdownUtils } from './MarkdownUtils'

const NOTE_STATE_START = '<!-- NOTE_STATE'
const NOTE_STATE_REGEX = /(?:\r?\n)?<!-- NOTE_STATE\r?\n([\s\S]*?)\r?\n-->\s*$/
const IMAGE_REF_REGEX = /!\[[^\]]*\]\((qingyu-note-image\/[^)]+)\)/g

export class NoteStateCodec {
  /** 笔记 NOTE_STATE 隐藏字段 `source`，标识鸿蒙客户端平台。 */
  static readonly NOTE_SOURCE: string = 'harmony'

  static parseNoteFile(raw: string, fallbackId: string = '', fallbackTimestamp: number = Date.now()): NoteFilePayload {
    const normalizedRaw = raw.replace(/\r/g, '')
    const match = normalizedRaw.match(NOTE_STATE_REGEX)
    const visibleContent = NoteStateCodec.stripStateBlock(normalizedRaw)
    const fallbackTitle = MarkdownUtils.extractTitle(visibleContent)
    if (!match) {
      return {
        content: visibleContent,
        rawContent: normalizedRaw,
        state: NoteStateCodec.createDefaultState(fallbackId, fallbackTitle, fallbackTimestamp),
        hasStateBlock: false,
        filePath: '',
        modifiedAt: fallbackTimestamp
      }
    }

    const parsedState = NoteStateCodec.parseStateBody(match[1], fallbackId, fallbackTitle, fallbackTimestamp)
    return {
      content: visibleContent,
      rawContent: normalizedRaw,
      state: parsedState,
      hasStateBlock: true,
      filePath: '',
      modifiedAt: fallbackTimestamp
    }
  }

  static stripStateBlock(raw: string): string {
    return raw.replace(/\r/g, '').replace(NOTE_STATE_REGEX, '')
  }

  static serializeNoteFile(note: Note): string {
    const normalizedContent = note.content.replace(/\r/g, '')
    const stateBlock = NoteStateCodec.serializeStateBlock(NoteStateCodec.noteToStateBlock(note))
    if (normalizedContent.length === 0) {
      return stateBlock
    }
    const separator = normalizedContent.endsWith('\n') ? '\n' : '\n\n'
    return `${normalizedContent}${separator}${stateBlock}`
  }

  static noteToStateBlock(note: Note): NoteStateBlock {
    return {
      id: note.id,
      title: note.title,
      tags: [...note.tags],
      parentId: note.parentId,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      isConflict: note.isConflict,
      latitude: note.latitude,
      longitude: note.longitude,
      altitude: note.altitude,
      author: note.author,
      sourceUrl: note.sourceUrl,
      isTodo: note.isTodo,
      todoDue: note.todoDue,
      todoCompleted: note.todoCompleted,
      source: note.source,
      order: note.order,
      userData: note.userData,
      rsa: note.rsa,
      imageRefs: [...note.imageRefs],
      audioId: note.audioId ?? '',
      deletedTime: note.deletedTime,
      type_: note.type_,
      extractStatus: note.extractStatus ?? 'none',
      extractJobId: note.extractJobId ?? '',
      extractError: note.extractError ?? '',
      extractedAt: note.extractedAt ?? 0,
      extractProgress: note.extractProgress ?? 0,
      voiceSummary: note.voiceSummary ?? '',
      voiceSegmentsJson: note.voiceSegmentsJson ?? '',
      voiceTranscribeStatus: note.voiceTranscribeStatus ?? 'none'
    }
  }

  static serializeStateBlock(state: NoteStateBlock): string {
    const lines: string[] = [
      `${NOTE_STATE_START}`,
      `id: ${state.id}`,
      `title: ${state.title}`,
      `tags_json: ${NoteStateCodec.serializeTags(state.tags)}`,
      `parent_id: ${state.parentId}`,
      `created_time: ${NoteStateCodec.formatTimestamp(state.createdAt)}`,
      `updated_time: ${NoteStateCodec.formatTimestamp(state.updatedAt)}`,
      `is_conflict: ${state.isConflict}`,
      `latitude: ${NoteStateCodec.formatDecimal(state.latitude, 8)}`,
      `longitude: ${NoteStateCodec.formatDecimal(state.longitude, 8)}`,
      `altitude: ${NoteStateCodec.formatDecimal(state.altitude, 4)}`,
      `author: ${state.author}`,
      `source_url: ${state.sourceUrl}`,
      `is_todo: ${state.isTodo}`,
      `todo_due: ${state.todoDue}`,
      `todo_completed: ${state.todoCompleted}`,
      `source: ${state.source}`,
      `order: ${state.order}`
    ]
    if (state.userData.length > 0) {
      lines.push(`user_data: ${state.userData}`)
    }
    if (state.rsa !== 0) {
      lines.push('rsa: true')
    }
    if (state.audioId.length > 0) {
      lines.push(`audio_id: ${state.audioId}`)
    }
    lines.push(`image_refs: ${NoteStateCodec.serializeTags(state.imageRefs)}`)
    lines.push(`deleted_time: ${state.deletedTime}`)
    lines.push(`type_: ${state.type_}`)
    if (state.extractStatus && state.extractStatus !== 'none') {
      lines.push(`extract_status: ${state.extractStatus}`)
    }
    if (state.extractJobId && state.extractJobId.length > 0) {
      lines.push(`extract_job_id: ${state.extractJobId}`)
    }
    if (state.extractError && state.extractError.length > 0) {
      lines.push(`extract_error: ${state.extractError}`)
    }
    if (state.extractedAt && state.extractedAt > 0) {
      lines.push(`extracted_at: ${NoteStateCodec.formatTimestamp(state.extractedAt)}`)
    }
    if (state.extractProgress && state.extractProgress > 0 && state.extractProgress < 1) {
      lines.push(`extract_progress: ${state.extractProgress.toFixed(2)}`)
    }
    if (state.voiceSummary.length > 0) {
      lines.push(`voice_summary: ${NoteStateCodec.escapeSingleLine(state.voiceSummary)}`)
    }
    if (state.voiceSegmentsJson.length > 0) {
      lines.push(`voice_segments_json: ${state.voiceSegmentsJson}`)
    }
    if (state.voiceTranscribeStatus && state.voiceTranscribeStatus !== 'none') {
      lines.push(`voice_transcribe_status: ${state.voiceTranscribeStatus}`)
    }
    lines.push('-->')
    return lines.join('\n')
  }

  static parseRsaFlag(value: string): number {
    const normalized = value.trim().toLowerCase()
    if (normalized === 'true' || normalized === '1') {
      return 1
    }
    return 0
  }

  static serializeRemoteRecycleBinFile(noteId: string, lastModifiedMs: number): string {
    const state = NoteStateCodec.createDefaultState(noteId, '', lastModifiedMs)
    state.deletedTime = 1
    state.updatedAt = lastModifiedMs
    const note: Note = {
      id: state.id,
      title: state.title,
      content: '',
      tags: [...state.tags],
      summary: '',
      localModified: lastModifiedMs,
      remoteModified: 0,
      deleted: false,
      deletedAt: 0,
      lastOperationAt: lastModifiedMs,
      syncStatus: 'synced',
      filePath: '',
      createdAt: state.createdAt,
      updatedAt: lastModifiedMs,
      parentId: state.parentId,
      isConflict: state.isConflict,
      latitude: state.latitude,
      longitude: state.longitude,
      altitude: state.altitude,
      author: state.author,
      sourceUrl: state.sourceUrl,
      isTodo: state.isTodo,
      todoDue: state.todoDue,
      todoCompleted: state.todoCompleted,
      source: state.source,
      order: state.order,
      userData: state.userData,
      rsa: state.rsa,
      imageRefs: [],
      audioId: '',
      deletedTime: 1,
      type_: state.type_,
      extractStatus: state.extractStatus,
      extractJobId: state.extractJobId,
      extractError: state.extractError,
      extractedAt: state.extractedAt,
      extractProgress: state.extractProgress,
      voiceSummary: state.voiceSummary,
      voiceSegmentsJson: state.voiceSegmentsJson,
      voiceTranscribeStatus: state.voiceTranscribeStatus
    }
    return NoteStateCodec.serializeNoteFile(note)
  }

  static createDefaultState(noteId: string, title: string, now: number = Date.now(), type: number = 1): NoteStateBlock {
    return {
      id: noteId,
      title,
      tags: [],
      parentId: '',
      createdAt: now,
      updatedAt: now,
      isConflict: 0,
      latitude: 0,
      longitude: 0,
      altitude: 0,
      author: '',
      sourceUrl: '',
      isTodo: 0,
      todoDue: 0,
      todoCompleted: 0,
      source: NoteStateCodec.NOTE_SOURCE,
      order: 0,
      userData: '',
      rsa: 0,
      imageRefs: [],
      audioId: '',
      deletedTime: 0,
      type_: type,
      extractStatus: 'none',
      extractJobId: '',
      extractError: '',
      extractedAt: 0,
      extractProgress: 0,
      voiceSummary: '',
      voiceSegmentsJson: '',
      voiceTranscribeStatus: 'none'
    }
  }

  private static parseStateBody(body: string, fallbackId: string, fallbackTitle: string,
    fallbackTimestamp: number): NoteStateBlock {
    const parsed = NoteStateCodec.createDefaultState(fallbackId, fallbackTitle, fallbackTimestamp)
    const lines = body.split('\n')
    for (const line of lines) {
      const separatorIndex = line.indexOf(':')
      if (separatorIndex <= -1) {
        continue
      }
      const key = line.slice(0, separatorIndex).trim()
      const value = line.slice(separatorIndex + 1).trim()
      switch (key) {
        case 'id':
          parsed.id = value.length > 0 ? value : fallbackId
          break
        case 'title':
          parsed.title = value.length > 0 ? value : fallbackTitle
          break
        case 'tags_json':
          parsed.tags = NoteStateCodec.parseTags(value)
          break
        case 'parent_id':
          parsed.parentId = value
          break
        case 'created_time':
          parsed.createdAt = NoteStateCodec.parseTimestamp(value, parsed.createdAt)
          break
        case 'updated_time':
          parsed.updatedAt = NoteStateCodec.parseTimestamp(value, parsed.updatedAt)
          break
        case 'is_conflict':
          parsed.isConflict = NoteStateCodec.parseInteger(value, parsed.isConflict)
          break
        case 'latitude':
          parsed.latitude = NoteStateCodec.parseNumber(value, parsed.latitude)
          break
        case 'longitude':
          parsed.longitude = NoteStateCodec.parseNumber(value, parsed.longitude)
          break
        case 'altitude':
          parsed.altitude = NoteStateCodec.parseNumber(value, parsed.altitude)
          break
        case 'author':
          parsed.author = value
          break
        case 'source_url':
          parsed.sourceUrl = value
          break
        case 'is_todo':
          parsed.isTodo = NoteStateCodec.parseInteger(value, parsed.isTodo)
          break
        case 'todo_due':
          parsed.todoDue = NoteStateCodec.parseInteger(value, parsed.todoDue)
          break
        case 'todo_completed':
          parsed.todoCompleted = NoteStateCodec.parseInteger(value, parsed.todoCompleted)
          break
        case 'source':
          parsed.source = value
          break
        case 'order':
          parsed.order = NoteStateCodec.parseInteger(value, parsed.order)
          break
        case 'user_data':
          parsed.userData = value
          break
        case 'rsa':
          parsed.rsa = NoteStateCodec.parseRsaFlag(value)
          break
        case 'image_refs':
          parsed.imageRefs = NoteStateCodec.parseTags(value)
          break
        case 'audio_id':
          parsed.audioId = value
          break
        case 'deleted_time':
          parsed.deletedTime = NoteStateCodec.parseInteger(value, parsed.deletedTime)
          break
        case 'type_':
          parsed.type_ = NoteStateCodec.parseInteger(value, parsed.type_)
          break
        case 'extract_status': {
          const v = value as ExtractStatus
          parsed.extractStatus = EXTRACT_STATUS_VALUES.includes(v) ? v : 'none'
          break
        }
        case 'extract_job_id':
          parsed.extractJobId = value
          break
        case 'extract_error':
          parsed.extractError = value
          break
        case 'extracted_at':
          parsed.extractedAt = NoteStateCodec.parseTimestamp(value, parsed.extractedAt)
          break
        case 'extract_progress':
          parsed.extractProgress = NoteStateCodec.parseNumber(value, parsed.extractProgress)
          break
        case 'voice_summary':
          parsed.voiceSummary = NoteStateCodec.unescapeSingleLine(value)
          break
        case 'voice_segments_json':
          parsed.voiceSegmentsJson = value
          break
        case 'voice_transcribe_status': {
          const v = value as VoiceTranscribeStatus
          parsed.voiceTranscribeStatus = VOICE_TRANSCRIBE_STATUS_VALUES.includes(v) ? v : 'none'
          break
        }
        default:
          break
      }
    }

    if (parsed.id.length === 0) {
      parsed.id = fallbackId
    }
    if (parsed.title.length === 0) {
      parsed.title = fallbackTitle
    }
    return parsed
  }

  private static parseTimestamp(value: string, fallback: number): number {
    if (value.length === 0) {
      return fallback
    }
    if (/^\d+$/.test(value)) {
      return NoteStateCodec.parseInteger(value, fallback)
    }
    const parsed = Date.parse(value)
    return Number.isNaN(parsed) ? fallback : parsed
  }

  private static parseInteger(value: string, fallback: number): number {
    const parsed = Number.parseInt(value, 10)
    return Number.isNaN(parsed) ? fallback : parsed
  }

  private static parseNumber(value: string, fallback: number): number {
    const parsed = Number.parseFloat(value)
    return Number.isNaN(parsed) ? fallback : parsed
  }

  private static serializeTags(tags: string[]): string {
    return JSON.stringify(tags.map((tag: string) => tag.trim()).filter((tag: string) => tag.length > 0))
  }

  private static parseTags(raw: string): string[] {
    if (raw.length === 0) {
      return []
    }
    try {
      const parsed = JSON.parse(raw) as Array<string | number | boolean | null | Object>
      if (!Array.isArray(parsed)) {
        return []
      }
      const tags: string[] = []
      parsed.forEach((item: string | number | boolean | null | Object) => {
        if (typeof item !== 'string') {
          return
        }
        const tag = item.trim()
        if (tag.length > 0) {
          tags.push(tag)
        }
      })
      return tags
    } catch (_) {
      return []
    }
  }

  private static formatTimestamp(timestamp: number): string {
    if (timestamp <= 0) {
      return '0'
    }
    return new Date(timestamp).toISOString()
  }

  private static formatDecimal(value: number, fractionDigits: number): string {
    if (!Number.isFinite(value)) {
      return (0).toFixed(fractionDigits)
    }
    return value.toFixed(fractionDigits)
  }

  /** Encode multiline text into a single NOTE_STATE value line. */
  private static escapeSingleLine(value: string): string {
    return value
      .replace(/\\/g, '\\\\')
      .replace(/\r\n/g, '\\n')
      .replace(/\n/g, '\\n')
      .replace(/\r/g, '\\n')
  }

  private static unescapeSingleLine(value: string): string {
    let out = ''
    for (let i = 0; i < value.length; i++) {
      const ch = value.charAt(i)
      if (ch === '\\' && i + 1 < value.length) {
        const next = value.charAt(i + 1)
        if (next === 'n') {
          out += '\n'
          i++
          continue
        }
        if (next === '\\') {
          out += '\\'
          i++
          continue
        }
      }
      out += ch
    }
    return out
  }

  /** 除去 Markdown 图片与 NOTE_STATE 后是否仍有实质正文。 */
  static hasSubstantiveNoteText(content: string): boolean {
    let text = NoteStateCodec.stripStateBlock(content.replace(/\r/g, ''))
    text = text.replace(/!\[[^\]]*\]\([^)]+\)/g, '')
    return text.trim().length > 0
  }

  /** 按文档顺序提取 Markdown 图片语法片段（`![alt](url)`）。 */
  static extractImageMarkdownSegments(content: string): string[] {
    const visible = NoteStateCodec.stripStateBlock(content.replace(/\r/g, ''))
    const segments: string[] = []
    const regex = /!\[[^\]]*\]\([^)]+\)/g
    let match: RegExpExecArray | null = regex.exec(visible)
    while (match) {
      segments.push(match[0])
      match = regex.exec(visible)
    }
    return segments
  }

  /** AI 优化/生成正文后，将原笔记中的图片 Markdown 保留在末尾。 */
  static mergeOptimizedWithTrailingImages(originalContent: string, optimizedContent: string): string {
    const segments = NoteStateCodec.extractImageMarkdownSegments(originalContent)
    if (segments.length === 0) {
      return optimizedContent.trim()
    }
    let body = optimizedContent.trim()
    for (let i = 0; i < segments.length; i++) {
      body = body.split(segments[i]).join('')
    }
    body = body.replace(/!\[[^\]]*\]\([^)]+\)/g, '').trim()
    body = body.replace(/\n{3,}/g, '\n\n')
    const imageBlock = segments.join('\n\n')
    if (body.length === 0) {
      return imageBlock
    }
    return `${body}\n\n${imageBlock}`
  }

  static extractImageRefs(content: string): string[] {
    const refs = new Set<string>()
    let match: RegExpExecArray | null = IMAGE_REF_REGEX.exec(content)
    while (match) {
      if (match[1].length > 0) {
        refs.add(match[1])
      }
      match = IMAGE_REF_REGEX.exec(content)
    }
    IMAGE_REF_REGEX.lastIndex = 0
    return Array.from(refs).sort()
  }

  /** 彻底删除笔记时合并正文 Markdown 与 NOTE_STATE 中的图片引用。 */
  static collectImageRefsForDeletion(rawContent: string, fallbackNoteId: string = ''): string[] {
    const parsed = NoteStateCodec.parseNoteFile(rawContent, fallbackNoteId)
    const refs = new Set<string>(NoteStateCodec.extractImageRefs(parsed.content))
    for (const ref of parsed.state.imageRefs) {
      if (ref.length > 0) {
        refs.add(ref)
      }
    }
    return Array.from(refs).sort()
  }
}
