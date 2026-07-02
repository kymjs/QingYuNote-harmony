import { image } from '@kit.ImageKit'
import { Logger } from './Logger'

const LOG_TAG: string = 'NoteEditShareSnapshot'

/**
 * 与单屏分享一致：先 ImagePacker(SDR) 再解码，使每张滚动截图的 PixelMap 与 PNG 编解码管线对齐。
 */
export async function normalizeShareSliceViaSdrPngRoundTrip(
  pm: image.PixelMap
): Promise<image.PixelMap | null> {
  const packer = image.createImagePacker()
  let inputReleased = false
  try {
    try {
      await pm.convertPixelFormat(image.PixelMapFormat.RGBA_8888)
    } catch (_) {
      // 部分 RS 截图 convert 失败仍可走 packing
    }
    const pngBuf = await packer.packToData(pm, {
      format: 'image/png',
      quality: 100,
      desiredDynamicRange: image.PackingDynamicRange.SDR
    })
    await pm.release()
    inputReleased = true
    const src = image.createImageSource(pngBuf)
    try {
      return await src.createPixelMap({
        desiredDynamicRange: image.DecodingDynamicRange.SDR,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      })
    } finally {
      await src.release()
    }
  } catch (e) {
    Logger.error(LOG_TAG, `normalizeShareSliceViaSdrPngRoundTrip failed: ${JSON.stringify(e)}`)
    if (!inputReleased) {
      try {
        await pm.release()
      } catch (_) {
      }
    }
    return null
  }
}

export async function normalizeAllShareSlicesForMerge(
  slices: image.PixelMap[]
): Promise<image.PixelMap[] | null> {
  const out: image.PixelMap[] = []
  for (let i = 0; i < slices.length; i++) {
    const n = await normalizeShareSliceViaSdrPngRoundTrip(slices[i])
    if (!n) {
      for (const p of out) {
        await p.release()
      }
      for (let j = i + 1; j < slices.length; j++) {
        await slices[j].release()
      }
      return null
    }
    out.push(n)
  }
  return out
}

export async function packSharePixelMapToPng(pm: image.PixelMap): Promise<ArrayBuffer | null> {
  const packer = image.createImagePacker()
  try {
    try {
      await pm.convertPixelFormat(image.PixelMapFormat.RGBA_8888)
    } catch (_) {
      // 部分 PixelMap 与 convert 不兼容时仍可 packing
    }
    const buf = await packer.packToData(pm, {
      format: 'image/png',
      quality: 100,
      desiredDynamicRange: image.PackingDynamicRange.SDR
    })
    await pm.release()
    return buf
  } catch (err) {
    Logger.error(LOG_TAG, `packSharePixelMapToPng failed: ${JSON.stringify(err)}`)
    await pm.release()
    return null
  }
}

/** 单屏分享截图：裁掉上下透明留白（Scroll 视口高于卡片内容时常见）。 */
export async function trimShareTransparentVerticalEdges(
  pm: image.PixelMap,
  contentPx: number
): Promise<image.PixelMap | null> {
  try {
    const info = pm.getImageInfoSync()
    const widthPx = info.size.width
    const srcH = info.size.height
    if (srcH <= 1) {
      return pm
    }
    const stride = info.stride
    const srcBuf = new ArrayBuffer(pm.getPixelBytesNumber())
    pm.readPixelsToBufferSync(srcBuf)
    const srcView = new Uint8Array(srcBuf)
    const alphaThreshold = 8
    let top = -1
    let bottom = -1
    for (let r = 0; r < srcH; r++) {
      const rowStart = r * stride
      let rowOpaque = false
      for (let x = 0; x < widthPx; x++) {
        const si = rowStart + x * 4
        if (srcView[si + 3] > alphaThreshold) {
          rowOpaque = true
          break
        }
      }
      if (rowOpaque) {
        if (top < 0) {
          top = r
        }
        bottom = r
      }
    }
    if (top < 0) {
      if (contentPx > 0 && contentPx < srcH) {
        top = 0
        bottom = contentPx - 1
      } else {
        return pm
      }
    } else if (contentPx > 0) {
      const contentBottom = top + contentPx - 1
      if (contentBottom < bottom) {
        bottom = contentBottom
      }
    }
    const cropH = bottom - top + 1
    if (cropH <= 0 || cropH >= srcH) {
      return pm
    }
    const headAlpha = info.alphaType
    const mergeAlphaType =
      headAlpha === image.AlphaType.UNKNOWN ? image.AlphaType.PREMUL : headAlpha
    const rowBytes = widthPx * 4
    const dstBuf = new ArrayBuffer(rowBytes * cropH)
    const dstView = new Uint8Array(dstBuf)
    for (let r = 0; r < cropH; r++) {
      const srcRow = top + r
      const srcLineStart = srcRow * stride
      const dstLineStart = r * rowBytes
      for (let x = 0; x < widthPx; x++) {
        const si = srcLineStart + x * 4
        const di = dstLineStart + x * 4
        dstView[di] = srcView[si + 2]
        dstView[di + 1] = srcView[si + 1]
        dstView[di + 2] = srcView[si]
        dstView[di + 3] = srcView[si + 3]
      }
    }
    await pm.release()
    return await image.createPixelMap(dstBuf, {
      size: { width: widthPx, height: cropH },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: mergeAlphaType
    })
  } catch (err) {
    Logger.error(LOG_TAG, `trimShareTransparentVerticalEdges failed: ${JSON.stringify(err)}`)
    return null
  }
}

export async function mergeSharePixelMapsVertical(
  slices: image.PixelMap[],
  widthPx: number,
  totalHeightPx: number,
  rowStepPx: number,
  sliceSkipTopPx: number[]
): Promise<image.PixelMap | null> {
  if (slices.length === 0 || totalHeightPx <= 0 || sliceSkipTopPx.length !== slices.length) {
    Logger.warn(LOG_TAG,
      `mergeSharePixelMapsVertical: bad args slices=${slices.length} totalH=${totalHeightPx} skipLen=${sliceSkipTopPx.length}`)
    return null
  }
  try {
    const headInfo = slices[0].getImageInfoSync()
    const headAlpha = headInfo.alphaType
    const mergeAlphaType =
      headAlpha === image.AlphaType.UNKNOWN ? image.AlphaType.PREMUL : headAlpha
    const mergeBufferPixelFormat = image.PixelMapFormat.RGBA_8888
    const rowBytes = widthPx * 4
    const dstBuf = new ArrayBuffer(rowBytes * totalHeightPx)
    const dstView = new Uint8Array(dstBuf)
    let dstRowTop = 0
    for (let s = 0; s < slices.length && dstRowTop < totalHeightPx; s++) {
      const pm = slices[s]
      const info = pm.getImageInfoSync()
      const srcStride = info.stride
      const srcH = info.size.height
      const srcBuf = new ArrayBuffer(pm.getPixelBytesNumber())
      pm.readPixelsToBufferSync(srcBuf)
      const srcView = new Uint8Array(srcBuf)
      let skipTop = Math.max(0, Math.floor(sliceSkipTopPx[s]))
      if (skipTop >= srcH) {
        Logger.warn(LOG_TAG, `mergeSharePixelMapsVertical: slice[${s}] skipped skipTop=${skipTop}>=srcH=${srcH}`)
        continue
      }
      const availAfterSkip = srcH - skipTop
      const cap = rowStepPx > 0 ? Math.min(availAfterSkip, rowStepPx) : availAfterSkip
      const rowsToCopy = Math.min(cap, totalHeightPx - dstRowTop)
      for (let r = 0; r < rowsToCopy; r++) {
        const srcRow = skipTop + r
        const srcLineStart = srcRow * srcStride
        const dstLineStart = (dstRowTop + r) * rowBytes
        if (srcLineStart + rowBytes > srcView.byteLength) {
          Logger.warn(LOG_TAG,
            `mergeSharePixelMapsVertical: slice[${s}] row=${r} src overflow srcLineStart=${srcLineStart}`)
          break
        }
        for (let x = 0; x < widthPx; x++) {
          const si = srcLineStart + x * 4
          const di = dstLineStart + x * 4
          dstView[di] = srcView[si + 2]
          dstView[di + 1] = srcView[si + 1]
          dstView[di + 2] = srcView[si]
          dstView[di + 3] = srcView[si + 3]
        }
      }
      dstRowTop += rowsToCopy
    }
    const actualHeight = Math.max(1, Math.min(dstRowTop, totalHeightPx))
    const trimmedBuf =
      actualHeight === totalHeightPx ? dstBuf : dstBuf.slice(0, rowBytes * actualHeight)
    const mergedPm = await image.createPixelMap(trimmedBuf, {
      size: { width: widthPx, height: actualHeight },
      pixelFormat: mergeBufferPixelFormat,
      alphaType: mergeAlphaType
    })
    return mergedPm
  } catch (err) {
    Logger.error(LOG_TAG, `mergeSharePixelMapsVertical failed: ${JSON.stringify(err)}`)
    return null
  } finally {
    for (const pm of slices) {
      await pm.release()
    }
  }
}
