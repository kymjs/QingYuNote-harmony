import { ComponentContent } from '@kit.ArkUI'
import promptAction from '@ohos.promptAction'

import {
  buildRegisterCaptchaDialogContent,
  type RegisterCaptchaDialogParams
} from '../dialogs/RegisterCaptchaDialog'
import { NoteApiClient } from '../services/NoteApiClient'

/**
 * 绑定手机号并设置登录密码（UI 与 Register 对齐：短信 + 图形验证 + 密码）。
 * 登录用户进入首页后若未绑定手机号则跳转此页，须完成绑定后方可返回。
 */
@Entry
@Component
struct BindPhone {
  @State phone: string = ''
  @State code: string = ''
  @State newPassword: string = ''
  @State submitting: boolean = false
  @State cooldownSec: number = 0
  @State phoneDigitsOk: boolean = false
  private lastScheduledDigits: string = ''

  private cooldownTimerId: number = -1

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

  aboutToAppear(): void {
    this.captureInitialPhone()
    const d = this.normalizePhoneDigits(this.phone)
    if (d !== this.phone) {
      this.phone = d
    }
    this.checkPhoneDigits(d)
  }

  aboutToDisappear(): void {
    if (this.cooldownTimerId >= 0) {
      clearInterval(this.cooldownTimerId)
      this.cooldownTimerId = -1
    }
  }

  /** 未绑定完成前禁止返回上一页。 */
  onBackPress(): boolean {
    return true
  }

  private checkPhoneDigits(d: string): void {
    const ok = d.length === 11 && this.isChinaMobile11(d)
    if (this.lastScheduledDigits === d && this.phoneDigitsOk === ok) {
      return
    }
    this.lastScheduledDigits = d
    this.phoneDigitsOk = ok
  }

  private showToast(message: string): void {
    const msg = message.trim()
    if (msg.length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 })
    } catch (_) {
      console.error(`BindPhone toast failed: ${msg}`)
    }
  }

  private mapPatchError(code: string): string {
    switch (code.trim()) {
      case 'sms_not_configured':
        return '短信服务未配置'
      case 'sms_verify_code_required':
        return '请输入短信验证码'
      case 'sms_code_invalid':
        return '验证码错误'
      case 'invalid_phone':
        return '手机号格式无效'
      case 'password_too_short':
        return '密码至少 8 位'
      case 'invalid_body':
        return '请求无效'
      case 'not_logged_in':
        return '未登录'
      case 'network_error':
        return '网络异常'
      case 'db_failed':
        return '服务暂时不可用'
      case 'phone_required':
        return '请输入手机号'
      case 'phone_bound_to_other':
        return '该手机号已绑定其他账号'
      case 'phone_rebind_race':
        return '手机号状态已变化，请重试绑定'
      default:
        return `操作失败（${code}）`
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

  private openProfilePhoneCaptchaDialog(phone: string): void {
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
      },
      sendSms: (p: string, captchaId: string, captchaCode: string): Promise<string | null> =>
        NoteApiClient.getInstance().sendProfilePhoneSms(p, captchaId, captchaCode)
    }
    holder = new ComponentContent(ui, wrapBuilder(buildRegisterCaptchaDialogContent), params)
    try {
      ui.getPromptAction().openCustomDialog(holder, {
        alignment: DialogAlignment.Center,
        autoCancel: false
      })
    } catch (e) {
      console.error(`BindPhone openProfilePhoneCaptchaDialog failed: ${JSON.stringify(e)}`)
    }
  }

  private async onSendCode(): Promise<void> {
    const p = this.phone.trim()
    if (p.length !== 11 || !this.isChinaMobile11(p)) {
      this.showToast('请输入 11 位手机号')
      return
    }
    if (this.cooldownSec > 0) {
      return
    }
    this.openProfilePhoneCaptchaDialog(p)
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
    const body: Record<string, Object> = {}
    body['phone'] = p
    body['sms_verify_code'] = c
    let err = await NoteApiClient.getInstance().patchProfile(body)
    if (err === 'phone_bound_to_other') {
      this.submitting = false
      let dlg: promptAction.ShowDialogSuccessResponse
      try {
        dlg = await this.getUIContext().getPromptAction().showDialog({
          title: '该手机号已绑定其他账号',
          message: '确定绑定到当前账号吗？',
          buttons: [
            { text: '取消', color: '#6B7280' },
            { text: '绑定', color: '#2563EB' }
          ]
        })
      } catch (e) {
        console.error(`BindPhone rebind dialog: ${JSON.stringify(e)}`)
        return
      }
      if (dlg.index !== 1) {
        return
      }
      this.submitting = true
      body['unbind_phone_from_other'] = true
      err = await NoteApiClient.getInstance().patchProfile(body)
    }
    if (err !== null) {
      this.submitting = false
      this.showToast(this.mapPatchError(err))
      return
    }
    const pwBody: Record<string, Object> = {}
    pwBody['new_password'] = pw
    err = await NoteApiClient.getInstance().patchProfile(pwBody)
    this.submitting = false
    if (err !== null) {
      this.showToast(this.mapPatchError(err))
      return
    }
    this.getUIContext().getRouter().back()
  }

  build() {
    Column() {
      Row() {
        Text('绑定手机号')
          .fontSize($r('app.float.title_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 14 }) {
          TextInput({ text: this.phone, placeholder: '请输入手机号' })
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
              this.checkPhoneDigits(d)
            })

          Row({ space: 8 }) {
            TextInput({ text: this.code, placeholder: '请输入验证码' })
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
              .enabled(this.cooldownSec <= 0 && this.phoneDigitsOk)
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
            Text(this.submitting ? '提交中…' : '绑定')
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
