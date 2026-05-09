/** 登录密码修改 / 清除，与 `ComponentContent` + `openCustomDialog` 配合使用。 */
export interface ProfilePasswordDialogParams {
  password_set: boolean
  onCancel: () => void
  onConfirm: (oldPwd: string, newPwd: string, newPwd2: string, clearPwd: boolean) => void
}

@Component
export struct ProfilePasswordDialog {
  @Prop params: ProfilePasswordDialogParams = {
    password_set: false,
    onCancel: (): void => {},
    onConfirm: (_a: string, _b: string, _c: string, _d: boolean): void => {}
  }
  @State pwdOld: string = ''
  @State pwdNew: string = ''
  @State pwdNew2: string = ''
  @State clearPwd: boolean = false

  aboutToAppear(): void {
    this.pwdOld = ''
    this.pwdNew = ''
    this.pwdNew2 = ''
    this.clearPwd = false
  }

  build() {
    Column({ space: 14 }) {
      Text('登录密码')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Scroll() {
        Column({ space: 12 }) {
          if (this.params.password_set === true) {
            TextInput({ text: this.pwdOld, placeholder: '当前密码' })
              .fontSize($r('app.float.body_font_size'))
              .type(InputType.Password)
              .width('100%')
              .onChange((v: string) => {
                this.pwdOld = v
              })
          }
          TextInput({ text: this.pwdNew, placeholder: '新密码（至少 8 位，留空表示不改）' })
            .fontSize($r('app.float.body_font_size'))
            .type(InputType.Password)
            .width('100%')
            .onChange((v: string) => {
              this.pwdNew = v
            })
          TextInput({ text: this.pwdNew2, placeholder: '确认新密码' })
            .fontSize($r('app.float.body_font_size'))
            .type(InputType.Password)
            .width('100%')
            .onChange((v: string) => {
              this.pwdNew2 = v
            })
          Row({ space: 12 }) {
            Checkbox()
              .select(this.clearPwd)
              .selectedColor($r('app.color.accent'))
              .onChange((v: boolean) => {
                this.clearPwd = v
              })
            Text('清除已设置的密码')
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: 280 })

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
        Button('确定')
          .layoutWeight(1)
          .fontSize($r('app.float.body_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .borderRadius($r('app.float.pill_radius'))
          .padding({ top: 12, bottom: 12 })
          .onClick(() => {
            this.params.onConfirm(this.pwdOld, this.pwdNew, this.pwdNew2, this.clearPwd)
          })
      }
      .width('100%')
    }
    .width('90%')
    .constraintSize({ maxWidth: 420 })
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
export function buildProfilePasswordDialogContent(params: ProfilePasswordDialogParams) {
  ProfilePasswordDialog({
    params: params
  })
}
