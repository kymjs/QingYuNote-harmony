/** 分享卡片主题。 */
export enum ShareCardTheme {
  CLASSIC = 'classic',
  QINGYU = 'qingyu',
  CALENDAR = 'calendar',
  JINSHU = 'jinshu'
}

/** 分享卡片色调。 */
export enum ShareCardTone {
  DARK = 'dark',
  LIGHT = 'light'
}

export interface ShareContentPadding {
  left: number
  right: number
  top: number
  bottom: number
}

export const DEFAULT_SHARE_CONTENT_PADDING: ShareContentPadding = {
  left: 18,
  right: 18,
  top: 18,
  bottom: 18
}

export const JINSHU_SHARE_CONTENT_PADDING: ShareContentPadding = {
  left: 28,
  right: 28,
  top: 36,
  bottom: 28
}

/** 锦书浅色：shell 不设统一 padding，各区块在 NoteShareExportCard 内单独控制边距。 */
export const JINSHU_LIGHT_SHARE_CONTENT_PADDING: ShareContentPadding = {
  left: 0,
  right: 0,
  top: 0,
  bottom: 0
}

export interface ShareThemePalette {
  background: string
  backgroundGradient?: [string, string]
  textPrimary: string
  textSecondary: string
  divider: string
  codeBackground: string
  accent?: string
  borderColor?: string
  showDoubleBorder: boolean
  showGridBackground: boolean
  showJinshuDecor: boolean
  jinshuBackground?: string
  contentPadding?: ShareContentPadding
}

export class ShareThemeColors {
  static parseTheme(raw: string): ShareCardTheme {
    switch (raw) {
      case ShareCardTheme.QINGYU:
        return ShareCardTheme.QINGYU
      case ShareCardTheme.CALENDAR:
        return ShareCardTheme.CALENDAR
      case ShareCardTheme.JINSHU:
        return ShareCardTheme.JINSHU
      case ShareCardTheme.CLASSIC:
      default:
        return ShareCardTheme.CLASSIC
    }
  }

  static parseTone(raw: string): ShareCardTone {
    return raw === ShareCardTone.LIGHT ? ShareCardTone.LIGHT : ShareCardTone.DARK
  }

  static label(theme: ShareCardTheme): string {
    switch (theme) {
      case ShareCardTheme.CLASSIC:
        return '经典'
      case ShareCardTheme.QINGYU:
        return '轻羽'
      case ShareCardTheme.CALENDAR:
        return '日历'
      case ShareCardTheme.JINSHU:
        return '锦书'
      default:
        return '经典'
    }
  }

  static toneLabel(tone: ShareCardTone): string {
    return tone === ShareCardTone.DARK ? '深色' : '浅色'
  }

  static resolve(theme: ShareCardTheme, tone: ShareCardTone): ShareThemePalette {
    if (theme === ShareCardTheme.CLASSIC) {
      return tone === ShareCardTone.DARK ? ShareThemeColors.CLASSIC_DARK : ShareThemeColors.CLASSIC_LIGHT
    }
    if (theme === ShareCardTheme.QINGYU) {
      return tone === ShareCardTone.DARK ? ShareThemeColors.QINGYU_DARK : ShareThemeColors.QINGYU_LIGHT
    }
    if (theme === ShareCardTheme.CALENDAR) {
      return tone === ShareCardTone.DARK ? ShareThemeColors.CALENDAR_DARK : ShareThemeColors.CALENDAR_LIGHT
    }
    return tone === ShareCardTone.DARK ? ShareThemeColors.JINSHU_DARK : ShareThemeColors.JINSHU_LIGHT
  }

  static readonly CLASSIC_DARK: ShareThemePalette = {
    background: '#FF1A1A1C',
    textPrimary: '#FFD4C39E',
    textSecondary: '#FFD4C39E',
    divider: '#4DD4C39E',
    codeBackground: '#FF252528',
    showDoubleBorder: false,
    showGridBackground: false,
    showJinshuDecor: false
  }

  static readonly CLASSIC_LIGHT: ShareThemePalette = {
    background: '#FFFAF6EE',
    backgroundGradient: ['#FFFAF6EE', '#FFD8E4CC'],
    textPrimary: '#FF2C2C2C',
    textSecondary: '#FF6B6B6B',
    divider: '#332C2C2C',
    codeBackground: '#FFE8E8E4',
    showDoubleBorder: false,
    showGridBackground: false,
    showJinshuDecor: false
  }

  static readonly QINGYU_DARK: ShareThemePalette = {
    background: '#FF2B2B2B',
    textPrimary: '#FFE8E4DC',
    textSecondary: '#FFAAAAAA',
    divider: '#33E8E4DC',
    codeBackground: '#FF333333',
    borderColor: '#55E8E4DC',
    showDoubleBorder: true,
    showGridBackground: false,
    showJinshuDecor: false
  }

  static readonly QINGYU_LIGHT: ShareThemePalette = {
    background: '#FFFAF6EE',
    backgroundGradient: ['#FFFAF6EE', '#FFD8E4CC'],
    textPrimary: '#FF333333',
    textSecondary: '#FF888888',
    divider: '#33AAAAAA',
    codeBackground: '#FFF0F0EC',
    borderColor: '#55AAAAAA',
    showDoubleBorder: true,
    showGridBackground: false,
    showJinshuDecor: false
  }

  static readonly CALENDAR_DARK: ShareThemePalette = {
    background: '#FF1A1A1A',
    textPrimary: '#FFE8DCC4',
    textSecondary: '#FFE8DCC4',
    divider: '#33E8DCC4',
    codeBackground: '#FF252525',
    showDoubleBorder: false,
    showGridBackground: false,
    showJinshuDecor: false
  }

  static readonly CALENDAR_LIGHT: ShareThemePalette = {
    background: '#FFFAF6EE',
    backgroundGradient: ['#FFFAF6EE', '#FFD8E4CC'],
    textPrimary: '#FF2C2C2C',
    textSecondary: '#FF555555',
    divider: '#332C2C2C',
    codeBackground: '#FFE8ECE0',
    showDoubleBorder: false,
    showGridBackground: false,
    showJinshuDecor: false
  }

  static readonly JINSHU_DARK: ShareThemePalette = {
    background: '#FF1A1A1B',
    jinshuBackground: '#FF1A1A1B',
    textPrimary: '#FFFFFFFF',
    textSecondary: '#FFFFFFFF',
    divider: '#33FFFFFF',
    codeBackground: '#FF2A2A2B',
    accent: '#FF39FF14',
    showDoubleBorder: false,
    showGridBackground: true,
    showJinshuDecor: true,
    contentPadding: JINSHU_SHARE_CONTENT_PADDING
  }

  static readonly JINSHU_LIGHT: ShareThemePalette = {
    background: '#FFFFF3F8',
    jinshuBackground: '#FFFFF3F8',
    textPrimary: '#FF34323D',
    textSecondary: '#FF757183',
    divider: '#3334323D',
    codeBackground: '#FFF5E8F1',
    accent: '#FF4FB6FF',
    showDoubleBorder: false,
    showGridBackground: false,
    showJinshuDecor: false,
    contentPadding: JINSHU_LIGHT_SHARE_CONTENT_PADDING
  }

  static readonly MONTH_ENGLISH: string[] =
    ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC']

  static weekdayChinese(date: Date): string {
    const names = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六']
    return names[date.getDay()]
  }

  static stripMarkdown(md: string): string {
    let s = md
    s = s.replace(/```[\s\S]*?```/g, '')
    s = s.replace(/`[^`]+`/g, '')
    s = s.replace(/!\[[^\]]*\]\([^)]*\)/g, '')
    s = s.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    s = s.replace(/^#{1,6}\s+/gm, '')
    s = s.replace(/^>\s?/gm, '')
    s = s.replace(/^[-*+]\s+/gm, '')
    s = s.replace(/^\d+\.\s+/gm, '')
    s = s.replace(/\*\*([^*]+)\*\*/g, '$1')
    s = s.replace(/\*([^*]+)\*/g, '$1')
    s = s.replace(/__([^_]+)__/g, '$1')
    s = s.replace(/_([^_]+)_/g, '$1')
    s = s.replace(/\n{2,}/g, '\n')
    return s.trim()
  }

  /** 锦书主题随机下划线片段（字符索引，基于 rune 长度近似）。 */
  static pickUnderlineRanges(text: string, seed: number, minCount: number = 2, maxCount: number = 4): Array<[number, number]> {
    if (text.length === 0) {
      return []
    }
    const candidates: Array<[number, number]> = []
    let i = 0
    while (i < text.length) {
      const ch = text.charAt(i)
      if (ShareThemeColors.isUnderlineChar(ch)) {
        const start = i
        while (i < text.length && ShareThemeColors.isUnderlineChar(text.charAt(i))) {
          i++
        }
        const len = i - start
        if (len >= 2 && len <= 6) {
          candidates.push([start, i])
        } else if (len > 6) {
          const windowCount = Math.min(3, Math.max(1, Math.floor(len / 4)))
          const maxSegLen = Math.min(5, len)
          for (let w = 0; w < windowCount; w++) {
            const segLen = Math.min(maxSegLen, len - w * 2)
            if (segLen >= 2) {
              candidates.push([start + w * 2, start + w * 2 + segLen])
            }
          }
        }
      } else {
        i++
      }
    }
    if (candidates.length === 0) {
      return []
    }
    const shuffled = ShareThemeColors.seededShuffle(candidates, seed)
    const count = Math.min(maxCount, Math.max(minCount, shuffled.length))
    return shuffled.slice(0, count).sort((a, b) => a[0] - b[0])
  }

  /** 锦书浅色正文分块字符上限，避免单块 ComponentSnapshot 高度超限（约 8614px 失败）。 */
  static readonly JINSHU_LIGHT_BODY_CHARS_PER_CHUNK: number = 150

  static jinshuLightBodyChunkCount(textLen: number): number {
    if (textLen <= 0) {
      return 1
    }
    return Math.max(1, Math.ceil(textLen / ShareThemeColors.JINSHU_LIGHT_BODY_CHARS_PER_CHUNK))
  }

  static jinshuLightBodyChunkId(index: number): string {
    return `jinshu_light_body_chunk_${index}`
  }

  /** 将锦书正文拆成多块，优先在换行处切分。 */
  static splitJinshuLightBodyChunks(text: string): string[] {
    const count = ShareThemeColors.jinshuLightBodyChunkCount(text.length)
    if (count <= 1) {
      return [text]
    }
    const chunks: string[] = []
    const targetSize = Math.ceil(text.length / count)
    let start = 0
    while (start < text.length) {
      let end = Math.min(start + targetSize, text.length)
      if (end < text.length) {
        const nl = text.lastIndexOf('\n', end)
        if (nl > start) {
          end = nl + 1
        }
      }
      chunks.push(text.substring(start, end))
      start = end
    }
    return chunks.filter((c: string) => c.length > 0)
  }

  private static isUnderlineChar(ch: string): boolean {
    if (ch.length === 0) {
      return false
    }
    const code = ch.charCodeAt(0)
    if (code >= 0x4E00 && code <= 0x9FFF) {
      return true
    }
    if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A)) {
      return true
    }
    if (code >= 0x30 && code <= 0x39) {
      return true
    }
    return false
  }

  private static seededShuffle<T>(arr: T[], seed: number): T[] {
    const out = [...arr]
    let s = seed
    for (let i = out.length - 1; i > 0; i--) {
      s = (s * 1103515245 + 12345) & 0x7fffffff
      const j = s % (i + 1)
      const tmp = out[i]
      out[i] = out[j]
      out[j] = tmp
    }
    return out
  }
}
