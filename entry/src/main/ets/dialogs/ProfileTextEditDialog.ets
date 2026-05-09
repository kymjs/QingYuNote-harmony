/** 单字段编辑（昵称 / 头像链接 / 邮箱 / 手机号），与 `ComponentContent` + `openCustomDialog` 配合使用。 */
export interface ProfileTextEditDialogParams {
  title: string
  initial: string
  placeholder: string
  onCancel: () => void
  onConfirm: (text: string) => void
}

@Component
export struct ProfileTextEditDialog {
  @Prop params: ProfileTextEditDialogParams = {
    title: '',
    initial: '',
    placeholder: '',
    onCancel: (): void => {},
    onConfirm: (_: string): void => {}
  }
  @State draft: string = ''

  aboutToAppear(): void {
    this.draft = this.params.initial
  }

  build() {
    Column({ space: 16 }) {
      Text(this.params.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      TextInput({ text: this.draft, placeholder: this.params.placeholder })
        .fontSize($r('app.float.body_font_size'))
        .width('100%')
        .onChange((v: string) => {
          this.draft = v
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
            this.params.onConfirm(this.draft)
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
export function buildProfileTextEditDialogContent(params: ProfileTextEditDialogParams) {
  ProfileTextEditDialog({
    params: params
  })
}
