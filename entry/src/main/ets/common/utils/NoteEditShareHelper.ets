import type { MarkdownBlock } from './MarkdownUtils'
import { ShareCardTheme, ShareCardTone } from '../../share/ShareTheme'
import { image } from '@kit.ImageKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { systemShare } from '@kit.ShareKit'
import { utd } from '@kit.ArkData'
import { Logger } from './Logger'

export const NOTE_EDIT_SHARE_SCROLL_ID: string = 'note_share_export_scroll_capture'
export const NOTE_EDIT_SHARE_SNAPSHOT_MAX_FULL_CARD_VP: number = 2400

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

export async function saveShareCachePngToGallery(
  context: common.UIAbilityContext,
  cachePath: string
): Promise<boolean> {
  try {
    const helper = photoAccessHelper.getPhotoAccessHelper(context)
    const srcFileUris: Array<string> = [fileUri.getUriFromPath(cachePath)]
    const photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [
      {
        title: `note_share_${Date.now()}`,
        fileNameExtension: 'png',
        photoType: photoAccessHelper.PhotoType.IMAGE,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT
      }
    ]
    const destUris: Array<string> = await helper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs)
    if (destUris.length === 0) {
      return false
    }
    const src = fileIo.openSync(cachePath, fileIo.OpenMode.READ_ONLY)
    const dest = await fileIo.open(destUris[0], fileIo.OpenMode.WRITE_ONLY)
    await fileIo.copyFile(src.fd, dest.fd)
    fileIo.closeSync(src)
    fileIo.closeSync(dest)
    return true
  } catch (error) {
    Logger.error('NoteEditShareHelper', `saveShareCachePngToGallery failed: ${JSON.stringify(error)}`)
    return false
  }
}

export async function updateSharePreviewImageLayoutVp(
  path: string,
  pageWidth: number
): Promise<number> {
  if (path.length === 0) {
    return 0
  }
  try {
    let src: image.ImageSource | null = null
    try {
      src = image.createImageSource(path)
    } catch (_) {
      src = image.createImageSource(`file://${path}`)
    }
    if (src === null) {
      return 0
    }
    const pm = await src.createPixelMap({
      desiredDynamicRange: image.DecodingDynamicRange.SDR,
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    })
    const info = pm.getImageInfoSync()
    await pm.release()
    await src.release()
    const w = info.size.width
    const h = info.size.height
    if (w <= 0 || h <= 0) {
      return 0
    }
    const previewW = Math.max(1, pageWidth)
    return (h / w) * previewW
  } catch (error) {
    Logger.warn('NoteEditShareHelper', `updateSharePreviewImageLayoutVp failed: ${JSON.stringify(error)}`)
    return 0
  }
}

export async function sharePngFromCachePath(
  context: common.UIAbilityContext,
  cachePath: string
): Promise<boolean> {
  try {
    const uri = fileUri.getUriFromPath(cachePath)
    const shareData: systemShare.SharedData = new systemShare.SharedData({
      utd: utd.UniformDataType.PNG,
      uri: uri
    })
    const controller: systemShare.ShareController = new systemShare.ShareController(shareData)
    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DETAIL
    })
    return true
  } catch (error) {
    Logger.error('NoteEditShareHelper', `sharePngFromCachePath failed: ${JSON.stringify(error)}`)
    return false
  }
}

