import { ComponentContent, UIContext } from '@kit.ArkUI'

export interface ConfirmAlertDialogParams {
  title: string
  message: string
  cancelLabel: string
  confirmLabel: string
  confirmColor: string
  onCancel: () => void
  onConfirm: () => void
}

export interface ConfirmAlertDialogOptions {
  title: string
  message: string
  cancelLabel: string
  confirmLabel: string
  confirmColor?: string
}

@Component
export struct ConfirmAlertDialog {
  @Prop params: ConfirmAlertDialogParams = {
    title: '',
    message: '',
    cancelLabel: '取消',
    confirmLabel: '确定',
    confirmColor: '#0DAA4A',
    onCancel: (): void => {},
    onConfirm: (): void => {}
  }

  build() {
    Column({ space: 16 }) {
      Text(this.params.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text(this.params.message)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .lineHeight(22)
        .width('100%')
      Row({ space: 12 }) {
        Button(this.params.cancelLabel)
          .layoutWeight(1)
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .backgroundColor(Color.Transparent)
          .borderRadius($r('app.float.pill_radius'))
          .padding({ top: 12, bottom: 12 })
          .onClick(() => {
            this.params.onCancel()
          })
        Button(this.params.confirmLabel)
          .layoutWeight(1)
          .fontSize($r('app.float.body_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.params.confirmColor)
          .backgroundColor(Color.Transparent)
          .borderRadius($r('app.float.pill_radius'))
          .padding({ top: 12, bottom: 12 })
          .onClick(() => {
            this.params.onConfirm()
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('85%')
    .constraintSize({ maxWidth: 400 })
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.card_radius'))
    .border({ width: 1, color: $r('app.color.card_border') })
    .shadow({
      radius: 20,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 4
    })
    .alignItems(HorizontalAlign.Start)
  }
}

@Builder
export function buildConfirmAlertDialogContent(params: ConfirmAlertDialogParams): void {
  ConfirmAlertDialog({ params: params })
}

/**
 * 与 Flutter `showDialog(barrierDismissible: false)` 对齐：仅按钮可关闭，蒙层/返回/侧滑无效。
 * @returns true 表示点击确认按钮，false 表示点击取消。
 */
export function showConfirmAlertDialog(
  uiContext: UIContext,
  options: ConfirmAlertDialogOptions
): Promise<boolean> {
  return new Promise((resolve) => {
    let holder: ComponentContent<ConfirmAlertDialogParams> | undefined = undefined
    const closeDialog = (): void => {
      if (holder === undefined) {
        return
      }
      try {
        uiContext.getPromptAction().closeCustomDialog(holder)
      } catch (_) {
        // ignore
      }
    }
    const params: ConfirmAlertDialogParams = {
      title: options.title,
      message: options.message,
      cancelLabel: options.cancelLabel,
      confirmLabel: options.confirmLabel,
      confirmColor: options.confirmColor ?? '#0DAA4A',
      onCancel: (): void => {
        closeDialog()
        resolve(false)
      },
      onConfirm: (): void => {
        closeDialog()
        resolve(true)
      }
    }
    holder = new ComponentContent(uiContext, wrapBuilder(buildConfirmAlertDialogContent), params)
    try {
      uiContext.getPromptAction().openCustomDialog(holder, {
        alignment: DialogAlignment.Center,
        autoCancel: false,
        isModal: true,
        onWillDismiss: (_: DismissDialogAction) => {
          // 不调用 dismiss()，禁止蒙层/返回/侧滑关闭
        }
      })
    } catch (error) {
      console.error(`showConfirmAlertDialog failed: ${JSON.stringify(error)}`)
      resolve(false)
    }
  })
}
