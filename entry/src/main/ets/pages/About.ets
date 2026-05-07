import { Want } from '@kit.AbilityKit'
import { AppContextHolder } from '../services/AppContextHolder'
import { getAppVersionName } from '../services/AppUpdateService'
import { runAppUpdateCheckManually } from '../services/AppUpdateUi'

@Entry
@Component
struct About {
  @State appVersionLine: string = '轻羽云笔记 v1.0.0'

  aboutToAppear(): void {
    void getAppVersionName().then((v: string) => {
      this.appVersionLine = `轻羽云笔记 v${v}`
    })
  }

  private openOfficialSite(): void {
    const context = AppContextHolder.tryGetContext()
    if (context === undefined) {
      return
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: 'https://note.kymjs.com'
    }
    context.startAbility(want).catch((err: Error) => {
      console.error(`openOfficialSite: ${JSON.stringify(err)}`)
    })
  }

  private openPrivacyPolicy(): void {
    const context = AppContextHolder.tryGetContext()
    if (context === undefined) {
      return
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: 'https://note.kymjs.com/private/harmony.html'
    }
    context.startAbility(want).catch((err: Error) => {
      console.error(`openPrivacyPolicy: ${JSON.stringify(err)}`)
    })
  }

  build() {
    Column() {
      Row() {
        Row() {
          Image($r('app.media.ic_back'))
            .width($r('app.float.toolbar_back_icon_size'))
            .height($r('app.float.toolbar_back_icon_size'))
            .objectFit(ImageFit.Contain)
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
          this.getUIContext().getRouter().back()
        })

        Row() {
          Text($r('app.string.about_title'))
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
        Column() {
          Column({ space: 0 }) {
            Image($r('app.media.startIcon'))
              .width(80)
              .height(80)
              .objectFit(ImageFit.Contain)
              .margin({ top: 20, bottom: 20 })

            Column({ space: 16 }) {
              Text(this.appVersionLine)
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.secondary_text'))
                .lineHeight(22)
                .textAlign(TextAlign.Center)
                .width('100%')
              Text('记录本身，就是意义。')
                .fontSize($r('app.float.body_font_size'))
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary_text'))
                .lineHeight(22)
                .textAlign(TextAlign.Center)
                .width('100%')
              Text('轻羽云笔记是一款跨平台云笔记应用，同时支持 Android、iOS、HarmonyOS、macOS、Windows、Linux，无论你正在使用哪台设备，笔记都在手边。')
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.secondary_text'))
                .lineHeight(22)
                .textAlign(TextAlign.Center)
                .width('100%')
              Text('轻盈，无负担')
                .fontSize($r('app.float.body_font_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary_text'))
                .textAlign(TextAlign.Center)
                .width('100%')
              Text('我们相信好的工具应该让人专注表达，而不是被工具本身所累。轻羽追求极致的轻量体验——安装包小、运行快、界面干净，没有多余的弹窗和引导，让你想写就写。')
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.secondary_text'))
                .lineHeight(22)
                .textAlign(TextAlign.Center)
                .width('100%')
              Row() {
                Text('官网：')
                  .fontSize($r('app.float.body_font_size'))
                  .fontColor($r('app.color.secondary_text'))
                  .lineHeight(22)
                Text('https://note.kymjs.com')
                  .fontSize($r('app.float.body_font_size'))
                  .fontColor(0xFF2563EB)
                  .lineHeight(22)
                  .decoration({
                    type: TextDecorationType.Underline,
                    color: 0xFF2563EB
                  })
                  .onClick(() => {
                    this.openOfficialSite()
                  })
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 20 })
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({ width: 1, color: $r('app.color.card_border') })
          .shadow({
            radius: 20,
            color: $r('app.color.shadow_color'),
            offsetX: 0,
            offsetY: 4
          })

          Column({ space: 0 }) {
            Row() {
              Text($r('app.string.feedback_title'))
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text('›')
                .fontSize(22)
                .fontColor($r('app.color.tertiary_text'))
            }
            .width('100%')
            .padding({
              left: 20,
              right: 16,
              top: 14,
              bottom: 14
            })
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/Feedback' }).catch((err: Error) => {
                console.error(`openFeedback: ${JSON.stringify(err)}`)
              })
            })

            Divider()
              .color($r('app.color.divider'))
              .strokeWidth(1)

            Row() {
              Text($r('app.string.privacy_policy'))
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text('›')
                .fontSize(22)
                .fontColor($r('app.color.tertiary_text'))
            }
            .width('100%')
            .padding({
              left: 20,
              right: 16,
              top: 14,
              bottom: 14
            })
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.openPrivacyPolicy()
            })

            Divider()
              .color($r('app.color.divider'))
              .strokeWidth(1)

            Row() {
              Text($r('app.string.check_update'))
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text('›')
                .fontSize(22)
                .fontColor($r('app.color.tertiary_text'))
            }
            .width('100%')
            .padding({
              left: 20,
              right: 16,
              top: 14,
              bottom: 14
            })
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              void runAppUpdateCheckManually(this.getUIContext())
            })
          }
          .width('100%')
          .margin({ top: 12 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({ width: 1, color: $r('app.color.card_border') })
          .shadow({
            radius: 20,
            color: $r('app.color.shadow_color'),
            offsetX: 0,
            offsetY: 4
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
      .padding({bottom: 15, top: 5})
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: 16,
      right: 16,
    })
    .backgroundColor($r('app.color.app_background'))
  }
}
