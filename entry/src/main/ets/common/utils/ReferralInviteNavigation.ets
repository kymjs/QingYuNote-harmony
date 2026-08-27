import { BusinessError } from '@kit.BasicServicesKit'
import { ComponentContent, UIContext } from '@kit.ArkUI'

import { NoteApiClient } from '../../services/NoteApiClient'
import { PreferencesService } from '../../services/PreferencesService'
import { AppContextHolder } from '../../services/AppContextHolder'
import { RemoteAppConfigService } from '../../services/RemoteAppConfigService'
import { LocaleService } from '../../services/LocaleService'

const OFFICIAL_INVITE_PAGE_URL = 'https://note.kymjs.com/invite.html'
const OFFICIAL_ACTIVITY_PAGE_URL = 'https://note.kymjs.com/activity.html'
const BRAND_GREEN = '#0DAA4A'

let referralInviteInFlight: boolean = false

/** 与官网 `invite-share.html` 一致的邀请文案（复制分享用）。 */
export function buildReferralInviteShareText(inviterUserId: string): string {
  return `这个笔记很好用，现在注册你得一个月会员，我得7天会员。${OFFICIAL_INVITE_PAGE_URL}?inviter_user_id=${encodeURIComponent(inviterUserId)}`
}

export function isValidReferralInviterUserId(value: string): boolean {
  const trimmed = value.trim()
  return trimmed.length > 0 && /^\d+$/.test(trimmed)
}

export interface ReferralGiftPackDialogParams {
  onClose: () => void
  onShare: () => void
}

export interface ReferralInviteFriendsDialogParams {
  onClose: () => void
  onShare: () => void
}

@Component
struct ReferralGiftPackDialog {
  @Prop params: ReferralGiftPackDialogParams = {
    onClose: (): void => {},
    onShare: (): void => {}
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column() {
          Text('🎁').fontSize(56)
        }
        .width('100%')
        .padding({ top: 20, bottom: 8 })
        .borderRadius({ topLeft: 24, topRight: 24 })
        .linearGradient({
          angle: 180,
          colors: [['#2ee87a33', 0], ['#ffffff', 1]]
        })

        Button({ type: ButtonType.Circle }) {
          Text('×').fontSize(20).fontColor('#666666')
        }
        .width(36)
        .height(36)
        .backgroundColor('#00000000')
        .margin({ top: 4, right: 4 })
        .onClick(() => this.params.onClose())
      }

      Text('你的专属邀请礼包已就绪')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1a1a1a')
        .margin({ top: 12 })
      Text('分享给好友，一起解锁轻羽云会员能力')
        .fontSize(14)
        .fontColor('#6b7280')
        .textAlign(TextAlign.Center)
        .margin({ top: 8, left: 20, right: 20 })

      Text('最高得 365 天会员')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(BRAND_GREEN)
        .margin({ top: 20 })

      Button('立即分享')
        .width('88%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor(BRAND_GREEN)
        .borderRadius(24)
        .margin({ top: 24, bottom: 8 })
        .onClick(() => this.params.onShare())

      Text('奖励将在好友完成注册后发放')
        .fontSize(12)
        .fontColor('#9ca3af')
        .margin({ bottom: 20 })
    }
    .width('88%')
    .constraintSize({ maxWidth: 400 })
    .backgroundColor(Color.White)
    .borderRadius(24)
    .clip(true)
  }
}

@Component
struct ReferralInviteFriendsDialog {
  @Prop params: ReferralInviteFriendsDialogParams = {
    onClose: (): void => {},
    onShare: (): void => {}
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column() {
          Text('📒').fontSize(48)
        }
        .width('100%')
        .padding({ top: 16, bottom: 4 })
        .borderRadius({ topLeft: 24, topRight: 24 })
        .linearGradient({
          angle: 180,
          colors: [['#2ee87a33', 0], ['#ffffff', 1]]
        })

        Button({ type: ButtonType.Circle }) {
          Text('×').fontSize(20).fontColor('#666666')
        }
        .width(36)
        .height(36)
        .backgroundColor('#00000000')
        .margin({ top: 4, right: 4 })
        .onClick(() => this.params.onClose())
      }

      Text('邀请好友得会员')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 12 })
      Text('每成功邀请 1 位好友，\n您得 7 天会员，好友得 1 个月会员')
        .fontSize(14)
        .fontColor('#6b7280')
        .textAlign(TextAlign.Center)
        .margin({ top: 8, left: 20, right: 20 })

      Row() {
        Text('无限空间').fontSize(12).layoutWeight(1).textAlign(TextAlign.Center)
        Text('AI 总结').fontSize(12).layoutWeight(1).textAlign(TextAlign.Center)
        Text('跨端同步').fontSize(12).layoutWeight(1).textAlign(TextAlign.Center)
      }
      .width('90%')
      .margin({ top: 20 })

      Button('立即邀请')
        .width('88%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor(BRAND_GREEN)
        .borderRadius(24)
        .margin({ top: 24, bottom: 24 })
        .onClick(() => this.params.onShare())
    }
    .width('88%')
    .constraintSize({ maxWidth: 400 })
    .backgroundColor(Color.White)
    .borderRadius(24)
    .clip(true)
  }
}

@Builder
function buildReferralGiftPackDialogContent(params: ReferralGiftPackDialogParams): void {
  ReferralGiftPackDialog({ params: params })
}

@Builder
function buildReferralInviteFriendsDialogContent(params: ReferralInviteFriendsDialogParams): void {
  ReferralInviteFriendsDialog({ params: params })
}

function showReferralGiftPackDialog(
  uiContext: UIContext,
  onShare: () => void
): boolean {
  let holder: ComponentContent<ReferralGiftPackDialogParams> | undefined = undefined
  const closeDialog = (): void => {
    if (holder === undefined) {
      return
    }
    try {
      uiContext.getPromptAction().closeCustomDialog(holder)
    } catch (_) {
      // ignore
    }
    holder = undefined
  }
  const params: ReferralGiftPackDialogParams = {
    onClose: closeDialog,
    onShare: (): void => {
      closeDialog()
      onShare()
    }
  }
  try {
    holder = new ComponentContent(uiContext, wrapBuilder(buildReferralGiftPackDialogContent), params)
    uiContext.getPromptAction().openCustomDialog(holder, {
      alignment: DialogAlignment.Center,
      autoCancel: false,
      isModal: true,
      onWillDismiss: (_: DismissDialogAction) => {
        // 仅右上角关闭或弹窗内按钮可关闭
      }
    })
    return true
  } catch (err) {
    console.error(`showReferralGiftPackDialog failed: ${JSON.stringify(err)}`)
    return false
  }
}

function showReferralInviteFriendsDialog(
  uiContext: UIContext,
  onShare: () => void
): boolean {
  let holder: ComponentContent<ReferralInviteFriendsDialogParams> | undefined = undefined
  const closeDialog = (): void => {
    if (holder === undefined) {
      return
    }
    try {
      uiContext.getPromptAction().closeCustomDialog(holder)
    } catch (_) {
      // ignore
    }
    holder = undefined
  }
  const params: ReferralInviteFriendsDialogParams = {
    onClose: closeDialog,
    onShare: (): void => {
      closeDialog()
      onShare()
    }
  }
  try {
    holder = new ComponentContent(uiContext, wrapBuilder(buildReferralInviteFriendsDialogContent), params)
    uiContext.getPromptAction().openCustomDialog(holder, {
      alignment: DialogAlignment.Center,
      autoCancel: false,
      isModal: true,
      onWillDismiss: (_: DismissDialogAction) => {
        // 仅右上角关闭或弹窗内按钮可关闭
      }
    })
    return true
  } catch (err) {
    console.error(`showReferralInviteFriendsDialog failed: ${JSON.stringify(err)}`)
    return false
  }
}

async function openReferralInviteShareFromPopup(uiContext: UIContext, variant: number): Promise<void> {
  await NoteApiClient.getInstance().reportReferralPopupClick(variant)
  await openReferralInviteSharePage(uiContext)
}

/** 设置页「邀请得会员」：打开原生邀请分享页。 */
export async function openReferralInviteSharePage(uiContext: UIContext): Promise<void> {
  try {
    uiContext.getRouter().pushUrl({
      url: 'pages/ReferralInviteShare'
    }).catch((err: BusinessError) => {
      console.error(`openReferralInviteSharePage failed: ${JSON.stringify(err)}`)
    })
  } catch (err) {
    console.error(`openReferralInviteSharePage failed: ${JSON.stringify(err)}`)
  }
}

/** 我的页「免费得会员」：应用内 WebView 打开活动 H5。 */
export async function openQingyuActivityPage(uiContext: UIContext): Promise<void> {
  let uid = ''
  try {
    uid = (await PreferencesService.getInstance().getNoteApiUserId()).trim()
  } catch (_) {
  }
  const title: string = LocaleService.loc('免费得会员', 'Free membership', '無料で会員')
  const parts: string[] = ['from=qingyu', 'platform=harmony']
  if (uid.length > 0) {
    parts.push(`uid=${encodeURIComponent(uid)}`)
  }
  const url: string = `${OFFICIAL_ACTIVITY_PAGE_URL}?${parts.join('&')}`
  try {
    await uiContext.getRouter().pushUrl({
      url: 'pages/H5WebContainer',
      params: {
        'title': title,
        'url': url
      }
    })
  } catch (err) {
    console.error(`openQingyuActivityPage failed: ${JSON.stringify(err)}`)
  }
}

/**
 * 首页进入后：远端 `redemption` + `redemption_version` 开启且服务端判定可展示时，随机展示两种样式之一。
 * 会员：历史上从未曝光；非会员：当日未曝光。
 */
export async function maybeShowReferralInviteDialog(uiContext: UIContext): Promise<void> {
  if (referralInviteInFlight) {
    return
  }
  referralInviteInFlight = true
  try {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    if (!await PreferencesService.getInstance().isUserLoggedIn() ||
      await PreferencesService.getInstance().isGuestMode()) {
      return
    }
    const filesDir = context?.filesDir ?? ''
    if (!await RemoteAppConfigService.referralInviteMenuEnabledFromCache(filesDir)) {
      return
    }
    const profile = await NoteApiClient.getInstance().fetchProfile()
    if (profile === null || profile.invite_popup_pending !== true) {
      return
    }
    const variant = Math.random() < 0.5 ? 1 : 2
    const onShare = (): void => {
      void openReferralInviteShareFromPopup(uiContext, variant)
    }
    const opened = variant === 1
      ? showReferralGiftPackDialog(uiContext, onShare)
      : showReferralInviteFriendsDialog(uiContext, onShare)
    if (opened) {
      await NoteApiClient.getInstance().reportReferralPopupImpression(variant)
    }
  } catch (err) {
    console.error(`maybeShowReferralInviteDialog failed: ${JSON.stringify(err)}`)
  } finally {
    referralInviteInFlight = false
  }
}
