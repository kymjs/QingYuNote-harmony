import { image } from '@kit.ImageKit'
import fs from '@ohos.file.fs'
import { fileUri } from '@kit.CoreFileKit'
import { Logger } from '../common/utils/Logger'

/** 与 Flutter `AvatarImageCompress.maxBytesDefault` 一致：2MB */
const MAX_AVATAR_BYTES = 2 * 1024 * 1024

/** 沙箱绝对路径缺少前导 `/` 时 ImageSource 会 realpath 失败 */
function normalizeLocalFilePath(p: string): string {
  const t = p.trim()
  if (t.length === 0) {
    return t
  }
  if (t.startsWith('/')) {
    return t
  }
  if (t.includes('data/storage/')) {
    return `/${t}`
  }
  return t
}

function writeArrayBufferToFile(path: string, data: ArrayBuffer): boolean {
  try {
    const f = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC)
    try {
      fs.writeSync(f.fd, data)
      return true
    } catch (e) {
      Logger.warn('AvatarImageCompress', `writeSync: ${JSON.stringify(e)}`)
      return false
    } finally {
      try {
        fs.closeSync(f)
      } catch (ce) {
        Logger.warn('AvatarImageCompress', `closeSync: ${JSON.stringify(ce)}`)
      }
    }
  } catch (e) {
    Logger.warn('AvatarImageCompress', `openSync: ${JSON.stringify(e)}`)
    return false
  }
}

/**
 * 将本地图片压成 JPEG 并覆盖写入 [filePath]（原路径可为相册拷贝的任意图片）。
 * 目标体积 ≤ 2MB；成功返回 true。
 */
export async function compressAvatarJpegFileUnder2M(filePath: string): Promise<boolean> {
  const normalized = normalizeLocalFilePath(filePath)
  let src: image.ImageSource | null = null
  try {
    try {
      src = image.createImageSource(normalized)
    } catch (_) {
      src = image.createImageSource(fileUri.getUriFromPath(normalized))
    }
  } catch (e) {
    Logger.warn('AvatarImageCompress', `createImageSource: ${JSON.stringify(e)}`)
    return false
  }

  let maxSide = 2048
  let lastBuf: ArrayBuffer | null = null

  try {
    for (let attempt = 0; attempt < 16; attempt++) {
      let pm: image.PixelMap | null = null
      try {
        pm = await src.createPixelMap({
          desiredSize: { width: maxSide, height: maxSide },
          desiredDynamicRange: image.DecodingDynamicRange.SDR,
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888
        })
      } catch (e) {
        Logger.warn('AvatarImageCompress', `createPixelMap: ${JSON.stringify(e)}`)
        return false
      }
      if (pm === null) {
        return false
      }

      const packer = image.createImagePacker()
      let packedOk = false
      for (let q = 90; q >= 26; q -= 4) {
        try {
          try {
            await pm.convertPixelFormat(image.PixelMapFormat.RGBA_8888)
          } catch (_) {
            // 部分图源可跳过
          }
          const buf = await packer.packToData(pm, {
            format: 'image/jpeg',
            quality: q,
            desiredDynamicRange: image.PackingDynamicRange.SDR
          })
          lastBuf = buf
          if (buf.byteLength <= MAX_AVATAR_BYTES) {
            if (writeArrayBufferToFile(filePath, buf)) {
              packedOk = true
              break
            }
            return false
          }
        } catch (e) {
          Logger.warn('AvatarImageCompress', `packToData: ${JSON.stringify(e)}`)
          break
        }
      }

      try {
        await pm.release()
      } catch (_) {
        // ignore
      }
      pm = null

      if (packedOk) {
        return true
      }

      maxSide = Math.floor(maxSide * 0.72)
      if (maxSide < 260) {
        break
      }
    }

    if (lastBuf !== null) {
      if (!writeArrayBufferToFile(filePath, lastBuf)) {
        return false
      }
      return lastBuf.byteLength <= MAX_AVATAR_BYTES
    }
    return false
  } finally {
    try {
      await src.release()
    } catch (_) {
      // ignore
    }
  }
}
