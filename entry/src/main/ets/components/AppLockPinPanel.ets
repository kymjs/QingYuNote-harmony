import { AppLockService } from '../services/AppLockService'
import { BiometricLockService, type BiometricLockKind } from '../services/BiometricLockService'

export type AppLockPinMode = 'setup' | 'unlock' | 'verifyDisable'

const PIN_LENGTH: number = 4

@Component
export struct AppLockPinPanel {
  @Prop mode: AppLockPinMode = 'unlock'
  @Prop showForgotPassword: boolean = false
  @Prop recovering: boolean = false
  onSuccess?: () => void
  onForgotPassword?: () => void

  @State private input: string = ''
  @State private setupFirstPin: string = ''
  @State private setupStep: number = 0
  @State private errorText: string = ''
  @State private busy: boolean = false
  @State private biometricKind: BiometricLockKind = 'none'
  @State private usePinFallback: boolean = true
  @State private biometricFailCount: number = 0
  @State private biometricAuthing: boolean = false

  aboutToAppear(): void {
    if (this.mode === 'unlock') {
      void this.prepareBiometricUnlock()
    }
  }

  private async prepareBiometricUnlock(): Promise<void> {
    const enabled = await BiometricLockService.getInstance().isEnabledLocally()
    const kind = await BiometricLockService.getInstance().getAvailableKind()
    this.biometricKind = kind
    if (!enabled || kind === 'none') {
      this.usePinFallback = true
      return
    }
    this.usePinFallback = false
    void this.tryBiometricAuth()
  }

  private async tryBiometricAuth(): Promise<void> {
    if (this.usePinFallback || this.busy || this.recovering || this.biometricAuthing) {
      return
    }
    this.biometricAuthing = true
    const outcome = await BiometricLockService.getInstance().authenticate(
      BiometricLockService.getInstance().unlockPromptFor(this.biometricKind))
    this.biometricAuthing = false
    if (outcome === 'success') {
      AppLockService.getInstance().markSessionUnlocked()
      this.onSuccess?.()
      return
    }
    if (outcome === 'fallback') {
      this.usePinFallback = true
      return
    }
    if (outcome === 'failed') {
      this.biometricFailCount += 1
      if (this.biometricFailCount >= BiometricLockService.maxConsecutiveFailures) {
        this.usePinFallback = true
      }
    }
  }

  private showBiometricUnlock(): boolean {
    return this.mode === 'unlock' && !this.usePinFallback && this.biometricKind !== 'none'
  }

  private getTitle(): string {
    if (this.mode === 'setup') {
      return this.setupStep === 0 ? '设置应用锁密码' : '再次输入确认'
    }
    if (this.mode === 'verifyDisable') {
      return '验证密码以关闭应用锁'
    }
    if (this.showBiometricUnlock()) {
      return '验证身份'
    }
    return '输入应用锁密码'
  }

  private appendDigit(digit: string): void {
    if (this.busy || this.recovering || this.input.length >= PIN_LENGTH) {
      return
    }
    this.input = `${this.input}${digit}`
    this.errorText = ''
    if (this.input.length === PIN_LENGTH) {
      void this.onPinComplete(this.input)
    }
  }

  private deleteDigit(): void {
    if (this.busy || this.recovering || this.input.length === 0) {
      return
    }
    this.input = this.input.substring(0, this.input.length - 1)
    this.errorText = ''
  }

  private async onPinComplete(pin: string): Promise<void> {
    if (this.busy || this.recovering) {
      return
    }
    this.busy = true
    try {
      if (this.mode === 'setup') {
        await this.handleSetup(pin)
      } else if (this.mode === 'verifyDisable') {
        await this.handleVerifyDisable(pin)
      } else {
        await this.handleUnlock(pin)
      }
    } finally {
      this.busy = false
    }
  }

  private async handleSetup(pin: string): Promise<void> {
    if (this.setupStep === 0) {
      this.setupFirstPin = pin
      this.setupStep = 1
      this.input = ''
      return
    }
    if (pin !== this.setupFirstPin) {
      this.errorText = '两次输入不一致，请重新设置'
      this.setupStep = 0
      this.setupFirstPin = ''
      this.input = ''
      return
    }
    await AppLockService.getInstance().enableWithPin(pin)
    this.onSuccess?.()
  }

  private async handleUnlock(pin: string): Promise<void> {
    const ok = await AppLockService.getInstance().verifyPin(pin)
    if (!ok) {
      this.errorText = '密码错误'
      this.input = ''
      return
    }
    AppLockService.getInstance().markSessionUnlocked()
    this.onSuccess?.()
  }

  private async handleVerifyDisable(pin: string): Promise<void> {
    const ok = await AppLockService.getInstance().verifyPin(pin)
    if (!ok) {
      this.errorText = '密码错误'
      this.input = ''
      return
    }
    await AppLockService.getInstance().disableAppLock()
    this.onSuccess?.()
  }

  @Builder
  private buildPinDot(index: number) {
    Column() {}
      .width(16)
      .height(16)
      .borderRadius(8)
      .backgroundColor(index < this.input.length
        ? (this.errorText.length > 0 ? $r('app.color.danger') : $r('app.color.accent'))
        : Color.Transparent)
      .border({
        width: 2,
        color: this.errorText.length > 0 ? $r('app.color.danger') : $r('app.color.card_border')
      })
      .margin({ left: 12, right: 12 })
  }

  @Builder
  private buildDigitKey(label: string) {
    Button({ type: ButtonType.Normal }) {
      Text(label)
        .fontSize(28)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
    }
    .width(72)
    .height(72)
    .borderRadius(36)
    .backgroundColor($r('app.color.surface_muted'))
    .enabled(!this.recovering)
    .onClick(() => {
      this.appendDigit(label)
    })
  }

  @Builder
  private buildHeaderRow() {
    Row() {
      Blank().width(72)
      Text(this.getTitle())
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      if (this.showForgotPassword) {
        Text($r('app.string.app_lock_forgot_password'))
          .fontSize(15)
          .fontColor($r('app.color.accent'))
          .padding({ right: 8 })
          .enabled(!this.busy && !this.recovering)
          .onClick(() => {
            this.onForgotPassword?.()
          })
      } else {
        Blank().width(72)
      }
    }
    .width('100%')
    .padding({ top: 8, left: 8, right: 8 })
  }

  @Builder
  private buildBiometricUnlockBody() {
    Column() {
      SymbolGlyph(this.biometricKind === 'face' ? $r('sys.symbol.face') :
        $r('sys.symbol.touchid'))
        .fontSize(72)
        .fontColor([$r('app.color.accent')])
      Text(this.biometricKind === 'face' ? $r('app.string.biometric_tap_face') :
        $r('app.string.biometric_tap_fingerprint'))
        .fontSize(15)
        .fontColor($r('app.color.primary_text'))
        .margin({ top: 20 })
      if (this.biometricAuthing) {
        LoadingProgress()
          .width(24)
          .height(24)
          .margin({ top: 20 })
      }
      if (this.biometricFailCount > 0 && !this.usePinFallback) {
        Text(`验证失败，还可尝试 ${BiometricLockService.maxConsecutiveFailures - this.biometricFailCount} 次`)
          .fontSize(14)
          .fontColor($r('app.color.danger'))
          .margin({ top: 12 })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (!this.biometricAuthing) {
        void this.tryBiometricAuth()
      }
    })
  }

  @Builder
  private buildRecoveringOverlay() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(36)
        .height(36)
      Text($r('app.string.app_lock_syncing'))
        .fontSize(15)
        .fontColor($r('app.color.primary_text'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.sheet_background'))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        if (this.mode === 'unlock') {
          this.buildHeaderRow()
        } else if (this.mode !== 'setup') {
          Blank().height(16)
          Text(this.getTitle())
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
        } else {
          Blank().height(16)
          Text(this.getTitle())
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .margin({ top: 16 })
        }

        Blank().height(32)

        if (this.showBiometricUnlock()) {
          this.buildBiometricUnlockBody()
        } else {
          Row() {
            ForEach([0, 1, 2, 3], (index: number) => {
              this.buildPinDot(index)
            }, (index: number) => `${index}`)
          }
          .justifyContent(FlexAlign.Center)

          if (this.errorText.length > 0) {
            Text(this.errorText)
              .fontSize(14)
              .fontColor($r('app.color.danger'))
              .margin({ top: 12 })
          }

          if (this.busy) {
            LoadingProgress()
              .width(24)
              .height(24)
              .margin({ top: 16 })
          }

          Blank().layoutWeight(1)

          Column({ space: 16 }) {
            Row({ space: 0 }) {
              this.buildDigitKey('1')
              this.buildDigitKey('2')
              this.buildDigitKey('3')
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceEvenly)

            Row({ space: 0 }) {
              this.buildDigitKey('4')
              this.buildDigitKey('5')
              this.buildDigitKey('6')
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceEvenly)

            Row({ space: 0 }) {
              this.buildDigitKey('7')
              this.buildDigitKey('8')
              this.buildDigitKey('9')
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceEvenly)

            Row({ space: 0 }) {
              Blank().width(72).height(72)
              this.buildDigitKey('0')
              Button({ type: ButtonType.Normal }) {
                SymbolGlyph($r('sys.symbol.delete_left'))
                  .fontSize(22)
                  .fontColor([$r('app.color.primary_text')])
              }
              .width(72)
              .height(72)
              .borderRadius(36)
              .backgroundColor($r('app.color.surface_muted'))
              .enabled(!this.recovering)
              .onClick(() => {
                this.deleteDigit()
              })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceEvenly)
          }
          .padding({ left: 32, right: 32 })
          .margin({ bottom: 24 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.app_background'))

      if (this.recovering) {
        this.buildRecoveringOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
