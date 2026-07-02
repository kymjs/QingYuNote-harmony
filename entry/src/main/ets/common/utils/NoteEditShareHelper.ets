import type { MarkdownBlock } from './MarkdownUtils'
import { ShareCardTheme, ShareCardTone } from '../../share/ShareTheme'

export function noteEditDelayMs(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

export function shareExportBodyHasImages(blocks: MarkdownBlock[]): boolean {
  for (const block of blocks) {
    if (block.type === 'image') {
      return true
    }
  }
  return false
}

export function shareExportContentHasImages(
  blocks: MarkdownBlock[],
  avatarUrlTrim: string
): boolean {
  if (avatarUrlTrim.length > 0) {
    return true
  }
  return shareExportBodyHasImages(blocks)
}

export function shareExportMountKey(
  captureKey: number,
  theme: ShareCardTheme,
  tone: ShareCardTone,
  snapshotCompatMode: boolean,
  snapshotSkipQr: boolean,
  showAppIcon: boolean
): string {
  return `${captureKey}_${theme}_${tone}_` +
    `${snapshotCompatMode ? 'compat' : 'normal'}_` +
    `${snapshotSkipQr ? 'noqr' : 'qr'}_` +
    `${showAppIcon ? 'appicon' : 'qrcode'}`
}

/** 分享卡片挂载后等待 ComponentSnapshot 渲染的延迟（毫秒）。 */
export function shareExportMountDelayMs(
  theme: ShareCardTheme,
  tone: ShareCardTone,
  hasImages: boolean
): number {
  const jinshuLight = theme === ShareCardTheme.JINSHU && tone === ShareCardTone.LIGHT
  if (jinshuLight) {
    return 1100
  }
  return hasImages ? 920 : 680
}
