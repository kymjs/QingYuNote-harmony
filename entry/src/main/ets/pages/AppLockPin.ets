import { ComponentContent } from '@kit.ArkUI'
import { PageLifecycle } from '../common/utils/PageLifecycle'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'
import { AppLockPinPanel, type AppLockPinMode } from '../components/AppLockPinPanel'
import {
  buildAppLockLoginPasswordDialogContent,
  type AppLockLoginPasswordDialogParams
} from '../dialogs/AppLockLoginPasswordDialog'

@Entry
@Component
struct AppLockPin {
  @State mode: AppLockPinMode = 'setup'
  private lifecycle = new PageLifecycle()
  private closeGuard = new PageCloseGuard()
  private loginPasswordDialogHolder?: ComponentContent<AppLockLoginPasswordDialogParams>

  aboutToAppear(): void {
    this.lifecycle.appear()
    this.closeGuard.reset()
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>
    const rawMode = `${params['mode'] ?? 'setup'}`
    if (rawMode === 'unlock' || rawMode === 'verifyDisable' || rawMode === 'setup') {
      this.mode = rawMode as AppLockPinMode
    }
  }

  aboutToDisappear(): void {
    this.lifecycle.disappear()
    this.closeLoginPasswordDialog()
  }

  private handleToolbarBack(): void {
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'AppLockPin')
  }

  onBackPress(): boolean {
    if (this.mode === 'unlock') {
      return true
    }
    this.handleToolbarBack()
    return true
  }

  private closeLoginPasswordDialog(): void {
    if (this.loginPasswordDialogHolder === undefined) {
      return
    }
    try {
      this.getUIContext().getPromptAction().closeCustomDialog(this.loginPasswordDialogHolder)
    } catch (_) {
    }
    this.loginPasswordDialogHolder = undefined
  }

  private openLoginPasswordDialog(): void {
    const ui = this.getUIContext()
    const params: AppLockLoginPasswordDialogParams = {
      onCancel: (): void => {
        this.closeLoginPasswordDialog()
      },
      onSuccess: (): void => {
        this.closeLoginPasswordDialog()
        if (this.lifecycle.isActive()) {
          this.getUIContext().getRouter().back()
        }
      }
    }
    this.loginPasswordDialogHolder =
      new ComponentContent(ui, wrapBuilder(buildAppLockLoginPasswordDialogContent), params)
    try {
      ui.getPromptAction().openCustomDialog(this.loginPasswordDialogHolder, {
        alignment: DialogAlignment.Center,
        autoCancel: false
      })
    } catch (_) {
      this.loginPasswordDialogHolder = undefined
    }
  }

  build() {
    Column() {
      if (this.mode !== 'unlock') {
        Row() {
          Row() {
            SymbolGlyph($r('sys.symbol.arrow_left'))
              .fontSize(18)
              .fontColor([$r('app.color.primary_text')])
          }
          .height('100%')
          .padding({
            left: $r('app.float.toolbar_icon_button_padding_h'),
            right: $r('app.float.toolbar_icon_button_padding_h')
          })
          .onClick(() => {
            this.handleToolbarBack()
          })

          Text(this.mode === 'setup' ? '设置应用锁' : '关闭应用锁')
            .fontSize($r('app.float.title_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          if (this.mode === 'verifyDisable') {
            Text($r('app.string.app_lock_forgot_password'))
              .fontSize(15)
              .fontColor($r('app.color.accent'))
              .padding({ right: $r('app.float.toolbar_icon_button_padding_h') })
              .onClick(() => {
                this.openLoginPasswordDialog()
              })
          } else {
            Blank().width(48)
          }
        }
        .width('100%')
        .height(56)
      }

      AppLockPinPanel({
        mode: this.mode,
        showForgotPassword: false,
        recovering: false,
        onSuccess: (): void => {
          if (this.lifecycle.isActive()) {
            this.getUIContext().getRouter().back()
          }
        }
      })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }
}
