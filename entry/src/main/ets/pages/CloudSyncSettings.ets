import { CryptoService } from '../services/CryptoService'
import { PreferencesService } from '../services/PreferencesService'
import { WebDAVClient } from '../services/WebDAVClient'
import type { SyncPolicy, WebDAVConfig, WebDAVProvider } from '../common/model/Note'
import type { QingyuCloudSubscriptionStatus } from '../common/model/QingyuCloudSubscription'
import { AppContextHolder } from '../services/AppContextHolder'
import { Logger } from '../common/utils/Logger'
import { buildQingyuCloudWebDavConfig } from '../services/QingyuCloudConfigHelper'

/** 与 `Login.ets` / `pushUrl` 参数一致，登录成功后 `router.back()` 返回云同步页 */
const LOGIN_RETURN_CLOUD_SYNC = 'cloudSync'

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
struct CloudSyncSettings {
  @State selectedProvider: WebDAVProvider = 'webdav'
  @State serverUrl: string = ''
  @State username: string = ''
  @State password: string = ''
  @State notesDir: string = '/qingyu-notes/'
  @State autoSync: boolean = true
  @State syncIntervalMinutes: string = '60'
  @State wifiOnly: boolean = false
  @State testing: boolean = false
  @State qingyuSubHint: string = ''
  @State qingyuSubShowRenew: boolean = false
  @State qingyuSubShowConfirm: boolean = false
  @State qingyuSubLoading: boolean = false
  @State qingyuSubButtonLabel: string = '立即续期'
  /** 与 Flutter `CloudSyncSettingPage` `_guestMode` 对齐 */
  @State guestMode: boolean = false
  private storedEncryptedPassword: string = ''
  private passwordTouched: boolean = false
  /** 页面是否仍在前台；异步回调返回前若已返回上一页则不再更新 @State，避免崩溃。 */
  private pageActive: boolean = false
  /** 防止连续快速返回导致多次 pop 或并发保存后返回。 */
  private closing: boolean = false
  /** 防止并发 handleSave（快速返回时后台保存与显式保存互斥）。 */
  private saveInFlight: boolean = false

  aboutToAppear(): void {
    this.pageActive = true
    this.closing = false
    void this.loadSettings()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.closing = true
  }

  /** 拦截系统返回键，与工具栏返回按钮共用单次关闭逻辑。 */
  onBackPress(): boolean {
    this.handleToolbarBack()
    return true
  }

  onPageShow(): void {
    void this.reloadGuestAndQingyuCard()
  }

  private isPageActive(): boolean {
    return this.pageActive
  }

  private async reloadGuestAndQingyuCard(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    if (!this.isPageActive()) {
      return
    }
    this.guestMode = await PreferencesService.getInstance().isGuestMode()
    if (!this.isPageActive()) {
      return
    }
    if (this.selectedProvider !== 'qingyu_cloud') {
      return
    }
    if (this.guestMode) {
      this.qingyuSubLoading = false
      return
    }
    await this.refreshQingyuSubscriptionCard()
  }

  private async loadSettings(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    if (!this.isPageActive()) {
      return
    }
    this.guestMode = await PreferencesService.getInstance().isGuestMode()
    const policy = await PreferencesService.getInstance().getSyncPolicy()
    const hasSavedCustom = await PreferencesService.getInstance().hasSavedCustomWebDAVConfig()
    if (!this.isPageActive()) {
      return
    }
    if (hasSavedCustom) {
      this.selectedProvider = 'webdav'
      const snap = await PreferencesService.getInstance().getSavedCustomWebDAVConfigSnapshot()
      if (snap !== null && snap.provider === 'webdav') {
        this.serverUrl = snap.baseUrl
        this.username = snap.username
        this.notesDir = snap.notesDir
        this.storedEncryptedPassword = snap.encryptedPassword
        this.password = ''
        this.passwordTouched = false
      }
    } else {
      this.selectedProvider = 'qingyu_cloud'
    }
    this.autoSync = policy.autoSync
    this.syncIntervalMinutes = `${policy.syncIntervalMinutes}`
    this.wifiOnly = policy.wifiOnly
    await this.refreshQingyuSubscriptionCard()
  }

  private async refreshQingyuSubscriptionCard(): Promise<void> {
    if (!this.isPageActive()) {
      return
    }
    if (this.selectedProvider !== 'qingyu_cloud') {
      return
    }
    if (this.guestMode) {
      this.qingyuSubLoading = false
      return
    }
    this.qingyuSubLoading = true
    try {
      // 与 Flutter `CloudSyncSettingPage` 一致：按账号拉订阅，避免本地仍为 WebDAV 时 intent=not_qingyu 导致卡片空白。
      const previewQingyu: WebDAVConfig = {
        baseUrl: '',
        username: '',
        encryptedPassword: '',
        notesDir: '/qingyu-notes/',
        enabled: true,
        provider: 'qingyu_cloud'
      }
      const status =
        await WebDAVClient.getInstance().fetchQingyuCloudSubscriptionStatus(previewQingyu)
      if (!this.isPageActive()) {
        return
      }
      this.applyQingyuSubscriptionStatus(status)
    } catch (error) {
      if (!this.isPageActive()) {
        return
      }
      Logger.warn('CloudSyncSettings', `refreshQingyuSubscriptionCard failed: ${this.describeError(error as Object)}`)
      this.qingyuSubHint = '暂时无法获取云服务状态'
      this.qingyuSubShowRenew = true
      this.qingyuSubShowConfirm = false
      this.qingyuSubButtonLabel = '立即续期'
    } finally {
      if (this.isPageActive()) {
        this.qingyuSubLoading = false
      }
    }
  }

  private applyQingyuSubscriptionStatus(status: QingyuCloudSubscriptionStatus): void {
    if (status.kind === 'need_note_api_session') {
      this.qingyuSubHint = '请先登录账号以使用轻羽云服务与支付'
      this.qingyuSubShowRenew = false
      this.qingyuSubShowConfirm = false
      return
    }
    if (status.kind === 'not_qingyu') {
      this.qingyuSubHint = ''
      this.qingyuSubShowRenew = false
      this.qingyuSubShowConfirm = false
      return
    }
    if (status.kind === 'lifetime') {
      this.qingyuSubHint = 'VIP用户可终身使用云服务'
      this.qingyuSubShowRenew = false
      this.qingyuSubShowConfirm = true
      return
    }
    if (status.kind === 'expired') {
      this.qingyuSubHint = '云服务已过期'
      this.qingyuSubShowRenew = true
      this.qingyuSubShowConfirm = false
      this.qingyuSubButtonLabel = '立即续期'
      return
    }
    if (status.kind === 'active') {
      this.qingyuSubHint = `云服务有效期至：${status.expiresDisplayYmd}`
      this.qingyuSubShowRenew = true
      this.qingyuSubShowConfirm = true
      this.qingyuSubButtonLabel = '立即续期'
      return
    }
    if (status.kind === 'not_purchased' || status.kind === 'not_configured') {
      this.qingyuSubHint = '暂未开通轻羽云服务'
      this.qingyuSubShowRenew = true
      this.qingyuSubShowConfirm = false
      this.qingyuSubButtonLabel = '前往开通'
      return
    }
    if (status.kind === 'fetch_failed') {
      this.qingyuSubHint = '暂时无法获取云服务状态'
      this.qingyuSubShowRenew = true
      this.qingyuSubShowConfirm = false
      this.qingyuSubButtonLabel = '立即续期'
      return
    }
    if (status.kind === 'malformed') {
      this.qingyuSubHint = '暂未开通轻羽云服务'
      this.qingyuSubShowRenew = true
      this.qingyuSubShowConfirm = false
      this.qingyuSubButtonLabel = '前往开通'
      return
    }
    this.qingyuSubHint = ''
    this.qingyuSubShowRenew = false
    this.qingyuSubShowConfirm = false
  }


  private async buildConfigPayload(skipRemoteQingyuFetch: boolean = false): Promise<SettingsPayload> {
    if (this.selectedProvider === 'qingyu_cloud') {
      return await this.buildQingyuPayload(skipRemoteQingyuFetch)
    }
    return await this.buildWebDAVPayload()
  }

  private async buildWebDAVPayload(): Promise<SettingsPayload> {
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
    const config: WebDAVConfig = {
      baseUrl,
      username,
      encryptedPassword,
      notesDir,
      enabled: baseUrl.length > 0 && username.length > 0 && effectivePasswordPresent,
      provider: 'webdav'
    }
    const policy: SyncPolicy = {
      autoSync: this.autoSync,
      syncIntervalMinutes: Number.parseInt(this.syncIntervalMinutes, 10) || 60,
      wifiOnly: this.wifiOnly,
      debounceSeconds: 5
    }
    const payload: SettingsPayload = {
      config,
      policy,
      reusedStoredPassword: shouldReuseStoredPassword,
      effectivePasswordPresent
    }
    return payload
  }

  private buildQingyuIntentOnlyPayload(policy: SyncPolicy): SettingsPayload {
    return {
      config: {
        baseUrl: '',
        username: '',
        encryptedPassword: '',
        notesDir: this.notesDir.length > 0 ? this.notesDir : '/qingyu-notes/',
        enabled: true,
        provider: 'qingyu_cloud'
      },
      policy,
      reusedStoredPassword: false,
      effectivePasswordPresent: false
    }
  }

  private async buildQingyuPayload(skipRemoteQingyuFetch: boolean = false): Promise<SettingsPayload> {
    const policy: SyncPolicy = {
      autoSync: this.autoSync,
      syncIntervalMinutes: Number.parseInt(this.syncIntervalMinutes, 10) || 60,
      wifiOnly: this.wifiOnly,
      debounceSeconds: 5
    }
    if (skipRemoteQingyuFetch) {
      return this.buildQingyuIntentOnlyPayload(policy)
    }
    const cfg = await buildQingyuCloudWebDavConfig()
    if (cfg === null) {
      Logger.warn('CloudSyncSettings',
        'buildQingyuPayload: GET /qingyu/webdav failed or timed out — still persist intent to use 轻羽云 (enabled=true)')
      return {
        config: {
          baseUrl: '',
          username: '',
          encryptedPassword: '',
          notesDir: this.notesDir.length > 0 ? this.notesDir : '/qingyu-notes/',
          enabled: true,
          provider: 'qingyu_cloud'
        },
        policy,
        reusedStoredPassword: false,
        effectivePasswordPresent: false
      }
    }
    Logger.info('CloudSyncSettings', `buildQingyuPayload: enabled=${cfg.enabled}, notesDir=${cfg.notesDir}`)
    return {
      config: cfg,
      policy,
      reusedStoredPassword: false,
      effectivePasswordPresent: cfg.encryptedPassword.length > 0
    }
  }

  private async openLoginFromCloudSync(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    await PreferencesService.getInstance().setLoginReturnTarget(LOGIN_RETURN_CLOUD_SYNC)
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/Login',
        params: { returnAfterLogin: LOGIN_RETURN_CLOUD_SYNC }
      })
    } catch (error) {
      Logger.warn('CloudSyncSettings',
        `openLoginFromCloudSync failed: ${this.describeError(error as Object)}`)
    }
  }

  private async handleSave(skipRemoteQingyuFetch: boolean = false): Promise<SettingsPayload> {
    if (this.saveInFlight) {
      Logger.warn('CloudSyncSettings', 'handleSave skipped: save already in flight')
      throw new Error('save already in flight')
    }
    this.saveInFlight = true
    Logger.info('CloudSyncSettings',
      `handleSave start: provider=${this.selectedProvider}, serverUrlEmpty=${this.serverUrl.trim().length === 0}, skipRemote=${skipRemoteQingyuFetch}`)
    try {
      const payload = await this.buildConfigPayload(skipRemoteQingyuFetch)
      if (payload.config.provider === 'qingyu_cloud' && await PreferencesService.getInstance().isGuestMode()) {
        this.showUserMessage('请先登录后再保存轻羽云同步')
        return payload
      }
      await PreferencesService.getInstance().saveSyncPolicy(payload.policy)
      await PreferencesService.getInstance().saveSyncProvider(this.selectedProvider)
      if (payload.config.provider === 'qingyu_cloud' && !payload.config.enabled) {
        Logger.warn('CloudSyncSettings', 'handleSave: qingyu_cloud with enabled=false (user turned off sync)')
        this.showUserMessage('轻羽云同步已关闭')
        await PreferencesService.getInstance().saveWebDAVConfig(payload.config)
        await PreferencesService.getInstance().setAuthInvalid(false)
        return payload
      }
      await PreferencesService.getInstance().saveWebDAVConfig(payload.config)
      await PreferencesService.getInstance().setAuthInvalid(false)
      if (payload.config.provider === 'webdav') {
        this.storedEncryptedPassword = payload.config.encryptedPassword
        this.passwordTouched = false
      }
      Logger.info('CloudSyncSettings',
        `handleSave success: enabled=${payload.config.enabled}, provider=${payload.config.provider}`)
      if (payload.config.provider === 'qingyu_cloud' && payload.config.enabled) {
        void this.refreshQingyuSubscriptionCard()
      }
      return payload
    } catch (error) {
      Logger.warn('CloudSyncSettings', `handleSave failed: ${this.describeError(error)}`)
      throw this.toRuntimeError(error)
    } finally {
      this.saveInFlight = false
    }
  }

  private tryBeginClose(): boolean {
    if (this.closing) {
      return false
    }
    this.closing = true
    this.pageActive = false
    return true
  }

  private popOnce(): void {
    try {
      this.getUIContext().getRouter().back()
    } catch (error) {
      Logger.warn('CloudSyncSettings', `popOnce failed: ${this.describeError(error as Object)}`)
    }
  }

  private handleToolbarBack(): void {
    if (!this.tryBeginClose()) {
      return
    }
    // 先 pop，避免等待 GET /qingyu/webdav 期间连按返回触发多次 router.back() → ExitToDesktop。
    this.popOnce()
    if (this.selectedProvider === 'qingyu_cloud') {
      void this.persistSettingsAfterLeave(true)
    }
  }

  /** 页面已关闭后在后台持久化；轻羽云返回时不阻塞等待远程 WebDAV 凭据。 */
  private async persistSettingsAfterLeave(skipRemoteQingyuFetch: boolean): Promise<void> {
    try {
      await this.handleSave(skipRemoteQingyuFetch)
    } catch (error) {
      Logger.warn('CloudSyncSettings',
        `persistSettingsAfterLeave failed: ${this.describeError(error)}`)
    }
  }

  private async handleSaveAndClose(): Promise<void> {
    if (!this.tryBeginClose()) {
      return
    }
    try {
      await this.handleSave(false)
    } catch (error) {
      Logger.warn('CloudSyncSettings', `handleSaveAndClose failed: ${this.describeError(error)}`)
      this.closing = false
      this.pageActive = true
      this.showUserMessage('保存失败，请稍后重试')
      return
    }
    this.popOnce()
  }

  /** 轻羽云订阅可用时，将当前选项保存为使用轻羽云同步（无需依赖底部其它保存入口）。 */
  private async handleConfirmQingyuService(): Promise<void> {
    try {
      const payload = await this.handleSave()
      if (!this.isPageActive()) {
        return
      }
      if (payload.config.provider === 'qingyu_cloud' && payload.config.enabled) {
        this.showUserMessage('已使用轻羽云作为同步服务')
      }
    } catch (error) {
      Logger.warn('CloudSyncSettings', `handleConfirmQingyuService failed: ${this.describeError(error)}`)
      this.showUserMessage('保存失败，请稍后重试')
    }
  }

  private showUserMessage(message: string): void {
    if (message.trim().length === 0 || !this.isPageActive()) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message,
        duration: 2000
      })
    } catch (error) {
      Logger.warn('CloudSyncSettings', `showToast failed: ${this.describeError(error as Object)}`)
    }
  }

  private async handleTestConnection(): Promise<void> {
    if (!this.isPageActive()) {
      return
    }
    this.testing = true
    Logger.info('CloudSyncSettings', 'handleTestConnection start')
    try {
      const payload = await this.handleSave()
      if (!this.isPageActive()) {
        return
      }
      if (!payload.config.enabled) {
        if (this.selectedProvider === 'qingyu_cloud') {
          this.showUserMessage('轻羽云同步未开启或暂时无法获取连接信息，请稍后重试')
        } else {
          this.showUserMessage('请先输入完整的 WebDAV 信息后再测试连接')
        }
        Logger.warn('CloudSyncSettings',
          `handleTestConnection aborted: incomplete config, effectivePasswordPresent=${payload.effectivePasswordPresent}`)
        return
      }
      Logger.info('CloudSyncSettings', 'handleTestConnection save completed, invoking WebDAVClient.testConnection')
      const success = await WebDAVClient.getInstance().testConnection()
      if (!this.isPageActive()) {
        return
      }
      Logger.info('CloudSyncSettings', `handleTestConnection result: success=${success}`)
      this.showUserMessage(success ? '连接测试成功' : '连接测试失败')
      if (success && this.selectedProvider === 'qingyu_cloud') {
        void this.refreshQingyuSubscriptionCard()
      }
    } catch (error) {
      Logger.warn('CloudSyncSettings', `handleTestConnection failed: ${this.describeError(error)}`)
      if (this.isCredentialDecryptFailure(error)) {
        this.showUserMessage('本地保存的 WebDAV 密码无效，请重新输入后重试')
      } else {
        this.showUserMessage('连接测试失败')
      }
    } finally {
      if (this.isPageActive()) {
        this.testing = false
        Logger.info('CloudSyncSettings', `handleTestConnection finish: testing=${this.testing}`)
      }
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

  @Builder
  private buildProviderRadioRow() {
    Column({ space: 10 }) {
      this.buildSectionTitle($r('app.string.settings_sync_provider_title'))
      Row({ space: 20 }) {
        Row({ space: 8 }) {
          Radio({ value: 'qingyu_cloud', group: 'sync_provider_pick' })
            .checked(this.selectedProvider === 'qingyu_cloud')
            .onChange((checked: boolean) => {
              if (checked) {
                this.selectedProvider = 'qingyu_cloud'
                void this.refreshQingyuSubscriptionCard()
              }
            })
          Text('轻羽云')
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.primary_text'))
        }

        Row({ space: 8 }) {
          Radio({ value: 'webdav', group: 'sync_provider_pick' })
            .checked(this.selectedProvider === 'webdav')
            .onChange((checked: boolean) => {
              if (checked) {
                this.selectedProvider = 'webdav'
              }
            })
          Text($r('app.string.settings_sync_provider_webdav'))
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.primary_text'))
        }
      }
      .width('100%')
    }
    .width('100%')
  }

  build() {
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
          Text($r('app.string.settings_cloud_sync'))
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
            this.buildProviderRadioRow()
          }
          .padding(20)
          .margin({ bottom: 10 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({ width: 1, color: $r('app.color.card_border') })
          .shadow({
            radius: 20,
            color: $r('app.color.shadow_color'),
            offsetX: 0,
            offsetY: 4
          })

          if (this.selectedProvider === 'webdav') {
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
            .margin({ bottom: 10 })
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

          if (this.selectedProvider === 'qingyu_cloud') {
            if (this.guestMode) {
              Column({ space: 14 }) {
                this.buildSectionTitle($r('app.string.settings_qingyu_title'))

                Row() {
                  Blank().layoutWeight(1)
                  Button('登录')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.on_accent'))
                    .backgroundColor($r('app.color.accent'))
                    .borderRadius($r('app.float.pill_radius'))
                    .padding({
                      left: 28,
                      right: 28,
                      top: 12,
                      bottom: 12
                    })
                    .onClick(() => {
                      void this.openLoginFromCloudSync()
                    })
                  Blank().layoutWeight(1)
                }
                .width('100%')
              }
              .padding(20)
              .margin({ bottom: 10 })
              .backgroundColor($r('app.color.card_background'))
              .borderRadius($r('app.float.card_radius'))
              .border({ width: 1, color: $r('app.color.card_border') })
              .shadow({
                radius: 20,
                color: $r('app.color.shadow_color'),
                offsetX: 0,
                offsetY: 4
              })
            } else {
              Column({ space: 14 }) {
                this.buildSectionTitle($r('app.string.settings_qingyu_title'))

                Text(this.qingyuSubLoading ? '加载中…' : this.qingyuSubHint)
                  .fontSize(12)
                  .fontColor($r('app.color.tertiary_text'))
                  .width('100%')

                if (this.qingyuSubShowRenew || this.qingyuSubShowConfirm) {
                  Row({ space: 10 }) {
                    if (this.qingyuSubShowRenew) {
                      Button(this.qingyuSubButtonLabel)
                        .layoutWeight(1)
                        .fontSize($r('app.float.caption_font_size'))
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.qingyuSubShowConfirm ? $r('app.color.primary_text') : $r('app.color.on_accent'))
                        .backgroundColor(this.qingyuSubShowConfirm ? $r('app.color.surface_muted') :
                        $r('app.color.accent'))
                        .borderRadius($r('app.float.pill_radius'))
                        .padding({ top: 12, bottom: 12 })
                        .onClick(() => {
                          this.getUIContext().getRouter().pushUrl({ url: 'pages/QingyuCloudRecharge' }).catch((err: Error) => {
                            console.error(`openQingyuCloudRecharge: ${JSON.stringify(err)}`)
                          })
                        })
                    }
                    if (this.qingyuSubShowConfirm) {
                      Button('确定')
                        .layoutWeight(1)
                        .fontSize($r('app.float.caption_font_size'))
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.on_accent'))
                        .backgroundColor($r('app.color.accent'))
                        .borderRadius($r('app.float.pill_radius'))
                        .padding({ top: 12, bottom: 12 })
                        .onClick(() => {
                          void this.handleConfirmQingyuService()
                        })
                    }
                  }
                  .width('100%')
                }
              }
              .padding(20)
              .margin({ bottom: 10 })
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
          }

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
    .padding({
      left: 16,
      right: 16
    })
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
