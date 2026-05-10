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

/** 从云同步设置 `pushUrl` 传入，`back()` 返回上一页（与 Flutter 弹窗登录对齐）。 */
const RETURN_CLOUD_SYNC = 'cloudSync'

@Entry
@Component
struct Login {
  private returnAfterLogin: string = ''
  /** 自 `peekLoginReturnTarget`（OAuth 返回后 router params 可能丢失） */
  private pendingReturnTarget: string = ''
  private loginResultCallback = (payload: Object): void => {
    const data = payload as WeChatLoginResultPayload
    if (data.mergeResult !== undefined) {
      return
    }
    if (data.success) {
      void this.navigateAfterLogin()
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

  private captureNavParams(): void {
    try {
      const p = this.getUIContext().getRouter().getParams() as Record<string, Object>
      const v = p['returnAfterLogin']
      this.returnAfterLogin = typeof v === 'string' ? v : ''
    } catch (_) {
      this.returnAfterLogin = ''
    }
  }

  /**
   * 登录成功或游客进入首页：若从云同步打开则返回上一页，否则进入首页。
   * OAuth 回调后 `router.getParams()` 可能丢失，故使用 `pendingReturnTarget`（来自 peek）。
   */
  private async navigateAfterLogin(): Promise<void> {
    let target = this.pendingReturnTarget.trim()
    if (target.length === 0) {
      this.captureNavParams()
      target = this.returnAfterLogin
    }
    try {
      await PreferencesService.getInstance().clearLoginReturnTarget()
    } catch (_) {
      // ignore
    }
    this.pendingReturnTarget = ''
    if (target === RETURN_CLOUD_SYNC) {
      try {
        this.getUIContext().getRouter().back()
      } catch (e) {
        console.error(`Login navigateAfterLogin back failed: ${JSON.stringify(e)}`)
        try {
          this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' })
        } catch (e2) {
          console.error(`Login navigateAfterLogin replaceUrl fallback failed: ${JSON.stringify(e2)}`)
        }
      }
      return
    }
    try {
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' })
    } catch (e) {
      console.error(`Login navigateAfterLogin replaceUrl failed: ${JSON.stringify(e)}`)
    }
  }

  aboutToAppear(): void {
    try {
      AppContextHolder.getContext().eventHub.on(WECHAT_LOGIN_RESULT_EVENT, this.loginResultCallback)
    } catch (_) {
      console.error('Login: eventHub.on failed')
    }
    void this.loadPendingReturnTarget()
  }

  private async loadPendingReturnTarget(): Promise<void> {
    const ctx = this.obtainUiAbilityContext()
    if (ctx !== undefined) {
      await PreferencesService.getInstance().init(ctx)
    }
    try {
      this.pendingReturnTarget = await PreferencesService.getInstance().peekLoginReturnTarget()
    } catch (_) {
      this.pendingReturnTarget = ''
    }
  }

  aboutToDisappear(): void {
    try {
      AppContextHolder.getContext().eventHub.off(WECHAT_LOGIN_RESULT_EVENT, this.loginResultCallback)
    } catch (_) {
      console.error('Login: eventHub.off failed')
    }
  }

  /** 栈底登录页按返回退出应用；从云同步进入时可返回设置页。 */
  onBackPress(): boolean {
    this.captureNavParams()
    if (this.returnAfterLogin === RETURN_CLOUD_SYNC || this.pendingReturnTarget === RETURN_CLOUD_SYNC) {
      void PreferencesService.getInstance().clearLoginReturnTarget()
      this.pendingReturnTarget = ''
      try {
        this.getUIContext().getRouter().back()
      } catch (_) {
        console.error('Login onBackPress back failed')
      }
      return true
    }
    const host = this.getUIContext().getHostContext()
    const ctx = host as common.UIAbilityContext | undefined
    if (ctx !== undefined) {
      try {
        ctx.terminateSelf()
      } catch (e) {
        console.error(`Login onBackPress terminateSelf failed: ${JSON.stringify(e)}`)
      }
    }
    return true
  }

  async onPageShow(): Promise<void> {
    this.captureNavParams()
    try {
      if (await PreferencesService.getInstance().isUserLoggedIn()) {
        void this.navigateAfterLogin()
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
      void this.navigateAfterLogin()
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

  /** 与 Flutter `login_page.dart` `_onGuestModeTap` 对齐 */
  private async onGuestTap(): Promise<void> {
    const ctx = this.obtainUiAbilityContext()
    if (ctx !== undefined) {
      await PreferencesService.getInstance().init(ctx)
    }
    await PreferencesService.getInstance().setGuestMode(true)
    void this.navigateAfterLogin()
  }

  build() {
    Column() {
      Column({ space: 12 }) {
        Image($r('app.media.icon_app'))
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

      // 与 Flutter `login_page.dart` 一致：`Padding(symmetric(horizontal: 28))` 包裹全宽按钮
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

        Button() {
          Text($r('app.string.login_with_phone'))
            .fontColor($r('app.color.primary_text'))
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
        }
          .type(ButtonType.Normal)
          .width('100%')
          .height(48)
          .backgroundColor(Color.Transparent)
          .border({
            width: 1,
            color: $r('app.color.card_border')
          })
          .borderRadius($r('app.float.pill_radius'))
          .margin({ bottom: 12 })
          .onClick((): void => {
            try {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/PhonePasswordLogin' })
            } catch (e) {
              console.error(`Login push PhonePasswordLogin failed: ${JSON.stringify(e)}`)
            }
          })

        Button() {
          Text($r('app.string.login_guest_mode'))
            .fontColor($r('app.color.primary_text'))
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
        }
          .type(ButtonType.Normal)
          .width('100%')
          .height(48)
          .backgroundColor(Color.Transparent)
          .border({
            width: 1,
            color: $r('app.color.card_border')
          })
          .borderRadius($r('app.float.pill_radius'))
          .onClick((): void => {
            void this.onGuestTap()
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
          .padding({ left: 24, right: 24, top: 12, bottom: 12 })
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
