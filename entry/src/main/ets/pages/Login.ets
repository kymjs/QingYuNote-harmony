import type common from '@ohos.app.ability.common'

import { AppContextHolder } from '../services/AppContextHolder'
import { describeHuaweiLoginError, startHuaweiLogin } from '../services/HuaweiAuthService'
import { NoteApiClient } from '../services/NoteApiClient'
import { PreferencesService } from '../services/PreferencesService'
import {
  startWeChatLogin,
  WECHAT_LOGIN_RESULT_EVENT,
  WeChatLoginResultPayload,
  wxApi
} from '../services/WeChatAuthService'

/** getUIContext().getRouter() 在部分 SDK 上带有清空页面栈的扩展，进入首页前清空以免返回登录页。 */
interface RouterWithOptionalClear {
  clear?: () => void
}

/** 从云同步设置 `pushUrl` 传入，`back()` 返回上一页（与 Flutter 弹窗登录对齐）。 */
const RETURN_CLOUD_SYNC = 'cloudSync'

@Entry
@Component
struct Login {
  private returnAfterLogin: string = ''
  /** 自 `peekLoginReturnTarget`（OAuth 返回后 router params 可能丢失） */
  private pendingReturnTarget: string = ''
  @State phone: string = ''
  @State password: string = ''
  @State accountBusy: boolean = false
  private loginResultCallback = (payload: Object): void => {
    const data = payload as WeChatLoginResultPayload
    if (data.mergeResult !== undefined) {
      return
    }
    if ((data.rebindTicket ?? '').trim().length > 0) {
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
   * 登录成功进入首页：若从云同步打开则返回上一页，否则进入首页。
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
          const router = this.getUIContext().getRouter()
          const routerWithClear = router as RouterWithOptionalClear
          if (routerWithClear.clear !== undefined) {
            routerWithClear.clear()
          }
          await router.replaceUrl({ url: 'pages/Index' })
        } catch (e2) {
          console.error(`Login navigateAfterLogin replaceUrl fallback failed: ${JSON.stringify(e2)}`)
        }
      }
      return
    }
    try {
      const router = this.getUIContext().getRouter()
      const routerWithClear = router as RouterWithOptionalClear
      if (routerWithClear.clear !== undefined) {
        routerWithClear.clear()
      }
      await router.replaceUrl({ url: 'pages/Index' })
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

  private mapLoginError(code: string): string {
    switch (code) {
      case 'invalid_body':
        return '请输入手机号和密码'
      case 'invalid_credentials':
        return '手机号或密码错误'
      case 'password_not_set':
        return '该账号尚未设置登录密码'
      case 'db_failed':
        return '服务暂时不可用'
      case 'network_error':
        return '网络异常，请稍后重试'
      default:
        return '登录失败'
    }
  }

  private showToast(message: string): void {
    const msg = message.trim()
    if (msg.length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 })
    } catch (_) {
      console.error(`Login toast failed: ${msg}`)
    }
  }

  private async onAccountPasswordSubmit(): Promise<void> {
    if (this.accountBusy) {
      return
    }
    this.accountBusy = true
    try {
      const ctx = this.obtainUiAbilityContext()
      if (ctx !== undefined) {
        await PreferencesService.getInstance().init(ctx)
      }
      const err = await NoteApiClient.getInstance().loginWithPhonePassword(this.phone, this.password)
      if (err !== null) {
        this.showToast(this.mapLoginError(err))
        return
      }
      void this.navigateAfterLogin()
    } finally {
      this.accountBusy = false
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

  build() {
    Column({ space: 0 }) {
      Column({ space: 10 }) {
        Image($r('app.media.icon_app'))
          .width(72)
          .height(72)
          .objectFit(ImageFit.Contain)

        Text($r('app.string.EntryAbility_label'))
          .fontSize(26)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .letterSpacing(2)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ top: 48, bottom: 20 })
      .alignItems(HorizontalAlign.Center)

      Blank()
        .width('100%')
        .layoutWeight(1)

      Column({ space: 14 }) {
          TextInput({ text: this.phone, placeholder: $r('app.string.login_account_placeholder') })
            .width('100%')
            .height(50)
            .fontSize($r('app.float.body_font_size'))
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .padding({ left: 14, right: 14 })
            .shadow({
              radius: 8,
              color: $r('app.color.shadow_color'),
              offsetX: 0,
              offsetY: 2
            })
            .enabled(!this.accountBusy)
            .onChange((v: string) => {
              this.phone = v
            })

          TextInput({
            text: this.password,
            placeholder: $r('app.string.login_password_placeholder')
          })
            .width('100%')
            .height(50)
            .fontSize($r('app.float.body_font_size'))
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .padding({ left: 14, right: 14 })
            .shadow({
              radius: 8,
              color: $r('app.color.shadow_color'),
              offsetX: 0,
              offsetY: 2
            })
            .type(InputType.Password)
            .enabled(!this.accountBusy)
            .onChange((v: string) => {
              this.password = v
            })

          Row() {
            Text($r('app.string.login_register'))
              .fontSize(14)
              .fontColor($r('app.color.secondary_text'))
              .padding({ top: 4, bottom: 4 })
              .onClick((): void => {
                if (!this.accountBusy) {
                  try {
                    this.captureNavParams()
                    const params: Record<string, Object> = {}
                    if (this.returnAfterLogin.length > 0) {
                      params['returnAfterLogin'] = this.returnAfterLogin
                    }
                    this.getUIContext().getRouter().pushUrl({
                      url: 'pages/Register',
                      params: Object.keys(params).length > 0 ? params : undefined
                    }).catch((err: Error) => {
                      console.error(`Login push Register: ${JSON.stringify(err)}`)
                    })
                  } catch (e) {
                    console.error(`Login push Register: ${JSON.stringify(e)}`)
                  }
                }
              })

            Blank().layoutWeight(1)

            Text($r('app.string.login_forgot_password'))
              .fontSize(14)
              .fontColor($r('app.color.secondary_text'))
              .padding({ top: 4, bottom: 4 })
              .onClick((): void => {
                if (!this.accountBusy) {
                  try {
                    this.getUIContext().getRouter().pushUrl({ url: 'pages/ChangePassword' }).catch((err: Error) => {
                      console.error(`Login push ChangePassword: ${JSON.stringify(err)}`)
                    })
                  } catch (e) {
                    console.error(`Login push ChangePassword: ${JSON.stringify(e)}`)
                  }
                }
              })
          }
          .width('100%')

          Button() {
            Text(this.accountBusy ? $r('app.string.phone_password_logging_in') : $r('app.string.phone_password_submit'))
              .fontColor('#FFFFFFFF')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
          }
            .type(ButtonType.Normal)
            .width('100%')
            .height(50)
            .backgroundColor($r('app.color.login_primary_button'))
            .borderRadius(12)
            .enabled(!this.accountBusy)
            .onClick((): void => {
              void this.onAccountPasswordSubmit()
            })

          Row() {
            Divider()
              .layoutWeight(1)
              .color($r('app.color.divider'))
              .strokeWidth(1)

            Text($r('app.string.login_other_methods'))
              .fontSize(13)
              .fontColor($r('app.color.tertiary_text'))
              .padding({ left: 14, right: 14 })

            Divider()
              .layoutWeight(1)
              .color($r('app.color.divider'))
              .strokeWidth(1)
          }
          .width('100%')
          .margin({ top: 18 })
          .alignItems(VerticalAlign.Center)

          Row({ space: 36 }) {
            Image($r('app.media.ic_login_huawei'))
              .width(48)
              .height(48)
              .borderRadius(24)
              .objectFit(ImageFit.Cover)
              .shadow({
                radius: 6,
                color: $r('app.color.shadow_color'),
                offsetX: 0,
                offsetY: 2
              })
              .onClick((): void => {
                if (!this.accountBusy) {
                  void this.onHuaweiTap()
                }
              })

            Image($r('app.media.ic_login_wechat'))
              .width(48)
              .height(48)
              .borderRadius(24)
              .objectFit(ImageFit.Cover)
              .shadow({
                radius: 6,
                color: $r('app.color.shadow_color'),
                offsetX: 0,
                offsetY: 2
              })
              .onClick((): void => {
                if (!this.accountBusy) {
                  void this.onWeChatTap()
                }
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 18 })
        }
        .width('100%')
        .padding({ left: 28, right: 28, top: 0, bottom: 36 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .padding({
      top: $r('app.float.toolbar_page_padding_top'),
      left: 0,
      right: 0,
      bottom: 36
    })
  }
}
