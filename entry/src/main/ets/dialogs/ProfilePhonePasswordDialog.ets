/** 手机号编辑：同时输入手机号与密码（已设密码则为当前密码；否则为新登录密码）。 */
export interface ProfilePhonePasswordDialogParams {
  initialPhone: string
  passwordSet: boolean
  onCancel: () => void
  onConfirm: (phone: string, password: string) => void
}

@Component
export struct ProfilePhonePasswordDialog {
  @Prop params: ProfilePhonePasswordDialogParams = {
    initialPhone: '',
    passwordSet: false,
    onCancel: (): void => {},
    onConfirm: (_p: string, _w: string): void => {}
  }
  @State draftPhone: string = ''
  @State draftPassword: string = ''

  aboutToAppear(): void {
    this.draftPhone = this.params.initialPhone
    this.draftPassword = ''
  }

  build() {
    Column({ space: 16 }) {
      Text('手机号')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      TextInput({ text: this.draftPhone, placeholder: '留空可清空' })
        .fontSize($r('app.float.body_font_size'))
        .width('100%')
        .onChange((v: string) => {
          this.draftPhone = v
        })
      Text(this.params.passwordSet ? '当前登录密码' : '登录密码')
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      TextInput({
        text: this.draftPassword,
        placeholder: this.params.passwordSet ? '验证身份' : '至少 8 位，用于手机号登录'
      })
        .fontSize($r('app.float.body_font_size'))
        .width('100%')
        .type(InputType.Password)
        .onChange((v: string) => {
          this.draftPassword = v
        })
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.pill_radius'))
          .padding({ top: 12, bottom: 12 })
          .onClick(() => {
            this.params.onCancel()
          })
        Button('保存')
          .layoutWeight(1)
          .fontSize($r('app.float.body_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .borderRadius($r('app.float.pill_radius'))
          .padding({ top: 12, bottom: 12 })
          .onClick(() => {
            this.params.onConfirm(this.draftPhone, this.draftPassword)
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
export function buildProfilePhonePasswordDialogContent(params: ProfilePhonePasswordDialogParams) {
  ProfilePhonePasswordDialog({
    params: params
  })
}
