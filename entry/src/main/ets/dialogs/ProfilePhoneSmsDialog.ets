import { NoteApiClient } from '../services/NoteApiClient'
import promptAction from '@ohos.promptAction'

/** 绑定手机号编辑：须填写新号码 + 验证码。 */
export interface ProfilePhoneSmsDialogParams {
  boundPhone: string
  onCancel: () => void
  onSuccess: () => void
}

@Component
export struct ProfilePhoneSmsDialog {
  @Prop params: ProfilePhoneSmsDialogParams = {
    boundPhone: '',
    onCancel: (): void => {},
    onSuccess: (): void => {}
  }
  @State draftPhone: string = ''
  @State draftCode: string = ''
  @State sending: boolean = false
  @State saving: boolean = false
  @State cooldownSec: number = 0

  private cooldownTimerId: number = -1

  aboutToAppear(): void {
    this.draftPhone = ''
    this.draftCode = ''
  }

  private filterPhoneDigits(v: string): string {
    let s = ''
    for (let i = 0; i < v.length; i++) {
      const c = v.charAt(i)
      if (c >= '0' && c <= '9') {
        s += c
      }
    }
    if (s.length > 11) {
      s = s.substring(0, 11)
    }
    return s
  }

  aboutToDisappear(): void {
    if (this.cooldownTimerId >= 0) {
      clearInterval(this.cooldownTimerId)
      this.cooldownTimerId = -1
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
      console.error(`ProfilePhoneSmsDialog toast: ${msg}`)
    }
  }

  private mapSmsSendError(code: string): string {
    switch (code.trim()) {
      case 'not_logged_in':
        return '未登录'
      case 'empty_phone':
        return '请输入手机号'
      case 'sms_not_configured':
        return '短信服务未配置'
      case 'phone_not_bound':
        return '账号未绑定手机号'
      case 'phone_mismatch':
        return '手机号与账号不一致'
      case 'sms_rate_limited':
        return '发送过于频繁，请稍后再试'
      case 'sms_limit_exceeded':
        return '今日发送次数已达上限'
      case 'invalid_phone':
        return '手机号格式无效'
      case 'sms_send_failed':
        return '短信发送失败（请查看服务端日志）'
      case 'sms_feature_not_opened':
        return '请在阿里云开通号码认证后再试'
      case 'sms_invalid_params':
        return '短信模板参数无效'
      case 'sms_sign_template_mismatch':
        return '签名或模板与控制台不一致'
      case 'sms_aliyun_auth':
        return '阿里云密钥或权限有误'
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
      case 'username_required':
        return '姓名不能为空'
      case 'clear_password_not_allowed':
        return '不支持清除已设置的密码'
      case 'sms_client_failed':
        return '短信服务暂时不可用'
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

  private async onSend(): Promise<void> {
    const typed = this.draftPhone.trim()
    if (this.sending || this.cooldownSec > 0) {
      return
    }
    if (typed.length === 0) {
      this.showToast('请输入手机号')
      return
    }
    this.sending = true
    const err = await NoteApiClient.getInstance().sendProfilePhoneSms(typed)
    this.sending = false
    if (err !== null) {
      this.showToast(this.mapSmsSendError(err))
      return
    }
    this.showToast('验证码已发送')
    this.startCooldown()
  }

  private async onSave(): Promise<void> {
    const phone = this.draftPhone.trim()
    if (phone.length === 0) {
      this.showToast('请输入手机号')
      return
    }
    const code = this.draftCode.trim()
    if (code.length === 0) {
      this.showToast('请输入验证码')
      return
    }
    if (this.saving) {
      return
    }
    this.saving = true
    const body: Record<string, Object> = {}
    body['phone'] = phone
    body['sms_verify_code'] = code
    let err = await NoteApiClient.getInstance().patchProfile(body)
    if (err === 'phone_bound_to_other') {
      this.saving = false
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
        console.error(`ProfilePhoneSmsDialog rebind dialog: ${JSON.stringify(e)}`)
        return
      }
      if (dlg.index !== 1) {
        return
      }
      this.saving = true
      body['unbind_phone_from_other'] = true
      err = await NoteApiClient.getInstance().patchProfile(body)
    }
    this.saving = false
    if (err !== null) {
      this.showToast(this.mapPatchError(err))
      return
    }
    this.params.onSuccess()
  }

  build() {
    Column({ space: 16 }) {
      Text('绑定手机号')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      TextInput({ text: this.draftPhone, placeholder: '请输入11位手机号' })
        .fontSize($r('app.float.body_font_size'))
        .width('100%')
        .type(InputType.Number)
        .onChange((v: string) => {
          this.draftPhone = this.filterPhoneDigits(v)
        })
      Row({ space: 8 }) {
        TextInput({ text: this.draftCode, placeholder: '请输入验证码' })
          .layoutWeight(1)
          .fontSize($r('app.float.body_font_size'))
          .type(InputType.Number)
          .onChange((v: string) => {
            this.draftCode = v
          })
        Button() {
          Text(this.sending ? '发送中…' :
            (this.cooldownSec > 0 ? `${this.cooldownSec}s 后重发` : '发送验证码'))
            .fontSize(14)
            .fontColor($r('app.color.accent'))
        }
          .type(ButtonType.Normal)
          .height(44)
          .padding({ left: 10, right: 10 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(8)
          .enabled(!this.sending && this.cooldownSec <= 0)
          .onClick((): void => {
            void this.onSend()
          })
      }
      .width('100%')
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.pill_radius'))
          .padding({ top: 12, bottom: 12 })
          .enabled(!this.saving)
          .onClick(() => {
            this.params.onCancel()
          })
        Button(this.saving ? '保存中…' : '保存')
          .layoutWeight(1)
          .fontSize($r('app.float.body_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .borderRadius($r('app.float.pill_radius'))
          .padding({ top: 12, bottom: 12 })
          .enabled(!this.saving)
          .onClick((): void => {
            void this.onSave()
          })
      }
      .width('100%')
    }
    .width('85%')
    .constraintSize({ maxWidth: 400 })
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.card_radius'))
    .border({ width: 1, color: $r('app.color.card_border') })
    .shadow({
      radius: 20,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 4
    })
    .alignItems(HorizontalAlign.Start)
  }
}

@Builder
export function buildProfilePhoneSmsDialogContent(params: ProfilePhoneSmsDialogParams) {
  ProfilePhoneSmsDialog({
    params: params
  })
}
