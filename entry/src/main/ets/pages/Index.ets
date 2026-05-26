import type { Note, SyncResult, SyncStatus } from '../common/model/Note'
import { DrawerModel } from '../common/model/DrawerModel'
import { HomeDrawerLayer } from './HomeDrawerLayer'
import { IndexNotesDataSource } from './IndexNotesDataSource'
import { NoteRepository } from '../services/NoteRepository'
import { SyncService } from '../services/SyncService'
import { PreferencesService } from '../services/PreferencesService'
import { AppContextHolder } from '../services/AppContextHolder'
import { runAppUpdateCheckOnLaunch } from '../services/AppUpdateUi'
import {
  previewQingyuForHomeSubscription,
  tryAutoProvisionQingyuCloudOnHomeEntry
} from '../services/QingyuCloudAutoProvision'
import { WebDAVClient } from '../services/WebDAVClient'
import { NoteApiClient } from '../services/NoteApiClient'
import { Logger } from '../common/utils/Logger'
import {
  NoteFolderTree,
  type FolderSidebarRow,
  type HomeSidebarFilterMode
} from '../common/utils/NoteFolderTree'
import { SyncConstants } from '../common/constants/SyncConstants'
import { UserFacingMessage } from '../common/utils/UserFacingMessage'
import { PageLifecycle } from '../common/utils/PageLifecycle'
import { IdUtils } from '../common/utils/IdUtils'
import { navigateToBindPhoneIfNeeded } from '../common/utils/BindPhoneNavigation'
import { HomeLiquidGlassTabBar } from '../components/HomeLiquidGlassTabBar'
import {
  buildHomeMoreOptionsSheetContent,
  type HomeMoreOptionsSheetParams
} from '../dialogs/HomeMoreOptionsSheet'
import { type NoteEditorEntryAction } from '../common/model/NoteEditorEntryAction'

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
const HOME_TAB_BAR_LOG_TAG = 'HomeTabBar'

@Entry
@Component
struct Index {
  @State notes: Note[] = []
  @State allNotes: Note[] = []
  @State tags: string[] = []
  @State selectedTag: string = ALL_NOTES_TAG
  @State filterMode: HomeSidebarFilterMode = 'tag'
  @State folderModeEnabled: boolean = false
  @State expandedFolderIds: string[] = []
  @State searchQuery: string = ''
  @State searchExpanded: boolean = false
  @State loading: boolean = true
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
  @State moreOptionsVisible: boolean = false
  /** 已配置自建 WebDAV，或轻羽云订阅有效（active/lifetime）时为 true，右上角不展示「去配置」图标；首帧默认 true 以免误闪。 */
  @State cloudSyncConfigured: boolean = true
  private hasShownOnce: boolean = false
  /** 仅统计「非首次」onPageShow 触发的 loadNotes 完成时间；与 initializeHome 首次加载无关，避免阻断从编辑页返回后的刷新。 */
  private lastPageShowNotesReloadAtMs: number = 0
  /** 当前水平拖动开始时抽屉进度，用于计算跟手位移。 */
  private drawerPanStartProgress: number = 0
  private searchFilterTimer: number = -1
  private noteListDataSource: IndexNotesDataSource = new IndexNotesDataSource()
  private qingyuBlockedHandler = (): void => {
    void this.showQingyuSubscriptionBlockedDialog()
  }
  private cloudSyncNotConfiguredHandler = (): void => {
    this.showUserMessage('当前未配置云服务')
  }
  private lifecycle = new PageLifecycle()

  aboutToAppear(): void {
    this.lifecycle.appear()
    try {
      AppContextHolder.getContext().eventHub.on(SyncConstants.qingyuSyncBlockedEvent, this.qingyuBlockedHandler)
      AppContextHolder.getContext().eventHub.on(SyncConstants.cloudSyncNotConfiguredToastEvent,
        this.cloudSyncNotConfiguredHandler)
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
    } catch (_) {
      console.error('Index: eventHub.off qingyu_sync_blocked failed')
    }
    this.clearSearchFilterTimer()
  }

  private async showQingyuSubscriptionBlockedDialog(): Promise<void> {
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

  onPageShow(): void {
    void this.handleIndexPageShow()
  }

  private async handleIndexPageShow(): Promise<void> {
    await this.ensureLoggedInOrRedirectToLogin()
    if (!this.lifecycle.isActive()) {
      return
    }
    void navigateToBindPhoneIfNeeded(this.getUIContext())
    await tryAutoProvisionQingyuCloudOnHomeEntry()
    if (!this.lifecycle.isActive()) {
      return
    }
    void this.refreshCloudSyncConfiguredState()
    if (!this.hasShownOnce) {
      this.hasShownOnce = true
      return
    }
    const now = Date.now()
    if (this.lastPageShowNotesReloadAtMs > 0 &&
      now - this.lastPageShowNotesReloadAtMs < MIN_HOME_PAGE_SHOW_RELOAD_INTERVAL_MS) {
      return
    }
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
    await tryAutoProvisionQingyuCloudOnHomeEntry()
    if (!this.lifecycle.isActive()) {
      return
    }
    await this.refreshCloudSyncConfiguredState()
    if (!this.lifecycle.isActive()) {
      return
    }
    await this.loadNotes(this.notes.length === 0)
    if (!this.lifecycle.isActive()) {
      return
    }
    /** 与版本检查并行启动同步，避免「检查更新」阻塞云同步开始时间。 */
    void this.startStartupSyncIfNeeded()
    await runAppUpdateCheckOnLaunch(this.getUIContext())
    if (this.lifecycle.isActive()) {
      void navigateToBindPhoneIfNeeded(this.getUIContext())
    }
  }

  private async startStartupSyncIfNeeded(): Promise<void> {
    if (await this.shouldRunStartupSync()) {
      void this.maybeSyncAfterInitialLoad()
    }
  }

  private async loadNotes(showLoading: boolean = false): Promise<void> {
    if (showLoading) {
      if (!this.lifecycle.isActive()) {
        return
      }
      this.loading = true
    }
    try {
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
      if (showLoading && this.lifecycle.isActive()) {
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

  private async refreshCloudSyncConfiguredState(): Promise<void> {
    try {
      const context = AppContextHolder.tryGetContext()
      if (context) {
        await PreferencesService.getInstance().init(context)
      }
      const snap = await PreferencesService.getInstance().getSavedCustomWebDAVConfigSnapshot()
      const customReady = snap !== null && snap.enabled
      if (customReady) {
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
        this.cloudSyncConfigured = true
      }
    }
  }

  private async shouldRunStartupSync(): Promise<boolean> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
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
    if (this.syncing) {
      /** 后台已在同步：不重复拉列表/请求同步，仅保持下拉刷新动画表示「仍在同步」。动画在 `releaseSyncProgressUi` 时收起。 */
      this.refreshing = true
      return
    }
    try {
      await this.loadNotes(false)
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
    } catch (error) {
      this.allNotes = previousAllNotes
      this.applyTagFilter()
      await this.loadNotes(false)
      console.error(JSON.stringify(error))
      this.showUserMessage(this.formatActionError('删除', error))
    }
  }

  private async openEditor(
    noteId?: string,
    openWithPreview: boolean = false,
    initialAction?: NoteEditorEntryAction
  ): Promise<void> {
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/NoteEdit',
        params: {
          noteId: noteId ?? '',
          openWithPreview: openWithPreview,
          initialAction: initialAction
        }
      })
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage(this.formatActionError('打开编辑页', error))
    }
  }

  private onHomeNoteTabPressed(): void {
    if (this.searchExpanded) {
      this.searchExpanded = false
      return
    }
    void this.openEditor()
  }

  private onHomeGraphTabPressed(): void {
    if (this.searchExpanded) {
      this.searchExpanded = false
      return
    }
    void this.openFlowchartFromDrawer()
  }

  private onHomeMoreTabPressed(): void {
    if (this.searchExpanded) {
      this.searchExpanded = false
      return
    }
    this.moreOptionsVisible = true
  }

  private closeMoreOptionsSheet(): void {
    this.moreOptionsVisible = false
  }

  @Builder
  private buildMoreOptionsSheet(): void {
    buildHomeMoreOptionsSheetContent({
      onClose: (): void => {
        this.closeMoreOptionsSheet()
      },
      onPasteLink: (): void => {
        void this.openEditor(undefined, false, 'aiLinkExtract')
      },
      onPhotoImage: (): void => {
        void this.openEditor(undefined, false, 'insertImage')
      },
      onSmartBookScan: (): void => {
        void this.openEditor(undefined, false, 'bookScan')
      }
    } as HomeMoreOptionsSheetParams)
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
    this.tags = mergedTags
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
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/Flowchart',
        params: {
          noteId,
          focusQuery
        }
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
      return `${actionLabel}失败：账号或密码可能已失效，请检查同步设置`
    }
    if (normalizedMessage.includes('qingyu webdav credentials unavailable')) {
      return `${actionLabel}失败：暂时无法连接轻羽云存储，请稍后重试或检查网络`
    }
    if (normalizedMessage.includes('not configured')) {
      return `${actionLabel}失败：请先完成 WebDAV 配置`
    }
    if (normalizedMessage.includes('timeout')) {
      return `${actionLabel}失败：请求超时，请稍后重试`
    }
    if (normalizedMessage.includes('100002') || normalizedMessage.includes('uri error')
      || normalizedMessage.includes('does not exist') || normalizedMessage.includes('not exist')) {
      return `${actionLabel}失败：目标页面不可用`
    }
    return `${actionLabel}失败，请稍后重试`
  }

  private summarizeSyncResult(results: SyncResult[]): string | null {
    const more = SyncService.getInstance().getLastFullSyncHadMoreNotes()
    if (results.length === 0) {
      return more ? '已同步本批笔记，请再次下拉以继续同步剩余条目' : '同步完成'
    }
    const failedResults = results.filter((result: SyncResult) => !result.success)
    if (failedResults.length === 0) {
      if (more) {
        return '已同步本批笔记，请再次下拉以继续同步剩余条目'
      }
      return '同步完成'
    }
    if (failedResults.length === 1 && failedResults[0].message.trim().length > 0) {
      return UserFacingMessage.forSyncNoteFailure(failedResults[0].message)
    }
    return `同步完成，但有 ${failedResults.length} 条笔记同步失败`
  }

  private async refreshNotesIfChanged(previousVersion: number): Promise<void> {
    if (NoteRepository.getInstance().getNotesVersion() === previousVersion) {
      return
    }
    await this.loadNotes(false)
  }

  @Builder
  private buildHomeTabBarLayer() {
    Column() {
      HomeLiquidGlassTabBar({
        onMore: (): void => {
          this.onHomeMoreTabPressed()
        },
        onGraph: (): void => {
          this.onHomeGraphTabPressed()
        },
        onNote: (): void => {
          this.onHomeNoteTabPressed()
        }
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
    .padding({ bottom: 50 })
    .hitTestBehavior(HitTestMode.None)
    .onAppear(() => {
      Logger.info(
        HOME_TAB_BAR_LOG_TAG,
        `layer appear page=${this.pageWidth}x${this.pageHeight} drawer=${this.drawerModel.progress}`
      )
    })
    .onAreaChange((_old: Area, area: Area) => {
      Logger.info(
        HOME_TAB_BAR_LOG_TAG,
        `layer area w=${area.width} h=${area.height} ` +
          `global=(${area.globalPosition.x},${area.globalPosition.y}) ` +
          `local=(${area.position.x},${area.position.y}) page=${this.pageWidth}x${this.pageHeight}`
      )
    })
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
      Column() {
        Text('✦')
          .fontSize(40)
          .fontColor($r('app.color.accent'))
          .opacity(0.85)
        Text('从这里开始')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Text($r('app.string.empty_notes'))
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Center)
          .lineHeight(24)
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
  private buildSearchEmptyStateCard() {
    Column({ space: 16 }) {
      Text('未找到匹配的笔记')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 72, bottom: 24, left: 28, right: 28 })
    .justifyContent(FlexAlign.Center)
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
          TextInput({ text: $$this.searchQuery, placeholder: '搜索标题或摘要' })
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
          Text('轻羽云笔记')
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
            Text('搜索')
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

          Text(note.summary.length > 0 ? note.summary : '暂无内容')
            .fontSize(13)
            .fontColor(note.summary.length > 0 ? $r('app.color.secondary_text') : $r('app.color.tertiary_text'))
            .lineHeight(18)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
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
    .padding({ top: 4, bottom: 0 })
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

      if (this.drawerModel.progress <= 0.001) {
        this.buildHomeTabBarLayer()
      }

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
        }
      })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .bindSheet($$this.moreOptionsVisible, this.buildMoreOptionsSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: false,
      showClose: false,
      backgroundColor: Color.Transparent,
      onDisappear: (): void => {
        this.moreOptionsVisible = false
      }
    })
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
      Logger.info(
        HOME_TAB_BAR_LOG_TAG,
        `index root area ${nextWidth}x${nextHeight} drawer=${this.drawerModel.progress}`
      )
    })
  }
}
