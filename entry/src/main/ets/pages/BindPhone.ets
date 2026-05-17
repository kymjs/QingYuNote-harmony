import { ComponentContent } from '@kit.ArkUI'

import { NoteApiClient } from '../services/NoteApiClient'
import { PreferencesService } from '../services/PreferencesService'

/**
 * 绑定手机号页面（UI 复制自 Register，去掉密码字段）。
 * 用于第三方登录（华为账号）成功后，若用户未绑定手机号则跳转此页面。
 */
@Entry
@Component
struct BindPhone {
  @State phone: string = ''
  @State code: string = ''
  @State submitting: boolean = false
  @State cooldownSec: number = 0
  @State sending: boolean = false
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
    if (this.cooldownSec > 0 || this.sending) {
      return
    }
    this.sending = true
    const err = await NoteApiClient.getInstance().sendProfilePhoneSms(p)
    this.sending = false
    if (err !== null) {
      this.showToast(err)
      return
    }
    this.showToast('验证码已发送')
    this.startCooldown()
  }

  private async onSubmit(): Promise<void> {
    const p = this.phone.trim()
    const c = this.code.trim()
    if (p.length !== 11 || !this.isChinaMobile11(p)) {
      this.showToast('请输入 11 位手机号')
      return
    }
    if (c.length === 0) {
      this.showToast('请输入验证码')
      return
    }
    if (this.submitting) {
      return
    }
    this.submitting = true
    const body: Record<string, Object> = {}
    body['phone'] = p
    body['sms_verify_code'] = c
    const err = await NoteApiClient.getInstance().patchProfile(body)
    this.submitting = false
    if (err !== null) {
      this.showToast(err)
      return
    }
    this.getUIContext().getRouter().back()
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
          Text('绑定手机号')
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
              Text(this.sending ? '发送中…' : (this.cooldownSec > 0 ? `${this.cooldownSec}s 后重发` : '发送验证码'))
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
              .enabled(this.cooldownSec <= 0 && !this.sending && this.phoneDigitsOk)
              .onClick((): void => {
                void this.onSendCode()
              })
          }
          .width('100%')

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