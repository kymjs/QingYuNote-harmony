import { AppContextHolder } from '../../services/AppContextHolder'
import { getAppVersionName } from '../../services/AppUpdateService'
import { LocaleService } from '../../services/LocaleService'
import { LocalDataUsageService } from '../../services/LocalDataUsageService'
import { NoteApiClient, type ProfileBody } from '../../services/NoteApiClient'
import { NoteRepository } from '../../services/NoteRepository'
import { PreferencesService } from '../../services/PreferencesService'
import { RemoteAppConfigService } from '../../services/RemoteAppConfigService'
import { CachedNetworkImage } from '../../components/CachedNetworkImage'
import { MineDiamondIcon, MineScalesIcon } from '../../components/MineSvgIcons'
import { openReferralInviteSharePage } from '../../common/utils/ReferralInviteNavigation'
import { Logger } from '../../common/utils/Logger'
import { ImageCacheService } from '../../services/ImageCacheService'

const ACCENT = '#0DAA4A'
const CARD_RADIUS = 16
const PAGE_PAD = 16
/** 标签 / 有效期芯片：圆角矩形，非胶囊 */
const TAG_RADIUS = 6
/** 「已开通会员」按钮 */
const ACTION_RADIUS = 8
/** 「查看权益 / 立即开通」：设计稿为胶囊 */
const CAPSULE_RADIUS = 16

function isQingyuMember(profile: ProfileBody | null): boolean {
  if (profile === null) {
    return false
  }
  if (profile.membership_is_lifetime === true) {
    return true
  }
  const level = (profile.membership_level ?? '').trim()
  return level === 'active' || level === 'lifetime'
}

function isLifetimeMember(profile: ProfileBody | null): boolean {
  if (profile === null) {
    return false
  }
  if (profile.membership_is_lifetime === true) {
    return true
  }
  return (profile.membership_level ?? '').trim() === 'lifetime'
}

function formatCount(n: number): string {
  const s = `${Math.floor(n)}`
  let out = ''
  for (let i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 === 0) {
      out += ','
    }
    out += s.charAt(i)
  }
  return out
}

function userRankLabel(id: string): string {
  const trimmed = id.trim()
  if (trimmed.length === 0) {
    return '—'
  }
  const asInt = Number.parseInt(trimmed, 10)
  const display = Number.isNaN(asInt) ? trimmed : formatCount(asInt)
  return LocaleService.loc(`第 ${display} 名`, `#${display}`, `第 ${display} 名`)
}

function formatYmd(raw: string): string {
  const t = raw.trim()
  if (t.length === 0) {
    return ''
  }
  if (t.length >= 10) {
    return t.substring(0, 10)
  }
  return t
}

function registrationDays(registeredAt: string): number {
  const raw = registeredAt.trim()
  if (raw.length < 10) {
    return 0
  }
  const parsed = Date.parse(raw.substring(0, 10))
  if (Number.isNaN(parsed)) {
    return 0
  }
  const start = new Date(parsed)
  const now = new Date()
  const a = new Date(start.getFullYear(), start.getMonth(), start.getDate()).getTime()
  const b = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  const days = Math.floor((b - a) / 86400000) + 1
  return days < 1 ? 1 : days
}

@Component
export struct DashboardMineTab {
  @Prop @Watch('onVisibleChanged') visible: boolean = false
  @Prop @Watch('onShellRefreshNonce') shellRefreshNonce: number = 0
  @StorageLink('appLocaleRevision') localeRevision: number = 0
  @State profile: ProfileBody | null = null
  @State userId: string = ''
  @State noteCount: number = 0
  @State usedBytes: number = 0
  @State appVersion: string = ''
  @State showReferralInviteMenu: boolean = false
  @State loading: boolean = true
  @State avatarLoadFailed: boolean = false
  private reloadGeneration: number = 0

  aboutToAppear(): void {
    void this.reload()
  }

  onVisibleChanged(): void {
    if (this.visible) {
      void this.reload()
    }
  }

  onShellRefreshNonce(): void {
    if (this.visible) {
      void this.reload()
    }
  }

  private async ensureLoggedInOrRedirect(): Promise<boolean> {
    const prefs = PreferencesService.getInstance()
    const ctx = AppContextHolder.tryGetContext()
    if (ctx) {
      await prefs.init(ctx)
    }
    const loggedIn = await prefs.isUserLoggedIn()
    if (!loggedIn) {
      await prefs.clearLoginSession()
      try {
        await this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' })
      } catch (err) {
        Logger.warn('DashboardMineTab', `replace Login failed: ${JSON.stringify(err)}`)
      }
      return false
    }
    return true
  }

  private async reload(): Promise<void> {
    const generation = ++this.reloadGeneration
    if (!(await this.ensureLoggedInOrRedirect())) {
      return
    }

    let profile: ProfileBody | null = null
    try {
      const cachedRaw = await PreferencesService.getInstance().getCachedUserProfile()
      if (cachedRaw !== null) {
        profile = cachedRaw as ProfileBody
      }
    } catch (_) {
    }
    try {
      const remote = await NoteApiClient.getInstance().fetchProfile()
      if (remote !== null) {
        profile = remote
      }
    } catch (_) {
    }

    if (!(await this.ensureLoggedInOrRedirect())) {
      return
    }

    const uid = (await PreferencesService.getInstance().getNoteApiUserId()).trim()

    let noteCount = 0
    try {
      const notes = await NoteRepository.getInstance().listNotes()
      noteCount = notes.length
    } catch (_) {
    }

    let usedBytes = 0
    try {
      usedBytes = await LocalDataUsageService.getInstance().calculateTotalBytes()
    } catch (_) {
    }

    let version = this.appVersion
    try {
      version = await getAppVersionName()
    } catch (_) {
    }

    let inviteEnabled = false
    try {
      const ctx = AppContextHolder.tryGetContext()
      const filesDir = ctx?.filesDir ?? ''
      inviteEnabled = await RemoteAppConfigService.referralInviteMenuEnabledFromCache(filesDir)
    } catch (_) {
    }

    if (generation !== this.reloadGeneration) {
      return
    }
    this.profile = profile
    this.userId = uid
    this.noteCount = noteCount
    this.usedBytes = usedBytes
    this.appVersion = version
    this.showReferralInviteMenu = inviteEnabled && uid.length > 0
    this.avatarLoadFailed = false
    this.loading = false
  }

  private displayName(): string {
    const name = (this.profile?.username ?? '').trim()
    if (name.length === 0) {
      return LocaleService.loc('轻羽云笔记', 'Qingyu Notes', '軽羽クラウドノート')
    }
    return name
  }

  private badgeText(): string {
    if (isLifetimeMember(this.profile)) {
      return LocaleService.loc('终身版', 'Lifetime', '生涯版')
    }
    return LocaleService.loc('专业版', 'Pro', 'プロ版')
  }

  private memberActive(): boolean {
    return isQingyuMember(this.profile)
  }

  private openRecharge(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/QingyuCloudRecharge' }).catch((err: Error) => {
      console.error(`DashboardMineTab push QingyuCloudRecharge: ${JSON.stringify(err)}`)
    })
  }

  private openProfile(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/Profile' }).catch((err: Error) => {
      console.error(`DashboardMineTab push Profile: ${JSON.stringify(err)}`)
    })
  }

  private expiryCapsuleText(): string {
    if (isLifetimeMember(this.profile)) {
      return LocaleService.loc('会员有效期:终身', 'Membership: lifetime', '会員期限:生涯')
    }
    const ymd = formatYmd(this.profile?.membership_expires_at ?? '')
    if (ymd.length === 0) {
      return LocaleService.loc('会员有效期至 —', 'Valid until —', '有効期限 —')
    }
    return `${LocaleService.loc('会员有效期至', 'Valid until', '有効期限')} ${ymd}`
  }

  private joinedCaption(): string {
    const days = registrationDays(this.profile?.registered_at ?? '')
    if (days <= 0) {
      return '—'
    }
    return `${LocaleService.loc('已加入', 'Joined', '参加')} ${days} ${LocaleService.loc('天', 'days', '日')}`
  }

  private cardTitle(): string {
    if (isLifetimeMember(this.profile)) {
      return LocaleService.loc('轻羽云会员·终身版', 'Qingyu Lifetime', '軽羽会員・生涯版')
    }
    return LocaleService.loc('轻羽云会员 · 专业版', 'Qingyu Pro', '軽羽会員・プロ版')
  }

  build() {
    Column() {
      if (this.loading && this.profile === null) {
        LoadingProgress()
          .width(40)
          .height(40)
          .margin({ top: 80 })
      } else {
        Scroll() {
          Column({ space: 14 }) {
            this.buildHeader()
            this.buildMembershipCard()
            this.buildMenuGroup1()
            this.buildMenuGroup2()
          }
          .width('100%')
          .padding({
            left: PAGE_PAD,
            right: PAGE_PAD,
            top: 16,
            bottom: 24
          })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildHeader() {
    Row() {
      // 头像
      Column() {
        this.buildAvatar()
      }
      .onClick(() => {
        this.openProfile()
      })

      // 中间：用户名+徽章紧挨、slogan、有效期芯片；左对齐贴头像
      Column({ space: 4 }) {
        Flex({
          direction: FlexDirection.Row,
          wrap: FlexWrap.NoWrap,
          justifyContent: FlexAlign.Start,
          alignItems: ItemAlign.Center
        }) {
          Text(this.displayName())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
            .flexGrow(0)
          Text(this.badgeText())
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent'))
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .backgroundColor($r('app.color.accent_subtle'))
            .borderRadius(TAG_RADIUS)
            .margin({ left: 6 })
            .flexShrink(0)
        }
        .width('100%')

        Text(LocaleService.loc('记录本身，就是意义', 'Recording is meaning itself', '記録そのものが意味'))
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))

        if (this.memberActive()) {
          Row({ space: 3 }) {
            MineScalesIcon({
              iconColor: $r('app.color.mine_expiry_fg'),
              iconSize: 11
            })
            Text(this.expiryCapsuleText())
              .fontSize(9)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.mine_expiry_fg'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('›')
              .fontSize(8)
              .fontColor($r('app.color.mine_expiry_fg'))
          }
          .padding({ left: 6, right: 4, top: 2, bottom: 2 })
          .backgroundColor($r('app.color.mine_expiry_bg'))
          .borderRadius(TAG_RADIUS)
          .margin({ top: 4 })
          .alignSelf(ItemAlign.Start)
          .onClick(() => {
            this.openRecharge()
          })
        } else {
          Row({ space: 3 }) {
            MineScalesIcon({
              iconColor: $r('app.color.secondary_text'),
              iconSize: 8
            })
            Text(LocaleService.loc('开通会员解锁全部功能', 'Unlock all features', '会員ですべて解放'))
              .fontSize(7)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.secondary_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('›')
              .fontSize(8)
              .fontColor($r('app.color.secondary_text'))
          }
          .padding({ left: 6, right: 4, top: 2, bottom: 2 })
          .backgroundColor($r('app.color.mine_unlock_chip_bg'))
          .borderRadius(TAG_RADIUS)
          .margin({ top: 4 })
          .alignSelf(ItemAlign.Start)
          .onClick(() => {
            this.openRecharge()
          })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
      .onClick(() => {
        this.openProfile()
      })

      // 右侧「已开通会员」：底边与左侧「会员有效期至」芯片底边对齐。
      // 中栏布局：用户名 Flex(~28) + gap4 + slogan(~17) + gap4 + 芯片margin-top4 = 约 57px 到芯片顶部；
      // 芯片高约 14，底边约 71px；按钮高约 30，top = 71 − 30 ≈ 41。
      Row({ space: 4 }) {
        MineScalesIcon({
          iconColor: $r('app.color.accent'),
          iconSize: 16
        })
        Text(this.memberActive()
          ? LocaleService.loc('已开通会员', 'Subscribed', '会員済み')
          : LocaleService.loc('开通会员', 'Go Pro', '会員になる'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent'))
      }
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 1, color: '#8C0DAA4A' })
      .borderRadius(ACTION_RADIUS)
      .margin({ top: 30 })
      .onClick(() => {
        this.openRecharge()
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  buildAvatar() {
    Stack() {
      if (!this.avatarLoadFailed &&
        ImageCacheService.isNetworkImageUrl((this.profile?.avatar_url ?? '').trim())) {
        CachedNetworkImage({
          url: (this.profile?.avatar_url ?? '').trim(),
          imageWidth: 56,
          imageHeight: 56,
          imageBorderRadius: 28,
          objectFit: ImageFit.Cover,
          onError: (): void => {
            this.avatarLoadFailed = true
          }
        })
      } else {
        Image($r('app.media.icon_app'))
          .width(56)
          .height(56)
          .borderRadius(28)
          .objectFit(ImageFit.Cover)
      }
    }
    .width(56)
    .height(56)
    .borderRadius(28)
    .clip(true)
  }

  @Builder
  buildMembershipCard() {
    Column({ space: 16 }) {
      Row() {
        MineDiamondIcon({
          iconColor: this.memberActive() ? ACCENT : $r('app.color.mine_non_member_accent'),
          iconSize: 20
        })
        Column({ space: 4 }) {
          Flex({
            direction: FlexDirection.Row,
            wrap: FlexWrap.NoWrap,
            justifyContent: FlexAlign.Start,
            alignItems: ItemAlign.Center
          }) {
            Text(this.cardTitle())
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1)
              .flexGrow(0)
            Text(this.memberActive()
              ? LocaleService.loc('已开通', 'Active', '開通済み')
              : LocaleService.loc('未开通', 'Not active', '未開通'))
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.memberActive() ? ACCENT : $r('app.color.mine_non_member_accent'))
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .backgroundColor(this.memberActive()
                ? $r('app.color.mine_member_status_bg')
                : $r('app.color.mine_non_member_status_bg'))
              .borderRadius(TAG_RADIUS)
              .margin({ left: 6 })
              .flexShrink(0)
          }
          .width('100%')
          Text(this.memberActive()
            ? LocaleService.loc('畅享全部会员功能', 'All member features', 'すべての会員機能')
            : LocaleService.loc('开通会员，畅享全部功能', 'Subscribe for all features', '会員ですべての機能を'))
            .fontSize(11)
            .fontColor($r('app.color.secondary_text'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 8 })

        if (this.memberActive()) {
          Button(LocaleService.loc('查看权益', 'Benefits', '特典を見る'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(ACCENT)
            .backgroundColor($r('app.color.card_background'))
            .border({ width: 1, color: '#800DAA4A' })
            .borderRadius(CAPSULE_RADIUS)
            .height(28)
            .padding({ left: 10, right: 10 })
            .onClick(() => {
              this.openRecharge()
            })
        } else {
          Button(LocaleService.loc('立即开通', 'Subscribe', '今すぐ開通'))
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.mine_non_member_accent'))
            .borderRadius(CAPSULE_RADIUS)
            .height(28)
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.openRecharge()
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row() {
        this.statCell(
          LocaleService.loc('用户序列', 'User #', 'ユーザー番号'),
          userRankLabel(this.userId),
          LocaleService.loc('全球用户排名', 'Global rank', 'グローバル順位')
        )
        this.statCell(
          LocaleService.loc('注册时间', 'Registered', '登録日'),
          formatYmd(this.profile?.registered_at ?? '') || '—',
          this.joinedCaption()
        )
        this.statCell(
          LocaleService.loc('云端存储', 'Cloud storage', 'クラウド容量'),
          `${LocalDataUsageService.QUOTA_GB} GB`,
          `${LocaleService.loc('已使用', 'Used', '使用済み')} ${LocalDataUsageService.formatUsedGbCeil1(this.usedBytes)} GB`
        )
        this.statCell(
          LocaleService.loc('笔记数量', 'Notes', 'ノート数'),
          LocaleService.loc('无上限', 'Unlimited', '無制限'),
          `${LocaleService.loc('已创建', 'Created', '作成済み')} ${formatCount(this.noteCount)} ${LocaleService.loc('条', 'notes', '件')}`
        )
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.memberActive()
      ? $r('app.color.mine_member_card_bg')
      : $r('app.color.mine_non_member_card_bg'))
    .borderRadius(CARD_RADIUS)
    .border({
      width: 1,
      color: this.memberActive()
        ? $r('app.color.mine_member_card_border')
        : $r('app.color.mine_non_member_card_border')
    })
  }

  @Builder
  statCell(label: string, value: string, caption: string) {
    Column({ space: 3 }) {
      Text(label)
        .fontSize(9)
        .fontColor($r('app.color.secondary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(value)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.memberActive() ? ACCENT : $r('app.color.mine_non_member_accent'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(caption)
        .fontSize(9)
        .fontColor($r('app.color.secondary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildMenuGroup1() {
    Column() {
      this.menuRow($r('sys.symbol.gearshape'),
        LocaleService.loc('设置中心', 'Settings', '設定センター'), '', false, () => {
          this.push('pages/Settings')
        }, true)
      this.menuRow($r('sys.symbol.folder'),
        LocaleService.loc('文件管理', 'Folders', 'フォルダ管理'), '', false, () => {
          this.push('pages/FolderManage')
        }, true)
      this.menuRow($r('sys.symbol.label'),
        LocaleService.loc('标签管理', 'Tags', 'タグ管理'), '', false, () => {
          this.push('pages/TagManage')
        }, true)
      this.menuRow($r('sys.symbol.clean'),
        LocaleService.loc('回收站', 'Recycle bin', 'ゴミ箱'), '', false, () => {
          this.push('pages/RecycleBin')
        }, true)
      this.menuRow($r('sys.symbol.quote'),
        LocaleService.loc('用户反馈', 'Feedback', 'フィードバック'), '', false, () => {
          this.getUIContext().getRouter().pushUrl({
            url: 'pages/H5WebContainer',
            params: {
              title: LocaleService.loc('用户反馈', 'Feedback', 'フィードバック'),
              url: 'https://vcnedpub4ekz.feishu.cn/share/base/form/shrcnexjZUlhIkZ4eD9BjcDfdkb'
            }
          }).catch((err: Error) => {
            console.error(`openFeedback: ${JSON.stringify(err)}`)
          })
        }, false)
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(CARD_RADIUS)
    .shadow({
      radius: 16,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 4
    })
  }

  @Builder
  buildMenuGroup2() {
    Column() {
      if (this.showReferralInviteMenu) {
        this.menuRow($r('sys.symbol.share'),
          LocaleService.loc('邀请得会员', 'Invite for membership', '招待で会員'),
          LocaleService.loc('限时奖励', 'Limited offer', '期間限定'),
          true,
          () => {
            void openReferralInviteSharePage(this.getUIContext())
          }, true)
      }
      this.menuRow($r('sys.symbol.doc_text'),
        LocaleService.loc('关于轻羽云笔记', 'About Qingyu Notes', '軽羽クラウドノートについて'),
        this.appVersion.length > 0 ? `v${this.appVersion}` : '',
        false,
        () => {
          this.push('pages/About')
        }, false)
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(CARD_RADIUS)
    .shadow({
      radius: 16,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 4
    })
  }

  @Builder
  menuRow(symbol: Resource, title: string, trailing: string, trailingAlert: boolean,
    onTap: () => void, showDivider: boolean) {
    Column() {
      Row() {
        SymbolGlyph(symbol)
          .fontSize(22)
          .fontColor([$r('app.color.secondary_text')])
        Text(title)
          .fontSize(15)
          .fontColor($r('app.color.primary_text'))
          .margin({ left: 12 })
          .layoutWeight(1)
        if (trailing.length > 0) {
          Text(trailing)
            .fontSize(13)
            .fontColor(trailingAlert ? '#E53935' : $r('app.color.secondary_text'))
            .margin({ right: 4 })
        }
        Text('›')
          .fontSize(20)
          .fontColor($r('app.color.tertiary_text'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => {
        onTap()
      })
      if (showDivider) {
        Divider()
          .color($r('app.color.card_border'))
          .margin({ left: 50 })
      }
    }
  }

  private push(url: string): void {
    this.getUIContext().getRouter().pushUrl({ url: url }).catch((err: Error) => {
      console.error(`DashboardMineTab push ${url}: ${JSON.stringify(err)}`)
    })
  }
}
