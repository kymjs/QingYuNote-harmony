import { common } from '@kit.AbilityKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { Logger } from '../common/utils/Logger'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'
import { showConfirmAlertDialog } from '../dialogs/ConfirmAlertDialog'

/** 与 Flutter `kBetaTestFeedbackMinStaySeconds` 一致。 */
const BETA_TEST_FEEDBACK_MIN_STAY_MS = 10_000

interface FeedbackParams {
  fromBetaTestInvite?: boolean
}

@Entry
@Component
struct Feedback {
  @State pageWidth: number = 360
  private closeGuard = new PageCloseGuard()
  private fromBetaTestInvite: boolean = false
  private enteredAtMs: number = 0

  private get isWideLayout(): boolean {
    return this.pageWidth >= 600
  }

  aboutToAppear(): void {
    this.enteredAtMs = Date.now()
    try {
      const params = this.getUIContext().getRouter().getParams() as FeedbackParams
      this.fromBetaTestInvite = params.fromBetaTestInvite === true
    } catch (_) {
      this.fromBetaTestInvite = false
    }
  }

  private showToastMessage(message: string): void {
    if (message.trim().length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message,
        duration: 2000
      })
    } catch (error) {
      console.error(`Feedback showToast failed: ${JSON.stringify(error)}`)
    }
  }

  private async saveQrToGallery(): Promise<void> {
    if (this.isWideLayout) {
      return
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    try {
      const rm = context.resourceManager
      const buf = await rm.getRawFileContent('wexin_kymjs.jpg')
      const cachePath = `${context.cacheDir}/feedback_wexin_kymjs.jpg`
      const f = fileIo.openSync(cachePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      // getRawFileContent 返回 Uint8Array，其 buffer 可能比视图更长，必须按字节范围切片后再写入
      const bytes = new Uint8Array(buf)
      const outBuf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)
      fileIo.writeSync(f.fd, outBuf)
      fileIo.closeSync(f)

      const helper = photoAccessHelper.getPhotoAccessHelper(context)
      const srcFileUris: Array<string> = [fileUri.getUriFromPath(cachePath)]
      const photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [
        {
          title: `feedback_qr_${Date.now()}`,
          fileNameExtension: 'jpg',
          photoType: photoAccessHelper.PhotoType.IMAGE,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT
        }
      ]
      const destUris: Array<string> = await helper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs)
      if (destUris.length === 0) {
        return
      }
      const src = fileIo.openSync(cachePath, fileIo.OpenMode.READ_ONLY)
      const dest = await fileIo.open(destUris[0], fileIo.OpenMode.WRITE_ONLY)
      await fileIo.copyFile(src.fd, dest.fd)
      fileIo.closeSync(src)
      fileIo.closeSync(dest)
      this.showToastMessage('已保存到相册')
    } catch (error) {
      Logger.error('Feedback', `saveQrToGallery failed: ${JSON.stringify(error)}`)
      this.showToastMessage('保存失败，请稍后重试')
    }
  }

  private handleToolbarBack(): void {
    void this.handleToolbarBackAsync()
  }

  private async handleToolbarBackAsync(): Promise<void> {
    if (this.fromBetaTestInvite) {
      const elapsed = Date.now() - this.enteredAtMs
      if (elapsed < BETA_TEST_FEEDBACK_MIN_STAY_MS) {
        try {
          const abandon = await showConfirmAlertDialog(this.getUIContext(), {
            title: '提示',
            message: '本活动仅展示一次，放弃后将不再展示，确认放弃吗？',
            cancelLabel: '取消',
            confirmLabel: '放弃',
            confirmColor: '#DC2626'
          })
          if (!abandon) {
            return
          }
        } catch (error) {
          console.error(`Feedback retention dialog failed: ${JSON.stringify(error)}`)
          return
        }
      }
    }
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'Feedback')
  }

  onBackPress(): boolean {
    this.handleToolbarBack()
    return true
  }

  build() {
    Column() {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(18)
            .fontColor([$r('app.color.primary_text')])
        }
        .height('100%')
        .padding({
          left: $r('app.float.toolbar_icon_button_padding_h'),
          right: $r('app.float.toolbar_icon_button_padding_h')
        })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.pill_radius'))
        .onClick(() => {
          this.handleToolbarBack()
        })

        Row() {
          Text($r('app.string.contact_us'))
            .fontSize($r('app.float.title_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 20 }) {
          Text(this.isWideLayout ? $r('app.string.feedback_hint_pc') : $r('app.string.feedback_hint_mobile'))
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .lineHeight(22)
            .textAlign(TextAlign.Center)
            .width('100%')

          Image($r('app.media.wexin_kymjs'))
            .width(280)
            .objectFit(ImageFit.Contain)
            .hitTestBehavior(HitTestMode.Default)
            // 嵌在 Scroll 内时父级滑动手势会抢占触摸序列，需用 priorityGesture 确保长按能识别
            .priorityGesture(
              LongPressGesture({ repeat: false, duration: 500 })
                .onAction(() => {
                  if (!this.isWideLayout) {
                    void this.saveQrToGallery()
                  }
                })
            )
        }
        .width('100%')
        .padding({ top: 24, bottom: 24 })
        .alignItems(HorizontalAlign.Center)
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
      .padding({ bottom: 15, top: 5 })
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: 16,
      right: 16
    })
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_, value) => {
      const nextWidth = Number.parseFloat(`${value.width}`) || 360
      if (Math.abs(this.pageWidth - nextWidth) >= 1) {
        this.pageWidth = nextWidth
      }
    })
  }
}
