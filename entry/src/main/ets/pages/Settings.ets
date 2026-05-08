import { Want } from '@kit.AbilityKit'
import { AppContextHolder } from '../services/AppContextHolder'
import { PreferencesService } from '../services/PreferencesService'
import { runAppUpdateCheckManually } from '../services/AppUpdateUi'

/** getUIContext().getRouter() 在部分 SDK 上带有清空页面栈的扩展，用于退出登录后避免返回敏感页。 */
interface RouterWithOptionalClear {
  clear?: () => void
}

@Entry
@Component
struct Settings {
  @State accountTitle: string = ''
  @State accountSubId: string = ''
  /** 是否展示第二行用户唯一标识；默认隐藏，点击首项区域切换。 */
  @State showUserIdentifier: boolean = false

  aboutToAppear(): void {
    void this.loadAccountBanner()
  }

  onPageShow(): void {
    void this.loadAccountBanner()
  }

  private async loadAccountBanner(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    const wechatOn = await PreferencesService.getInstance().isWeChatLoggedIn()
    const huaweiOn = await PreferencesService.getInstance().isHuaweiLoggedIn()
    const wxId = (await PreferencesService.getInstance().getWeChatThirdPartyUserId()).trim()
    const hwId = (await PreferencesService.getInstance().getHuaweiThirdPartyUserId()).trim()
    const hwDisplayId = (await PreferencesService.getInstance().getHuaweiSettingsDisplayId()).trim()
    if (wechatOn) {
      this.accountTitle = '微信用户'
      this.accountSubId = wxId
    } else if (huaweiOn) {
      this.accountTitle = '华为用户'
      this.accountSubId = hwId.length > 0 ? hwId : hwDisplayId
    } else {
      this.accountTitle = '未登录'
      this.accountSubId = ''
    }
  }

  private async handleLogout(): Promise<void> {
    try {
      const context = AppContextHolder.tryGetContext()
      if (context) {
        await PreferencesService.getInstance().init(context)
      }
      await PreferencesService.getInstance().clearLoginSession()
      const router = this.getUIContext().getRouter()
      const routerWithClear = router as RouterWithOptionalClear
      if (routerWithClear.clear !== undefined) {
        routerWithClear.clear()
      }
      await router.replaceUrl({ url: 'pages/Login' })
    } catch (error) {
      console.error(`handleLogout: ${JSON.stringify(error)}`)
      try {
        this.getUIContext().getPromptAction().showToast({
          message: '退出登录失败，请稍后重试',
          duration: 2000
        })
      } catch (_) {
        console.error('handleLogout showToast failed')
      }
    }
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

  private openTermsOfService(): void {
    const context = AppContextHolder.tryGetContext()
    if (context === undefined) {
      return
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: 'https://note.kymjs.com/private/terms.html'
    }
    context.startAbility(want).catch((err: Error) => {
      console.error(`openTermsOfService: ${JSON.stringify(err)}`)
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
          Text($r('app.string.settings'))
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
        Column({ space: 12 }) {
          Column({ space: 6 }) {
            Text(this.accountTitle.length > 0 ? this.accountTitle : ' ')
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.primary_text'))
              .width('100%')
            if (this.accountSubId.length > 0 && this.showUserIdentifier) {
              Text(this.accountSubId)
                .fontSize(12)
                .fontColor($r('app.color.tertiary_text'))
                .width('100%')
                .lineHeight(18)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({
            left: 20,
            right: 20,
            top: 16,
            bottom: 16
          })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({ width: 1, color: $r('app.color.card_border') })
          .shadow({
            radius: 20,
            color: $r('app.color.shadow_color'),
            offsetX: 0,
            offsetY: 4
          })
          .onClick(() => {
            if (this.accountSubId.length > 0) {
              this.showUserIdentifier = !this.showUserIdentifier
            }
          })

          Column({ space: 0 }) {
            Row() {
              Text($r('app.string.settings_cloud_sync'))
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
              this.getUIContext().getRouter().pushUrl({ url: 'pages/CloudSyncSettings' }).catch((err: Error) => {
                console.error(`openCloudSyncSettings: ${JSON.stringify(err)}`)
              })
            })

            Divider()
              .color($r('app.color.divider'))
              .strokeWidth(1)

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
              Text($r('app.string.terms_of_service'))
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
              this.openTermsOfService()
            })

            Divider()
              .color($r('app.color.divider'))
              .strokeWidth(1)

            Row() {
              Text($r('app.string.about_title'))
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
              this.getUIContext().getRouter().pushUrl({ url: 'pages/About' }).catch((err: Error) => {
                console.error(`openAbout: ${JSON.stringify(err)}`)
              })
            })
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({ width: 1, color: $r('app.color.card_border') })
          .shadow({
            radius: 20,
            color: $r('app.color.shadow_color'),
            offsetX: 0,
            offsetY: 4
          })

          Button() {
            Text($r('app.string.logout'))
              .fontColor(Color.White)
              .fontSize($r('app.float.body_font_size'))
              .fontWeight(FontWeight.Medium)
          }
            .type(ButtonType.Normal)
            .width('100%')
            .height(48)
            .backgroundColor($r('app.color.danger'))
            .borderRadius($r('app.float.pill_radius'))
            .margin({ top: 8 })
            .onClick((): void => {
              void this.handleLogout()
            })
        }
        .width('100%')
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
  }
}
