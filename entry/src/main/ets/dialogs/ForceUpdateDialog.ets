import { Want } from '@kit.AbilityKit'
import { AppContextHolder } from '../services/AppContextHolder'

/** 与 `ComponentContent` / `wrapBuilder` 配合传递强更弹窗参数。 */
export interface ForceUpdateDialogParams {
  message: string
  downloadUrl: string
}

@Component
export struct ForceUpdateDialog {
  @Prop message: string = ''
  @Prop downloadUrl: string = ''

  build() {
    Column({ space: 16 }) {
      Text('需要更新')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Scroll() {
        Text(this.message)
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .lineHeight(22)
          .width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: 360 })

      Button('立即更新')
        .width('100%')
        .fontSize($r('app.float.caption_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_accent'))
        .backgroundColor($r('app.color.accent'))
        .borderRadius($r('app.float.pill_radius'))
        .padding({ top: 12, bottom: 12 })
        .onClick(() => {
          const context = AppContextHolder.tryGetContext()
          if (context === undefined) {
            return
          }
          const want: Want = {
            action: 'ohos.want.action.viewData',
            entities: ['entity.system.browsable'],
            uri: this.downloadUrl
          }
          context.startAbility(want).catch((err: Error) => {
            console.error(`ForceUpdate open download: ${JSON.stringify(err)}`)
          })
        })
    }
    .width('75%')
    .margin({ left: 24, right: 24 })
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
    .padding(20)
  }
}
