import { NoteApiClient } from '../services/NoteApiClient'

/** 个人信息页修改密码：已设密码为「当前密码 + 新密码」，否则为「新密码 + 确认」。 */
export interface ProfileChangePasswordDialogParams {
  password_set: boolean
  onCancel: () => void
  onSuccess: () => void
}

@Component
export struct ProfileChangePasswordDialog {
  @Prop params: ProfileChangePasswordDialogParams = {
    password_set: false,
    onCancel: (): void => {},
    onSuccess: (): void => {}
  }
  @State pwdOld: string = ''
  @State pwdNew: string = ''
  @State pwdConfirm: string = ''
  @State saving: boolean = false

  aboutToAppear(): void {
    this.pwdOld = ''
    this.pwdNew = ''
    this.pwdConfirm = ''
  }

  private showToast(message: string): void {
    const msg = message.trim()
    if (msg.length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 })
    } catch (_) {
      console.error(`ProfileChangePasswordDialog toast: ${msg}`)
    }
  }

  private mapPatchError(code: string): string {
    switch (code.trim()) {
      case 'old_password_invalid':
        return '当前密码不正确'
      case 'old_password_required':
        return '请输入当前密码'
      case 'password_too_short':
        return '新密码至少 8 位'
      case 'invalid_body':
        return '请求无效'
      case 'not_logged_in':
        return '未登录'
      case 'network_error':
        return '网络异常'
      case 'db_failed':
        return '服务暂时不可用'
      case 'clear_password_not_allowed':
        return '不支持清除已设置的密码'
      case 'username_required':
        return '姓名不能为空'
      case 'phone_required':
        return '请输入手机号'
      default:
        return '操作失败，请稍后重试'
    }
  }

  private async onSave(): Promise<void> {
    const n = this.pwdNew.trim()
    const n2 = this.pwdConfirm.trim()
    if (this.params.password_set === true) {
      const o = this.pwdOld.trim()
      if (o.length === 0) {
        this.showToast('请输入当前密码')
        return
      }
      if (n.length === 0) {
        this.showToast('请输入新密码')
        return
      }
      if (n.length < 8) {
        this.showToast('新密码至少 8 位')
        return
      }
    } else {
      if (n.length === 0) {
        this.showToast('请输入新密码')
        return
      }
      if (n.length < 8) {
        this.showToast('新密码至少 8 位')
        return
      }
      if (n !== n2) {
        this.showToast('两次输入的新密码不一致')
        return
      }
    }
    if (this.saving) {
      return
    }
    this.saving = true
    const body: Record<string, Object> = {}
    if (this.params.password_set === true) {
      body['old_password'] = this.pwdOld.trim()
      body['new_password'] = n
    } else {
      body['new_password'] = n
    }
    const err = await NoteApiClient.getInstance().patchProfile(body, false)
    this.saving = false
    if (err !== null) {
      this.showToast(this.mapPatchError(err))
      return
    }
    this.params.onSuccess()
  }

  build() {
    Column({ space: 16 }) {
      Text('修改密码')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      if (this.params.password_set === true) {
        TextInput({ text: this.pwdOld, placeholder: '当前密码' })
          .fontSize($r('app.float.body_font_size'))
          .width('100%')
          .type(InputType.Password)
          .onChange((v: string) => {
            this.pwdOld = v
          })
        TextInput({ text: this.pwdNew, placeholder: '新密码（至少 8 位）' })
          .fontSize($r('app.float.body_font_size'))
          .width('100%')
          .type(InputType.Password)
          .onChange((v: string) => {
            this.pwdNew = v
          })
      } else {
        TextInput({ text: this.pwdNew, placeholder: '新密码（至少 8 位）' })
          .fontSize($r('app.float.body_font_size'))
          .width('100%')
          .type(InputType.Password)
          .onChange((v: string) => {
            this.pwdNew = v
          })
        TextInput({ text: this.pwdConfirm, placeholder: '确认新密码' })
          .fontSize($r('app.float.body_font_size'))
          .width('100%')
          .type(InputType.Password)
          .onChange((v: string) => {
            this.pwdConfirm = v
          })
      }
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
        Button(this.saving ? '保存中…' : '确定')
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
export function buildProfileChangePasswordDialogContent(params: ProfileChangePasswordDialogParams) {
  ProfileChangePasswordDialog({
    params: params
  })
}
