import { Want } from '@kit.AbilityKit'
import common from '@ohos.app.ability.common'

import { ComponentContent } from '@kit.ArkUI'

import {
  buildRegisterCaptchaDialogContent,
  type RegisterCaptchaDialogParams
} from '../dialogs/RegisterCaptchaDialog'
import { NoteApiClient } from '../services/NoteApiClient'
import { PreferencesService } from '../services/PreferencesService'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'

/** getUIContext().getRouter() 在部分 SDK 上带有清空页面栈的扩展，进入首页前清空以免返回登录/注册页。 */
interface RouterWithOptionalClear {
  clear?: () => void
}

/** 从云同步设置 `pushUrl` 传入 `returnAfterLogin`，与 Login 一致。 */
const RETURN_CLOUD_SYNC = 'cloudSync'

/**
 * 手机号注册（与 Flutter `RegisterPage` / `ChangePassword` 布局一致：短信 + 密码）。
 */
@Entry
@Component
struct Register {
  private returnAfterLogin: string = ''
  private pendingReturnTarget: string = ''
  @State phone: string = ''
  @State code: string = ''
  @State newPassword: string = ''
  @State submitting: boolean = false
  @State agreeToTerms: boolean = false
  @State cooldownSec: number = 0
  /** 当前 11 位号校验为「未注册」后可发码 */
  @State phoneGateOk: boolean = false
  @State checkingPhone: boolean = false

  private cooldownTimerId: number = -1
  private phoneDebounceTimerId: number = -1
  private lastScheduledDigits: string = ''
  private closeGuard = new PageCloseGuard()

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
   * 注册成功进入首页：若从云同步打开登录页再注册，行为与 Login.navigateAfterLogin 一致。
   */
  private async navigateAfterRegister(): Promise<void> {
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
        console.error(`Register navigateAfterRegister back failed: ${JSON.stringify(e)}`)
        try {
          const router = this.getUIContext().getRouter()
          const routerWithClear = router as RouterWithOptionalClear
          if (routerWithClear.clear !== undefined) {
            routerWithClear.clear()
          }
          await router.replaceUrl({ url: 'pages/Index' })
        } catch (e2) {
          console.error(`Register navigateAfterRegister replaceUrl fallback failed: ${JSON.stringify(e2)}`)
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
      console.error(`Register navigateAfterRegister replaceUrl failed: ${JSON.stringify(e)}`)
    }
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

  aboutToAppear(): void {
    this.closeGuard.reset()
    this.captureNavParams()
    void this.loadPendingReturnTarget()
    this.captureInitialPhone()
    const d = this.normalizePhoneDigits(this.phone)
    if (d !== this.phone) {
      this.phone = d
    }
    this.scheduleAccountCheck(d)
  }

  aboutToDisappear(): void {
    if (this.cooldownTimerId >= 0) {
      clearInterval(this.cooldownTimerId)
      this.cooldownTimerId = -1
    }
    if (this.phoneDebounceTimerId >= 0) {
      clearTimeout(this.phoneDebounceTimerId)
      this.phoneDebounceTimerId = -1
    }
  }

  private captureInitialPhone(): void {
    try {
      const p = this.getUIContext().getRouter().getParams() as Record<string, Object>
      const v = p['initialPhone']
      if (typeof v === 'string') {
        this.phone = this.normalizePhoneDigits(v.trim())
      }
    } catch (_) {
      // ignore
    }
  }

  private normalizePhoneDigits(v: string): string {
    let d = ''
    for (let i = 0; i < v.length; i++) {
      const c = v.charAt(i)
      if (c >= '0' && c <= '9') {
        d += c
      }
      if (d.length >= 11) {
        break
      }
    }
    return d
  }

  private isChinaMobile11(d: string): boolean {
    if (d.length !== 11 || d.charAt(0) !== '1') {
      return false
    }
    const second = d.charCodeAt(1)
    return second >= 0x33 && second <= 0x39
  }

  private scheduleAccountCheck(d: string): void {
    if (this.phoneDebounceTimerId >= 0) {
      clearTimeout(this.phoneDebounceTimerId)
      this.phoneDebounceTimerId = -1
    }
    if (d.length !== 11 || !this.isChinaMobile11(d)) {
      this.phoneGateOk = false
      this.checkingPhone = false
      this.lastScheduledDigits = ''
      return
    }
    if (this.lastScheduledDigits === d && this.phoneGateOk) {
      return
    }
    this.phoneDebounceTimerId = setTimeout((): void => {
      this.phoneDebounceTimerId = -1
      void this.runAccountCheck(d)
    }, 350)
  }

  private async runAccountCheck(d: string): Promise<void> {
    this.checkingPhone = true
    this.phoneGateOk = false
    const reg = await NoteApiClient.getInstance().checkPasswordResetRegistered(d)
    this.checkingPhone = false
    this.lastScheduledDigits = d
    if (reg === false) {
      this.phoneGateOk = true
      return
    }
    if (reg === true) {
      this.phoneGateOk = false
      this.showToast('该手机号已注册')
      return
    }
    this.phoneGateOk = false
    this.showToast('校验失败，请检查网络')
  }

  private showToast(message: string): void {
    const msg = message.trim()
    if (msg.length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 })
    } catch (_) {
      console.error(`Register toast failed: ${msg}`)
    }
  }

  /** 将服务端 `error` 映射为 Toast。`sms_quota_exceeded` 含义见 `server/TECHNICAL.md` §2.11；对用户勿写维度与次数。 */
  private mapSmsSendError(code: string): string {
    switch (code.trim()) {
      case 'not_logged_in':
        return '未登录'
      case 'empty_phone':
        return '请输入手机号'
      case 'sms_not_configured':
        return '短信服务未配置'
      case 'no_account':
        return '没有对应账号'
      case 'already_registered':
        return '该手机号已注册'
      case 'invalid_phone':
        return '手机号格式无效'
      case 'phone_not_bound':
        return '账号未绑定手机号'
      case 'phone_mismatch':
        return '手机号与账号不一致'
      case 'sms_rate_limited':
        return '发送过于频繁，请稍后再试'
      case 'sms_limit_exceeded':
        return '今日发送次数已达上限'
      case 'sms_quota_exceeded':
        return '发送过于频繁，请稍后再试'
      case 'sms_send_failed':
      case 'sms_feature_not_opened':
      case 'sms_invalid_params':
      case 'sms_sign_template_mismatch':
      case 'sms_aliyun_auth':
        return '短信发送失败，请稍后重试'
      case 'sms_client_failed':
        return '短信服务暂时不可用'
      case 'invalid_body':
        return '请求无效'
      case 'network_error':
        return '网络异常'
      case 'captcha_required':
        return '请先完成图形验证'
      case 'captcha_invalid':
        return '图形验证码错误'
      default:
        return '发送失败'
    }
  }

  private mapRegisterConfirmError(code: string): string {
    switch (code.trim()) {
      case 'invalid_phone':
        return '手机号格式无效'
      case 'already_registered':
        return '该手机号已注册'
      case 'password_too_short':
        return '密码至少 8 位'
      case 'sms_verify_code_required':
        return '请输入验证码'
      case 'sms_not_configured':
        return '短信服务未配置'
      case 'sms_code_invalid':
        return '验证码错误'
      case 'sms_client_failed':
        return '短信服务暂时不可用'
      case 'invalid_body':
        return '请求无效'
      case 'token_failed':
        return '登录票据签发失败'
      case 'db_failed':
      case 'hash_failed':
        return '服务暂时不可用'
      default:
        return '操作失败，请稍后重试'
    }
  }

  private startCooldown(): void {
    if (this.cooldownTimerId >= 0) {
      clearInterval(this.cooldownTimerId)
      this.cooldownTimerId = -1
    }
    this.cooldownSec = 60
    this.cooldownTimerId = setInterval((): void => {
      if (this.cooldownSec <= 1) {
        this.cooldownSec = 0
        if (this.cooldownTimerId >= 0) {
          clearInterval(this.cooldownTimerId)
          this.cooldownTimerId = -1
        }
      } else {
        this.cooldownSec -= 1
      }
    }, 1000)
  }

  private closeCaptchaDialog(holder: ComponentContent<RegisterCaptchaDialogParams> | undefined): void {
    if (holder === undefined) {
      return
    }
    try {
      this.getUIContext().getPromptAction().closeCustomDialog(holder)
    } catch (_) {
      // ignore
    }
  }

  private openRegisterCaptchaDialog(phone: string): void {
    const ui = this.getUIContext()
    let holder: ComponentContent<RegisterCaptchaDialogParams> | undefined = undefined
    const params: RegisterCaptchaDialogParams = {
      phone,
      onDismiss: (): void => {
        this.closeCaptchaDialog(holder)
      },
      onSmsSent: (): void => {
        this.closeCaptchaDialog(holder)
        this.showToast('验证码已发送')
        this.startCooldown()
      }
    }
    holder = new ComponentContent(ui, wrapBuilder(buildRegisterCaptchaDialogContent), params)
    try {
      ui.getPromptAction().openCustomDialog(holder, {
        alignment: DialogAlignment.Center,
        autoCancel: false
      })
    } catch (e) {
      console.error(`Register openRegisterCaptchaDialog failed: ${JSON.stringify(e)}`)
    }
  }

  private async onSendCode(): Promise<void> {
    const p = this.phone.trim()
    if (p.length !== 11 || !this.isChinaMobile11(p)) {
      this.showToast('请输入 11 位手机号')
      return
    }
    if (!this.phoneGateOk || this.checkingPhone) {
      return
    }
    if (this.cooldownSec > 0) {
      return
    }
    this.openRegisterCaptchaDialog(p)
  }

  private async onSubmit(): Promise<void> {
    const p = this.phone.trim()
    const c = this.code.trim()
    const pw = this.newPassword.trim()
    if (p.length !== 11 || !this.isChinaMobile11(p)) {
      this.showToast('请输入 11 位手机号')
      return
    }
    if (c.length === 0) {
      this.showToast('请输入验证码')
      return
    }
    if (pw.length === 0) {
      this.showToast('请输入密码')
      return
    }
    if (pw.length < 8) {
      this.showToast('密码至少 8 位')
      return
    }
    if (this.submitting) {
      return
    }
    this.submitting = true
    const ctx = this.obtainUiAbilityContext()
    if (ctx !== undefined) {
      await PreferencesService.getInstance().init(ctx)
    }
    const err = await NoteApiClient.getInstance().registerWithPhoneSms(p, c, pw)
    this.submitting = false
    if (err !== null) {
      this.showToast(this.mapRegisterConfirmError(err))
      return
    }
    // 与手机号登录成功一致：直接进入首页，不额外 Toast 打断过渡。
    void this.navigateAfterRegister()
  }

  private async openInBrowser(url: string): Promise<void> {
    const ctx = this.obtainUiAbilityContext()
    if (ctx === undefined) {
      return
    }
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url
      }
      await ctx.startAbility(want)
    } catch (e) {
      console.error(`Register openInBrowser: ${JSON.stringify(e)}`)
    }
  }

  private handleToolbarBack(): void {
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'Register')
  }

  onBackPress(): boolean {
    this.handleToolbarBack()
    return true
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
          this.handleToolbarBack()
        })

        Row() {
          Text($r('app.string.register_title'))
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
            .type(InputType.Number)
            .onChange((v: string) => {
              const d = this.normalizePhoneDigits(v)
              this.phone = d
              this.scheduleAccountCheck(d)
            })

          Row({ space: 8 }) {
            TextInput({ text: this.code, placeholder: $r('app.string.register_code_placeholder') })
              .layoutWeight(1)
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
              .type(InputType.Number)
              .onChange((v: string) => {
                this.code = v
              })

            Button() {
              Text(this.cooldownSec > 0 ? `${this.cooldownSec}s 后重发` : '发送验证码')
                .fontSize(14)
                .fontColor($r('app.color.accent'))
            }
              .type(ButtonType.Normal)
              .height(50)
              .padding({ left: 10, right: 10 })
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(12)
              .shadow({
                radius: 8,
                color: $r('app.color.shadow_color'),
                offsetX: 0,
                offsetY: 2
              })
              .enabled(this.cooldownSec <= 0 && !this.checkingPhone && this.phoneGateOk)
              .onClick((): void => {
                void this.onSendCode()
              })
          }
          .width('100%')

          TextInput({
            text: this.newPassword,
            placeholder: $r('app.string.register_password_placeholder')
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
            .onChange((v: string) => {
              this.newPassword = v
            })

          Button() {
            Text(this.submitting ? '提交中…' : $r('app.string.register_submit'))
              .fontColor('#FFFFFFFF')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
          }
            .type(ButtonType.Normal)
            .width('100%')
            .height(50)
            .backgroundColor($r('app.color.login_primary_button'))
            .borderRadius(12)
            .margin({ top: 10 })
            .enabled(!this.submitting)
            .onClick((): void => {
              if (!this.agreeToTerms) {
                this.showToast('请先同意用户协议')
                return
              }
              void this.onSubmit()
            })

          Row() {
            Checkbox()
              .select(this.agreeToTerms)
              .width(16)
              .height(16)
              .onChange((isChecked: boolean) => {
                this.agreeToTerms = isChecked
              })
            Text('我已阅读并同意')
              .fontSize(12)
              .fontColor($r('app.color.tertiary_text'))
            Text('《隐私政策》')
              .fontSize(12)
              .fontColor($r('app.color.accent'))
              .onClick((): void => {
                void this.openInBrowser('https://note.kymjs.com/private/harmony.html')
              })
            Text('和')
              .fontSize(12)
              .fontColor($r('app.color.tertiary_text'))
            Text('《服务协议》')
              .fontSize(12)
              .fontColor($r('app.color.accent'))
              .onClick((): void => {
                void this.openInBrowser('https://note.kymjs.com/private/terms.html')
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .margin({ top: 12 })
        }
        .width('100%')
        .padding({ top: 16, bottom: 24 })
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
