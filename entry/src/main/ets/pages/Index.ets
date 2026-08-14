import type { Note, SyncResult, SyncStatus } from '../common/model/Note'
import { isExtractStatusPending } from '../common/model/Note'
import { AudioConstants } from '../common/constants/AudioConstants'
import { DrawerModel } from '../common/model/DrawerModel'
import { HomeDrawerLayer } from './HomeDrawerLayer'
import { IndexNotesDataSource } from './IndexNotesDataSource'
import { NoteRepository } from '../services/NoteRepository'
import { SyncService } from '../services/SyncService'
import { PreferencesService } from '../services/PreferencesService'
import { AppContextHolder } from '../services/AppContextHolder'
import { runAppUpdateCheckOnLaunch, recheckForceUpdateOnResume } from '../services/AppUpdateUi'
import {
  previewQingyuForHomeSubscription,
  tryAutoProvisionQingyuCloudOnHomeEntry
} from '../services/QingyuCloudAutoProvision'
import { SyncSettingsRemoteReport } from '../services/SyncSettingsRemoteReport'
import { WebDAVClient } from '../services/WebDAVClient'
import { NoteApiClient, type ProfileBody } from '../services/NoteApiClient'
import { LinkExtractClient, type JobStatusResult } from '../services/LinkExtractClient'
import { AiNoteBackgroundTaskService } from '../services/AiNoteBackgroundTaskService'
import { Logger } from '../common/utils/Logger'
import {
  NoteFolderTree,
  type FolderSidebarRow,
  type HomeSidebarFilterMode
} from '../common/utils/NoteFolderTree'
import { TagSortUtils } from '../common/utils/TagSortUtils'
import { SyncConstants, WereadImportToastPayload, YinxiangImportToastPayload } from '../common/constants/SyncConstants'
import { UserFacingMessage } from '../common/utils/UserFacingMessage'
import { CloudSyncNotifyThrottle } from '../common/utils/CloudSyncNotifyThrottle'
import { PageLifecycle } from '../common/utils/PageLifecycle'
import { IdUtils } from '../common/utils/IdUtils'
import { navigateToBindPhoneIfNeeded } from '../common/utils/BindPhoneNavigation'
import { maybeShowReferralInviteDialog } from '../common/utils/ReferralInviteNavigation'
import { type NoteEditorEntryAction } from '../common/model/NoteEditorEntryAction'
import { navigateToNoteEdit } from '../common/utils/NoteEditNavigation'
import { navigateToFlowchart } from '../common/utils/FlowchartNavigation'
import { AppLockPinPanel } from '../components/AppLockPinPanel'
import { AppLockService } from '../services/AppLockService'
import { APP_LOCALE_REVISION_KEY, LocaleService } from '../services/LocaleService'
import { EditorUiStrings } from '../common/utils/EditorUiStrings'

/** 与 HomeDrawerLayer 内 DRAWER_SPAN 一致，用于全屏横向拖动手势计算行程。 */
const DRAWER_OFFSCREEN_PAD = 20
const DRAWER_SPAN = 248 * 1.2 + DRAWER_OFFSCREEN_PAD
/** 松手吸附动画时长（抽屉已由手指实时拖动，此处仅收尾过渡）。 */
const DRAWER_SNAP_MS = 220
/** 搜索框输入防抖后再筛选列表，降低大库全文扫描频率。 */
const SEARCH_DEBOUNCE_MS = 280
/** 与 Flutter `_minHomeNotesReloadInterval`：`onPageShow` 再次拉列表的最短间隔，避免短时间内重复请求。 */
const MIN_HOME_PAGE_SHOW_RELOAD_INTERVAL_MS = 5000
const ALL_NOTES_TAG = '__ALL_NOTES__'

@Entry
@Component
struct Index {
  @StorageProp(APP_LOCALE_REVISION_KEY) @Watch('onLocaleChanged') localeRevision: number = 0
  @State notes: Note[] = []
  @State allNotes: Note[] = []
  @State tags: string[] = []
  @State selectedTag: string = ALL_NOTES_TAG
  @State filterMode: HomeSidebarFilterMode = 'tag'
  @State folderModeEnabled: boolean = false
  @State expandedFolderIds: string[] = []
  @State searchQuery: string = ''
  @State searchExpanded: boolean = false
  @State loading: boolean = false
  @State syncing: boolean = false
  @State refreshing: boolean = false
  /** 抽屉开启比例 0～1：`DrawerModel` 为 @Observed，经 @Provide 由 HomeDrawerLayer @Consume（勿使用 `$drawerModel` 初始化子组件）。 */
  @Provide('drawerModel') drawerModel: DrawerModel = new DrawerModel()
  /** 菜单「汉堡」每次点击递增，子组件 @Watch 内切换开/关。 */
  @State drawerToggleNonce: number = 0
  /** 选标签或跳转前递增，子组件 @Watch 内吸附关闭。 */
  @State drawerCloseNonce: number = 0
  @State pageWidth: number = 360
  @State pageHeight: number = 780
  /** 已配置自建 WebDAV，或轻羽云订阅有效（active/lifetime）时为 true，右上角不展示「去配置」图标；首帧默认 true 以免误闪。 */
  @State cloudSyncConfigured: boolean = true
  /** 侧栏顶部用户信息，与 Flutter `HomePage` 抽屉区一致。 */
  @State drawerUsername: string = ''
  @State drawerAvatarUrl: string = ''
  @State drawerGuestMode: boolean = false
  @State drawerLoggedIn: boolean = false
  @State appLockBlocking: boolean = false
  @State appLockRecovering: boolean = false
  @State undoNoteId: string = ''
  @State undoBarVisible: boolean = false
  private undoHideTimer: number = -1
  private hasShownOnce: boolean = false
  private startupSyncHandled: boolean = false
  /** 仅统计「非首次」onPageShow 触发的 loadNotes 完成时间；与 initializeHome 首次加载无关，避免阻断从编辑页返回后的刷新。 */
  private lastPageShowNotesReloadAtMs: number = 0
  /** 当前水平拖动开始时抽屉进度，用于计算跟手位移。 */
  private drawerPanStartProgress: number = 0
  private searchFilterTimer: number = -1
  /** 丢弃过期的 loadNotes，且与 Flutter `_notesLoadGeneration` 一致在 finally 收敛 loading。 */
  private notesLoadGeneration: number = 0
  private noteListDataSource: IndexNotesDataSource = new IndexNotesDataSource()
  private qingyuBlockedHandler = (): void => {
    void this.showQingyuSubscriptionBlockedDialog()
  }
  private cloudSyncNotConfiguredHandler = (): void => {
    void this.showCloudSyncNotConfiguredToastIfAllowed()
  }
  private noteSettingsChangedHandler = (): void => {
    void this.reloadNoteSettingsFromService()
    void this.refreshAppLockState()
  }
  private wereadImportToastHandler = (payload: WereadImportToastPayload): void => {
    const message = payload?.message ?? ''
    if (message.trim().length > 0) {
      this.showUserMessage(message.trim())
    }
  }
  private yinxiangImportToastHandler = (payload: YinxiangImportToastPayload): void => {
    const message = payload?.message ?? ''
    if (message.trim().length > 0) {
      this.showUserMessage(message.trim())
    }
  }
  private lifecycle = new PageLifecycle()

  aboutToAppear(): void {
    Logger.info('LinkExtractDebug', `trigger=aboutToAppear`)
    this.lifecycle.appear()
    AppContextHolder.setLastUiContext(this.getUIContext())
    try {
      AppContextHolder.getContext().eventHub.on(SyncConstants.qingyuSyncBlockedEvent, this.qingyuBlockedHandler)
      AppContextHolder.getContext().eventHub.on(SyncConstants.cloudSyncNotConfiguredToastEvent,
        this.cloudSyncNotConfiguredHandler)
      AppContextHolder.getContext().eventHub.on(SyncConstants.noteSettingsChangedEvent,
        this.noteSettingsChangedHandler)
      AppContextHolder.getContext().eventHub.on(SyncConstants.wereadImportToastEvent,
        this.wereadImportToastHandler)
      AppContextHolder.getContext().eventHub.on(SyncConstants.yinxiangImportToastEvent,
        this.yinxiangImportToastHandler)
    } catch (_) {
      console.error('Index: eventHub.on qingyu_sync_blocked failed')
    }
    void this.initializeHome()
  }

  aboutToDisappear(): void {
    this.lifecycle.disappear()
    try {
      AppContextHolder.getContext().eventHub.off(SyncConstants.qingyuSyncBlockedEvent, this.qingyuBlockedHandler)
      AppContextHolder.getContext().eventHub.off(SyncConstants.cloudSyncNotConfiguredToastEvent,
        this.cloudSyncNotConfiguredHandler)
      AppContextHolder.getContext().eventHub.off(SyncConstants.noteSettingsChangedEvent,
        this.noteSettingsChangedHandler)
      AppContextHolder.getContext().eventHub.off(SyncConstants.wereadImportToastEvent,
        this.wereadImportToastHandler)
      AppContextHolder.getContext().eventHub.off(SyncConstants.yinxiangImportToastEvent,
        this.yinxiangImportToastHandler)
    } catch (_) {
      console.error('Index: eventHub.off qingyu_sync_blocked failed')
    }
    this.clearSearchFilterTimer()
    this.clearUndoHideTimer()
  }

  private async showQingyuSubscriptionBlockedDialog(): Promise<void> {
    if (!(await PreferencesService.getInstance().canRunCloudSync())) {
      return
    }
    if (!CloudSyncNotifyThrottle.tryConsumeQingyuSubscriptionDialogSlot()) {
      return
    }
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '提示',
        message: '请开通轻羽云服务',
        buttons: [
          { text: '稍后', color: '#6B7280' },
          { text: '去开通', color: '#0DAA4A' }
        ]
      })
      if (result.index === 1) {
        this.getUIContext().getRouter().pushUrl({ url: 'pages/QingyuCloudRecharge' }).catch((err: Error) => {
          console.error(`push QingyuCloudRecharge: ${JSON.stringify(err)}`)
        })
      }
    } catch (_) {
      console.error('showQingyuSubscriptionBlockedDialog failed')
    }
  }

  private async showCloudSyncNotConfiguredToastIfAllowed(): Promise<void> {
    if (!(await PreferencesService.getInstance().canRunCloudSync())) {
      return
    }
    this.showUserMessage('当前未配置云服务')
  }

  onPageShow(): void {
    Logger.info('LinkExtractDebug', `trigger=onPageShow`)
    void this.handleIndexPageShow()
  }

  private async handleIndexPageShow(): Promise<void> {
    AppContextHolder.setLastUiContext(this.getUIContext())
    await this.ensureLoggedInOrRedirectToLogin()
    if (!this.lifecycle.isActive()) {
      return
    }
    void recheckForceUpdateOnResume(this.getUIContext())
    void this.loadDrawerUserProfile()
    void navigateToBindPhoneIfNeeded(this.getUIContext())
    void maybeShowReferralInviteDialog(this.getUIContext())
    void this.runHomeEntryNetworkSetup()
    void this.loadDrawerUserProfile()
    if (!this.hasShownOnce) {
      this.hasShownOnce = true
      return
    }
    const now = Date.now()
    if (this.lastPageShowNotesReloadAtMs > 0 &&
      now - this.lastPageShowNotesReloadAtMs < MIN_HOME_PAGE_SHOW_RELOAD_INTERVAL_MS) {
      // 节流窗口内仍允许拉一次 extract status（轻量，不打列表接口）。
      Logger.info('LinkExtractDebug', `trigger=onPageShow throttled, calling refreshExtractStatuses`)
      void this.refreshExtractStatuses()
      return
    }
    Logger.info('LinkExtractDebug', `trigger=onPageShow full, calling refreshExtractStatuses+loadNotes`)
    await this.refreshExtractStatuses()
    await this.loadNotes(false)
    if (this.lifecycle.isActive()) {
      this.lastPageShowNotesReloadAtMs = Date.now()
    }
  }

  /** 退出登录后若仍停留在首页栈，则拉回登录页 */
  private async ensureLoggedInOrRedirectToLogin(): Promise<void> {
    try {
      const context = AppContextHolder.tryGetContext()
      if (context) {
        await PreferencesService.getInstance().init(context)
      }
      const loggedIn = await PreferencesService.getInstance().isUserLoggedIn()
      const guest = await PreferencesService.getInstance().isGuestMode()
      if (!loggedIn && !guest) {
        await this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' })
      }
    } catch (_) {
    }
  }

  private async initializeHome(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    if (!this.lifecycle.isActive()) {
      return
    }
    await this.refreshAppLockState()
    if (!this.lifecycle.isActive()) {
      return
    }
    void this.loadDrawerUserProfile()
    /** 启动时清理超过 30 天未编辑的回收站笔记（与新版首页回收站 Tab 一致）。 */
    try {
      await NoteRepository.getInstance().purgeExpiredRecycleBinNotes()
    } catch (error) {
      Logger.warn('Index', `purgeExpiredRecycleBinNotes failed: ${JSON.stringify(error)}`)
    }
    await this.loadNotes(this.allNotes.length === 0)
    if (!this.lifecycle.isActive()) {
      return
    }
    /** 先完成自动开通与上报，再判定启动同步，避免首启竞态导致有订阅却未选用轻羽云。 */
    await this.runHomeEntryNetworkSetup()
    await runAppUpdateCheckOnLaunch(this.getUIContext())
    if (this.lifecycle.isActive()) {
      void navigateToBindPhoneIfNeeded(this.getUIContext())
      void maybeShowReferralInviteDialog(this.getUIContext())
    }
  }

  private async runHomeEntryNetworkSetup(): Promise<void> {
    try {
      await tryAutoProvisionQingyuCloudOnHomeEntry()
      await SyncSettingsRemoteReport.getInstance().reportCurrentIfPossible()
      if (!this.lifecycle.isActive()) {
        return
      }
      await this.refreshCloudSyncConfiguredState()
      if (!this.lifecycle.isActive()) {
        return
      }
      if (!this.startupSyncHandled && await this.shouldRunStartupSync()) {
        this.startupSyncHandled = true
        void this.maybeSyncAfterInitialLoad()
      }
    } catch (error) {
      Logger.error('Index', `runHomeEntryNetworkSetup failed: ${JSON.stringify(error)}`)
    }
  }

  private async startStartupSyncIfNeeded(): Promise<void> {
    if (await this.shouldRunStartupSync()) {
      void this.maybeSyncAfterInitialLoad()
    }
  }

  private async reloadNoteSettingsFromService(): Promise<void> {
    await this.ensurePreferencesInitialized()
    if (!this.lifecycle.isActive()) {
      return
    }
    this.folderModeEnabled =
      await PreferencesService.getInstance().getNoteFolderModeEnabled()
    let filterMode = await PreferencesService.getInstance().getHomeSidebarFilterMode()
    if (!this.lifecycle.isActive()) {
      return
    }
    if (!this.folderModeEnabled && filterMode === 'folder') {
      filterMode = 'tag'
      await PreferencesService.getInstance().setHomeSidebarFilterMode('tag')
    }
    if (this.lifecycle.isActive()) {
      this.filterMode = filterMode
      this.applyTagFilter()
    }
  }

  private async refreshAppLockState(): Promise<void> {
    const blocking = await AppLockService.getInstance().needsUnlockOnLaunch()
    if (this.lifecycle.isActive()) {
      this.appLockBlocking = blocking
    }
  }

  private async handleAppLockForgotPassword(): Promise<void> {
    if (this.appLockRecovering) {
      return
    }
    this.appLockRecovering = true
    try {
      await AppLockService.getInstance().forgotPasswordOnLaunch()
    } finally {
      if (this.lifecycle.isActive()) {
        this.appLockRecovering = false
        this.appLockBlocking = false
      }
    }
    if (this.lifecycle.isActive()) {
      await this.ensureLoggedInOrRedirectToLogin()
    }
  }

  private async loadNotes(showLoading: boolean = false): Promise<void> {
    const generation = ++this.notesLoadGeneration
    if (showLoading && this.lifecycle.isActive()) {
      this.loading = true
    }
    try {
      if (!this.lifecycle.isActive()) {
        return
      }
      const context = AppContextHolder.tryGetContext()
      if (context) {
        await PreferencesService.getInstance().init(context)
      }
      await NoteRepository.getInstance().init()
      const listedNotes = await NoteRepository.getInstance().listNotes()
      if (!this.lifecycle.isActive()) {
        return
      }
      this.allNotes = listedNotes
      await this.ensurePreferencesInitialized()
      this.folderModeEnabled =
        await PreferencesService.getInstance().getNoteFolderModeEnabled()
      let filterMode = await PreferencesService.getInstance().getHomeSidebarFilterMode()
      if (!this.lifecycle.isActive()) {
        return
      }
      if (!this.folderModeEnabled && filterMode === 'folder') {
        filterMode = 'tag'
        await PreferencesService.getInstance().setHomeSidebarFilterMode('tag')
      }
      this.filterMode = filterMode
      await this.refreshTagCatalog(listedNotes)
      if (this.lifecycle.isActive()) {
        this.applyTagFilter()
      }
    } finally {
      if (this.lifecycle.isActive() && generation === this.notesLoadGeneration) {
        this.loading = false
      }
    }
  }

  private async maybeSyncAfterInitialLoad(): Promise<void> {
    const notesVersion = NoteRepository.getInstance().getNotesVersion()
    this.syncing = true
    try {
      const results = await this.runSyncWithTimeout()
      if (results.some((result: SyncResult) => !result.success)) {
        const summary = this.summarizeSyncResult(results)
        if (summary) {
          this.showUserMessage(summary)
        }
      }
    } catch (error) {
      Logger.error('Index', `maybeSyncAfterInitialLoad failed: ${JSON.stringify(error)}`)
      console.error(JSON.stringify(error))
      this.showUserMessage(this.formatActionError('自动同步', error))
    } finally {
      try {
        await this.refreshNotesIfChanged(notesVersion)
      } finally {
        this.releaseSyncProgressUi()
      }
    }
  }

  /** 已配置完整自建 WebDAV，或轻羽云订阅有效（active/lifetime）时为 true，右上角不展示配置入口。 */
  private async refreshCloudSyncConfiguredState(): Promise<void> {
    try {
      const context = AppContextHolder.tryGetContext()
      if (context) {
        await PreferencesService.getInstance().init(context)
      }
      if (await PreferencesService.getInstance().hasEnabledCustomWebDAVConfig()) {
        if (this.lifecycle.isActive()) {
          this.cloudSyncConfigured = true
        }
        return
      }
      const status =
        await WebDAVClient.getInstance().fetchQingyuCloudSubscriptionStatus(previewQingyuForHomeSubscription)
      if (!this.lifecycle.isActive()) {
        return
      }
      const purchased = status.kind === 'lifetime' || status.kind === 'active'
      this.cloudSyncConfigured = purchased
    } catch (_) {
      if (this.lifecycle.isActive()) {
        this.cloudSyncConfigured = false
      }
    }
  }

  /** 仅在手动下拉刷新时使用：是否完全没配置任何云存储（既无轻羽云订阅、也未配置自建 WebDAV）。
   *  拉取失败视为「未配置」，与齿轮入口的容错策略保持一致。 */
  private async hasAnyCloudStorageForPullRefresh(): Promise<boolean> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    const snap = await PreferencesService.getInstance().getSavedCustomWebDAVConfigSnapshot()
    if (snap !== null && snap.enabled) {
      return true
    }
    try {
      const status =
        await WebDAVClient.getInstance().fetchQingyuCloudSubscriptionStatus(previewQingyuForHomeSubscription)
      return status.kind === 'lifetime' || status.kind === 'active'
    } catch (_) {
      return false
    }
  }

  private async shouldRunStartupSync(): Promise<boolean> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    if (!(await PreferencesService.getInstance().canRunCloudSync())) {
      return false
    }
    const config = await PreferencesService.getInstance().getWebDAVConfig()
    if (!config || !config.enabled) {
      return false
    }
    return !(await PreferencesService.getInstance().isAuthInvalid())
  }

  private async handleSyncNow(): Promise<void> {
    if (this.syncing) {
      return
    }
    const notesVersion = NoteRepository.getInstance().getNotesVersion()
    this.syncing = true
    try {
      const results = await this.runSyncWithTimeout()
      await this.refreshNotesIfChanged(notesVersion)
      const summary = this.summarizeSyncResult(results)
      if (summary) {
        this.showUserMessage(summary)
      }
    } catch (error) {
      Logger.error('Index', `handleSyncNow failed: ${JSON.stringify(error)}`)
      console.error(JSON.stringify(error))
      this.showUserMessage(this.formatActionError('同步', error))
    } finally {
      this.releaseSyncProgressUi()
    }
  }

  /** 结束任意来源的全量同步：收起顶部下拉刷新指示并解除「同步中」状态。 */
  private releaseSyncProgressUi(): void {
    this.syncing = false
    this.refreshing = false
  }

  private async handlePullToRefresh(): Promise<void> {
    Logger.info('LinkExtractDebug', `trigger=pullToRefresh start`)
    if (this.syncing) {
      /** 后台已在同步：不重复拉列表/请求同步，仅保持下拉刷新动画表示「仍在同步」。动画在 `releaseSyncProgressUi` 时收起。 */
      this.refreshing = true
      return
    }
    try {
      Logger.info('LinkExtractDebug', `trigger=pullToRefresh calling refreshExtractStatuses`)
      await this.refreshExtractStatuses()
      await this.loadNotes(false)
      await tryAutoProvisionQingyuCloudOnHomeEntry()
      await SyncSettingsRemoteReport.getInstance().reportCurrentIfPossible()
      await this.refreshCloudSyncConfiguredState()
      if (!(await this.hasAnyCloudStorageForPullRefresh())) {
        this.showUserMessage('未配置云存储，无法同步笔记')
        return
      }
      await this.handleSyncNow()
    } finally {
      this.refreshing = false
    }
  }

  /** 不对整次 syncNow 做外层超时：笔记量大时易误判；单次请求仍有超时。 */
  private async runSyncWithTimeout(): Promise<SyncResult[]> {
    return await SyncService.getInstance().syncNow()
  }

  private async handleDelete(noteId: string): Promise<void> {
    const previousAllNotes = [...this.allNotes]
    this.allNotes = this.allNotes.filter((note: Note) => note.id !== noteId)
    this.applyTagFilter()
    try {
      await NoteRepository.getInstance().deleteNote(noteId, Date.now())
      await this.refreshTagCatalog(this.allNotes)
      this.showUndoBar(noteId)
    } catch (error) {
      this.allNotes = previousAllNotes
      this.applyTagFilter()
      await this.loadNotes(false)
      console.error(JSON.stringify(error))
      this.showUserMessage(this.formatActionError('删除', error))
    }
  }

  private clearUndoHideTimer(): void {
    if (this.undoHideTimer >= 0) {
      clearTimeout(this.undoHideTimer)
      this.undoHideTimer = -1
    }
  }

  private showUndoBar(noteId: string): void {
    this.clearUndoHideTimer()
    this.undoNoteId = noteId
    this.undoBarVisible = true
    this.undoHideTimer = setTimeout((): void => {
      this.undoBarVisible = false
      this.undoNoteId = ''
      this.undoHideTimer = -1
    }, 5000)
  }

  private async undoDelete(): Promise<void> {
    const noteId = this.undoNoteId
    this.clearUndoHideTimer()
    this.undoBarVisible = false
    this.undoNoteId = ''
    if (noteId.length === 0) {
      return
    }
    try {
      await NoteRepository.getInstance().restoreRecycleBinNote(noteId)
      await this.loadNotes(false)
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage(this.formatActionError('撤销', error))
      await this.loadNotes(false)
    }
  }

  private async openEditor(
    noteId?: string,
    openWithPreview: boolean = false,
    initialAction?: NoteEditorEntryAction
  ): Promise<void> {
    try {
      await navigateToNoteEdit(this.getUIContext(), {
        noteId: noteId,
        openWithPreview: openWithPreview,
        initialAction: initialAction
      })
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage(this.formatActionError('打开编辑页', error))
    }
  }

  private async openVoiceNote(): Promise<void> {
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/VoiceNote'
      })
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage(this.formatActionError('打开语音笔记', error))
    }
  }

  private onHomeTodoTabPressed(): void {
    if (this.searchExpanded) {
      this.searchExpanded = false
      return
    }
    void this.openEditor(undefined, false, 'todoList')
  }

  private async ensurePreferencesInitialized(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
  }

  private normalizeTags(tags: string[]): string[] {
    const seen: Set<string> = new Set()
    const normalized: string[] = []
    for (const rawTag of tags) {
      const tag = `${rawTag ?? ''}`.trim()
      if (tag.length === 0 || seen.has(tag)) {
        continue
      }
      seen.add(tag)
      normalized.push(tag)
    }
    normalized.sort((left: string, right: string) => left.localeCompare(right, 'zh-Hans-CN'))
    return normalized
  }

  private extractTagsFromNotes(notes: Note[]): string[] {
    const collected: string[] = []
    for (const note of notes) {
      for (const tag of note.tags) {
        collected.push(tag)
      }
    }
    return this.normalizeTags(collected)
  }

  private async refreshTagCatalog(notes: Note[]): Promise<void> {
    await this.ensurePreferencesInitialized()
    const storedTags = await PreferencesService.getInstance().getNoteTags()
    const mergedTags = this.normalizeTags(this.extractTagsFromNotes(notes).concat(storedTags))
    this.tags = TagSortUtils.sortByNoteCountDesc(mergedTags, notes)
    this.validateSidebarSelection(notes)
  }

  private validateSidebarSelection(notes: Note[]): void {
    if (this.selectedTag === ALL_NOTES_TAG) {
      return
    }
    if (!this.folderModeEnabled || this.filterMode === 'tag') {
      if (!this.tags.includes(this.selectedTag)) {
        this.selectedTag = ALL_NOTES_TAG
      }
      return
    }
    if (!NoteFolderTree.folderNoteIds(notes).has(this.selectedTag)) {
      this.selectedTag = ALL_NOTES_TAG
    }
  }

  private expandedFolderIdSet(): Set<string> {
    return new Set(this.expandedFolderIds)
  }

  private getFolderSidebarRows(): FolderSidebarRow[] {
    return NoteFolderTree.visibleSidebarRows(this.allNotes, this.expandedFolderIdSet())
  }

  private async setFilterMode(mode: HomeSidebarFilterMode): Promise<void> {
    if (!this.folderModeEnabled && mode === 'folder') {
      return
    }
    if (this.filterMode === mode) {
      return
    }
    await this.ensurePreferencesInitialized()
    await PreferencesService.getInstance().setHomeSidebarFilterMode(mode)
    this.filterMode = mode
    this.selectedTag = ALL_NOTES_TAG
    this.expandedFolderIds = []
    this.applyTagFilter()
  }

  private clearSearchFilterTimer(): void {
    if (this.searchFilterTimer !== -1) {
      clearTimeout(this.searchFilterTimer)
      this.searchFilterTimer = -1
    }
  }

  /** 搜索框输入防抖后再执行筛选；其它路径（加载、删笔记等）请直接调用 applyTagFilter。 */
  private scheduleSearchFilterApply(): void {
    this.clearSearchFilterTimer()
    this.searchFilterTimer = setTimeout(() => {
      this.searchFilterTimer = -1
      this.applyTagFilter()
    }, SEARCH_DEBOUNCE_MS)
  }

  private applyTagFilter(): void {
    let pool: Note[] = []
    if (this.selectedTag === ALL_NOTES_TAG) {
      pool = [...this.allNotes]
    } else if (!this.folderModeEnabled || this.filterMode === 'tag') {
      pool = this.allNotes.filter((note: Note) => note.tags.includes(this.selectedTag))
    } else {
      pool = this.allNotes.filter((note: Note) =>
        NoteFolderTree.isUnderFolder(note, this.selectedTag, this.allNotes))
    }
    const raw = this.searchQuery.trim()
    if (raw.length > 0) {
      const q = raw.toLowerCase()
      pool = pool.filter((note: Note) => {
        const title = `${note.title ?? ''}`.toLowerCase()
        const summaryText = `${note.summary ?? ''}`.toLowerCase()
        const contentText = `${note.content ?? ''}`.toLowerCase()
        return title.includes(q) || summaryText.includes(q) || contentText.includes(q)
      })
    }
    this.updateNotes(pool)
  }

  private selectTag(tag: string): void {
    const rootInFolderMode =
      this.folderModeEnabled && this.filterMode === 'folder' && tag === ALL_NOTES_TAG
    if (tag === this.selectedTag) {
      if (rootInFolderMode) {
        this.drawerCloseNonce += 1
      }
      return
    }
    this.selectedTag = tag
    this.applyTagFilter()
    if (!this.folderModeEnabled || this.filterMode === 'tag' || rootInFolderMode) {
      this.drawerCloseNonce += 1
    }
  }

  private selectFolder(folderId: string): void {
    this.selectedTag = folderId
    const expanded = this.expandedFolderIdSet()
    NoteFolderTree.applyToggleExpand(folderId, this.allNotes, expanded)
    this.expandedFolderIds = Array.from(expanded)
    this.applyTagFilter()
  }

  private animateDrawerSnapTo(targetOpen: number): void {
    const target = targetOpen >= 0.5 ? 1 : 0
    if (Math.abs(this.drawerModel.progress - target) < 0.001) {
      return
    }
    this.getUIContext().animateTo({
      duration: DRAWER_SNAP_MS,
      curve: Curve.EaseOut
    }, () => {
      this.drawerModel.progress = target
    })
  }

  private onDrawerPanStart(): void {
    this.drawerPanStartProgress = this.drawerModel.progress
  }

  /** 手指拖动：进度随累计水平位移连续变化（行程含 OFFSCREEN_PAD，与 translate 一致）。 */
  private onDrawerPanUpdate(event: GestureEvent): void {
    const next = this.drawerPanStartProgress + event.offsetX / DRAWER_SPAN
    if (next <= 0) {
      this.drawerModel.progress = 0
    } else if (next >= 1) {
      this.drawerModel.progress = 1
    } else {
      this.drawerModel.progress = next
    }
  }

  /** 手指抬起：按当前位置过半吸附到完全开或完全关（ArkTS 不便读取 velocity 时用位置判定）。 */
  private onDrawerPanEnd(_event: GestureEvent): void {
    this.animateDrawerSnapTo(this.drawerModel.progress >= 0.5 ? 1 : 0)
  }

  private async openTagEditor(): Promise<void> {
    this.drawerCloseNonce += 1
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/TagManage'
      })
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage(this.formatActionError('打开标签页', error))
    }
  }

  private async openFolderManage(): Promise<void> {
    this.drawerCloseNonce += 1
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/FolderManage'
      })
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage(this.formatActionError('打开文件管理', error))
    }
  }

  private async openFlowchart(noteId: string, focusQuery: string = ''): Promise<void> {
    this.drawerCloseNonce += 1
    try {
      await navigateToFlowchart(this.getUIContext(), {
        noteId: noteId,
        focusQuery: focusQuery
      })
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage(this.formatActionError('打开流程图', error))
    }
  }

  private async openFlowchartFromDrawer(): Promise<void> {
    const noteId = IdUtils.uuid()
    await this.openFlowchart(noteId)
  }

  private async openNoteFromList(note: Note): Promise<void> {
    if (note.type_ === 2) {
      const q = this.searchQuery.trim()
      await this.openFlowchart(note.id, q)
      return
    }
    if (isExtractStatusPending(note.extractStatus) ||
      note.extractStatus === 'failed' ||
      note.voiceTranscribeStatus === 'running' ||
      note.voiceTranscribeStatus === 'failed') {
      const kind = note.sourceUrl.trim().length === 0 &&
        note.extractStatus !== 'failed' &&
        !isExtractStatusPending(note.extractStatus)
        ? 'voiceTranscribe'
        : 'linkExtract'
      try {
        await this.getUIContext().getRouter().pushUrl({
          url: 'pages/LinkExtractProgress',
          params: {
            noteId: note.id,
            kind: kind,
            url: note.sourceUrl.trim()
          }
        })
      } catch (error) {
        console.error(`open LinkExtractProgress: ${JSON.stringify(error)}`)
      }
      return
    }
    if (`${note.audioId ?? ''}`.trim().length > 0) {
      try {
        await this.getUIContext().getRouter().pushUrl({
          url: 'pages/VoiceNoteDetail',
          params: { noteId: note.id }
        })
      } catch (error) {
        console.error(JSON.stringify(error))
        this.showUserMessage(this.formatActionError('打开语音笔记', error))
      }
      return
    }
    const hasBody = `${note.content ?? ''}`.trim().length > 0
    await this.openEditor(note.id, hasBody)
  }

  private async openRecycleBin(): Promise<void> {
    this.drawerCloseNonce += 1
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/RecycleBin'
      })
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage(this.formatActionError('打开回收站', error))
    }
  }

  private async openSettingsFromDrawer(): Promise<void> {
    this.drawerCloseNonce += 1
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/Settings'
      })
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage(this.formatActionError('打开设置页', error))
    }
  }

  private async loadDrawerUserProfile(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    if (!this.lifecycle.isActive()) {
      return
    }
    const uid = (await PreferencesService.getInstance().getNoteApiUserId()).trim()
    const guest = await PreferencesService.getInstance().isGuestMode()
    const loggedIn = uid.length > 0
    if (this.lifecycle.isActive()) {
      this.drawerGuestMode = guest
      this.drawerLoggedIn = loggedIn
    }
    if (!loggedIn) {
      if (this.lifecycle.isActive()) {
        this.drawerUsername = ''
        this.drawerAvatarUrl = ''
      }
      return
    }
    const cachedRaw = await PreferencesService.getInstance().getCachedUserProfile()
    const cached = cachedRaw !== null ? cachedRaw as ProfileBody : null
    if (this.lifecycle.isActive() && cached !== null) {
      this.drawerUsername = (cached.username ?? '').trim()
      this.drawerAvatarUrl = (cached.avatar_url ?? '').trim()
    }
    const profile = await NoteApiClient.getInstance().fetchProfile()
    if (!this.lifecycle.isActive()) {
      return
    }
    const resolved = profile ?? cached
    if (resolved !== null) {
      this.drawerUsername = (resolved.username ?? '').trim()
      this.drawerAvatarUrl = (resolved.avatar_url ?? '').trim()
    }
  }

  private async openProfileFromDrawer(): Promise<void> {
    this.drawerCloseNonce += 1
    try {
      if (this.drawerGuestMode || !this.drawerLoggedIn) {
        await this.getUIContext().getRouter().pushUrl({ url: 'pages/Login' })
      } else {
        await this.getUIContext().getRouter().pushUrl({ url: 'pages/Profile' })
      }
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage(this.formatActionError('打开个人信息', error))
    }
    void this.loadDrawerUserProfile()
  }

  private async openWebDAVSettings(): Promise<void> {
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/CloudSyncSettings'
      })
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage('打开云同步设置失败，请稍后重试')
    }
  }

  private statusLabel(status: SyncStatus): string {
    if (status === 'synced') {
      return '已同步'
    }
    if (status === 'error') {
      return '错误'
    }
    return '待同步'
  }

  private statusColor(status: SyncStatus): ResourceColor {
    if (status === 'synced') {
      return $r('app.color.success')
    }
    if (status === 'error') {
      return $r('app.color.danger')
    }
    return $r('app.color.warning')
  }

  private shouldShowUnsyncedBadge(note: Note): boolean {
    return note.syncStatus !== 'synced'
  }

  private updateNotes(notes: Note[]): void {
    if (this.areNotesEqual(this.notes, notes)) {
      return
    }
    this.notes = notes
    this.noteListDataSource.replaceAll(notes)
  }

  private areNotesEqual(left: Note[], right: Note[]): boolean {
    if (left.length !== right.length) {
      return false
    }
    for (let index = 0; index < left.length; index += 1) {
      if (left[index].id !== right[index].id || left[index].title !== right[index].title
        || left[index].summary !== right[index].summary || left[index].updatedAt !== right[index].updatedAt
        || left[index].syncStatus !== right[index].syncStatus) {
        return false
      }
    }
    return true
  }

  private noteListItemKey(note: Note): string {
    return `${note.id}:${note.title}:${note.summary}:${note.syncStatus}:${note.updatedAt}`
  }

  private showUserMessage(message: string): void {
    if (message.trim().length === 0) {
      return
    }
    if (CloudSyncNotifyThrottle.shouldSuppressUserMessage(message)) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message,
        duration: 2000
      })
    } catch (error) {
      console.error(`showToast failed: ${JSON.stringify(error)}`)
    }
  }

  private formatActionError(actionLabel: string, error: Object | string | undefined): string {
    let rawMessage = ''
    if (typeof error === 'string') {
      rawMessage = error
    } else {
      const serialized = JSON.stringify(error)
      rawMessage = serialized && serialized !== '{}' ? serialized : `${error ?? ''}`
    }
    const normalizedMessage = rawMessage.toLowerCase()
    if (normalizedMessage.includes('authentication')) {
      return LocaleService.loc(
        `${actionLabel}失败：账号或密码可能已失效，请检查同步设置`,
        `${actionLabel} failed: credentials may be invalid; check sync settings`,
        `${actionLabel}失敗：認証情報が無効の可能性があります。同期設定を確認してください`)
    }
    if (normalizedMessage.includes('qingyu webdav credentials unavailable')) {
      return LocaleService.loc(
        `${actionLabel}失败：暂时无法连接轻羽云存储，请稍后重试或检查网络`,
        `${actionLabel} failed: cannot reach Qingyu Cloud; check network`,
        `${actionLabel}失敗：Qingyu Cloudに接続できません。ネットワークを確認してください`)
    }
    if (normalizedMessage.includes('not configured')) {
      return LocaleService.loc(
        `${actionLabel}失败：请先完成 WebDAV 配置`,
        `${actionLabel} failed: complete WebDAV setup first`,
        `${actionLabel}失敗：先にWebDAV設定を完了してください`)
    }
    if (normalizedMessage.includes('timeout')) {
      return LocaleService.loc(
        `${actionLabel}失败：请求超时，请稍后重试`,
        `${actionLabel} failed: timed out, please try again`,
        `${actionLabel}失敗：タイムアウトしました。後でもう一度お試しください`)
    }
    if (normalizedMessage.includes('100002') || normalizedMessage.includes('uri error')
      || normalizedMessage.includes('does not exist') || normalizedMessage.includes('not exist')) {
      return LocaleService.loc(
        `${actionLabel}失败：目标页面不可用`,
        `${actionLabel} failed: target unavailable`,
        `${actionLabel}失敗：ページが利用できません`)
    }
    return LocaleService.loc(
      `${actionLabel}失败，请稍后重试`,
      `${actionLabel} failed, please try again`,
      `${actionLabel}に失敗しました。後でもう一度お試しください`)
  }

  private summarizeSyncResult(results: SyncResult[]): string | null {
    const more = SyncService.getInstance().getLastFullSyncHadMoreNotes()
    if (results.length === 0) {
      return more
        ? LocaleService.loc('已同步本批笔记，请再次下拉以继续同步剩余条目',
          'Batch synced. Pull down again to sync remaining notes.',
          'このバッチの同期が完了しました。残りを同期するには再度プルダウンしてください')
        : LocaleService.loc('同步完成', 'Sync complete', '同期完了')
    }
    const failedResults = results.filter((result: SyncResult) => !result.success)
    if (failedResults.length === 0) {
      if (more) {
        return LocaleService.loc('已同步本批笔记，请再次下拉以继续同步剩余条目',
          'Batch synced. Pull down again to sync remaining notes.',
          'このバッチの同期が完了しました。残りを同期するには再度プルダウンしてください')
      }
      return LocaleService.loc('同步完成', 'Sync complete', '同期完了')
    }
    if (failedResults.length === 1 && failedResults[0].message.trim().length > 0) {
      return UserFacingMessage.forSyncNoteFailure(failedResults[0].message)
    }
    return LocaleService.loc(
      `同步完成，但有 ${failedResults.length} 条笔记同步失败`,
      `Sync complete, but ${failedResults.length} note(s) failed to sync`,
      `同期完了しましたが、${failedResults.length}件のノートの同期に失敗しました`)
  }

  private async refreshNotesIfChanged(previousVersion: number): Promise<void> {
    if (NoteRepository.getInstance().getNotesVersion() === previousVersion) {
      return
    }
    await this.loadNotes(false)
  }

  @Builder
  private buildMenuAction() {
    Row() {
      Image($r('app.media.ic_menu'))
        .width(22)
        .height(22)
        .objectFit(ImageFit.Contain)
    }
    .height( $r('app.float.search_box_height'))
    .padding({
      left: $r('app.float.toolbar_icon_button_padding_h'),
      right: $r('app.float.toolbar_icon_button_padding_h')
    })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.surface_muted'))
    .borderRadius($r('app.float.pill_radius'))
    .onClick(() => {
      this.drawerToggleNonce += 1
    })
  }

  @Builder
  private buildSettingsAction() {
    Row() {
      SymbolGlyph($r('sys.symbol.gearshape'))
        .fontSize(20)
        .fontColor([$r('app.color.primary_text')])
    }
    .height($r('app.float.search_box_height'))
    .padding({
      left: $r('app.float.toolbar_icon_button_padding_h'),
      right: $r('app.float.toolbar_icon_button_padding_h')
    })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.surface_muted'))
    .borderRadius($r('app.float.pill_radius'))
    .onClick(() => {
      void this.openWebDAVSettings()
    })
  }

  @Builder
  private buildEmptyStateCard() {
    Column({ space: 20 }) {
      Column({ space: 12 }) {
        Text('✦')
          .fontSize(40)
          .fontColor($r('app.color.accent'))
          .opacity(0.85)
        Text(LocaleService.loc('从这里开始', 'Start here', 'ここから始める'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Text($r('app.string.empty_notes'))
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Center)
          .lineHeight(24)
        Row({ space: 10 }) {
          Button(LocaleService.loc('语音笔记', 'Voice note', '音声ノート'))
            .layoutWeight(1)
            .height(44)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius(22)
            .onClick(() => {
              void this.openVoiceNote()
            })
          Button(LocaleService.loc('写笔记', 'Write a note', 'ノートを書く'))
            .layoutWeight(1)
            .height(44)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.accent'))
            .borderRadius(22)
            .onClick(() => {
              void this.openEditor()
            })
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .width('100%')
      .padding({ left: 28, right: 28, top: 36, bottom: 36 })
      .backgroundColor($r('app.color.card_background'))
      .borderRadius($r('app.float.card_radius'))
      .border({ width: 1, color: $r('app.color.card_border') })
      .shadow({
        radius: 24,
        color: $r('app.color.shadow_color'),
        offsetX: 0,
        offsetY: 6
      })
    }
    .width('100%')
    .padding({ top: 72, bottom: 24 })
  }

  @Builder
  private buildSearchEmptyStateCard() {
    Column({ space: 16 }) {
      Text(LocaleService.loc('未找到匹配的笔记', 'No matching notes', '一致するノートが見つかりません'))
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
      Button(LocaleService.loc('清除搜索', 'Clear search', '検索をクリア'))
        .height(40)
        .fontSize(14)
        .fontColor($r('app.color.accent'))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.clearSearchFilterTimer()
          this.searchQuery = ''
          this.searchExpanded = false
          this.applyTagFilter()
        })
    }
    .width('100%')
    .padding({ top: 72, bottom: 24, left: 28, right: 28 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private buildRefreshableHomeContent() {
    Column({ space: $r('app.float.toolbar_spacing_below') }) {
      this.buildHomeHeader()

      Stack() {
        Refresh({ refreshing: $$this.refreshing }) {
          this.buildHomeContentList()
        }
        .width('100%')
        .height('100%')
        .onRefreshing(() => {
          void this.handlePullToRefresh()
        })
        if (this.searchExpanded) {
          Row() {}
            .width('100%')
            .height('100%')
            .backgroundColor('#01000000')
            .onClick(() => {
              this.searchExpanded = false
            })
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private buildHomeContent() {
    if (this.loading) {
      this.buildLoadingState()
    } else {
      this.buildRefreshableHomeContent()
    }
  }

  @Builder
  private buildHomeLayout() {
    Column() {
      this.buildHomeContent()
    }
    .width('100%')
  }

  @Builder
  private buildUnsyncedBadge(note: Note) {
    if (this.shouldShowUnsyncedBadge(note)) {
      Row() {
        Text(' ')
          .width(6)
          .height(6)
          .borderRadius(3)
          .backgroundColor(this.statusColor(note.syncStatus))
      }
      .padding(5)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(999)
      .shadow({
        radius: 6,
        color: $r('app.color.shadow_color'),
        offsetX: 0,
        offsetY: 1
      })
      .margin({ top: 10, right: 10 })
    }
  }

  @Builder
  private buildHomeHeader() {
    Row({ space: $r('app.float.toolbar_spacing_inline') }) {
      this.buildMenuAction()

      if (this.searchExpanded) {
        Row() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(20)
            .fontColor([$r('app.color.tertiary_text')])
            .padding({ left: 10, right: 6 })
            .focusable(false)
          TextInput({ text: $$this.searchQuery, placeholder: EditorUiStrings.searchNotesHint() })
            .layoutWeight(1)
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.primary_text'))
            .placeholderColor($r('app.color.tertiary_text'))
            .backgroundColor(Color.Transparent)
            .border({ width: 0 })
            .padding({ left: 0, right: 4, top: 0, bottom: 0 })
            .onChange((_value: string) => {
              this.scheduleSearchFilterApply()
            })
          if (this.searchQuery.trim().length > 0) {
            Row() {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(16)
                .fontColor([$r('app.color.secondary_text')])
            }
            .padding({ left: 6, right: 10, top: 10, bottom: 10 })
            .onClick(() => {
              this.clearSearchFilterTimer()
              this.searchQuery = ''
              this.searchExpanded = false
              this.applyTagFilter()
            })
          }
        }
        .layoutWeight(1)
        .height($r('app.float.search_box_height'))
        .alignItems(VerticalAlign.Center)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .border({ width: 1, color: $r('app.color.card_border') })
      } else {
        Row({ space: 0 }) {
          Text($r('app.string.app_name'))
            .fontSize($r('app.float.title_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .letterSpacing(0.3)
            .layoutWeight(1)
            .padding({ top: 3})
            .textAlign(TextAlign.Start)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(18)
              .fontColor([$r('app.color.tertiary_text')])
            Text(LocaleService.loc('搜索', 'Search'))
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
          }
          .padding({ left: 18, right: 18, top: 8, bottom: 8 })
          .offset({ y: 0 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.card_border') })
          .onClick(() => {
            this.searchExpanded = true
          })
        }
        .layoutWeight(1)
        .height($r('app.float.search_box_height'))
        .alignItems(VerticalAlign.Center)
      }

      if (!this.cloudSyncConfigured) {
        this.buildSettingsAction()
      }
    }
    .width('100%')
    .height($r('app.float.search_box_toolbar_height'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildNoteCard(note: Note) {
    Column({ space: 0 }) {
      Row() {
        Column({ space: 8 }) {
          Row({ space: 6 }) {
            Text(' ')
              .width(6)
              .height(6)
              .borderRadius(3)
              .backgroundColor(this.statusColor(note.syncStatus))

            Text(note.title.length > 0 ? note.title : '无标题')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))
              .lineHeight(20)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (isExtractStatusPending(note.extractStatus)) {
            this.buildExtractPendingLine(note)
          } else if (note.extractStatus === 'failed') {
            this.buildExtractFailedLine(note)
          } else {
            Text(note.summary.length > 0 ? note.summary : '暂无内容')
              .fontSize(13)
              .fontColor(note.summary.length > 0 ? $r('app.color.secondary_text') : $r('app.color.tertiary_text'))
              .lineHeight(18)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 2, right: 2, top: 4, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      Text('')
        .width('100%')
        .height(1)
        .backgroundColor($r('app.color.divider'))
    }
    .padding({ left: 6, right: 6 })
    .onClick(() => {
      void this.openNoteFromList(note)
    })
    .width('100%')
  }

  @Builder
  private buildExtractPendingLine(note: Note) {
    Row({ space: 6 }) {
      LoadingProgress()
        .width(14)
        .height(14)
        .color($r('app.color.accent'))
      Text(`AI 提取链接中… · ${note.sourceUrl.length > 0 ? note.sourceUrl : note.title}`)
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
        .lineHeight(18)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildExtractFailedLine(note: Note) {
    Row({ space: 6 }) {
      Text('⚠')
        .fontSize(13)
        .fontColor($r('app.color.danger'))
      Text(this.formatExtractFailure(note.extractError))
        .fontSize(13)
        .fontColor($r('app.color.danger'))
        .lineHeight(18)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text('重试')
        .fontSize(12)
        .fontColor($r('app.color.accent'))
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .borderRadius(4)
        .border({ width: 1, color: $r('app.color.accent') })
        .onClick(() => {
          void this.retryExtract(note)
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  private formatExtractFailure(code: string): string {
    const c = (code ?? '').trim()
    if (c.length === 0) {
      return 'AI 提取失败'
    }
    switch (c) {
      case 'video_parse_failed': return '无法解析视频链接'
      case 'video_download_failed': return '视频下载失败'
      case 'audio_extract_failed': return '音频提取失败'
      case 'asr_failed': return '语音识别失败'
      case 'asr_timeout': return '语音识别超时'
      case 'scrape_failed': return '页面抓取失败'
      case 'minimax_failed': return 'AI 摘要失败'
      case 'timeout': return 'AI 摘要超时'
      case 'minimax_not_configured': return 'AI 摘要未配置'
      case 'invalid_url': return '链接无效'
      default: return `AI 提取失败 · ${c}`
    }
  }

  private async retryExtract(note: Note): Promise<void> {
    Logger.info('LinkExtractDebug', `trigger=retryExtract noteId=${note.id}`)
    const url = (note.sourceUrl ?? '').trim().length > 0
      ? note.sourceUrl.trim()
      : note.title.trim()
    if (url.length === 0) {
      return
    }
    if (!(await AiNoteBackgroundTaskService.getInstance().ensureNoPendingExtractOrNotify())) {
      return
    }
    if (LinkExtractClient.isVideoPlatformUrl(url)) {
      const ok = await SyncService.getInstance().isQingyuCloudAvailableForVideoExtract()
      if (!ok) {
        this.showUserMessage(LocaleService.loc(
          '视频链接提取需要登录并启用轻羽云同步',
          'Video link extract requires login and Qingyu Cloud sync',
          '動画リンク抽出にはログインとQingyu Cloud同期が必要です'
        ))
        return
      }
      await NoteRepository.getInstance().saveDraft(note.id, {
        audioId: AudioConstants.audioFileNameForVideoNote(note.id),
        voiceTranscribeStatus: 'running'
      })
    }
    await NoteRepository.getInstance().updateExtractInfo({
      noteId: note.id,
      jobId: '',
      status: 'queued',
      error: ''
    })
    try {
      const job = await LinkExtractClient.getInstance().submitJob(
        url,
        '请根据链接内容生成结构化的 Markdown 笔记摘要。',
        0,
        note.id
      )
      if (job.jobId.trim().length === 0) {
        await NoteRepository.getInstance().updateExtractInfo({
          noteId: note.id,
          status: 'failed',
          error: 'extract_failed'
        })
      } else {
        await NoteRepository.getInstance().updateExtractInfo({
          noteId: note.id,
          jobId: job.jobId,
          status: 'running',
          error: ''
        })
      }
    } catch (_) {
      await NoteRepository.getInstance().updateExtractInfo({
        noteId: note.id,
        status: 'failed',
        error: 'extract_failed'
      })
    }
    await this.refreshExtractStatuses()
  }

  private async refreshExtractStatuses(): Promise<void> {
    try {
      const pending = await NoteRepository.getInstance().listNotesNeedingExtract()
      Logger.info('LinkExtractDebug', `FLOW refreshExtractStatuses step=LIST_DONE pendingCount=${pending.length}`)
      if (pending.length === 0) {
        return
      }
      let mutated = false
      for (const n of pending) {
        const beforeStatus = n.extractStatus
        const updated = await NoteRepository.getInstance().refreshExtractJobForNote(n.id)
        if (updated !== null && updated.extractStatus !== beforeStatus) {
          mutated = true
        }
      }
      Logger.info('LinkExtractDebug', `FLOW step=REFRESH_DONE mutated=${mutated}`)
      if (mutated) {
        await this.loadNotes()
        Logger.info('LinkExtractDebug', `FLOW step=LOADNOTES_AFTER_REFRESH done`)
      }
    } catch (e) {
      Logger.warn('LinkExtractDebug', `FLOW step=REFRESH_FAILED: ${JSON.stringify(e)}`)
    }
  }

  @Builder
  private buildNoteDeleteAction(note: Note) {
    Row() {
      Text('删除')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
    }
    .width(88)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.danger'))
    .onClick(() => {
      void this.handleDelete(note.id)
    })
  }

  @Builder
  private buildHomeContentList() {
    List({ space: 4 }) {
      if (this.notes.length === 0) {
        ListItem() {
          Column() {
            if (this.searchQuery.trim().length > 0) {
              this.buildSearchEmptyStateCard()
            } else {
              this.buildEmptyStateCard()
            }
          }
          .width('100%')
        }
        .width('100%')
      } else {
        LazyForEach(this.noteListDataSource, (item: Object) => {
          ListItem() {
            this.buildNoteCard(item as Note)
          }
          .width('100%')
          .swipeAction({
            end: {
              builder: () => {
                this.buildNoteDeleteAction(item as Note)
              },
              actionAreaDistance: 88
            },
            edgeEffect: SwipeEdgeEffect.Spring
          })
        }, (item: Object) => this.noteListItemKey(item as Note))
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: 4 })
    .contentEndOffset(24)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  private buildLoadingState() {
    Column({ space: 18 }) {
      Column({ space: 16 }) {
        LoadingProgress()
          .width(36)
          .height(36)
          .color($r('app.color.accent'))
        Text('正在加载笔记…')
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
  }

  onLocaleChanged(): void {
    // @Watch：语言切换后重建首页以刷新 $r 与 LocaleService.loc 文案。
  }

  @Builder
  private buildUndoDeleteBar() {
    if (this.undoBarVisible) {
      Row() {
        Text(LocaleService.loc('已删除', 'Deleted', '削除しました'))
          .fontSize(14)
          .fontColor(Color.White)
          .layoutWeight(1)
        Text(LocaleService.loc('撤销', 'Undo', '元に戻す'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent'))
          .padding({ left: 12, right: 4, top: 8, bottom: 8 })
          .onClick(() => {
            void this.undoDelete()
          })
      }
      .width('86%')
      .padding({ left: 16, right: 12, top: 10, bottom: 10 })
      .backgroundColor($r('app.color.primary_text'))
      .borderRadius(16)
      .shadow({
        radius: 16,
        color: $r('app.color.shadow_color'),
        offsetX: 0,
        offsetY: 4
      })
      .margin({ bottom: 16 })
    }
  }

  build() {
    Stack() {
      Column() {
        this.buildHomeLayout()
      }
      .padding({top:$r('app.float.toolbar_page_padding_top'),
        left:$r('app.float.toolbar_page_padding_top'),
        right:$r('app.float.toolbar_page_padding_top')})
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.app_background'))

      Column() {
        Blank()
        this.buildUndoDeleteBar()
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)

      HomeDrawerLayer({
        tags: this.tags,
        selectedTag: this.selectedTag,
        allNotesTag: ALL_NOTES_TAG,
        folderModeEnabled: this.folderModeEnabled,
        filterMode: this.filterMode,
        folderRows: this.getFolderSidebarRows(),
        drawerToggleNonce: this.drawerToggleNonce,
        drawerCloseNonce: this.drawerCloseNonce,
        onTagSelected: (tag: string): void => {
          this.selectTag(tag)
        },
        onFolderSelected: (folderId: string): void => {
          this.selectFolder(folderId)
        },
        onFilterModeChanged: (mode: HomeSidebarFilterMode): void => {
          void this.setFilterMode(mode)
        },
        onOpenTagManage: (): void => {
          void this.openTagEditor()
        },
        onOpenFolderManage: (): void => {
          void this.openFolderManage()
        },
        onOpenRecycleBin: (): void => {
          void this.openRecycleBin()
        },
        onOpenSettings: (): void => {
          void this.openSettingsFromDrawer()
        },
        onOpenProfile: (): void => {
          void this.openProfileFromDrawer()
        },
        drawerUsername: this.drawerUsername,
        drawerAvatarUrl: this.drawerAvatarUrl,
        drawerGuestMode: this.drawerGuestMode,
        drawerLoggedIn: this.drawerLoggedIn
      })

      if (this.appLockBlocking) {
        AppLockPinPanel({
          mode: 'unlock',
          showForgotPassword: true,
          recovering: this.appLockRecovering,
          onSuccess: (): void => {
            this.appLockBlocking = false
          },
          onForgotPassword: (): void => {
            void this.handleAppLockForgotPassword()
          }
        })
          .width('100%')
          .height('100%')
          .zIndex(20000)
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .parallelGesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 8 })
        .onActionStart((_event: GestureEvent) => {
          this.onDrawerPanStart()
        })
        .onActionUpdate((event: GestureEvent) => {
          this.onDrawerPanUpdate(event)
        })
        .onActionEnd((event: GestureEvent) => {
          this.onDrawerPanEnd(event)
        })
        .onActionCancel(() => {
          this.animateDrawerSnapTo(this.drawerModel.progress >= 0.5 ? 1 : 0)
        }),
      GestureMask.Normal
    )
    .padding({
      bottom: 0,
      left: this.pageWidth >= 600 ? 28 : 0,
      right: this.pageWidth >= 600 ? 28 : 0
    })
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_, value) => {
      const nextWidth = Number.parseFloat(`${value.width}`) || 360
      const nextHeight = Number.parseFloat(`${value.height}`) || 780
      if (Math.abs(this.pageWidth - nextWidth) >= 1) {
        this.pageWidth = nextWidth
      }
      if (Math.abs(this.pageHeight - nextHeight) >= 1) {
        this.pageHeight = nextHeight
      }
    })
  }
}

interface ExtractRefreshEntry {
  note: Note
  job: JobStatusResult
}
