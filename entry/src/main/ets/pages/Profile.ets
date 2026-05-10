import type common from '@ohos.app.ability.common'
import { ComponentContent } from '@kit.ArkUI'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import fs from '@ohos.file.fs'
import {
  PROFILE_ACCOUNT_BIND_SUPPORTED_APPLE,
  PROFILE_ACCOUNT_BIND_SUPPORTED_HUAWEI,
  PROFILE_ACCOUNT_BIND_SUPPORTED_WECHAT
} from '../common/constants/ProfileAccountBindConstants'
import { WECHAT_APP_ID } from '../common/constants/WeChatConstants'
import { AppContextHolder } from '../services/AppContextHolder'
import { obtainHuaweiAuthorizationCode, describeHuaweiLoginError } from '../services/HuaweiAuthService'
import {
  MergeAccountResponseBody,
  NoteApiClient,
  type ProfileBody
} from '../services/NoteApiClient'
import {
  setWeChatOAuthIntent,
  startWeChatLogin,
  WECHAT_LOGIN_RESULT_EVENT,
  WeChatLoginResultPayload,
  wxApi
} from '../services/WeChatAuthService'
import { PreferencesService } from '../services/PreferencesService'
import { Logger } from '../common/utils/Logger'
import {
  buildProfileTextEditDialogContent,
  type ProfileTextEditDialogParams
} from '../dialogs/ProfileTextEditDialog'
import {
  AVATAR_CROP_RESULT_EVENT,
  AvatarCropEmitCancel,
  AvatarCropEmitPath
} from '../common/constants/AvatarCropConstants'

/** getUIContext().getRouter() 在部分 SDK 上带有清空页面栈的扩展 */
interface RouterWithOptionalClear {
  clear?: () => void
}

@Entry
@Component
struct Profile {
  @State loading: boolean = true
  @State loadError: string = ''
  @State avatarUploading: boolean = false
  /** 网络头像加载失败（含明文 HTTP 被拦截）时回退到首字母占位 */
  @State avatarNetworkLoadFailed: boolean = false
  @State profile: ProfileBody | null = null
  /** 登录会话写入的 Note API `users.id`，用于「第 xx 名用户」。 */
  @State noteApiUserId: string = ''
  /** 正在拉起 OAuth（华为同步 / 微信异步回调），用于禁用行重复点击。 */
  @State bindBusy: boolean = false
  /** 仅在个人信息发起微信绑定时为 true，用于过滤 EventHub 中与登录页无关的事件。 */
  private expectingWeChatBind: boolean = false

  private weChatBindResultCallback = (payload: Object): void => {
    if (!this.expectingWeChatBind) {
      return
    }
    this.expectingWeChatBind = false
    this.bindBusy = false
    const data = payload as WeChatLoginResultPayload
    if (!data.success) {
      const msg =
        data.errStr ??
        (data.errCode !== undefined ? `授权失败（${data.errCode}）` : '微信绑定未完成')
      this.showToast(msg)
      return
    }
    if (data.mergeResult !== undefined) {
      this.showToast(this.describeMergeOutcome(data.mergeResult, '微信'))
      void this.reload()
    }
  }

  aboutToAppear(): void {
    void this.bootstrap()
    try {
      AppContextHolder.getContext().eventHub.on(WECHAT_LOGIN_RESULT_EVENT, this.weChatBindResultCallback)
    } catch (e) {
      Logger.warn('Profile', `eventHub.on wechat bind failed: ${JSON.stringify(e)}`)
    }
  }

  aboutToDisappear(): void {
    try {
      AppContextHolder.getContext().eventHub.off(WECHAT_LOGIN_RESULT_EVENT, this.weChatBindResultCallback)
    } catch (e) {
      Logger.warn('Profile', `eventHub.off wechat bind failed: ${JSON.stringify(e)}`)
    }
  }

  private async bootstrap(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context !== undefined) {
      await PreferencesService.getInstance().init(context)
    }
    await this.reload()
  }

  private async reload(): Promise<void> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      this.loading = false
      this.loadError = '请先登录'
      this.profile = null
      this.noteApiUserId = ''
      this.avatarNetworkLoadFailed = false
      return
    }
    this.loading = true
    this.loadError = ''
    const p = await NoteApiClient.getInstance().fetchProfile()
    const uid = (await PreferencesService.getInstance().getNoteApiUserId()).trim()
    this.loading = false
    if (p === null) {
      this.loadError = '无法加载个人信息'
      this.profile = null
      this.noteApiUserId = uid
      this.avatarNetworkLoadFailed = false
      return
    }
    this.avatarNetworkLoadFailed = false
    this.profile = p
    this.noteApiUserId = uid
  }

  private membershipTitle(p: ProfileBody): string {
    if (p.membership_is_lifetime === true) {
      return '轻羽云尊贵会员'
    }
    const st = (p.membership_level ?? '').trim()
    if (st === 'active' || st === 'lifetime') {
      return '轻羽云会员'
    }
    if (st === 'expired') {
      return '会员（已过期）'
    }
    return '轻羽云服务'
  }

  private isLifetimeVip(p: ProfileBody): boolean {
    if (p.membership_is_lifetime === true) {
      return true
    }
    return (p.membership_level ?? '').trim() === 'lifetime'
  }

  private membershipRight(p: ProfileBody): string {
    if (this.isLifetimeVip(p)) {
      return '终身VIP'
    }
    const st = (p.membership_level ?? '').trim()
    if (st === 'active') {
      const exp = (p.membership_expires_at ?? '').trim()
      return exp.length > 0 ? exp : '生效中'
    }
    if (st === 'expired') {
      const exp = (p.membership_expires_at ?? '').trim()
      return exp.length > 0 ? exp : '—'
    }
    return '未开通'
  }

  private bindLabel(on: boolean | undefined): string {
    return on === true ? '已绑定' : '未绑定'
  }

  private obtainUiAbilityContext(): common.UIAbilityContext | undefined {
    const host = this.getUIContext().getHostContext()
    return host as common.UIAbilityContext
  }

  /** 未绑定且平台支持绑定且未在拉起 OAuth 时可点并展示 ›。 */
  private thirdPartyRowInteractive(supported: boolean, linked: boolean | undefined): boolean {
    return supported && linked !== true && !this.bindBusy
  }

  /** 与 `›` 列同宽，无箭头行用占位保证右侧文案右缘与其它行对齐（略窄于字形框即可，过大则右侧文案整体偏左） */
  private static readonly PROFILE_KV_TRAILING_CHEVRON_WIDTH_VP: number = 14
  /** 右侧文案与 `›`/占位之间的间距 */
  private static readonly PROFILE_KV_VALUE_TO_TRAILING_GAP_VP: number = 2

  private describeMergeOutcome(body: MergeAccountResponseBody, platformShortName: string): string {
    const action = (body.action ?? '').trim()
    switch (action) {
      case 'linked':
        return `${platformShortName}账号已绑定`
      case 'noop':
        return '该身份已关联当前账号'
      case 'merged':
        return '已将该第三方账号关联的用户数据合并到当前账号'
      default:
        return '绑定完成'
    }
  }

  private async onTapBindHuawei(): Promise<void> {
    if (this.profile === null || !PROFILE_ACCOUNT_BIND_SUPPORTED_HUAWEI) {
      return
    }
    if (this.profile.huawei_linked === true || this.bindBusy) {
      return
    }
    const ctx = this.obtainUiAbilityContext()
    if (ctx === undefined) {
      this.showToast('无法获取界面上下文')
      return
    }
    this.bindBusy = true
    try {
      const code = await obtainHuaweiAuthorizationCode(ctx)
      const merged = await NoteApiClient.getInstance().mergeAccountWithHuaweiAuthorizationCode(code)
      if (merged === null || merged.ok !== true) {
        this.showToast('绑定失败，请稍后重试')
        return
      }
      await PreferencesService.getInstance().setHuaweiLoggedIn(true)
      this.showToast(this.describeMergeOutcome(merged, '华为'))
      await this.reload()
    } catch (error) {
      this.showToast(describeHuaweiLoginError(error as Object))
    } finally {
      this.bindBusy = false
    }
  }

  private async onTapBindWeChat(): Promise<void> {
    if (this.profile === null || !PROFILE_ACCOUNT_BIND_SUPPORTED_WECHAT) {
      return
    }
    if (this.profile.wechat_linked === true || this.bindBusy) {
      return
    }
    const wid = WECHAT_APP_ID.trim()
    if (wid.length === 0 || wid === 'wx0000000000000000') {
      this.showToast('请在 WeChatConstants 中配置微信开放平台移动应用 AppID')
      return
    }
    if (!wxApi.isWXAppInstalled()) {
      this.showToast('未安装微信，请先安装微信客户端')
      return
    }
    const ctx = this.obtainUiAbilityContext()
    if (ctx === undefined) {
      this.showToast('无法获取界面上下文')
      return
    }
    this.expectingWeChatBind = true
    this.bindBusy = true
    setWeChatOAuthIntent('profile_merge')
    try {
      await startWeChatLogin(ctx)
    } catch (error) {
      this.expectingWeChatBind = false
      this.bindBusy = false
      setWeChatOAuthIntent('login')
      Logger.warn('Profile', `startWeChatLogin bind: ${JSON.stringify(error)}`)
      this.showToast('无法拉起微信，请稍后重试')
    }
  }

  /** 注册时间仅展示年月日（本地日历日）。 */
  private formatRegisteredYmd(raw: string): string {
    const t = raw.trim()
    if (t.length === 0) {
      return '—'
    }
    const ms = Date.parse(t)
    if (Number.isNaN(ms)) {
      if (t.length >= 10) {
        const head = t.substring(0, 10)
        if (/^\d{4}-\d{2}-\d{2}$/.test(head)) {
          return head
        }
      }
      return t
    }
    const d = new Date(ms)
    const y = d.getFullYear()
    const m = String(d.getMonth() + 1).padStart(2, '0')
    const day = String(d.getDate()).padStart(2, '0')
    return `${y}-${m}-${day}`
  }

  private regLine(): string {
    if (this.profile === null) {
      return '—'
    }
    return this.formatRegisteredYmd(this.profile.registered_at ?? '')
  }

  private userSequenceLine(): string {
    const id = this.noteApiUserId.trim()
    if (id.length === 0) {
      return '—'
    }
    return `第${id}名用户`
  }

  private displayNickname(): string {
    if (this.profile === null) {
      return '未设置'
    }
    const u = (this.profile.username ?? '').trim()
    return u.length > 0 ? u : '未设置'
  }

  private displayPhone(): string {
    if (this.profile === null) {
      return '未绑定'
    }
    const u = (this.profile.phone ?? '').trim()
    return u.length > 0 ? u : '未绑定'
  }

  private async pickAndUploadAvatar(): Promise<void> {
    if (this.profile === null || this.avatarUploading) {
      return
    }
    try {
      const photoSelectOptions: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions()
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      photoSelectOptions.maxSelectNumber = 1
      const photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker()
      const result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(photoSelectOptions)
      const uri: string = result.photoUris[0] ?? ''
      if (uri.length === 0) {
        return
      }
      const hub = AppContextHolder.getContext().eventHub
      const once = (data: Object): void => {
        hub.off(AVATAR_CROP_RESULT_EVENT, once)
        if (data instanceof AvatarCropEmitCancel) {
          return
        }
        if (data instanceof AvatarCropEmitPath) {
          const p = data.path.trim()
          if (p.length > 0) {
            void this.finishAvatarUploadAfterCrop(p)
          }
        }
      }
      hub.on(AVATAR_CROP_RESULT_EVENT, once)
      try {
        await this.getUIContext().getRouter().pushUrl({
          url: 'pages/AvatarCrop',
          params: { uri: uri }
        })
      } catch (e) {
        hub.off(AVATAR_CROP_RESULT_EVENT, once)
        Logger.warn('Profile', `push AvatarCrop failed: ${JSON.stringify(e)}`)
        this.showToast('无法打开裁剪页')
      }
    } catch (error) {
      this.avatarUploading = false
      Logger.warn('Profile', `pickAndUploadAvatar failed: ${JSON.stringify(error)}`)
      this.showToast('选择或上传失败')
    }
  }

  /** 裁剪页已产出 JPEG（并完成体积压缩）后再上传 */
  private async finishAvatarUploadAfterCrop(croppedPath: string): Promise<void> {
    this.avatarUploading = true
    try {
      const err = await NoteApiClient.getInstance().uploadAvatar(croppedPath)
      if (err !== null) {
        this.showToast(this.mapErr(err))
        return
      }
      this.showToast('头像已更新')
      await this.reload()
    } finally {
      this.avatarUploading = false
      try {
        fs.unlinkSync(croppedPath)
      } catch (_) {
        // ignore
      }
    }
  }

  private avatarUrlTrim(): string {
    if (this.profile === null) {
      return ''
    }
    return (this.profile.avatar_url ?? '').trim()
  }

  private avatarInitial(): string {
    const u = (this.profile?.username ?? '').trim()
    if (u.length > 0) {
      return u.substring(0, 1).toUpperCase()
    }
    return '?'
  }

  private showToast(message: string): void {
    if (message.trim().length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message, duration: 2000 })
    } catch (e) {
      Logger.warn('Profile', `showToast failed: ${JSON.stringify(e)}`)
    }
  }

  private mapErr(code: string): string {
    switch (code) {
      case 'old_password_invalid':
        return '原密码不正确'
      case 'old_password_required':
        return '请输入原密码'
      case 'password_not_set':
        return '尚未设置密码'
      case 'password_too_short':
        return '新密码至少 8 位'
      case 'qingyu_folder_delete_failed':
        return '云盘目录删除失败，请稍后重试'
      case 'not_logged_in':
        return '未登录'
      case 'network_error':
        return '网络异常'
      case 'avatar_webdav_not_configured':
        return '头像服务未配置'
      case 'avatar_upload_failed':
        return '头像存储失败，请稍后重试'
      case 'avatar_webdav_unauthorized':
        return '头像存储失败'
      case 'avatar_webdav_forbidden':
        return '头像目录无写入权限'
      case 'avatar_webdav_not_found':
        return '头像存储路径不存在或 URL 配置错误'
      case 'avatar_webdav_method_not_allowed':
        return '存储服务不允许上传（WebDAV PUT 未开启）'
      case 'avatar_webdav_insufficient_storage':
        return '存储空间不足'
      case 'avatar_webdav_upstream_error':
        return '头像存储服务暂时不可用（NAS 或反代异常）'
      case 'invalid_image_type':
        return '请选择 JPG / PNG / GIF / WebP 图片'
      case 'file_too_large':
        return '图片过大（最多 5MB）'
      case 'gateway_body_too_large':
        return '请选用较小的图片'
      case 'empty_file':
      case 'file_required':
        return '请选择有效图片'
      case 'invalid_multipart':
        return '上传格式无效'
      case 'redemption_invalid':
        return '兑换码无效或已使用'
      case 'invalid_code':
      case 'invalid_body':
        return '兑换码格式无效'
      case 'db_failed':
        return '服务暂时不可用'
      default:
        return `操作失败（${code}）`
    }
  }

  private closeTextEditDialog(content: ComponentContent<ProfileTextEditDialogParams> | undefined): void {
    if (content === undefined) {
      return
    }
    try {
      this.getUIContext().getPromptAction().closeCustomDialog(content)
    } catch (e) {
      Logger.warn('Profile', `closeCustomDialog failed: ${JSON.stringify(e)}`)
    }
  }

  private openRedeemDialog(): void {
    const ui = this.getUIContext()
    let holder: ComponentContent<ProfileTextEditDialogParams> | undefined = undefined
    const params: ProfileTextEditDialogParams = {
      title: '兑换轻羽云服务',
      initial: '',
      placeholder: '请输入兑换码',
      confirmButtonLabel: '确定兑换',
      onCancel: (): void => {
        this.closeTextEditDialog(holder)
      },
      onConfirm: (text: string): void => {
        this.closeTextEditDialog(holder)
        void this.submitRedeem(text)
      }
    }
    holder = new ComponentContent(ui, wrapBuilder(buildProfileTextEditDialogContent), params)
    try {
      ui.getPromptAction().openCustomDialog(holder, {
        alignment: DialogAlignment.Center,
        autoCancel: true
      })
    } catch (e) {
      Logger.warn('Profile', `openRedeemDialog failed: ${JSON.stringify(e)}`)
    }
  }

  private async submitRedeem(code: string): Promise<void> {
    const trimmed = code.trim()
    if (trimmed.length === 0) {
      this.showToast('请输入兑换码')
      return
    }
    const r = await NoteApiClient.getInstance().redeemCode(trimmed)
    if (r === null) {
      this.showToast('网络异常，请稍后重试')
      return
    }
    if (typeof r === 'string') {
      this.showToast(this.mapErr(r))
      return
    }
    const planId = (r.plan_id ?? '').trim()
    const msg = this.redeemSuccessMessage(planId)
    try {
      await this.getUIContext().getPromptAction().showDialog({
        title: '兑换成功',
        message: msg,
        buttons: [{ text: '好的', color: '#2563EB' }]
      })
    } catch (e) {
      Logger.warn('Profile', `redeem success dialog: ${JSON.stringify(e)}`)
    }
    await this.reload()
  }

  private redeemSuccessMessage(planId: string): string {
    switch (planId) {
      case 'monthly':
        return '已获赠轻羽云服务月卡权益'
      case 'half_year':
        return '已获赠轻羽云服务半年卡权益'
      case 'yearly':
        return '已获赠轻羽云服务年卡权益'
      case 'lifetime_vip':
        return '已获赠终身 VIP 权益'
      default:
        return '兑换成功，权益已生效'
    }
  }

  private openTextEdit(title: string, fieldKey: string, initial: string): void {
    const ui = this.getUIContext()
    let holder: ComponentContent<ProfileTextEditDialogParams> | undefined = undefined
    const params: ProfileTextEditDialogParams = {
      title,
      initial,
      placeholder: '留空可清空',
      onCancel: (): void => {
        this.closeTextEditDialog(holder)
      },
      onConfirm: (text: string): void => {
        this.closeTextEditDialog(holder)
        void this.patchSingleField(fieldKey, text)
      }
    }
    holder = new ComponentContent(ui, wrapBuilder(buildProfileTextEditDialogContent), params)
    try {
      ui.getPromptAction().openCustomDialog(holder, {
        alignment: DialogAlignment.Center,
        autoCancel: true
      })
    } catch (e) {
      Logger.warn('Profile', `openTextEdit dialog failed: ${JSON.stringify(e)}`)
    }
  }

  private async patchSingleField(fieldKey: string, value: string): Promise<void> {
    const body: Record<string, Object> = {}
    body[fieldKey] = value.trim()
    const err = await NoteApiClient.getInstance().patchProfile(body)
    if (err !== null) {
      this.showToast(this.mapErr(err))
      return
    }
    this.showToast('已保存')
    await this.reload()
  }

  private async confirmDelete(): Promise<void> {
    const p = this.profile
    if (p === null) {
      return
    }
    let msg =
      '注销后将永久删除账号资料与云端笔记目录，且无法恢复。'
    if (p.qingyu_subscription_active === true) {
      msg +=
        '您当前轻羽云服务仍在有效期内：注销即视为放弃剩余会员权益，云盘数据一并删除且不可找回。'
    }
    try {
      const r1 = await this.getUIContext().getPromptAction().showDialog({
        title: '注销账号',
        message: msg,
        buttons: [
          { text: '取消', color: '#6B7280' },
          { text: '继续', color: '#E53935' }
        ]
      })
      if (r1.index !== 1) {
        return
      }
      const r2 = await this.getUIContext().getPromptAction().showDialog({
        title: '最后确认',
        message: '确定要注销账号吗？此操作不可撤销。',
        buttons: [
          { text: '取消', color: '#6B7280' },
          { text: '确认注销', color: '#E53935' }
        ]
      })
      if (r2.index !== 1) {
        return
      }
    } catch (e) {
      Logger.warn('Profile', `delete dialog failed: ${JSON.stringify(e)}`)
      return
    }

    const err = await NoteApiClient.getInstance().deleteAccount()
    if (err !== null) {
      this.showToast(this.mapErr(err))
      return
    }
    try {
      const context = AppContextHolder.tryGetContext()
      if (context !== undefined) {
        await PreferencesService.getInstance().init(context)
      }
      await PreferencesService.getInstance().clearLoginSession()
      const router = this.getUIContext().getRouter()
      const routerWithClear = router as RouterWithOptionalClear
      if (routerWithClear.clear !== undefined) {
        routerWithClear.clear()
      }
      await router.replaceUrl({ url: 'pages/Login' })
    } catch (error) {
      Logger.warn('Profile', `after delete navigate failed: ${JSON.stringify(error)}`)
      this.showToast('已注销，请重新打开应用')
    }
  }

  @Builder
  groupGap() {
    Column()
      .width('100%')
      .height(8)
  }

  @Builder
  rowDivider() {
    Divider()
      .color($r('app.color.divider'))
      .strokeWidth(1)
      .margin({ left: 16 })
  }

  @Builder
  dangerNavRow(onRowClick: () => void) {
    Row() {
      Text('注销账号')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.danger'))
        .layoutWeight(1)
      Text('›')
        .fontSize(22)
        .fontColor($r('app.color.danger'))
        .width(Profile.PROFILE_KV_TRAILING_CHEVRON_WIDTH_VP)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 14,
      bottom: 14
    })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      onRowClick()
    })
  }

  @Builder
  kvRow(label: string, value: string, showChevron: boolean, dangerValue: boolean, onRowClick: () => void,
    rowEnabled?: boolean) {
    Row() {
      Text(label)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .layoutWeight(1)
      if (value.length > 0) {
        Text(value)
          .fontSize($r('app.float.body_font_size'))
          .fontColor(dangerValue ? $r('app.color.danger') : $r('app.color.secondary_text'))
          .textAlign(TextAlign.End)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
      }
      if (showChevron) {
        Text('›')
          .fontSize(22)
          .fontColor(dangerValue ? $r('app.color.danger') : $r('app.color.tertiary_text'))
          .width(Profile.PROFILE_KV_TRAILING_CHEVRON_WIDTH_VP)
          .textAlign(TextAlign.Center)
          .margin({ left: value.length > 0 ? Profile.PROFILE_KV_VALUE_TO_TRAILING_GAP_VP : 0 })
      } else {
        Blank()
          .width(Profile.PROFILE_KV_TRAILING_CHEVRON_WIDTH_VP)
          .height(1)
          .margin({ left: value.length > 0 ? Profile.PROFILE_KV_VALUE_TO_TRAILING_GAP_VP : 0 })
      }
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 14,
      bottom: 14
    })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .enabled(rowEnabled !== false)
    .onClick((): void => {
      onRowClick()
    })
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
          Text('个人信息')
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
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column() {
          if (this.loading) {
            Text('加载中…')
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.tertiary_text'))
              .padding({ top: 24, bottom: 24 })
          } else if (this.loadError.length > 0) {
            Text(this.loadError)
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.tertiary_text'))
              .padding({ top: 24, bottom: 24 })
          } else if (this.profile !== null) {
            Column() {
              Row() {
                if (this.avatarUrlTrim().length > 0 && !this.avatarNetworkLoadFailed) {
                  Image(this.avatarUrlTrim())
                    .width(56)
                    .height(56)
                    .borderRadius(28)
                    .objectFit(ImageFit.Cover)
                    .onError((): void => {
                      this.avatarNetworkLoadFailed = true
                    })
                } else {
                  Column() {
                    Text(this.avatarInitial())
                      .fontSize(22)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.secondary_text'))
                  }
                  .width(56)
                  .height(56)
                  .borderRadius(28)
                  .backgroundColor($r('app.color.surface_muted'))
                  .justifyContent(FlexAlign.Center)
                }
                Blank().layoutWeight(1)
                Text(this.avatarUploading ? '上传中…' : '更换头像')
                  .fontSize($r('app.float.body_font_size'))
                  .fontColor($r('app.color.accent'))
                Blank()
                  .width(Profile.PROFILE_KV_TRAILING_CHEVRON_WIDTH_VP)
                  .height(1)
                  .margin({ left: Profile.PROFILE_KV_VALUE_TO_TRAILING_GAP_VP })
              }
              .width('100%')
              .padding({
                left: 16,
                right: 16,
                top: 12,
                bottom: 12
              })
              .alignItems(VerticalAlign.Center)
              .onClick((): void => {
                if (!this.avatarUploading) {
                  void this.pickAndUploadAvatar()
                }
              })
            }
            .width('100%')
            .backgroundColor($r('app.color.card_background'))

            this.groupGap()

            Column() {
              this.kvRow(
                this.membershipTitle(this.profile!),
                this.membershipRight(this.profile!),
                !this.isLifetimeVip(this.profile!),
                false,
                (): void => {
                  if (this.isLifetimeVip(this.profile!)) {
                    return
                  }
                  this.getUIContext().getRouter().pushUrl({ url: 'pages/QingyuCloudRecharge' }).catch((err: Error) => {
                    console.error(`Profile push QingyuCloudRecharge: ${JSON.stringify(err)}`)
                  })
                },
                !this.isLifetimeVip(this.profile!)
              )
            }
            .width('100%')
            .backgroundColor($r('app.color.card_background'))

            this.groupGap()

            Column() {
              this.kvRow(
                '昵称',
                this.displayNickname(),
                true,
                false,
                (): void => {
                  this.openTextEdit('昵称', 'username', (this.profile!.username ?? '').trim())
                }
              )
            }
            .width('100%')
            .backgroundColor($r('app.color.card_background'))

            this.groupGap()

            Column() {
              this.kvRow(
                '手机号',
                this.displayPhone(),
                true,
                false,
                (): void => {
                  this.openTextEdit('手机号', 'phone', (this.profile!.phone ?? '').trim())
                }
              )
              this.rowDivider()
              this.kvRow(
                '华为账号',
                this.bindLabel(this.profile!.huawei_linked),
                this.thirdPartyRowInteractive(PROFILE_ACCOUNT_BIND_SUPPORTED_HUAWEI, this.profile!.huawei_linked),
                false,
                (): void => {
                  void this.onTapBindHuawei()
                },
                this.thirdPartyRowInteractive(PROFILE_ACCOUNT_BIND_SUPPORTED_HUAWEI, this.profile!.huawei_linked)
              )
              this.rowDivider()
              this.kvRow(
                '微信账号',
                this.bindLabel(this.profile!.wechat_linked),
                this.thirdPartyRowInteractive(PROFILE_ACCOUNT_BIND_SUPPORTED_WECHAT, this.profile!.wechat_linked),
                false,
                (): void => {
                  void this.onTapBindWeChat()
                },
                this.thirdPartyRowInteractive(PROFILE_ACCOUNT_BIND_SUPPORTED_WECHAT, this.profile!.wechat_linked)
              )
              this.rowDivider()
              this.kvRow(
                'Apple 账号',
                this.bindLabel(this.profile!.apple_linked),
                this.thirdPartyRowInteractive(PROFILE_ACCOUNT_BIND_SUPPORTED_APPLE, this.profile!.apple_linked),
                false,
                (): void => {},
                this.thirdPartyRowInteractive(PROFILE_ACCOUNT_BIND_SUPPORTED_APPLE, this.profile!.apple_linked)
              )
            }
            .width('100%')
            .backgroundColor($r('app.color.card_background'))

            this.groupGap()

            Column() {
              this.kvRow(
                '兑换码',
                '点击兑换',
                true,
                false,
                (): void => {
                  this.openRedeemDialog()
                },
                true
              )
              this.rowDivider()
              this.kvRow(
                '注册时间',
                this.regLine(),
                false,
                false,
                (): void => {}
              )
              this.rowDivider()
              this.kvRow(
                '用户序列',
                this.userSequenceLine(),
                false,
                false,
                (): void => {}
              )
            }
            .width('100%')
            .backgroundColor($r('app.color.card_background'))

            this.groupGap()

            Column() {
              this.dangerNavRow((): void => {
                void this.confirmDelete()
              })
            }
            .width('100%')
            .backgroundColor($r('app.color.card_background'))

            Column().height(24)
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
    .backgroundColor($r('app.color.surface_muted'))
  }
}
