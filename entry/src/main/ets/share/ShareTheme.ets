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
    background: '#FF7B7CFF',
    jinshuBackground: '#FF7B7CFF',
    textPrimary: '#FFFFFFFF',
    textSecondary: '#FFFFFFFF',
    divider: '#33FFFFFF',
    codeBackground: '#FF6A6BEE',
    accent: '#FFCCFF00',
    showDoubleBorder: false,
    showGridBackground: false,
    showJinshuDecor: false,
    contentPadding: JINSHU_SHARE_CONTENT_PADDING
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
