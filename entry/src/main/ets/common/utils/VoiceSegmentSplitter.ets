/** One timed transcript slice for voice-note detail playback. */
export interface VoiceTranscriptSegment {
  startMs: number
  text: string
}

/** Client-side approximate time slicing by paragraph/sentence + char weight. */
export class VoiceSegmentSplitter {
  static readonly minDurationMsForSlices: number = 10000
  static readonly targetSliceMs: number = 18000
  private static readonly sentenceSplit: RegExp = /(?<=[。！？.!?\n])/

  static split(text: string, durationMs: number): VoiceTranscriptSegment[] {
    const cleaned = text.replace(/\r\n/g, '\n').trim()
    if (cleaned.length === 0 || durationMs <= VoiceSegmentSplitter.minDurationMsForSlices) {
      return []
    }

    let parts = VoiceSegmentSplitter.splitParagraphs(cleaned)
    if (parts.length < 2) {
      parts = VoiceSegmentSplitter.splitSentences(cleaned)
    }
    if (parts.length < 2) {
      parts = VoiceSegmentSplitter.splitByCharBudget(cleaned, durationMs)
    }
    if (parts.length === 0) {
      return []
    }
    if (parts.length === 1) {
      return [{ startMs: 0, text: parts[0] }]
    }

    let totalChars = 0
    for (const part of parts) {
      totalChars += part.length
    }
    if (totalChars <= 0) {
      return []
    }

    const segments: VoiceTranscriptSegment[] = []
    let usedChars = 0
    for (const part of parts) {
      const startMs = Math.floor((usedChars / totalChars) * durationMs)
      segments.push({ startMs: startMs, text: part })
      usedChars += part.length
    }
    if (segments.length > 0) {
      segments[0] = { startMs: 0, text: segments[0].text }
    }
    return segments
  }

  static encodeJson(segments: VoiceTranscriptSegment[]): string {
    const arr: Array<Record<string, Object>> = []
    for (const segment of segments) {
      arr.push({ 'start_ms': segment.startMs, 'text': segment.text })
    }
    return JSON.stringify(arr)
  }

  static decodeJson(raw: string): VoiceTranscriptSegment[] {
    const trimmed = raw.trim()
    if (trimmed.length === 0) {
      return []
    }
    try {
      const decoded = JSON.parse(trimmed) as Object
      if (!Array.isArray(decoded)) {
        return []
      }
      const list: Object[] = decoded as Object[]
      const segments: VoiceTranscriptSegment[] = []
      for (let i = 0; i < list.length; i++) {
        const item: Object = list[i]
        if (typeof item !== 'object' || item === null) {
          continue
        }
        const segment = VoiceSegmentSplitter.fromJson(item as Record<string, Object>)
        if (segment.text.trim().length > 0) {
          segments.push(segment)
        }
      }
      return segments
    } catch (_) {
      return []
    }
  }

  private static fromJson(json: Record<string, Object>): VoiceTranscriptSegment {
    const startRaw = json['start_ms']
    let startMs = 0
    if (typeof startRaw === 'number') {
      startMs = Math.floor(startRaw)
    }
    return {
      startMs: startMs,
      text: `${json['text'] ?? ''}`
    }
  }

  private static splitParagraphs(text: string): string[] {
    return text
      .split(/\n\s*\n|\n/)
      .map((part: string) => part.trim())
      .filter((part: string) => part.length > 0)
  }

  private static splitSentences(text: string): string[] {
    return text
      .split(VoiceSegmentSplitter.sentenceSplit)
      .map((part: string) => part.trim())
      .filter((part: string) => part.length > 0)
  }

  private static splitByCharBudget(text: string, durationMs: number): string[] {
    const total = text.length
    if (total === 0) {
      return []
    }
    const sliceCount = Math.min(40, Math.max(2, Math.ceil(durationMs / VoiceSegmentSplitter.targetSliceMs)))
    const budget = Math.min(total, Math.max(1, Math.ceil(total / sliceCount)))
    const parts: string[] = []
    let cursor = 0
    while (cursor < total) {
      const end = Math.min(cursor + budget, total)
      parts.push(text.substring(cursor, end).trim())
      cursor = end
    }
    return parts.filter((part: string) => part.length > 0)
  }
}
