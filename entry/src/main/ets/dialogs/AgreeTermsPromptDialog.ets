import { ComponentContent, UIContext } from '@kit.ArkUI'

export interface AgreeTermsPromptDialogParams {
  message: string
  confirmLabel: string
  onConfirm: () => void
}

@Component
export struct AgreeTermsPromptDialog {
  @Prop params: AgreeTermsPromptDialogParams = {
    message: '请阅读并同意《隐私政策》和《服务协议》',
    confirmLabel: '确定',
    onConfirm: (): void => {}
  }

  build() {
    Column({ space: 16 }) {
      Text(this.params.message)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .lineHeight(22)
        .width('100%')
      Row() {
        Button() {
          Text(this.params.confirmLabel)
            .fontColor('#FFFFFFFF')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
        }
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(50)
          .backgroundColor($r('app.color.login_primary_button'))
          .borderRadius(12)
          .onClick(() => {
            this.params.onConfirm()
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
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
export function buildAgreeTermsPromptDialogContent(params: AgreeTermsPromptDialogParams): void {
  AgreeTermsPromptDialog({ params: params })
}

/**
 * 与 Flutter `showDialog(barrierDismissible: true)` 对齐：仅确定按钮；点击蒙层可关闭。
 * @returns true 表示点击确定，false 表示点击蒙层关闭或打开失败。
 */
export function showAgreeTermsPromptDialog(uiContext: UIContext): Promise<boolean> {
  return new Promise((resolve) => {
    let holder: ComponentContent<AgreeTermsPromptDialogParams> | undefined = undefined
    let settled: boolean = false
    const settle = (value: boolean): void => {
      if (settled) {
        return
      }
      settled = true
      resolve(value)
    }
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
    const params: AgreeTermsPromptDialogParams = {
      message: '请阅读并同意《隐私政策》和《服务协议》',
      confirmLabel: '确定',
      onConfirm: (): void => {
        settle(true)
        closeDialog()
      }
    }
    holder = new ComponentContent(uiContext, wrapBuilder(buildAgreeTermsPromptDialogContent), params)
    try {
      uiContext.getPromptAction().openCustomDialog(holder, {
        alignment: DialogAlignment.Center,
        autoCancel: true,
        isModal: true,
        onWillDismiss: (action: DismissDialogAction) => {
          action.dismiss()
          settle(false)
        }
      })
    } catch (error) {
      console.error(`showAgreeTermsPromptDialog failed: ${JSON.stringify(error)}`)
      settle(false)
    }
  })
}
