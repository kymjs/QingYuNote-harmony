import type common from '@ohos.app.ability.common'
import { WECHAT_APP_ID } from '../common/constants/WeChatConstants'
import { AppContextHolder } from '../services/AppContextHolder'
import { describeHuaweiLoginError, startHuaweiLogin } from '../services/HuaweiAuthService'
import { PreferencesService } from '../services/PreferencesService'
import {
  startWeChatLogin,
  WECHAT_LOGIN_RESULT_EVENT,
  WeChatLoginResultPayload,
  wxApi
} from '../services/WeChatAuthService'

@Entry
@Component
struct Login {
  private loginResultCallback = (payload: Object): void => {
    const data = payload as WeChatLoginResultPayload
    if (data.success) {
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' })
      return
    }
    const msg =
      data.errStr ??
      (data.errCode !== undefined ? `授权失败（${data.errCode}）` : '微信授权未完成')
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 })
    } catch (_) {
      console.error(`Login toast failed: ${msg}`)
    }
  }

  private obtainUiAbilityContext(): common.UIAbilityContext | undefined {
    const host = this.getUIContext().getHostContext()
    return host as common.UIAbilityContext
  }

  aboutToAppear(): void {
    try {
      AppContextHolder.getContext().eventHub.on(WECHAT_LOGIN_RESULT_EVENT, this.loginResultCallback)
    } catch (_) {
      console.error('Login: eventHub.on failed')
    }
  }

  aboutToDisappear(): void {
    try {
      AppContextHolder.getContext().eventHub.off(WECHAT_LOGIN_RESULT_EVENT, this.loginResultCallback)
    } catch (_) {
      console.error('Login: eventHub.off failed')
    }
  }

  /** 登录栈底不可返回上一层；按返回键退出应用。 */
  onBackPress(): boolean {
    const host = this.getUIContext().getHostContext()
    const ctx = host as common.UIAbilityContext | undefined
    if (ctx !== undefined) {
      void ctx.terminateSelf()
    }
    return true
  }

  async onPageShow(): Promise<void> {
    try {
      if (await PreferencesService.getInstance().isUserLoggedIn()) {
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' })
      }
    } catch (_) {
      console.error('Login: onPageShow check failed')
    }
  }

  private async onHuaweiTap(): Promise<void> {
    const ctx = this.obtainUiAbilityContext()
    if (ctx === undefined) {
      return
    }
    try {
      await startHuaweiLogin(ctx)
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' })
    } catch (error) {
      const message = describeHuaweiLoginError(error as Object)
      try {
        this.getUIContext().getPromptAction().showToast({ message, duration: 2000 })
      } catch (_) {
        console.error(`Login Huawei toast failed: ${message}`)
      }
    }
  }

  private async onWeChatTap(): Promise<void> {
    if (!wxApi.isWXAppInstalled()) {
      try {
        this.getUIContext().getPromptAction().showToast({
          message: '未安装微信，请先安装微信客户端',
          duration: 2000
        })
      } catch (_) {
        console.error('Login: showToast failed')
      }
      return
    }
    const ctx = this.obtainUiAbilityContext()
    if (ctx === undefined) {
      return
    }
    try {
      await startWeChatLogin(ctx)
    } catch (error) {
      console.error(`Login: sendReq failed: ${JSON.stringify(error)}`)
      try {
        this.getUIContext().getPromptAction().showToast({ message: '无法拉起微信，请稍后重试', duration: 2000 })
      } catch (_) {
        console.error('Login: showToast failed')
      }
    }
  }

  build() {
    Column() {
      Column({ space: 12 }) {
        Image($r('app.media.startIcon'))
          .width(88)
          .height(88)
          .objectFit(ImageFit.Contain)
          .margin({ top: 72, bottom: 8 })

        Text($r('app.string.login_title'))
          .fontSize($r('app.float.title_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .textAlign(TextAlign.Center)
          .width('100%')

        Text($r('app.string.login_options_hint'))
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .lineHeight(22)
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ left: 28, right: 28 })
      }
      .width('100%')

      Blank().layoutWeight(1)

      // 与 Flutter `login_page.dart` 一致：`Padding(symmetric(horizontal: 28))` 包裹全宽按钮，避免 width 100% 与 margin 叠加导致左右贴边。
      Column({ space: 0 }) {
        Button() {
          Text($r('app.string.login_with_huawei'))
            .fontColor('#FFFFFFFF')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
        }
          .type(ButtonType.Normal)
          .width('100%')
          .height(48)
          .backgroundColor($r('app.color.huawei_login_brand'))
          .borderRadius($r('app.float.pill_radius'))
          .margin({ bottom: 12 })
          .onClick((): void => {
            void this.onHuaweiTap()
          })

        Button() {
          Text($r('app.string.login_with_wechat'))
            .fontColor('#FFFFFFFF')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
        }
          .type(ButtonType.Normal)
          .width('100%')
          .height(48)
          .backgroundColor($r('app.color.wechat_brand'))
          .borderRadius($r('app.float.pill_radius'))
          .margin({ bottom: 12 })
          .onClick((): void => {
            void this.onWeChatTap()
          })
      }
        .width('100%')
        .padding({ left: 28, right: 28 })

      if (this.buildAppIdHint().length > 0) {
        Text(this.buildAppIdHint())
          .fontSize(12)
          .fontColor($r('app.color.tertiary_text'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ left: 24, right: 24, bottom: 12 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .padding({
      top: $r('app.float.toolbar_page_padding_top'),
      left: 0,
      right: 0,
      bottom: 48
    })
  }

  private buildAppIdHint(): string {
    const raw = WECHAT_APP_ID.trim()
    if (raw.length === 0 || raw === 'wx0000000000000000') {
      return '请在 WeChatConstants 中配置微信开放平台移动应用 AppID'
    }
    return ''
  }
}
