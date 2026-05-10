import type common from '@ohos.app.ability.common'

import { NoteApiClient } from '../services/NoteApiClient'
import { PreferencesService } from '../services/PreferencesService'

@Entry
@Component
struct PhonePasswordLogin {
  @State phone: string = ''
  @State password: string = ''
  @State busy: boolean = false

  private obtainUiAbilityContext(): common.UIAbilityContext | undefined {
    const host = this.getUIContext().getHostContext()
    return host as common.UIAbilityContext
  }

  private showToast(message: string): void {
    const msg = message.trim()
    if (msg.length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 })
    } catch (_) {
      console.error(`PhonePasswordLogin toast failed: ${msg}`)
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

  private async onSubmit(): Promise<void> {
    if (this.busy) {
      return
    }
    this.busy = true
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
      try {
        this.getUIContext().getRouter().back()
      } catch (e) {
        console.error(`PhonePasswordLogin back failed: ${JSON.stringify(e)}`)
      }
    } finally {
      this.busy = false
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
          .padding({
            left: 4,
            right: 12,
            top: 12,
            bottom: 12
          })
          .onClick((): void => {
            try {
              this.getUIContext().getRouter().back()
            } catch (e) {
              console.error(`PhonePasswordLogin toolbar back failed: ${JSON.stringify(e)}`)
            }
          })

        Text($r('app.string.phone_password_login_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Blank().width(40)
      }
        .width('100%')
        .padding({ left: 12, right: 12, top: $r('app.float.toolbar_page_padding_top') })

      Column({ space: 16 }) {
        TextInput({ text: this.phone, placeholder: $r('app.string.phone_password_field_phone') })
          .width('100%')
          .height(48)
          .onChange((v: string) => {
            this.phone = v
          })

        TextInput({ text: this.password, placeholder: $r('app.string.phone_password_field_password') })
          .width('100%')
          .height(48)
          .type(InputType.Password)
          .onChange((v: string) => {
            this.password = v
          })

        Button() {
          Text(this.busy ? $r('app.string.phone_password_logging_in') : $r('app.string.phone_password_submit'))
            .fontColor('#FFFFFFFF')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
        }
          .type(ButtonType.Normal)
          .width('100%')
          .height(48)
          .backgroundColor($r('app.color.accent'))
          .borderRadius($r('app.float.pill_radius'))
          .enabled(!this.busy)
          .onClick((): void => {
            void this.onSubmit()
          })
      }
        .width('100%')
        .padding({ left: 28, right: 28, top: 24 })
    }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.app_background'))
      .alignItems(HorizontalAlign.Start)
  }
}
