import { AppContextHolder } from '../services/AppContextHolder'
import { NoteApiClient } from '../services/NoteApiClient'
import { PreferencesService } from '../services/PreferencesService'

/**
 * 重置密码（与 Flutter `ChangePasswordPage` 对齐：短信验证码 + 服务端公开重置接口）。
 */
@Entry
@Component
struct ChangePassword {
  @State phone: string = ''
  @State code: string = ''
  @State newPassword: string = ''
  @State sending: boolean = false
  @State submitting: boolean = false
  @State cooldownSec: number = 0
  /** 当前 11 位号是否已通过服务端校验存在账号 */
  @State phoneGateOk: boolean = false
  @State checkingPhone: boolean = false

  private cooldownTimerId: number = -1
  private phoneDebounceTimerId: number = -1
  private lastScheduledDigits: string = ''

  aboutToAppear(): void {
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
    if (reg === true) {
      this.phoneGateOk = true
      return
    }
    if (reg === false) {
      this.phoneGateOk = false
      this.showToast('没有对应账号')
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
      console.error(`ChangePassword toast failed: ${msg}`)
    }
  }

  /** 将服务端 `error` 映射为 Toast。`sms_quota_exceeded` 对应公开短信三轴频控（见 `server/TECHNICAL.md` §2.11），对用户勿展开规则。 */
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
      default:
        return '发送失败'
    }
  }

  private mapResetPasswordError(code: string): string {
    switch (code.trim()) {
      case 'invalid_phone':
        return '手机号格式无效'
      case 'no_account':
        return '没有对应账号'
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

  private async onSendCode(): Promise<void> {
    const p = this.phone.trim()
    if (p.length !== 11 || !this.isChinaMobile11(p)) {
      this.showToast('请输入 11 位手机号')
      return
    }
    if (!this.phoneGateOk || this.checkingPhone) {
      return
    }
    if (this.sending || this.cooldownSec > 0) {
      return
    }
    this.sending = true
    const ctx = AppContextHolder.tryGetContext()
    if (ctx !== undefined) {
      await PreferencesService.getInstance().init(ctx)
    }
    const err = await NoteApiClient.getInstance().sendPasswordResetSms(p)
    this.sending = false
    if (err !== null) {
      this.showToast(this.mapSmsSendError(err))
      return
    }
    this.showToast('验证码已发送')
    this.startCooldown()
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
    const err = await NoteApiClient.getInstance().resetPasswordWithSms(p, c, pw)
    this.submitting = false
    if (err !== null) {
      this.showToast(this.mapResetPasswordError(err))
      return
    }
    this.showToast('密码已更新')
    try {
      this.getUIContext().getRouter().back()
    } catch (_) {
      // ignore
    }
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
          Text($r('app.string.change_password_title'))
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
            TextInput({ text: this.code, placeholder: $r('app.string.change_password_code_placeholder') })
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
              Text(this.sending ? '发送中…' :
                (this.cooldownSec > 0 ? `${this.cooldownSec}s 后重发` : '发送验证码'))
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
              .enabled(!this.sending && this.cooldownSec <= 0 && !this.checkingPhone && this.phoneGateOk)
              .onClick((): void => {
                void this.onSendCode()
              })
          }
          .width('100%')

          TextInput({
            text: this.newPassword,
            placeholder: $r('app.string.change_password_new_password_placeholder')
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
            Text(this.submitting ? '提交中…' : $r('app.string.change_password_submit'))
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
              void this.onSubmit()
            })
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
