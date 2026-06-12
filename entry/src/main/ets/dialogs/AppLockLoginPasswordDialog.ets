import { AppLockService } from '../services/AppLockService'

export interface AppLockLoginPasswordDialogParams {
  onCancel: () => void
  onSuccess: () => void
}

@Builder
export function buildAppLockLoginPasswordDialogContent(params: AppLockLoginPasswordDialogParams) {
  AppLockLoginPasswordDialog({ params: params })
}

@Component
struct AppLockLoginPasswordDialog {
  @Prop params: AppLockLoginPasswordDialogParams = {
    onCancel: (): void => {},
    onSuccess: (): void => {}
  }
  @State password: string = ''
  @State saving: boolean = false

  private showToast(message: string): void {
    const msg = message.trim()
    if (msg.length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 })
    } catch (_) {
      console.error(`AppLockLoginPasswordDialog toast: ${msg}`)
    }
  }

  private async onConfirm(): Promise<void> {
    const pwd = this.password.trim()
    if (pwd.length === 0) {
      this.showToast('请输入登录密码')
      return
    }
    if (this.saving) {
      return
    }
    this.saving = true
    const err = await AppLockService.getInstance().disableAppLockWithLoginPassword(pwd)
    this.saving = false
    if (err !== null) {
      this.showToast(err)
      return
    }
    this.params.onSuccess()
  }

  build() {
    Column({ space: 16 }) {
      Text('验证登录密码')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))

      Text('请输入登录密码以关闭应用锁')
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))

      TextInput({ placeholder: '登录密码', text: this.password })
        .type(InputType.Password)
        .enabled(!this.saving)
        .onChange((value: string) => {
          this.password = value
        })

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .enabled(!this.saving)
          .backgroundColor($r('app.color.surface_muted'))
          .fontColor($r('app.color.primary_text'))
          .onClick(() => {
            this.params.onCancel()
          })
        Button(this.saving ? '验证中…' : '确定')
          .layoutWeight(1)
          .enabled(!this.saving)
          .onClick(() => {
            void this.onConfirm()
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.card_radius'))
  }
}
