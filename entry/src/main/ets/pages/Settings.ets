import { CryptoService } from '../services/CryptoService'
import { PreferencesService } from '../services/PreferencesService'
import { WebDAVClient } from '../services/WebDAVClient'
import type { SyncPolicy, WebDAVConfig } from '../common/model/Note'
import { AppContextHolder } from '../services/AppContextHolder'
import { Logger } from '../common/utils/Logger'

interface SettingsPayload {
  config: WebDAVConfig
  policy: SyncPolicy
  reusedStoredPassword: boolean
  effectivePasswordPresent: boolean
}

interface ErrorLike {
  code?: number | string
  message?: string
  name?: string
}

@Entry
@Component
struct Settings {
  @State serverUrl: string = ''
  @State username: string = ''
  @State password: string = ''
  @State notesDir: string = '/qingyu-notes/'
  @State autoSync: boolean = true
  @State syncIntervalMinutes: string = '60'
  @State wifiOnly: boolean = false
  @State testing: boolean = false
  private storedEncryptedPassword: string = ''
  private passwordTouched: boolean = false

  aboutToAppear(): void {
    void this.loadSettings()
  }

  private async loadSettings(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    const config = await PreferencesService.getInstance().getWebDAVConfig()
    const policy = await PreferencesService.getInstance().getSyncPolicy()
    if (config) {
      this.serverUrl = config.baseUrl
      this.username = config.username
      this.notesDir = config.notesDir
      this.storedEncryptedPassword = config.encryptedPassword
      this.password = ''
      this.passwordTouched = false
    }
    this.autoSync = policy.autoSync
    this.syncIntervalMinutes = `${policy.syncIntervalMinutes}`
    this.wifiOnly = policy.wifiOnly
  }

  private async buildConfigPayload(): Promise<SettingsPayload> {
    const baseUrl = this.serverUrl.trim()
    const username = this.username.trim()
    const notesDir = this.notesDir.trim()
    const hasTypedPassword = this.password.trim().length > 0
    const shouldReuseStoredPassword = !this.passwordTouched && this.storedEncryptedPassword.length > 0
    let encryptedPassword = ''
    if (shouldReuseStoredPassword) {
      encryptedPassword = this.storedEncryptedPassword
    } else if (hasTypedPassword) {
      encryptedPassword = await CryptoService.getInstance().encryptText(this.password)
    }
    const effectivePasswordPresent = encryptedPassword.length > 0
    return {
      config: {
        baseUrl,
        username,
        encryptedPassword,
        notesDir,
        enabled: baseUrl.length > 0 && username.length > 0 && effectivePasswordPresent
      },
      policy: {
        autoSync: this.autoSync,
        syncIntervalMinutes: Number.parseInt(this.syncIntervalMinutes, 10) || 60,
        wifiOnly: this.wifiOnly,
        debounceSeconds: 5
      },
      reusedStoredPassword: shouldReuseStoredPassword,
      effectivePasswordPresent
    }
  }

  private async handleSave(): Promise<SettingsPayload> {
    Logger.info('Settings',
      `handleSave start: serverUrlEmpty=${this.serverUrl.trim().length === 0}, usernameEmpty=${this.username.trim().length === 0}, passwordEmpty=${this.password.trim().length === 0}, passwordTouched=${this.passwordTouched}, storedPasswordPresent=${this.storedEncryptedPassword.length > 0}, notesDir=${this.notesDir.trim()}`)
    try {
      const payload = await this.buildConfigPayload()
      await PreferencesService.getInstance().saveWebDAVConfig(payload.config)
      await PreferencesService.getInstance().saveSyncPolicy(payload.policy)
      await PreferencesService.getInstance().setAuthInvalid(false)
      this.storedEncryptedPassword = payload.config.encryptedPassword
      this.passwordTouched = false
      Logger.info('Settings',
        `handleSave success: enabled=${payload.config.enabled}, notesDir=${payload.config.notesDir}, syncIntervalMinutes=${payload.policy.syncIntervalMinutes}, reusedStoredPassword=${payload.reusedStoredPassword}, effectivePasswordPresent=${payload.effectivePasswordPresent}`)
      return payload
    } catch (error) {
      Logger.warn('Settings', `handleSave failed: ${this.describeError(error)}`)
      throw this.toRuntimeError(error)
    }
  }

  private async handleSaveAndClose(): Promise<void> {
    await this.handleSave()
    this.getUIContext().getRouter().back()
  }

  private showUserMessage(message: string): void {
    if (message.trim().length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message,
        duration: 2000
      })
    } catch (error) {
      Logger.warn('Settings', `showToast failed: ${this.describeError(error as Object)}`)
    }
  }

  private async handleTestConnection(): Promise<void> {
    this.testing = true
    Logger.info('Settings', 'handleTestConnection start')
    try {
      const payload = await this.handleSave()
      if (!payload.config.enabled) {
        this.showUserMessage('请先输入完整的 WebDAV 信息后再测试连接')
        Logger.warn('Settings',
          `handleTestConnection aborted: incomplete config, effectivePasswordPresent=${payload.effectivePasswordPresent}, reusedStoredPassword=${payload.reusedStoredPassword}`)
        return
      }
      Logger.info('Settings', 'handleTestConnection save completed, invoking WebDAVClient.testConnection')
      const success = await WebDAVClient.getInstance().testConnection()
      Logger.info('Settings', `handleTestConnection result: success=${success}`)
      this.showUserMessage(success ? '连接测试成功' : '连接测试失败')
    } catch (error) {
      Logger.warn('Settings', `handleTestConnection failed: ${this.describeError(error)}`)
      if (this.isCredentialDecryptFailure(error)) {
        this.showUserMessage('本地保存的 WebDAV 密码无效，请重新输入后重试')
      } else {
        this.showUserMessage('连接测试失败')
      }
    } finally {
      this.testing = false
      Logger.info('Settings', `handleTestConnection finish: testing=${this.testing}`)
    }
  }

  @Builder
  private buildSectionTitle(label: Resource) {
    Text(label)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.tertiary_text'))
      .letterSpacing(1.2)
      .margin({ bottom: 4, left: 4 })
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
          Text($r('app.string.settings'))
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
        Column() {
          Column({ space: 14 }) {
            this.buildSectionTitle($r('app.string.settings_webdav_title'))

            TextInput({ text: this.serverUrl, placeholder: 'https://dav.example.com/remote.php/dav/files/user' })
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.primary_text'))
              .placeholderColor($r('app.color.tertiary_text'))
              .backgroundColor($r('app.color.editor_background'))
              .borderRadius(12)
              .border({ width: 1, color: $r('app.color.card_border') })
              .padding({ left: 14, right: 14 })
              .onChange((value: string) => {
                this.serverUrl = value
              })
            TextInput({ text: this.username, placeholder: '账号' })
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.primary_text'))
              .placeholderColor($r('app.color.tertiary_text'))
              .backgroundColor($r('app.color.editor_background'))
              .borderRadius(12)
              .border({ width: 1, color: $r('app.color.card_border') })
              .padding({ left: 14, right: 14 })
              .onChange((value: string) => {
                this.username = value
              })
            TextInput({ text: this.password, placeholder: '密码' })
              .type(InputType.Password)
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.primary_text'))
              .placeholderColor($r('app.color.tertiary_text'))
              .backgroundColor($r('app.color.editor_background'))
              .borderRadius(12)
              .border({ width: 1, color: $r('app.color.card_border') })
              .padding({ left: 14, right: 14 })
              .onChange((value: string) => {
                this.password = value
                this.passwordTouched = true
              })
            TextInput({ text: this.notesDir, placeholder: '/qingyu-notes/' })
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.primary_text'))
              .placeholderColor($r('app.color.tertiary_text'))
              .backgroundColor($r('app.color.editor_background'))
              .borderRadius(12)
              .border({ width: 1, color: $r('app.color.card_border') })
              .padding({ left: 14, right: 14 })
              .onChange((value: string) => {
                this.notesDir = value
              })

            Row({ space: 10 }) {
              Button(this.testing ? '测试中…' : '测试连接')
                .layoutWeight(1)
                .fontSize($r('app.float.caption_font_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary_text'))
                .backgroundColor($r('app.color.surface_muted'))
                .borderRadius($r('app.float.pill_radius'))
                .padding({ top: 12, bottom: 12 })
                .enabled(!this.testing)
                .onClick(() => {
                  void this.handleTestConnection()
                })
              Button('保存')
                .layoutWeight(1)
                .fontSize($r('app.float.caption_font_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.on_accent'))
                .backgroundColor($r('app.color.accent'))
                .borderRadius($r('app.float.pill_radius'))
                .padding({ top: 12, bottom: 12 })
                .onClick(() => {
                  void this.handleSaveAndClose()
                })
            }
            .width('100%')
            .margin({ top: 4 })
          }
          .padding(20)
          .margin({bottom: 10})
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({ width: 1, color: $r('app.color.card_border') })
          .shadow({
            radius: 20,
            color: $r('app.color.shadow_color'),
            offsetX: 0,
            offsetY: 4
          })

          Column({ space: 16 }) {
            this.buildSectionTitle($r('app.string.settings_sync_title'))

            Row() {
              Text('自动同步')
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.autoSync })
                .selectedColor($r('app.color.accent'))
                .onChange((value: boolean) => {
                  this.autoSync = value
                })
            }
            .width('100%')

            Divider().color($r('app.color.divider')).strokeWidth(1)

            Row() {
              Text('仅 Wi-Fi 同步')
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.wifiOnly })
                .selectedColor($r('app.color.accent'))
                .onChange((value: boolean) => {
                  this.wifiOnly = value
                })
            }
            .width('100%')

            Text('同步间隔（分钟）')
              .fontSize(12)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 4, left: 4 })
            TextInput({ text: this.syncIntervalMinutes, placeholder: '例如 60' })
              .type(InputType.Number)
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.primary_text'))
              .placeholderColor($r('app.color.tertiary_text'))
              .backgroundColor($r('app.color.editor_background'))
              .borderRadius(12)
              .border({ width: 1, color: $r('app.color.card_border') })
              .padding({ left: 14, right: 14 })
              .onChange((value: string) => {
                this.syncIntervalMinutes = value
              })
          }
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
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
        .padding({
          left: 16,
          right: 16,
          top: $r('app.float.toolbar_scroll_padding_top'),
          bottom: 32
        })
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .backgroundColor($r('app.color.app_background'))
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor($r('app.color.app_background'))
  }

  private describeError(error: Object): string {
    const detail = error as ErrorLike
    const raw = JSON.stringify(error)
    const fallbackRaw = raw.length > 0 ? raw : `${error}`
    return `code=${detail.code ?? 'n/a'}, name=${detail.name ?? 'n/a'}, message=${detail.message ?? 'n/a'}, raw=${fallbackRaw}`
  }

  private isCredentialDecryptFailure(error: Object): boolean {
    const detail = error as ErrorLike
    return (detail.message ?? `${error}`).includes('WebDAV credential decrypt failed')
  }

  private toRuntimeError(error: Object): Error {
    return new Error(this.describeError(error))
  }
}
