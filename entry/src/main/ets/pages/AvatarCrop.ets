import { image } from '@kit.ImageKit'
import componentSnapshot from '@ohos.arkui.componentSnapshot'
import display from '@ohos.display'
import fs from '@ohos.file.fs'
import { AppContextHolder } from '../services/AppContextHolder'
import { compressAvatarJpegFileUnder2M } from '../services/AvatarImageCompress'
import { Logger } from '../common/utils/Logger'
import {
  AVATAR_CROP_RESULT_EVENT,
  AvatarCropEmitCancel,
  AvatarCropEmitPath
} from '../common/constants/AvatarCropConstants'

/** 裁剪圆直径（vp） */
const CROP_DIAMETER_VP = 300

@Entry
@Component
struct AvatarCrop {
  @State private uriStr: string = ''
  /** 用户缩放倍数；勿命名为 scale（与 CustomComponent.scale() 冲突） */
  @State private zoomScale: number = 1
  @State private tx: number = 0
  @State private ty: number = 0
  @State private dispWvp: number = CROP_DIAMETER_VP
  @State private dispHvp: number = CROP_DIAMETER_VP
  private pinchStartScale: number = 1
  private panBaseTx: number = 0
  private panBaseTy: number = 0
  private imgWp: number = 1
  private imgHp: number = 1

  aboutToAppear(): void {
    try {
      const p = this.getUIContext().getRouter().getParams() as Record<string, Object>
      const u = p['uri']
      this.uriStr = typeof u === 'string' ? u.trim() : ''
    } catch (_) {
      this.uriStr = ''
    }
    void this.loadImageSize()
  }

  private refreshDispAndClamp(): void {
    const D = CROP_DIAMETER_VP
    if (this.imgWp <= 0 || this.imgHp <= 0) {
      this.dispWvp = D * this.zoomScale
      this.dispHvp = D * this.zoomScale
      this.clampPan()
      return
    }
    const cover = Math.max(D / this.imgWp, D / this.imgHp)
    this.dispWvp = this.imgWp * cover * this.zoomScale
    this.dispHvp = this.imgHp * cover * this.zoomScale
    this.clampPan()
  }

  private async loadImageSize(): Promise<void> {
    if (this.uriStr.length === 0) {
      return
    }
    let src: image.ImageSource | null = null
    let pm: image.PixelMap | null = null
    try {
      src = image.createImageSource(this.uriStr)
      pm = await src.createPixelMap({
        desiredDynamicRange: image.DecodingDynamicRange.SDR,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      })
      const info = pm.getImageInfoSync()
      const dd = display.getDefaultDisplaySync()
      const dpi = dd.densityPixels > 0 ? dd.densityPixels : 480
      this.imgWp = pxToVp(info.size.width, dpi)
      this.imgHp = pxToVp(info.size.height, dpi)
      this.zoomScale = 1
      this.tx = 0
      this.ty = 0
      this.refreshDispAndClamp()
    } catch (e) {
      Logger.warn('AvatarCrop', `loadImageSize failed: ${JSON.stringify(e)}`)
      this.imgWp = 0
      this.imgHp = 0
    } finally {
      if (pm !== null) {
        try {
          await pm.release()
        } catch (_) {
          // ignore
        }
      }
      if (src !== null) {
        try {
          await src.release()
        } catch (_) {
          // ignore
        }
      }
    }
  }

  private emitDone(path: string): void {
    try {
      AppContextHolder.getContext().eventHub.emit(AVATAR_CROP_RESULT_EVENT, new AvatarCropEmitPath(path))
    } catch (e) {
      Logger.warn('AvatarCrop', `emitDone failed: ${JSON.stringify(e)}`)
    }
  }

  private emitCancelled(): void {
    try {
      AppContextHolder.getContext().eventHub.emit(AVATAR_CROP_RESULT_EVENT, new AvatarCropEmitCancel())
    } catch (e) {
      Logger.warn('AvatarCrop', `emitCancelled failed: ${JSON.stringify(e)}`)
    }
  }

  private clampPan(): void {
    const D = CROP_DIAMETER_VP
    const maxTx = Math.max(0, (this.dispWvp - D) / 2)
    const maxTy = Math.max(0, (this.dispHvp - D) / 2)
    if (this.tx > maxTx) {
      this.tx = maxTx
    }
    if (this.tx < -maxTx) {
      this.tx = -maxTx
    }
    if (this.ty > maxTy) {
      this.ty = maxTy
    }
    if (this.ty < -maxTy) {
      this.ty = -maxTy
    }
  }

  private async onConfirmCrop(): Promise<void> {
    if (this.uriStr.length === 0) {
      return
    }
    try {
      const snap = this.getUIContext().getComponentSnapshot()
      const opts: componentSnapshot.SnapshotOptions = { waitUntilRenderFinished: true }
      let pm: image.PixelMap | null = null
      try {
        pm = await snap.get('avatarCropHost', opts)
      } catch (e) {
        Logger.warn('AvatarCrop', `snapshot failed: ${JSON.stringify(e)}`)
        try {
          this.getUIContext().getPromptAction().showToast({ message: '截取头像失败', duration: 2000 })
        } catch (_) {
          // ignore
        }
        return
      }
      if (pm === null) {
        return
      }
      const packer = image.createImagePacker()
      let jpegBuf: ArrayBuffer
      try {
        try {
          await pm.convertPixelFormat(image.PixelMapFormat.RGBA_8888)
        } catch (_) {
          // ignore
        }
        jpegBuf = await packer.packToData(pm, {
          format: 'image/jpeg',
          quality: 95,
          desiredDynamicRange: image.PackingDynamicRange.SDR
        })
      } finally {
        try {
          await pm.release()
        } catch (_) {
          // ignore
        }
      }

      const ctx = AppContextHolder.tryGetContext()
      if (ctx === undefined) {
        return
      }
      const base = (ctx.filesDir ?? '').trim()
      if (base.length === 0) {
        try {
          this.getUIContext().getPromptAction().showToast({ message: '无法写入本地目录', duration: 2000 })
        } catch (_) {
          // ignore
        }
        return
      }
      const dir = `${base}/avatar_upload`
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true)
      }
      const outPath = `${dir}/crop_${Date.now()}.jpg`
      const f = fs.openSync(outPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC)
      try {
        fs.writeSync(f.fd, jpegBuf)
      } finally {
        fs.closeSync(f)
      }

      const ok = await compressAvatarJpegFileUnder2M(outPath)
      if (!ok) {
        try {
          fs.unlinkSync(outPath)
        } catch (_) {
          // ignore
        }
        try {
          this.getUIContext().getPromptAction().showToast({ message: '图片处理失败', duration: 2000 })
        } catch (_) {
          // ignore
        }
        return
      }

      this.emitDone(outPath)
      try {
        await this.getUIContext().getRouter().back()
      } catch (e) {
        Logger.warn('AvatarCrop', `back after crop failed: ${JSON.stringify(e)}`)
      }
    } catch (e) {
      Logger.warn('AvatarCrop', `onConfirmCrop failed: ${JSON.stringify(e)}`)
      try {
        this.getUIContext().getPromptAction().showToast({ message: '处理失败', duration: 2000 })
      } catch (_) {
        // ignore
      }
    }
  }

  build() {
    Column() {
      Row() {
        Text('取消')
          .fontSize(16)
          .fontColor($r('app.color.accent'))
          .padding({ left: 8, right: 12, top: 8, bottom: 8 })
          .onClick((): void => {
            this.emitCancelled()
            try {
              void this.getUIContext().getRouter().back()
            } catch (e) {
              Logger.warn('AvatarCrop', `cancel back failed: ${JSON.stringify(e)}`)
            }
          })
        Blank().layoutWeight(1)
        Text('裁剪头像')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
        Blank().layoutWeight(1)
        Text('完成')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent'))
          .padding({ left: 12, right: 8, top: 8, bottom: 8 })
          .onClick((): void => {
            void this.onConfirmCrop()
          })
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })
      .justifyContent(FlexAlign.SpaceBetween)

      Text('拖动调整位置，双指缩放；确认后将自动压缩至 2MB 以内再上传')
        .fontSize(13)
        .fontColor($r('app.color.tertiary_text'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ left: 16, right: 16, bottom: 8 })

      Column() {
        Stack({ alignContent: Alignment.Center }) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.uriStr.length > 0) {
              Image(this.uriStr)
                .width(this.dispWvp)
                .height(this.dispHvp)
                .objectFit(ImageFit.Cover)
                .translate({ x: this.tx, y: this.ty })
                .parallelGesture(
                  PinchGesture({ fingers: 2 })
                    .onActionStart((_event: GestureEvent) => {
                      this.pinchStartScale = this.zoomScale
                    })
                    .onActionUpdate((event: GestureEvent) => {
                      const s = event.scale
                      if (s !== undefined && s > 0) {
                        let next = this.pinchStartScale * s
                        if (next < 1) {
                          next = 1
                        }
                        if (next > 6) {
                          next = 6
                        }
                        this.zoomScale = next
                        this.refreshDispAndClamp()
                      }
                    }),
                  GestureMask.Normal
                )
                .parallelGesture(
                  PanGesture({ fingers: 1 })
                    .onActionStart((_event: GestureEvent) => {
                      this.panBaseTx = this.tx
                      this.panBaseTy = this.ty
                    })
                    .onActionUpdate((event: GestureEvent) => {
                      const ox = event.offsetX
                      const oy = event.offsetY
                      if (ox !== undefined) {
                        this.tx = this.panBaseTx + ox
                      }
                      if (oy !== undefined) {
                        this.ty = this.panBaseTy + oy
                      }
                      this.clampPan()
                    }),
                  GestureMask.Normal
                )
            }
          }
          .id('avatarCropHost')
          .width(CROP_DIAMETER_VP)
          .height(CROP_DIAMETER_VP)
          .borderRadius(CROP_DIAMETER_VP / 2)
          .clip(true)
          .backgroundColor('#33000000')
        }
        .width('100%')
        .layoutWeight(1)
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
      .backgroundColor($r('app.color.app_background'))
  }

  /** 实体返回键退出裁剪页时解除 Profile 侧一次性监听 */
  onBackPress(): boolean {
    this.emitCancelled()
    return false
  }
}

function pxToVp(px: number, densityDpi: number): number {
  const d = densityDpi > 0 ? densityDpi : 480
  return (px * 160) / d
}
