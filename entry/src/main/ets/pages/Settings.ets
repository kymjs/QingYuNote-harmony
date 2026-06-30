import { AppContextHolder } from '../services/AppContextHolder'
import { NoteRepository } from '../services/NoteRepository'
import { PreferencesService } from '../services/PreferencesService'
import { RemoteAppConfigService } from '../services/RemoteAppConfigService'
import { openReferralInviteSharePage } from '../common/utils/ReferralInviteNavigation'
import { PageLifecycle } from '../common/utils/PageLifecycle'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'
import { SyncConstants } from '../common/constants/SyncConstants'
import { BiometricLockService } from '../services/BiometricLockService'
import { APP_LOCALE_REVISION_KEY, LocaleService } from '../services/LocaleService'

/** getUIContext().getRouter() 在部分 SDK 上带有清空页面栈的扩展，用于退出登录后避免返回敏感页。 */
interface RouterWithOptionalClear {
  clear?: () => void
}

@Entry
@Component
struct Settings {
  @StorageProp(APP_LOCALE_REVISION_KEY) @Watch('onLocaleChanged') localeRevision: number = 0
  /** 有 Note API 用户 id 时展示「个人信息」；游客且无 id 时展示「未登录」跳转登录页 */
  @State accountSubId: string = ''
  /** 与 Flutter `SettingsHubPage` 对齐：游客模式下不展示退出登录 */
  @State guestMode: boolean = false
  /** 退出登录中：true 时 Stack 覆盖一层全屏遮罩并禁用退出登录按钮 */
  @State loggingOut: boolean = false
  @State noteSettingsLoading: boolean = true
  @State quickActionBarEnabled: boolean = true
  @State folderModeEnabled: boolean = false
  @State appLockEnabled: boolean = false
  @State biometricAvailable: boolean = false
  @State biometricLockEnabled: boolean = false
  @State biometricLockLabel: string = ''
  @State showReferralInviteMenu: boolean = false
  private lifecycle = new PageLifecycle()
  private closeGuard = new PageCloseGuard()
  private noteSettingsChangedHandler = (): void => {
    void this.loadNoteSettingsOnly()
  }

  aboutToAppear(): void {
    this.lifecycle.appear()
    this.closeGuard.reset()
    try {
      AppContextHolder.getContext().eventHub.on(SyncConstants.noteSettingsChangedEvent,
        this.noteSettingsChangedHandler)
    } catch (_) {
      // ignore
    }
    void this.loadSettingsState()
    void this.loadReferralInviteMenuVisibility()
  }

  aboutToDisappear(): void {
    this.lifecycle.disappear()
    try {
      AppContextHolder.getContext().eventHub.off(SyncConstants.noteSettingsChangedEvent,
        this.noteSettingsChangedHandler)
    } catch (_) {
      // ignore
    }
  }

  onPageShow(): void {
    void this.loadSettingsState()
    void this.loadReferralInviteMenuVisibility()
  }

  private async loadReferralInviteMenuVisibility(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    const filesDir = context?.filesDir ?? ''
    const enabled = await RemoteAppConfigService.referralInviteMenuEnabledFromCache(filesDir)
    if (this.lifecycle.isActive()) {
      this.showReferralInviteMenu = enabled
    }
  }

  private async loadNoteSettingsOnly(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    if (!this.lifecycle.isActive()) {
      return
    }
    this.quickActionBarEnabled =
      await PreferencesService.getInstance().getNoteQuickActionBarEnabled()
    if (!this.lifecycle.isActive()) {
      return
    }
    this.folderModeEnabled =
      await PreferencesService.getInstance().getNoteFolderModeEnabled()
    if (!this.lifecycle.isActive()) {
      return
    }
    this.appLockEnabled =
      await PreferencesService.getInstance().getAppLockEnabled()
    await this.loadBiometricSettings()
  }

  private async loadBiometricSettings(): Promise<void> {
    await BiometricLockService.getInstance().ensureConsistentWithAppLock(this.appLockEnabled)
    const kind = await BiometricLockService.getInstance().getAvailableKind()
    const enabled = await PreferencesService.getInstance().getBiometricLockEnabled()
    if (this.lifecycle.isActive()) {
      this.biometricAvailable = kind !== 'none'
      this.biometricLockEnabled = enabled && this.appLockEnabled
      this.biometricLockLabel = BiometricLockService.getInstance().settingsLabelFor(kind)
    }
  }

  private async loadSettingsState(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    if (!this.lifecycle.isActive()) {
      return
    }
    this.guestMode = await PreferencesService.getInstance().isGuestMode()
    if (!this.lifecycle.isActive()) {
      return
    }
    this.accountSubId = (await PreferencesService.getInstance().getNoteApiUserId()).trim()
    if (!this.lifecycle.isActive()) {
      return
    }
    this.noteSettingsLoading = true
    this.quickActionBarEnabled =
      await PreferencesService.getInstance().getNoteQuickActionBarEnabled()
    if (!this.lifecycle.isActive()) {
      return
    }
    this.folderModeEnabled =
      await PreferencesService.getInstance().getNoteFolderModeEnabled()
    if (!this.lifecycle.isActive()) {
      return
    }
    this.appLockEnabled =
      await PreferencesService.getInstance().getAppLockEnabled()
    await this.loadBiometricSettings()
    if (this.lifecycle.isActive()) {
      this.noteSettingsLoading = false
    }
  }

  private async setQuickActionBarEnabled(enabled: boolean): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    await PreferencesService.getInstance().setNoteQuickActionBarEnabled(enabled)
    if (this.lifecycle.isActive()) {
      this.quickActionBarEnabled = enabled
    }
  }

  private toggleQuickActionBar(): void {
    void this.setQuickActionBarEnabled(!this.quickActionBarEnabled)
  }

  private async setFolderModeEnabled(enabled: boolean): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    await PreferencesService.getInstance().setNoteFolderModeEnabled(enabled)
    if (!enabled) {
      await PreferencesService.getInstance().setHomeSidebarFilterMode('tag')
    }
    if (this.lifecycle.isActive()) {
      this.folderModeEnabled = enabled
    }
  }

  private toggleFolderMode(): void {
    void this.setFolderModeEnabled(!this.folderModeEnabled)
  }

  private async setAppLockEnabled(enabled: boolean): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    if (enabled) {
      const hasPassword =
        (await PreferencesService.getInstance().getAppLockPasswordEnc()).length > 0
      if (hasPassword) {
        const enc = await PreferencesService.getInstance().getAppLockPasswordEnc()
        await PreferencesService.getInstance().enableAppLock(enc)
        if (this.lifecycle.isActive()) {
          this.appLockEnabled = true
        }
        return
      }
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/AppLockPin',
        params: { mode: 'setup' }
      })
      if (this.lifecycle.isActive()) {
        this.appLockEnabled = await PreferencesService.getInstance().getAppLockEnabled()
      }
      return
    }
    await this.getUIContext().getRouter().pushUrl({
      url: 'pages/AppLockPin',
      params: { mode: 'verifyDisable' }
    })
    if (this.lifecycle.isActive()) {
      this.appLockEnabled = await PreferencesService.getInstance().getAppLockEnabled()
      await this.loadBiometricSettings()
    }
  }

  private async setBiometricLockEnabled(enabled: boolean): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    if (enabled) {
      if (!this.appLockEnabled) {
        this.showToast(LocaleService.loc('请先开启应用锁', 'Enable app lock first', '先にアプリロックを有効にしてください'))
        return
      }
      const kind = await BiometricLockService.getInstance().getAvailableKind()
      const reason = kind === 'face'
        ? LocaleService.loc('验证面容以开启', 'Verify face to enable', 'Face IDで有効化')
        : LocaleService.loc('验证指纹以开启', 'Verify fingerprint to enable', '指紋で有効化')
      const outcome = await BiometricLockService.getInstance().authenticate(reason)
      if (outcome !== 'success') {
        return
      }
      await PreferencesService.getInstance().setBiometricLockEnabled(true)
      if (this.lifecycle.isActive()) {
        this.biometricLockEnabled = true
      }
      return
    }
    await PreferencesService.getInstance().setBiometricLockEnabled(false)
    if (this.lifecycle.isActive()) {
      this.biometricLockEnabled = false
    }
  }

  private toggleBiometricLock(): void {
    void this.setBiometricLockEnabled(!this.biometricLockEnabled)
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 })
    } catch (_) {
      console.error(`Settings toast: ${message}`)
    }
  }

  private toggleAppLock(): void {
    void this.setAppLockEnabled(!this.appLockEnabled)
  }

  private async handleLogout(): Promise<void> {
    if (this.loggingOut) {
      return
    }
    this.loggingOut = true
    try {
      const context = AppContextHolder.tryGetContext()
      if (context) {
        await PreferencesService.getInstance().init(context)
        await NoteRepository.getInstance().init(context)
      }
      await NoteRepository.getInstance().clearAllLocalNotes()
      await PreferencesService.getInstance().clearLoginSession()
      const router = this.getUIContext().getRouter()
      const routerWithClear = router as RouterWithOptionalClear
      if (routerWithClear.clear !== undefined) {
        routerWithClear.clear()
      }
      await router.replaceUrl({ url: 'pages/Login' })
      // router.replaceUrl 成功后 Settings 页被销毁，遮罩随页面一并销毁
    } catch (error) {
      console.error(`handleLogout: ${JSON.stringify(error)}`)
      this.loggingOut = false
      try {
        this.getUIContext().getPromptAction().showToast({
          message: LocaleService.loc('退出登录失败，请稍后重试', 'Sign out failed, please try again', 'ログアウトに失敗しました。後でもう一度お試しください'),
          duration: 2000
        })
      } catch (_) {
        console.error('handleLogout showToast failed')
      }
    }
  }

  private handleToolbarBack(): void {
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'Settings')
  }

  onBackPress(): boolean {
    this.handleToolbarBack()
    return true
  }

  onLocaleChanged(): void {
    void this.loadBiometricSettings()
  }

  build() {
    Stack() {
    Column() {
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
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.pill_radius'))
        .onClick(() => {
          this.handleToolbarBack()
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
        Column({ space: 12 }) {
          Column({ space: 0 }) {
            if (this.accountSubId.length > 0) {
              Row() {
                Text($r('app.string.settings_user_info'))
                  .fontSize($r('app.float.body_font_size'))
                  .fontColor($r('app.color.primary_text'))
                  .layoutWeight(1)
                Text('›')
                  .fontSize(22)
                  .fontColor($r('app.color.tertiary_text'))
              }
              .width('100%')
              .padding({
                left: 20,
                right: 16,
                top: 14,
                bottom: 14
              })
              .justifyContent(FlexAlign.SpaceBetween)
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/Profile' }).catch((err: Error) => {
                  console.error(`openProfile: ${JSON.stringify(err)}`)
                })
              })

              Divider()
                .color($r('app.color.divider'))
                .strokeWidth(1)
            } else if (this.guestMode) {
              Row() {
                Text($r('app.string.settings_not_logged_in'))
                  .fontSize($r('app.float.body_font_size'))
                  .fontColor($r('app.color.primary_text'))
                  .layoutWeight(1)
                Text('›')
                  .fontSize(22)
                  .fontColor($r('app.color.tertiary_text'))
              }
              .width('100%')
              .padding({
                left: 20,
                right: 16,
                top: 14,
                bottom: 14
              })
              .justifyContent(FlexAlign.SpaceBetween)
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/Login' }).catch((err: Error) => {
                  console.error(`openLoginFromSettings: ${JSON.stringify(err)}`)
                })
              })

              Divider()
                .color($r('app.color.divider'))
                .strokeWidth(1)
            }
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({ width: 1, color: $r('app.color.card_border') })
          .shadow({
            radius: 20,
            color: $r('app.color.shadow_color'),
            offsetX: 0,
            offsetY: 4
          })

          if (!this.noteSettingsLoading) {
            Column({ space: 0 }) {
              Row() {
                Text($r('app.string.note_quick_action_bar'))
                  .fontSize($r('app.float.body_font_size'))
                  .fontColor($r('app.color.primary_text'))
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.quickActionBarEnabled })
                  .selectedColor($r('app.color.accent'))
                  .hitTestBehavior(HitTestMode.None)
              }
              .width('100%')
              .padding({
                left: 20,
                right: 16,
                top: 14,
                bottom: 14
              })
              .justifyContent(FlexAlign.SpaceBetween)
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.toggleQuickActionBar()
              })

              Divider()
                .color($r('app.color.divider'))
                .strokeWidth(1)

              Row() {
                Text($r('app.string.note_folder_mode_enabled'))
                  .fontSize($r('app.float.body_font_size'))
                  .fontColor($r('app.color.primary_text'))
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.folderModeEnabled })
                  .selectedColor($r('app.color.accent'))
                  .hitTestBehavior(HitTestMode.None)
              }
              .width('100%')
              .padding({
                left: 20,
                right: 16,
                top: 14,
                bottom: 14
              })
              .justifyContent(FlexAlign.SpaceBetween)
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.toggleFolderMode()
              })

              Divider()
                .color($r('app.color.divider'))
                .strokeWidth(1)

              Row() {
                Text($r('app.string.app_lock_enabled'))
                  .fontSize($r('app.float.body_font_size'))
                  .fontColor($r('app.color.primary_text'))
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.appLockEnabled })
                  .selectedColor($r('app.color.accent'))
                  .hitTestBehavior(HitTestMode.None)
              }
              .width('100%')
              .padding({
                left: 20,
                right: 16,
                top: 14,
                bottom: 14
              })
              .justifyContent(FlexAlign.SpaceBetween)
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.toggleAppLock()
              })

              if (this.biometricAvailable) {
                Divider()
                  .color($r('app.color.divider'))
                  .strokeWidth(1)

                Row() {
                  Text(this.biometricLockLabel)
                    .fontSize($r('app.float.body_font_size'))
                    .fontColor($r('app.color.primary_text'))
                    .layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.biometricLockEnabled })
                    .selectedColor($r('app.color.accent'))
                    .hitTestBehavior(HitTestMode.None)
                }
                .width('100%')
                .padding({
                  left: 20,
                  right: 16,
                  top: 14,
                  bottom: 14
                })
                .justifyContent(FlexAlign.SpaceBetween)
                .alignItems(VerticalAlign.Center)
                .onClick(() => {
                  this.toggleBiometricLock()
                })
              }
            }
            .width('100%')
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

            Column({ space: 0 }) {
            Row() {
              Text($r('app.string.settings_cloud_sync'))
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text('›')
                .fontSize(22)
                .fontColor($r('app.color.tertiary_text'))
            }
            .width('100%')
            .padding({
              left: 20,
              right: 16,
              top: 14,
              bottom: 14
            })
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/CloudSyncSettings' }).catch((err: Error) => {
                console.error(`openCloudSyncSettings: ${JSON.stringify(err)}`)
              })
            })

            Divider()
              .color($r('app.color.divider'))
              .strokeWidth(1)

            Row() {
              Text($r('app.string.import_notes_title'))
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text('›')
                .fontSize(22)
                .fontColor($r('app.color.tertiary_text'))
            }
            .width('100%')
            .padding({
              left: 20,
              right: 16,
              top: 14,
              bottom: 14
            })
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/ImportNotes' }).catch((err: Error) => {
                console.error(`openImportNotes: ${JSON.stringify(err)}`)
              })
            })

            Divider()
              .color($r('app.color.divider'))
              .strokeWidth(1)

            Row() {
              Text($r('app.string.settings_language'))
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text('›')
                .fontSize(22)
                .fontColor($r('app.color.tertiary_text'))
            }
            .width('100%')
            .padding({
              left: 20,
              right: 16,
              top: 14,
              bottom: 14
            })
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/LanguageSettings' }).catch((err: Error) => {
                console.error(`openLanguageSettings: ${JSON.stringify(err)}`)
              })
            })

            Divider()
              .color($r('app.color.divider'))
              .strokeWidth(1)

            Row() {
              Text($r('app.string.feedback_title'))
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text('›')
                .fontSize(22)
                .fontColor($r('app.color.tertiary_text'))
            }
            .width('100%')
            .padding({
              left: 20,
              right: 16,
              top: 14,
              bottom: 14
            })
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({
                url: 'pages/H5WebContainer',
                params: {
                  title: LocaleService.loc('用户反馈', 'Feedback', 'フィードバック'),
                  url: 'https://vcnedpub4ekz.feishu.cn/share/base/form/shrcnexjZUlhIkZ4eD9BjcDfdkb'
                }
              }).catch((err: Error) => {
                console.error(`openFeedback: ${JSON.stringify(err)}`)
              })
            })
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({ width: 1, color: $r('app.color.card_border') })
          .shadow({
            radius: 20,
            color: $r('app.color.shadow_color'),
            offsetX: 0,
            offsetY: 4
          })

          Column({ space: 0 }) {
            if (this.showReferralInviteMenu && !this.guestMode && this.accountSubId.length > 0) {
              Row() {
                Text('邀请得会员')
                  .fontSize($r('app.float.body_font_size'))
                  .fontColor($r('app.color.primary_text'))
                  .layoutWeight(1)
                Text('›')
                  .fontSize(22)
                  .fontColor($r('app.color.tertiary_text'))
              }
              .width('100%')
              .padding({
                left: 20,
                right: 16,
                top: 14,
                bottom: 14
              })
              .justifyContent(FlexAlign.SpaceBetween)
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                void openReferralInviteSharePage(this.getUIContext())
              })

              Divider()
                .color($r('app.color.divider'))
                .strokeWidth(1)
            }

            Row() {
              Text($r('app.string.about_title'))
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text('›')
                .fontSize(22)
                .fontColor($r('app.color.tertiary_text'))
            }
            .width('100%')
            .padding({
              left: 20,
              right: 16,
              top: 14,
              bottom: 14
            })
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/About' }).catch((err: Error) => {
                console.error(`openAbout: ${JSON.stringify(err)}`)
              })
            })
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({ width: 1, color: $r('app.color.card_border') })
          .shadow({
            radius: 20,
            color: $r('app.color.shadow_color'),
            offsetX: 0,
            offsetY: 4
          })

          if (!this.guestMode) {
            Button() {
              Text($r('app.string.logout'))
                .fontColor(Color.White)
                .fontSize($r('app.float.body_font_size'))
                .fontWeight(FontWeight.Medium)
            }
              .type(ButtonType.Normal)
              .width('100%')
              .height(48)
              .backgroundColor($r('app.color.danger'))
              .borderRadius($r('app.float.pill_radius'))
              .margin({ top: 8 })
              .enabled(!this.loggingOut)
              .onClick((): void => {
                void this.handleLogout()
              })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
      .padding({ bottom: 15, top: 5 })
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: 16,
      right: 16
    })
    .backgroundColor($r('app.color.app_background'))

      if (this.loggingOut) {
        this.buildLogoutOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildLogoutOverlay() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color($r('app.color.accent'))
      Text($r('app.string.logout_in_progress'))
        .fontSize($r('app.float.body_font_size'))
        .fontColor(Color.White)
        .margin({ top: 16 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#B3000000')
  }
}
