import { ComponentContent, SymbolGlyphModifier, window } from '@kit.ArkUI'
import type { MarkdownBlock } from '../common/utils/MarkdownUtils'
import { MarkdownUtils, shouldPersistTodoNote } from '../common/utils/MarkdownUtils'
import {
  EditorMarkdownInsert,
  type EditorInsertResult,
  type EditorTextDiff
} from '../common/utils/EditorMarkdownInsert'
import { EditorQuickActionBar, type EditorQuickActionType } from '../components/EditorQuickActionBar'
import { MermaidTemplates } from '../common/utils/MermaidTemplates'
import { MermaidRenderBarrier } from '../components/MermaidPreview'
import { ImageCacheService } from '../services/ImageCacheService'
import {
  buildEditorLinkInsertDialogContent,
  type EditorLinkInsertDialogParams
} from '../dialogs/EditorLinkInsertDialog'
import type { Note } from '../common/model/Note'
import { isExtractStatusPending } from '../common/model/Note'
import { NoteRepository } from '../services/NoteRepository'
import { NoteHistoryService } from '../services/NoteHistoryService'
import { NoteHistoryReason } from '../common/model/NoteHistory'
import { PreferencesService } from '../services/PreferencesService'
import { AppContextHolder } from '../services/AppContextHolder'
import { NoteImagesChangedEventPayload, SyncConstants } from '../common/constants/SyncConstants'
import { TimeUtils } from '../common/utils/TimeUtils'
import { Logger } from '../common/utils/Logger'
import { EditorUiStrings } from '../common/utils/EditorUiStrings'
import { APP_LOCALE_REVISION_KEY } from '../services/LocaleService'
import componentSnapshot from '@ohos.arkui.componentSnapshot'
import { image } from '@kit.ImageKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { common, Configuration } from '@kit.AbilityKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { NoteEditEditorPane } from './NoteEditEditorPane'
import { NoteEditFolderMovePanel } from '../components/NoteEditFolderMovePanel'
import { NoteEditTagChip, NoteEditTagDropdown } from '../components/NoteEditTagDropdown'
import { NoteEditPreviewPane } from './NoteEditPreviewPane'
import { NoteApiClient, type ProfileBody } from '../services/NoteApiClient'
import { AiTagService } from '../services/AiTagService'
import { AiNotePrompt } from '../services/AiNotePrompt'
import { UserFacingMessage } from '../common/utils/UserFacingMessage'
import { RemoteAppConfigService } from '../services/RemoteAppConfigService'
import { PageLifecycle } from '../common/utils/PageLifecycle'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'
import { NoteImageGalleryUtils } from '../common/utils/NoteImageGalleryUtils'
import { NoteStateCodec } from '../common/utils/NoteStateCodec'
import { capturePhotoUri, requestCameraPermission } from '../common/utils/NoteCameraCapture'
import { NoteFolderTree, type FolderSidebarRow, type HomeSidebarFilterMode, type MovePickerEntry } from '../common/utils/NoteFolderTree'
import {
  hasEditorTitleOrBody,
  resolveTitleForSave,
  shouldSkipAutoSaveSchedule,
  type TitleSaveResolution
} from '../common/utils/NoteEditSaveHelper'
import {
  noteEditDelayMs,
  NOTE_EDIT_SHARE_SCROLL_ID,
  NOTE_EDIT_SHARE_SNAPSHOT_MAX_FULL_CARD_VP,
  saveShareCachePngToGallery,
  shareExportBodyHasImages,
  shareExportContentHasImages,
  shareExportMountDelayMs,
  shareExportMountKey,
  sharePngFromCachePath,
  updateSharePreviewImageLayoutVp
} from '../common/utils/NoteEditShareHelper'
import {
  mergeSharePixelMapsVertical,
  normalizeAllShareSlicesForMerge,
  packSharePixelMapToPng,
  trimShareTransparentVerticalEdges
} from '../common/utils/NoteEditShareSnapshot'
import { NoteEditShareExportMount } from '../components/NoteEditShareExportMount'
import { NoteEditSharePreviewOverlay } from '../components/NoteEditSharePreviewOverlay'
import { type NoteEditorEntryAction } from '../common/model/NoteEditorEntryAction'
import { maybeShowMembershipExpiryReminderDialog } from '../common/utils/MembershipExpiryReminderNavigation'
import { ensureAiMembershipAccess } from '../common/utils/AiMembershipGateNavigation'
import { ShareCardTheme, ShareCardTone, ShareThemeColors } from '../share/ShareTheme'
import {
  NoteShareExportCard,
  NOTE_SHARE_EXPORT_SNAPSHOT_ID,
  buildJinshuLightSegmentCaptureIds
} from '../share/NoteShareExportCard'
import { NoteSharePreviewSheetParams } from '../share/NoteSharePreviewSheet'
import { NoteAudioPlayerBar } from '../components/NoteAudioPlayerBar'
import {
  AiNoteBackgroundTaskService,
  type AiNoteBackgroundTaskResult
} from '../services/AiNoteBackgroundTaskService'

interface NoteEditParams {
  noteId?: string
  /** 从首页点入且正文非空时置为 true，与 Flutter `openWithPreview` 对齐。 */
  openWithPreview?: boolean
  /** 从首页「更多方式」进入时，加载完成后自动触发的动作。 */
  initialAction?: NoteEditorEntryAction
  /** 语音笔记页完成后带入，加载笔记后触发转写。 */
  pendingVoicePath?: string
}

@Entry
@Component
struct NoteEdit {
  @StorageProp(APP_LOCALE_REVISION_KEY) localeRevision: number = 0
  @State noteId: string = ''
  @State title: string = ''
  @State content: string = ''
  @State saveStatus: string = '未保存'
  @State previewMode: string = 'split'
  @State editorEnterEditToken: number = 0
  @State editorRefreshToken: number = 0
  @State editorToolbarSignal: string = ''
  /** 深浅色切换后递增，驱动 RichEditor span 色重建。 */
  @State editorColorModeToken: number = 0
  @State pageWidth: number = 360
  @State pageHeight: number = 780
  @State lastSavedAt: number = 0
  @State noteCreatedAt: number = 0
  @State shareProfile: ProfileBody | null = null
  @State shareAvatarNetworkFailed: boolean = false
  @State previewBlocksState: MarkdownBlock[] = []
  @State previewSource: string = ''
  @State noteTags: string[] = []
  @State tagPool: string[] = []
  @State tagMenuVisible: boolean = false
  @State aiTagCreating: boolean = false
  @State aiFeatureEnabled: boolean = false
  @State aiNoteWorking: boolean = false
  @State aiWorkingOverlayMessage: string = 'AI 处理中…'
  private extractPollTimer: number = -1
  private extractPollingActive: boolean = false
  private lastAppliedAiBgResult: AiNoteBackgroundTaskResult | null = null
  private readonly onAiBackgroundTaskChanged = (): void => {
    this.handleAiBackgroundTaskChanged()
  }
  @State aiUndoAvailable: boolean = false
  private aiUndoBaselineContent: string | null = null
  @State parentId: string = ''
  @State allNotes: Note[] = []
  @State expandedFolderIds: string[] = []
  @State folderMovePopupVisible: boolean = false
  @State tagBarX: number = 0
  @State tagBarY: number = 0
  @State tagBarWidth: number = 120
  @State tagBarHeight: number = 32
  /** 标题输入框是否处于焦点（编辑）状态。 */
  @State titleFieldFocused: boolean = false
  /** 窄屏大标题是否处于点击编辑态（与 VoiceNoteDetail 一致）。 */
  @State titleEditing: boolean = false
  /** 顶栏标题透明度：0 隐藏，1 完全显示，随外层滚动连续变化（窄屏）。 */
  @State toolbarTitleOpacity: number = 0
  /** 大标题块高度，用于顶栏标题滚动淡入计算。 */
  @State titleBlockH: number = 48
  /** 标题编辑 dismiss 遮罩的顶部 Y（标题底边之下，不盖住标题）。 */
  @State titleDismissTop: number = 120
  /** 窄屏编辑/预览 Tab 当前下标：0=编辑，1=预览，与 previewMode 同步。 */
  @State contentTabIndex: number = 0
  /** 窄屏外层 Scroll 视口高；吸顶 TabBar 高；Swiper = viewport - tabBar。 */
  @State scrollViewportH: number = 0
  @State tabBarH: number = 48
  @State stickyHeaderH: number = 0
  /** 笔记设置：是否展示编辑 Tab 下方快捷操作栏。 */
  @State quickActionBarEnabled: boolean = true
  @State folderModeEnabled: boolean = false
  /** 首页侧栏筛选模式（本地偏好 `home_sidebar_filter_mode`）。 */
  @State sidebarFilterMode: HomeSidebarFilterMode = 'tag'
  /** 软键盘占用高度（vp）；快捷栏仅在键盘可见时展示。 */
  @State keyboardHeightVp: number = 0
  /** 上一帧键盘高度（px），用于检测显隐后重建富文本 spans。 */
  private lastKeyboardHeightPx: number = 0
  /** 正文上次已知光标位置；点击快捷栏时 TextArea 失焦，getCaretOffset 常误报文末。 */
  private contentCaretIndex: number = 0
  private previousContent: string = ''
  /** 程序化插入期间勿用控制器同步光标（避免把缓存覆盖成文末）。 */
  private suppressContentCaretSync: boolean = false
  private pendingInsertCaret: number = -1
  private caretRestoreTimer: number = -1
  private textAreaController: TextAreaController = new TextAreaController()
  private keyboardWindow?: window.Window
  /** 软键盘真实高度回调（px），与 caret 滚动导致的 avoidArea 膨胀解耦。 */
  private readonly onKeyboardHeightChange = (heightPx: number): void => {
    const prev = this.lastKeyboardHeightPx
    this.lastKeyboardHeightPx = heightPx
    this.keyboardHeightVp = heightPx > 0 ? this.getUIContext().px2vp(heightPx) : 0
    const inEdit = this.previewMode === 'edit' || this.previewMode === 'split'
    // 键盘显隐后 RichEditor ImageSpan/BuilderSpan 可能丢失，延迟刷新重建。
    if (prev > 0 && heightPx <= 0 && inEdit) {
      setTimeout((): void => {
        this.editorRefreshToken = this.editorRefreshToken + 1
      }, 50)
      setTimeout((): void => {
        this.editorRefreshToken = this.editorRefreshToken + 1
      }, 200)
    } else if (prev <= 0 && heightPx > 0 && inEdit) {
      setTimeout((): void => {
        this.editorRefreshToken = this.editorRefreshToken + 1
      }, 100)
    }
  }
  private shareScroller: Scroller = new Scroller()
  /** 窄屏外层 Scroll（吸顶标题+Tab）；与 VoiceNoteDetail outerScroller 同构。 */
  private outerScroller: Scroller = new Scroller()
  private lastOuterOffsetY: number = 0
  private swiperController: SwiperController = new SwiperController()
  private pathCaptionScroller: Scroller = new Scroller()
  private pathCaptionMarqueeToken: number = 0
  private pathCaptionMarqueeTimer: number = -1
  @State private pathCaptionContentWidthVp: number = 0
  @State private pathCaptionViewportWidthVp: number = 0
  /** 与 Flutter 路径跑马灯一致的横向步进（vp/帧）。 */
  private static readonly PATH_CAPTION_LED_STEP_VP: number = 0.8
  private static readonly PATH_CAPTION_LED_FRAME_MS: number = 16
  private static readonly TAG_DROPDOWN_ITEM_HEIGHT_VP: number = 44
  private static readonly TAG_DROPDOWN_MAX_VISIBLE_ITEMS: number = 5
  /** 分享卡片内 Column 总高度（vp），用于长截图分段滚动。 */
  @State shareExportColumnVp: number = 0
  @State shareTheme: ShareCardTheme = ShareCardTheme.CLASSIC
  @State shareTone: ShareCardTone = ShareCardTone.DARK
  @State sharePreviewVisible: boolean = false
  @State sharePreviewPath: string = ''
  @State sharePreviewRegenerating: boolean = false
  @State sharePreviewPreparing: boolean = false
  @State shareOptionsSheetVisible: boolean = false
  @State shareSheetRevision: number = 0
  @State shareCardCaptureKey: number = 0
  @State sharePreviewImageHeightVp: number = 0
  @State shareExportScrollBg: string = '#FF1A1A1C'
  /** 仅截屏期间挂载分享卡片，避免离屏节点复用旧色调帧。 */
  @State shareExportActive: boolean = false
  @State shareExportTheme: ShareCardTheme = ShareCardTheme.CLASSIC
  @State shareExportTone: ShareCardTone = ShareCardTone.DARK
  @State shareExportSnapshotCompatMode: boolean = false
  @State shareExportSnapshotSkipQr: boolean = false
  @State shareShowAppIcon: boolean = false
  @State audioId: string = ''
  private saveTimer: number = -1
  private previewTimer: number = -1
  private previewDirty: boolean = true
  /** 远端图片落盘后递增，强制预览区 Image 重建（正文未变时 blocks 解析会短路）。 */
  @State previewImageRefreshKey: number = 0
  private onNoteImagesChanged = (payload: NoteImagesChangedEventPayload): void => {
    if (!this.lifecycle.isActive() || payload.noteId !== this.noteId) {
      return
    }
    this.previewImageRefreshKey += 1
    this.previewDirty = true
    if (this.shouldRenderPreview()) {
      this.schedulePreviewRefresh()
    }
  }
  private onNoteSettingsChanged = (): void => {
    void this.loadQuickActionBarPref()
    void this.loadFolderModePref()
  }
  private preferPreviewOnOpen: boolean = false
  private pendingInitialAction: NoteEditorEntryAction | null = null
  private initialActionHandled: boolean = false
  private pendingVoicePath: string = ''
  private pendingVoiceHandled: boolean = false
  /** 打开页面时待办笔记是否已有实质内容（避免清空后误删历史笔记）。 */
  private initialHadTodoContent: boolean = false
  private shareCardHeight: number = 0
  /** 缓存 ability `filesDir`，避免预览中多张图片重复解析上下文。 */
  private filesDirCache: string = ''
  private lifecycle = new PageLifecycle()
  private closeGuard = new PageCloseGuard()
  private static readonly SHARE_CARD_ID: string = NOTE_SHARE_EXPORT_SNAPSHOT_ID
  /** 超过此高度（vp）时整卡 snapshot 易触发 100001，改优先截 Scroll 视口再分段拼接。 */
  private static readonly SHARE_SNAPSHOT_MAX_FULL_CARD_VP: number = NOTE_EDIT_SHARE_SNAPSHOT_MAX_FULL_CARD_VP

  /** 使用 UIContext.getHostContext，替代已废弃的全局 getContext。 */
  private obtainUiAbilityContext(): common.UIAbilityContext | undefined {
    const host = this.getUIContext().getHostContext()
    if (host !== undefined && host !== null) {
      return host as common.UIAbilityContext
    }
    return AppContextHolder.tryGetContext()
  }

  /** 打开图片画廊前保存的预览模式，返回编辑页后恢复（避免 onPageShow 误切回编辑）。 */
  private pendingRestorePreviewMode: string = ''

  onPageShow(): void {
    void this.loadQuickActionBarPref()
    void this.loadFolderModePref()
    void this.loadSidebarFilterModePref()
    void this.onNoteEditPageShow()
    this.bumpEditorColorModeToken()
  }

  onConfigurationUpdate(_config: Configuration): void {
    this.bumpEditorColorModeToken()
  }

  private bumpEditorColorModeToken(): void {
    this.editorColorModeToken = this.editorColorModeToken + 1
  }

  private async onNoteEditPageShow(): Promise<void> {
    const savedMode = this.pendingRestorePreviewMode
    this.pendingRestorePreviewMode = ''
    await this.applyRouterParamsIfNeeded()
    if (savedMode.length > 0 && !this.isSplitMode()) {
      this.previewMode = savedMode
      if (savedMode === 'preview') {
        this.preparePreviewForCurrentMode(this.content, true)
      }
      this.syncContentTabIndexFromPreviewMode()
    }
  }

  aboutToAppear(): void {
    this.lifecycle.appear()
    this.closeGuard.reset()
    AppContextHolder.setLastUiContext(this.getUIContext())
    const ctx = this.obtainUiAbilityContext()
    if (ctx !== undefined) {
      this.filesDirCache = ctx.filesDir
    }
    const params = this.getUIContext().getRouter().getParams() as NoteEditParams
    this.noteId = params?.noteId ?? ''
    this.preferPreviewOnOpen = params?.openWithPreview === true
    this.pendingInitialAction = params?.initialAction ?? null
    this.initialActionHandled = false
    this.pendingVoicePath = `${params?.pendingVoicePath ?? ''}`.trim()
    this.pendingVoiceHandled = false
    AiNoteBackgroundTaskService.getInstance().addListener(this.onAiBackgroundTaskChanged)
    void this.loadNote()
    void this.refreshAllNotes()
    void this.loadQuickActionBarPref()
    void this.loadFolderModePref()
    void this.loadSidebarFilterModePref()
    void this.loadAiFeatureConfig()
    void this.initKeyboardAvoidArea()
    this.syncAiWorkingFromBackgroundTask()
    try {
      AppContextHolder.getContext().eventHub.on(SyncConstants.noteImagesChangedEvent, this.onNoteImagesChanged)
      AppContextHolder.getContext().eventHub.on(SyncConstants.noteSettingsChangedEvent, this.onNoteSettingsChanged)
    } catch (error) {
      Logger.warn('NoteEdit', `eventHub.on note_images_changed failed: ${JSON.stringify(error)}`)
    }
  }

  private async applyRouterParamsIfNeeded(): Promise<void> {
    const params = this.getUIContext().getRouter().getParams() as NoteEditParams
    const nextNoteId = `${params?.noteId ?? ''}`.trim()
    // 从子页面 router.back() 返回时 getParams 可能为空，勿因此重载笔记并丢掉预览模式。
    if (nextNoteId.length === 0 && this.noteId.length > 0) {
      return
    }
    const nextPreview = params?.openWithPreview === true
    const nextAction = params?.initialAction ?? null
    const nextPendingVoice = `${params?.pendingVoicePath ?? ''}`.trim()
    if (nextNoteId === this.noteId &&
      nextPreview === this.preferPreviewOnOpen &&
      nextAction === this.pendingInitialAction &&
      nextPendingVoice.length === 0) {
      return
    }
    // Same note re-opened with a pending recording: only attach the path.
    // Do not flush autosave first — that would purge a voice placeholder.
    if (nextNoteId === this.noteId && nextPendingVoice.length > 0) {
      this.preferPreviewOnOpen = nextPreview
      this.pendingInitialAction = nextAction
      this.initialActionHandled = false
      this.pendingVoicePath = nextPendingVoice
      this.pendingVoiceHandled = false
      this.runPendingVoicePathIfNeeded()
      return
    }
    await this.flushAndAutoSaveAfterLeave()
    if (!this.lifecycle.isActive()) {
      return
    }
    this.noteId = nextNoteId
    this.preferPreviewOnOpen = nextPreview
    this.pendingInitialAction = nextAction
    this.initialActionHandled = false
    if (nextPendingVoice.length > 0) {
      this.pendingVoicePath = nextPendingVoice
      this.pendingVoiceHandled = false
    }
    void this.loadNote()
    void this.refreshAllNotes()
  }

  aboutToDisappear(): void {
    this.lifecycle.disappear()
    AiNoteBackgroundTaskService.getInstance().removeListener(this.onAiBackgroundTaskChanged)
    if (this.keyboardWindow !== undefined) {
      try {
        this.keyboardWindow.off('keyboardHeightChange', this.onKeyboardHeightChange)
      } catch (_) {
        // ignore
      }
      this.keyboardWindow = undefined
    }
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer)
      this.saveTimer = -1
    }
    if (this.previewTimer !== -1) {
      clearTimeout(this.previewTimer)
      this.previewTimer = -1
    }
    this.stopExtractPolling()
    this.stopPathCaptionMarquee()
    try {
      AppContextHolder.getContext().eventHub.off(SyncConstants.noteImagesChangedEvent, this.onNoteImagesChanged)
      AppContextHolder.getContext().eventHub.off(SyncConstants.noteSettingsChangedEvent, this.onNoteSettingsChanged)
    } catch (_) {
      // ignore
    }
  }

  private async loadQuickActionBarPref(): Promise<void> {
    await this.ensurePreferencesInitialized()
    if (!this.lifecycle.isActive()) {
      return
    }
    this.quickActionBarEnabled =
      await PreferencesService.getInstance().getNoteQuickActionBarEnabled()
  }

  private async loadFolderModePref(): Promise<void> {
    await this.ensurePreferencesInitialized()
    if (!this.lifecycle.isActive()) {
      return
    }
    this.folderModeEnabled =
      await PreferencesService.getInstance().getNoteFolderModeEnabled()
    if (!this.lifecycle.isActive()) {
      return
    }
    if (!this.folderModeEnabled) {
      this.folderMovePopupVisible = false
    }
  }

  private async loadSidebarFilterModePref(): Promise<void> {
    await this.ensurePreferencesInitialized()
    if (!this.lifecycle.isActive()) {
      return
    }
    const mode = await PreferencesService.getInstance().getHomeSidebarFilterMode()
    if (!this.lifecycle.isActive()) {
      return
    }
    this.sidebarFilterMode = mode
    if (mode === 'folder') {
      this.tagMenuVisible = false
    }
  }

  private async loadAiFeatureConfig(): Promise<void> {
    const filesDir = this.filesDirCache.length > 0
      ? this.filesDirCache
      : (this.obtainUiAbilityContext()?.filesDir ?? '')
    const enabled = await RemoteAppConfigService.readAiConfigFromCache(filesDir)
    if (this.lifecycle.isActive()) {
      this.aiFeatureEnabled = enabled
    }
  }

  /** 顶栏「更多」菜单中是否展示 AI 项。 */
  private shouldShowMobileToolbarAi(): boolean {
    return !this.isSplitMode() &&
      this.aiFeatureEnabled &&
      hasEditorTitleOrBody(this.title, this.content)
  }

  /** 从更多菜单打开「移动本文至」弹层：展开虚拟根目录，与顶栏点击一致。 */
  private openMoveFolderPopup(): void {
    this.folderMovePopupVisible = true
    if (!this.expandedFolderIds.includes(NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID)) {
      this.expandedFolderIds = [...this.expandedFolderIds, NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID]
    }
    this.tagMenuVisible = false
  }

  private buildToolbarMoreMenuItems(): Array<MenuElement> {
    const items: Array<MenuElement> = [
      {
        value: EditorUiStrings.loc('分享', 'Share', '共有'),
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.share')),
        action: (): void => {
          void this.runShareNote()
        }
      }
    ]
    if (this.noteId.length > 0) {
      items.push({
        value: EditorUiStrings.loc('历史版本', 'Version history', '履歴'),
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.clock')),
        action: (): void => {
          void this.openHistoryPage()
        }
      })
    }
    if (this.folderModeEnabled) {
      items.push({
        value: EditorUiStrings.loc('移动本文至', 'Move this note to', 'このノートを移動'),
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.folder')),
        action: (): void => {
          this.openMoveFolderPopup()
        }
      })
    }
    if (this.shouldShowMobileToolbarAi()) {
      items.push({
        value: this.aiNoteWorking
          ? EditorUiStrings.loc('AI 处理中…', 'AI working…', 'AI処理中…')
          : EditorUiStrings.loc('AI优化语句', 'AI polish', 'AIで文章を整える'),
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.wand_and_stars')),
        action: (): void => {
          if (!this.aiNoteWorking) {
            void this.onAiOptimizeContent()
          }
        }
      })
      if (this.aiUndoAvailable) {
        items.push({
          value: EditorUiStrings.loc('撤回AI修改', 'Undo AI edit', 'AI編集を元に戻す'),
          symbolIcon: new SymbolGlyphModifier($r('sys.symbol.undo')),
          action: (): void => {
            if (!this.aiNoteWorking) {
              this.onAiUndo()
            }
          }
        })
      }
    }
    return items
  }

  private static readonly FLOAT_MENU_WIDTH: number = 154
  private static readonly FLOAT_MENU_GAP: number = 8
  private static readonly TAG_MENU_ITEM_HEIGHT: number = 44
  private static readonly TAG_MENU_MAX_VISIBLE_ITEMS: number = 5

  /** 标签悬浮按钮在屏幕上半部时菜单向下展开，否则向上展开。 */
  private floatMenuShowBelow(): boolean {
    const buttonCenterY = this.tagBarY + this.tagBarHeight / 2
    const screenHeight = this.pageHeight > 0 ? this.pageHeight : 780
    return buttonCenterY < screenHeight / 2
  }

  private floatMenuPosX(menuWidth: number = NoteEdit.FLOAT_MENU_WIDTH): number {
    let x = this.tagBarX + this.tagBarWidth - menuWidth
    if (x < 8) {
      x = 8
    }
    const maxX = this.pageWidth - menuWidth - 8
    if (x > maxX) {
      x = maxX
    }
    return x
  }

  private tagMenuEstimatedHeight(): number {
    const visibleCount = this.tagPool.length === 0
      ? 1
      : Math.min(this.tagPool.length, NoteEdit.TAG_MENU_MAX_VISIBLE_ITEMS)
    const listHeight = visibleCount * NoteEdit.TAG_MENU_ITEM_HEIGHT
    return listHeight + 120
  }

  private tagMenuPosY(): number {
    const menuHeight = this.tagMenuEstimatedHeight()
    if (this.floatMenuShowBelow()) {
      return this.tagBarY + this.tagBarHeight + NoteEdit.FLOAT_MENU_GAP
    }
    return this.tagBarY - menuHeight - NoteEdit.FLOAT_MENU_GAP
  }

  private captureAiUndoBaseline(contentBeforeChange: string): void {
    if (this.aiUndoBaselineContent === null) {
      this.aiUndoBaselineContent = contentBeforeChange
      this.aiUndoAvailable = true
    }
  }

  private onAiUndo(): void {
    if (this.aiNoteWorking || this.aiUndoBaselineContent === null) {
      return
    }
    this.content = this.aiUndoBaselineContent
    this.aiUndoBaselineContent = null
    this.aiUndoAvailable = false
    this.handleContentChange()
    this.showPreviewMessage(EditorUiStrings.loc('已撤回 AI 修改', 'AI edit undone', 'AI編集を元に戻しました'))
  }

  private async initKeyboardAvoidArea(): Promise<void> {
    const host = this.obtainUiAbilityContext()
    if (host === undefined) {
      return
    }
    try {
      const win = await window.getLastWindow(host)
      this.keyboardWindow = win
      win.on('keyboardHeightChange', this.onKeyboardHeightChange)
    } catch (error) {
      Logger.warn('NoteEdit', `initKeyboardHeightListener: ${JSON.stringify(error)}`)
    }
  }

  private shouldShowQuickActionBar(): boolean {
    return this.quickActionBarEnabled &&
      !this.isSplitMode() &&
      this.previewMode !== 'preview' &&
      this.keyboardHeightVp > 0
  }

  private rememberContentCaret(selectionStart: number, selectionEnd: number): void {
    const end = selectionEnd >= 0 ? selectionEnd : selectionStart
    const start = selectionStart >= 0 ? selectionStart : end
    const index = end >= start ? end : start
    this.contentCaretIndex = Math.max(0, Math.min(index, this.content.length))
  }

  /**
   * 快捷栏 TouchDown：优先保留 RichEditor onSelectionChange 已缓存的光标。
   * TextAreaController 不再驱动正文，仅在仍能读到有效选区时更新缓存。
   */
  private captureContentCaretFromSelection(): void {
    try {
      const range = this.textAreaController.getSelection()
      const start = range.start !== undefined && range.start >= 0 ? range.start : -1
      const end = range.end !== undefined && range.end >= 0 ? range.end : start
      if (start >= 0) {
        this.rememberContentCaret(start, end)
      }
    } catch (_) {
      // 保留 contentCaretIndex
    }
  }

  private currentContentCaret(): number {
    return Math.max(0, Math.min(this.contentCaretIndex, this.content.length))
  }

  private scheduleApplyCaret(caret: number, textLength?: number): void {
    const len = textLength !== undefined ? textLength : this.content.length
    const pos = Math.max(0, Math.min(caret, len))
    this.pendingInsertCaret = pos
    this.contentCaretIndex = pos
    const apply = (): void => {
      const maxLen = textLength !== undefined ? textLength : this.content.length
      const target = Math.max(0, Math.min(this.pendingInsertCaret, maxLen))
      try {
        this.textAreaController.setTextSelection(target, target)
      } catch (_) {
        try {
          this.textAreaController.caretPosition(target)
        } catch (_2) {
          // ignore
        }
      }
      this.contentCaretIndex = target
    }
    if (this.caretRestoreTimer >= 0) {
      clearTimeout(this.caretRestoreTimer)
    }
    apply()
    setTimeout(apply, 0)
    setTimeout(apply, 50)
    this.caretRestoreTimer = setTimeout(() => {
      apply()
      this.suppressContentCaretSync = false
      this.pendingInsertCaret = -1
      this.caretRestoreTimer = -1
    }, 120) as number
  }

  private applyContentInsertViaController(_diff: EditorTextDiff): boolean {
    // 正文已切换为 RichEditor，不再通过 TextAreaController 增量改字。
    return false
  }

  private bumpEditorRefresh(): void {
    this.editorRefreshToken = this.editorRefreshToken + 1
  }

  private signalToolbarEmbed(kind: string, label: string, url: string): void {
    this.editorToolbarSignal = `${kind}|${label}|${url}@${Date.now()}`
  }

  private applyContentInsert(result: EditorInsertResult): void {
    const oldText = this.content
    const newText = result.text
    const caret = Math.max(0, Math.min(result.caret, newText.length))
    if (oldText === newText) {
      this.scheduleApplyCaret(caret, newText.length)
      return
    }

    this.suppressContentCaretSync = true
    this.contentCaretIndex = caret
    this.content = newText
    this.bumpEditorRefresh()
    this.scheduleApplyCaret(caret, newText.length)
    this.scheduleSave()
    if (this.shouldRenderPreview()) {
      this.schedulePreviewRefresh()
    } else {
      this.previewDirty = true
    }
  }

  private handleContentChange(): void {
    if (!this.suppressContentCaretSync) {
      const oldText = this.previousContent
      const newText = this.content
      const result = MarkdownUtils.applyMarkdownMarkerOnNewline(
        oldText,
        newText,
        this.noteTagsSafe().includes('Todo')
      )
      if (result !== null) {
        this.applyContentInsert(result)
        this.previousContent = result.text
        return
      }
    }
    this.previousContent = this.content
    if (this.suppressContentCaretSync) {
      if (this.pendingInsertCaret >= 0) {
        this.scheduleApplyCaret(this.pendingInsertCaret)
      }
    } else {
      this.captureContentCaretFromSelection()
    }
    if (this.shouldRenderPreview()) {
      this.schedulePreviewRefresh()
    } else {
      this.previewDirty = true
    }
    this.scheduleSave()
  }

  private openLinkInsertDialog(): void {
    const ui = this.getUIContext()
    let holder: ComponentContent<EditorLinkInsertDialogParams> | undefined = undefined
    const params: EditorLinkInsertDialogParams = {
      onCancel: (): void => {
        if (holder !== undefined) {
          try {
            ui.getPromptAction().closeCustomDialog(holder)
          } catch (_) {
            // ignore
          }
        }
      },
      onConfirm: (label: string, url: string): void => {
        if (holder !== undefined) {
          try {
            ui.getPromptAction().closeCustomDialog(holder)
          } catch (_) {
            // ignore
          }
        }
        if (label.length === 0 || url.length === 0) {
          return
        }
        this.captureContentCaretFromSelection()
        const caret = this.currentContentCaret()
        const result = EditorMarkdownInsert.insertLink(
          this.content,
          caret,
          caret,
          label,
          url
        )
        this.applyContentInsert(result)
        this.signalToolbarEmbed('link', label, url)
      }
    }
    holder = new ComponentContent(ui, wrapBuilder(buildEditorLinkInsertDialogContent), params)
    try {
      ui.getPromptAction().openCustomDialog(holder, {
        alignment: DialogAlignment.Center,
        autoCancel: false
      })
    } catch (error) {
      Logger.warn('NoteEdit', `openLinkInsertDialog: ${JSON.stringify(error)}`)
    }
  }

  private handleQuickAction(action: EditorQuickActionType): void {
    this.captureContentCaretFromSelection()
    if (action === 'link') {
      this.openLinkInsertDialog()
      return
    }
    if (action === 'image') {
      void this.insertImage()
      return
    }
    if (action === 'mermaid') {
      this.insertMermaidTemplate(MermaidTemplates.DEFAULT_KIND)
      return
    }
    const caret = this.currentContentCaret()
    let result: EditorInsertResult
    switch (action) {
      case 'quote':
        result = EditorMarkdownInsert.insertBlockPrefix(this.content, caret, '>')
        break
      case 'hr':
        result = EditorMarkdownInsert.insertBlockPrefix(this.content, caret, '---')
        break
      case 'checkbox':
        result = EditorMarkdownInsert.insertAtLineStart(this.content, caret, '[ ] ')
        break
      case 'orderedList':
        result = EditorMarkdownInsert.insertOrderedListItem(this.content, caret, true)
        break
      case 'bulletList':
        result = EditorMarkdownInsert.insertBlockPrefix(this.content, caret, '* ', true)
        break
      case 'bold':
        result = EditorMarkdownInsert.wrapPlaceholder(
          this.content,
          caret,
          caret,
          '**',
          '**',
          '文字',
          2
        )
        break
      case 'strike':
        result = EditorMarkdownInsert.wrapPlaceholder(
          this.content,
          caret,
          caret,
          '~~',
          '~~',
          '文字',
          2
        )
        break
      case 'italic':
        result = EditorMarkdownInsert.wrapPlaceholder(
          this.content,
          caret,
          caret,
          '*',
          '*',
          '文字',
          1
        )
        break
      default:
        return
    }
    this.applyContentInsert(result)
  }

  private insertMermaidTemplate(kind: string = MermaidTemplates.DEFAULT_KIND): void {
    this.captureContentCaretFromSelection()
    const caret = this.currentContentCaret()
    const result = MermaidTemplates.insertTemplate(this.content, caret, kind)
    this.applyContentInsert(result)
  }

  private async ensurePreferencesInitialized(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
  }

  private async refreshTagPool(): Promise<void> {
    await this.ensurePreferencesInitialized()
    const stored = await PreferencesService.getInstance().getNoteTags()
    const allNotes = await NoteRepository.getInstance().listNotes()
    const fromNotes: string[] = []
    for (const n of allNotes) {
      fromNotes.push(...n.tags)
    }
    this.tagPool = this.normalizeTags(fromNotes.concat(stored).concat(this.noteTags))
  }

  private onPreviewCheckboxToggle(lineIndex: number, checked: boolean): void {
    const updated = MarkdownUtils.toggleCheckboxLine(this.content, lineIndex, checked)
    if (updated === this.content) {
      return
    }
    this.suppressContentCaretSync = true
    this.content = updated
    this.previousContent = updated
    this.scheduleSave()
    if (this.shouldRenderPreview()) {
      this.previewDirty = true
      this.refreshPreviewBlocks(updated)
    } else {
      this.previewDirty = true
    }
  }

  private applyTodoListEntryDefaults(): void {
    this.title = '待办事项'
    void this.onTagChecked('Todo', true)
    this.content = '[ ] '
    this.previousContent = this.content
    this.contentCaretIndex = this.content.length
    this.scheduleApplyCaret(this.content.length, this.content.length)
    this.handleContentChange()
    if (this.shouldRenderPreview()) {
      this.schedulePreviewRefresh()
    } else {
      this.previewDirty = true
    }
  }

  private isVoicePlaceholderNote(): boolean {
    if (this.pendingVoicePath.trim().length > 0) {
      return false
    }
    return this.audioId.length === 0 &&
      this.content.trim().length === 0 &&
      (this.title.trim().length === 0 ||
        this.title.trim() === EditorUiStrings.loc('新录音', 'New recording', '新規録音'))
  }

  private async abandonVoicePlaceholderIfNeeded(): Promise<void> {
    if (!this.isVoicePlaceholderNote() || this.noteId.length === 0) {
      return
    }
    const id = this.noteId
    this.noteId = ''
    await NoteRepository.getInstance().purgeLocalNoteCompletely(id)
  }

  private async onVoiceRecordingComplete(outputPath: string): Promise<void> {
    if (!(await ensureAiMembershipAccess(this.getUIContext()))) {
      return
    }
    if (this.noteId.length === 0) {
      return
    }
    const svc = AiNoteBackgroundTaskService.getInstance()
    if (!svc.ensureIdleOrNotifyBusy()) {
      return
    }
    this.aiWorkingOverlayMessage = EditorUiStrings.loc('AI 处理中…', 'AI working…', 'AI処理中…')
    this.aiNoteWorking = true
    const started = await svc.runVoiceTranscribe(this.noteId, outputPath)
    if (!started && !svc.isBusy) {
      this.aiNoteWorking = false
    }
  }

  private runPendingVoicePathIfNeeded(): void {
    if (this.pendingVoiceHandled) {
      return
    }
    const path = this.pendingVoicePath.trim()
    if (path.length === 0) {
      return
    }
    this.pendingVoiceHandled = true
    this.pendingVoicePath = ''
    setTimeout((): void => {
      if (!this.lifecycle.isActive()) {
        return
      }
      void this.onVoiceRecordingComplete(path)
    }, 0)
  }

  private noteTagsSafe(): string[] {
    return this.noteTags ?? []
  }

  private shouldPersistTodoNote(): boolean {
    if (!this.noteTagsSafe().includes('Todo')) {
      return true
    }
    return shouldPersistTodoNote(this.title, this.content)
  }

  private async abandonPlaceholderTodoIfNeeded(): Promise<void> {
    if (this.shouldPersistTodoNote() || this.initialHadTodoContent || this.noteId.length === 0) {
      return
    }
    await NoteRepository.getInstance().purgeLocalNoteCompletely(this.noteId)
    this.noteId = ''
  }

  private normalizeTags(tags?: string[]): string[] {
    const seen: Set<string> = new Set()
    const normalized: string[] = []
    for (const rawTag of tags ?? []) {
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

  private async onAiCreateTag(): Promise<void> {
    if (this.aiTagCreating) {
      return
    }
    if (!(await ensureAiMembershipAccess(this.getUIContext()))) {
      return
    }
    this.aiTagCreating = true
    this.tagMenuVisible = false
    try {
      await this.refreshTagPool()
      const suggested = await AiTagService.getInstance().suggestTag(
        this.title,
        this.content,
        this.tagPool
      )
      const resolved = suggested
      const isNew = AiTagService.findExactPoolTag(resolved, this.tagPool) === null
      if (isNew) {
        const stored = await PreferencesService.getInstance().getNoteTags()
        const nextStored = this.normalizeTags(stored.concat([resolved]))
        await PreferencesService.getInstance().saveNoteTags(nextStored)
        await this.refreshTagPool()
      }
      await this.onTagChecked(resolved, true)
      this.showPreviewMessage(EditorUiStrings.loc(
        isNew ? `已创建并应用标签：${resolved}` : `已应用标签：${resolved}`,
        isNew ? `Created and applied tag: ${resolved}` : `Applied tag: ${resolved}`,
        isNew ? `タグを作成して適用：${resolved}` : `タグを適用：${resolved}`
      ))
    } catch (e) {
      const msg = e instanceof Error ? e.message : ''
      if (msg === 'subscription_required') {
        await ensureAiMembershipAccess(this.getUIContext())
        return
      }
      const detail = e instanceof Error
        ? e.message
        : AiTagService.describeError(e as Object)
      this.showPreviewMessage(
        UserFacingMessage.forAi(
          e instanceof Error ? e.message : undefined,
          EditorUiStrings.loc('AI 创建标签失败，请稍后重试', 'AI tag creation failed; try again', 'AIタグ作成に失敗しました。後でもう一度お試しください')
        )
      )
      Logger.error('NoteEdit', `onAiCreateTag failed: ${detail}`)
    } finally {
      this.aiTagCreating = false
    }
  }

  private async onTagChecked(tag: string, selected: boolean): Promise<void> {
    const next: string[] = [...this.noteTags]
    if (selected) {
      if (!next.includes(tag)) {
        next.push(tag)
      }
    } else {
      const idx = next.indexOf(tag)
      if (idx >= 0) {
        next.splice(idx, 1)
      }
    }
    this.noteTags = this.normalizeTags(next)
    if (this.noteId.length === 0) {
      this.scheduleSave()
      return
    }
    await this.persistTagsToRepository()
  }

  private resolveTitleForSave(rawTitle: string, content: string): TitleSaveResolution {
    return resolveTitleForSave(rawTitle, content, this.titleFieldFocused)
  }

  private onTitleFieldFocus(): void {
    this.titleFieldFocused = true
  }

  private onTitleFieldBlur(): void {
    this.titleFieldFocused = false
    if (this.title.trim().length === 0 && this.content.trim().length > 0) {
      this.scheduleSave()
    }
  }

  private async persistTagsToRepository(): Promise<void> {
    try {
      const resolved = this.resolveTitleForSave(this.title, this.content)
      const note = await NoteRepository.getInstance().saveDraft(this.noteId, {
        title: resolved.title,
        content: this.content,
        tags: this.noteTags,
        skipTitleAutoFill: resolved.skipTitleAutoFill
      })
      this.lastSavedAt = note.updatedAt
      this.saveStatus = '已保存'
    } catch (error) {
      this.saveStatus = '保存失败'
      Logger.error('NoteEdit', `persistTagsToRepository failed: ${JSON.stringify(error)}`)
    }
  }

  private async openTagManage(): Promise<void> {
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/TagManage',
        params: {}
      })
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showPreviewMessage(EditorUiStrings.loc('打开标签管理失败', 'Could not open tag manager', 'タグ管理を開けませんでした'))
    }
  }

  private async openHistoryPage(): Promise<void> {
    if (this.noteId.length === 0) {
      return
    }
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/NoteHistory',
        params: { noteId: this.noteId }
      })
    } catch (error) {
      Logger.warn('NoteEdit', `openHistoryPage failed: ${JSON.stringify(error)}`)
    }
  }

  private async loadNote(): Promise<void> {
    this.aiUndoBaselineContent = null
    this.aiUndoAvailable = false
    await NoteRepository.getInstance().init()
    if (!this.lifecycle.isActive()) {
      return
    }
    if (!this.noteId) {
      this.previewMode = this.pageWidth >= 600 ? 'split' : 'edit'
      this.syncContentTabIndexFromPreviewMode()
      this.preparePreviewForCurrentMode(this.content)
      void this.refreshAllNotes()
      this.runInitialActionIfNeeded()
      this.runPendingVoicePathIfNeeded()
      this.scheduleMembershipExpiryReminderIfNeeded()
      return
    }
    const note = await NoteRepository.getInstance().getNote(this.noteId)
    if (!this.lifecycle.isActive()) {
      return
    }
    if (!note) {
      this.preparePreviewForCurrentMode(this.content)
      this.runInitialActionIfNeeded()
      this.runPendingVoicePathIfNeeded()
      this.scheduleMembershipExpiryReminderIfNeeded()
      return
    }
    this.title = note.title
    this.content = note.content
    this.audioId = note.audioId ?? ''
    this.previousContent = note.content
    this.contentCaretIndex = note.content.length
    this.lastSavedAt = note.updatedAt
    this.noteCreatedAt = note.createdAt
    this.saveStatus = '已保存'
    this.noteTags = this.normalizeTags(note.tags)
    this.parentId = `${note.parentId ?? ''}`.trim()
    this.initialHadTodoContent = this.noteTagsSafe().includes('Todo') &&
      shouldPersistTodoNote(note.title, note.content)
    const hasBody = note.content.trim().length > 0
    if (this.preferPreviewOnOpen && hasBody) {
      this.previewMode = this.isSplitMode() ? 'split' : 'preview'
    } else {
      this.previewMode = this.isSplitMode() ? 'split' : 'edit'
    }
    this.syncContentTabIndexFromPreviewMode()
    // 编辑/分屏：强制富文本编辑器按正文重建（aboutToAppear 时可能还是空 content）
    if (this.previewMode === 'edit' || this.previewMode === 'split') {
      this.editorEnterEditToken = this.editorEnterEditToken + 1
      Logger.info('NoteEdit',
        `loadNote bump enterEditToken=${this.editorEnterEditToken} contentLen=${note.content.length} mode=${this.previewMode}`)
    }
    this.preparePreviewForCurrentMode(note.content)
    void this.refreshAllNotes()
    this.schedulePathCaptionMarquee()
    this.syncAiWorkingFromBackgroundTask()
    this.runInitialActionIfNeeded()
    this.runPendingVoicePathIfNeeded()
    this.scheduleMembershipExpiryReminderIfNeeded()
    if (isExtractStatusPending(note.extractStatus)) {
      setTimeout((): void => {
        if (!this.lifecycle.isActive()) {
          return
        }
        void this.getUIContext().getRouter().replaceUrl({
          url: 'pages/LinkExtractProgress',
          params: {
            noteId: note.id,
            kind: 'linkExtract',
            url: note.sourceUrl.trim()
          }
        }).catch((err: Error) => {
          console.error(`redirect extract progress: ${JSON.stringify(err)}`)
        })
      }, 0)
    }
  }

  private scheduleMembershipExpiryReminderIfNeeded(): void {
    if (!this.lifecycle.isActive()) {
      return
    }
    void maybeShowMembershipExpiryReminderDialog(this.getUIContext())
  }

  private runInitialActionIfNeeded(): void {
    if (this.initialActionHandled || this.pendingInitialAction === null) {
      return
    }
    this.initialActionHandled = true
    const action = this.pendingInitialAction
    setTimeout((): void => {
      if (!this.lifecycle.isActive()) {
        return
      }
      if (action === 'aiLinkExtract') {
        void this.openAiLinkExtractPage()
      } else if (action === 'insertImage') {
        void this.insertImage()
      } else if (action === 'generateNoteFromImage') {
        void this.insertImage(true, true)
      } else if (action === 'bookScan') {
        void this.insertImage(true, true, true, true)
      } else if (action === 'todoList') {
        this.applyTodoListEntryDefaults()
      }
      // voiceMemo：首页已改为先开 VoiceNote，不再从编辑页二次打开
    }, 0)
  }

  private async refreshAllNotes(): Promise<void> {
    await NoteRepository.getInstance().init()
    const notes = await NoteRepository.getInstance().listNotes()
    if (this.lifecycle.isActive()) {
      this.allNotes = notes
    }
  }

  private expandedFolderIdSet(): Set<string> {
    return new Set(this.expandedFolderIds)
  }

  private scheduleSave(): void {
    if (this.isVoicePlaceholderNote() || shouldSkipAutoSaveSchedule(
      this.title,
      this.content,
      this.noteTagsSafe().includes('Todo'),
      this.shouldPersistTodoNote()
    )) {
      if (this.saveTimer !== -1) {
        clearTimeout(this.saveTimer)
        this.saveTimer = -1
      }
      this.saveStatus = '未保存'
      return
    }
    this.saveStatus = '保存中...'
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer)
    }
    this.saveTimer = setTimeout(() => {
      void this.handleAutoSave()
    }, 2000)
  }

  private schedulePreviewRefresh(): void {
    if (!this.shouldRenderPreview()) {
      this.previewDirty = true
      if (this.previewTimer !== -1) {
        clearTimeout(this.previewTimer)
        this.previewTimer = -1
      }
      return
    }
    if (this.previewTimer !== -1) {
      clearTimeout(this.previewTimer)
    }
    this.previewDirty = true
    this.previewTimer = setTimeout(() => {
      this.previewTimer = -1
      this.refreshPreviewBlocks(this.content)
    }, 260)
  }

  private refreshPreviewBlocks(content: string): void {
    if (!this.previewDirty && this.previewSource === content && this.previewBlocksState.length > 0) {
      return
    }
    this.previewSource = content
    this.previewBlocksState = MarkdownUtils.parseBlocks(content)
    this.previewDirty = false
  }

  private async handleAutoSave(): Promise<void> {
    try {
      if (AiNoteBackgroundTaskService.getInstance().shouldSkipEditorAutoSave(
        this.noteId,
        this.content,
        this.title
      )) {
        return
      }
      Logger.info('NoteEdit',
        `handleAutoSave start: noteId=${this.noteId || 'new'}, titleLength=${this.title.length}, contentLength=${this.content.length}`)
      const rawTitle = this.title
      if (this.noteTagsSafe().includes('Todo') && !this.shouldPersistTodoNote()) {
        await this.abandonPlaceholderTodoIfNeeded()
        this.saveStatus = '未保存'
        Logger.info('NoteEdit', 'handleAutoSave skipped: placeholder todo note')
        return
      }
      if (this.isVoicePlaceholderNote()) {
        if (this.pendingVoicePath.trim().length > 0) {
          this.saveStatus = '未保存'
          Logger.info('NoteEdit', 'handleAutoSave skipped: pending voice path')
          return
        }
        await this.abandonVoicePlaceholderIfNeeded()
        this.saveStatus = '未保存'
        Logger.info('NoteEdit', 'handleAutoSave skipped: voice placeholder note')
        return
      }
      if (rawTitle.trim().length === 0 && this.content.trim().length === 0) {
        this.saveStatus = '未保存'
        Logger.info('NoteEdit', 'handleAutoSave skipped: title and content are empty')
        return
      }
      const resolved = this.resolveTitleForSave(rawTitle, this.content)
      let note: Note | null = null
      if (!this.noteId) {
        note = await NoteRepository.getInstance().createNote({
          title: resolved.title,
          content: this.content,
          tags: this.normalizeTags(this.noteTags),
          skipTitleAutoFill: resolved.skipTitleAutoFill
        })
        this.noteId = note.id
        if (this.parentId.trim().length > 0) {
          note = await NoteRepository.getInstance().saveDraft(this.noteId, {
            parentId: this.parentId
          })
        }
      } else {
        note = await NoteRepository.getInstance().saveDraft(this.noteId, {
          title: resolved.title,
          content: this.content,
          tags: this.normalizeTags(this.noteTags),
          parentId: this.parentId,
          skipTitleAutoFill: resolved.skipTitleAutoFill
        })
      }
      if (!this.titleFieldFocused) {
        this.title = note.title
      }
      this.noteTags = this.normalizeTags(note.tags)
      this.lastSavedAt = note.updatedAt
      this.noteCreatedAt = note.createdAt
      this.saveStatus = '已保存'
      Logger.info('NoteEdit',
        `handleAutoSave success: noteId=${this.noteId}, titleLength=${this.title.length}, contentLength=${this.content.length}`)
    } catch (error) {
      this.saveStatus = '保存失败'
      Logger.error('NoteEdit', `handleAutoSave failed: ${JSON.stringify(error)}`)
      console.error(JSON.stringify(error))
    }
  }

  /** 拦截系统返回键，与工具栏返回一致。 */
  onBackPress(): boolean {
    this.handleBack()
    return true
  }

  private handleBack(): void {
    if (!this.closeGuard.tryBeginClose()) {
      return
    }
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer)
      this.saveTimer = -1
    }
    this.getUIContext().getRouter().back()
    void this.flushAndAutoSaveAfterLeave()
  }

  private async flushAndAutoSaveAfterLeave(): Promise<void> {
    await new Promise<void>((resolve: () => void) => setTimeout(() => resolve(), 0))
    if (AiNoteBackgroundTaskService.getInstance().shouldSkipEditorAutoSave(
      this.noteId,
      this.content,
      this.title
    )) {
      return
    }
    try {
      await this.handleAutoSave()
      if (this.noteId.length > 0) {
        const note = await NoteRepository.getInstance().getNote(this.noteId)
        if (note !== null) {
          await NoteHistoryService.getInstance().captureIfNeeded(note, NoteHistoryReason.editorLeave)
        }
      }
    } catch (error) {
      Logger.warn('NoteEdit', `flushAndAutoSaveAfterLeave failed: ${JSON.stringify(error)}`)
    }
  }

  private async ensureNoteIdForAiTask(): Promise<void> {
    if (this.noteId.length > 0) {
      return
    }
    const note = await NoteRepository.getInstance().createNote({
      title: '',
      content: '',
      tags: []
    })
    this.noteId = note.id
    this.lastSavedAt = note.updatedAt
    this.saveStatus = '已保存'
  }

  private onToggleFolderExpand(folderId: string): void {
    if (folderId === NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID) {
      if (this.expandedFolderIds.includes(NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID)) {
        this.expandedFolderIds = this.expandedFolderIds.filter(
          (id: string) => id !== NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID
        )
      } else {
        this.expandedFolderIds = [...this.expandedFolderIds, NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID]
      }
      return
    }
    const expanded = this.expandedFolderIdSet()
    NoteFolderTree.applyToggleExpand(folderId, this.allNotes, expanded)
    this.expandedFolderIds = Array.from(expanded)
  }

  private getMovePickerEntries(): MovePickerEntry[] {
    return NoteFolderTree.visibleMovePickerEntries(
      this.allNotes,
      this.expandedFolderIdSet(),
      this.noteId
    )
  }

  private async onSelectMoveFolder(folderId: string): Promise<void> {
    if (this.noteId.length > 0 &&
      NoteFolderTree.wouldCreateParentCycle(this.noteId, folderId, this.allNotes)) {
      return
    }
    this.parentId = folderId
    this.folderMovePopupVisible = false
    if (this.noteId.length === 0) {
      this.scheduleSave()
      return
    }
    try {
      let note = await NoteRepository.getInstance().saveDraft(this.noteId, {
        parentId: folderId
      })
      this.parentId = `${note.parentId ?? ''}`.trim()
      this.lastSavedAt = note.updatedAt
      this.saveStatus = '已保存'
      void this.refreshAllNotes()
      this.schedulePathCaptionMarquee()
    } catch (error) {
      this.saveStatus = '保存失败'
      Logger.error('NoteEdit', `onSelectMoveFolder failed: ${JSON.stringify(error)}`)
    }
  }

  private parentPathSegments(): string[] {
    return NoteFolderTree.parentPathSegments(this.parentId, this.allNotes)
  }

  private stopPathCaptionTimer(): void {
    if (this.pathCaptionMarqueeTimer !== -1) {
      clearInterval(this.pathCaptionMarqueeTimer)
      this.pathCaptionMarqueeTimer = -1
    }
  }

  private stopPathCaptionMarquee(): void {
    this.pathCaptionMarqueeToken += 1
    this.stopPathCaptionTimer()
    this.pathCaptionScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
  }

  private startPathCaptionLedMarquee(maxX: number, token: number): void {
    this.stopPathCaptionTimer()
    this.pathCaptionScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
    this.pathCaptionMarqueeTimer = setInterval(() => {
      if (token !== this.pathCaptionMarqueeToken || this.isSplitMode()) {
        this.stopPathCaptionTimer()
        return
      }
      this.pathCaptionScroller.scrollBy(NoteEdit.PATH_CAPTION_LED_STEP_VP, 0)
      const current = this.pathCaptionScroller.currentOffset().xOffset
      if (current >= maxX) {
        this.pathCaptionScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
      }
    }, NoteEdit.PATH_CAPTION_LED_FRAME_MS)
  }

  private tryStartPathCaptionMarqueeFromMeasure(): void {
    if (this.isSplitMode()) {
      return
    }
    if (this.pathCaptionContentWidthVp <= 0 || this.pathCaptionViewportWidthVp <= 0) {
      return
    }
    const maxX = this.pathCaptionContentWidthVp - this.pathCaptionViewportWidthVp
    if (maxX <= 1) {
      this.stopPathCaptionTimer()
      this.pathCaptionScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
      return
    }
    this.startPathCaptionLedMarquee(maxX, this.pathCaptionMarqueeToken)
  }

  private schedulePathCaptionMarquee(): void {
    this.stopPathCaptionTimer()
    this.pathCaptionContentWidthVp = 0
    this.pathCaptionViewportWidthVp = 0
    this.pathCaptionScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
  }

  private onPathCaptionContentAreaChange(area: Area): void {
    const width = Number.parseFloat(`${area.width}`)
    if (width > 0 && Math.abs(this.pathCaptionContentWidthVp - width) >= 0.5) {
      this.pathCaptionContentWidthVp = width
      this.tryStartPathCaptionMarqueeFromMeasure()
    }
  }

  private onPathCaptionViewportAreaChange(area: Area): void {
    const width = Number.parseFloat(`${area.width}`)
    if (width > 0 && Math.abs(this.pathCaptionViewportWidthVp - width) >= 0.5) {
      this.pathCaptionViewportWidthVp = width
      this.tryStartPathCaptionMarqueeFromMeasure()
    }
  }

  @Builder
  private buildParentPathCaption() {
    Scroll(this.pathCaptionScroller) {
      Row({ space: 0 }) {
        Text(EditorUiStrings.loc('当前位置：/', 'Location: /', '現在地：/'))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .flexShrink(0)
        Text(EditorUiStrings.loc('根目录', 'Root', 'ルート'))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .flexShrink(0)
        ForEach(this.parentPathSegments(), (segment: string, index: number) => {
          Text('/')
            .fontSize(13)
            .fontColor($r('app.color.secondary_text'))
            .flexShrink(0)
          Text(segment)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent'))
            .maxLines(1)
            .flexShrink(0)
        }, (segment: string, index: number) => `path_${this.parentId}_${index}_${segment}`)
      }
      .justifyContent(FlexAlign.Start)
      .onAreaChange((_: Area, area: Area) => {
        this.onPathCaptionContentAreaChange(area)
      })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .enableScrollInteraction(false)
    .clip(true)
    .align(Alignment.Start)
    .constraintSize({ maxWidth: '100%' })
    .onAreaChange((_: Area, area: Area) => {
      this.onPathCaptionViewportAreaChange(area)
    })
    .onAppear(() => {
      this.schedulePathCaptionMarquee()
    })
    .onDisAppear(() => {
      this.stopPathCaptionMarquee()
    })
  }

  private isSplitMode(): boolean {
    return this.pageWidth >= 600
  }

  private switchMode(mode: string): void {
    if (this.previewMode === mode) {
      if (mode === 'preview') {
        this.preparePreviewForCurrentMode(this.content, true)
      }
      this.syncContentTabIndexFromPreviewMode()
      return
    }
    const wasEditing = this.previewMode === 'edit' || this.previewMode === 'split'
    const willEdit = mode === 'edit' || mode === 'split'
    this.previewMode = mode
    if (mode === 'preview') {
      this.preparePreviewForCurrentMode(this.content, true)
    } else if (mode === 'edit') {
      this.tagMenuVisible = false
    }
    if (willEdit && !wasEditing) {
      this.editorEnterEditToken = this.editorEnterEditToken + 1
    }
    this.syncContentTabIndexFromPreviewMode()
  }

  /** 窄屏：contentTabIndex 与 previewMode 保持一致，并驱动 Swiper 切页。 */
  private syncContentTabIndexFromPreviewMode(): void {
    if (this.isSplitMode()) {
      return
    }
    const index = this.previewMode === 'preview' ? 1 : 0
    if (this.contentTabIndex !== index) {
      this.contentTabIndex = index
    }
    try {
      this.swiperController.changeIndex(index, true)
    } catch (error) {
      Logger.warn('NoteEdit', `swiperController.changeIndex failed: ${JSON.stringify(error)}`)
    }
  }

  private maybeSwitchToPreviewAfterAiSuccess(switchToPreviewOnSuccess: boolean): void {
    if (!switchToPreviewOnSuccess) {
      return
    }
    this.switchMode(this.isSplitMode() ? 'split' : 'preview')
  }

  private shouldRenderPreview(): boolean {
    return this.isSplitMode() || this.previewMode === 'preview'
  }

  private preparePreviewForCurrentMode(content: string, forceRefresh: boolean = false): void {
    if (!this.shouldRenderPreview() && !forceRefresh) {
      this.previewDirty = true
      return
    }
    if (forceRefresh) {
      this.previewDirty = true
    }
    this.refreshPreviewBlocks(content)
  }

  private showPreviewMessage(message: string): void {
    if (message.trim().length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message,
        duration: 1600
      })
    } catch (error) {
      console.error(`showToast failed: ${JSON.stringify(error)}`)
    }
  }

  private previewLinkPageTitle(href: string): string {
    const url = href.trim()
    const match = url.match(/^https?:\/\/([^/?#]+)/i)
    if (match !== null && match[1] !== undefined && match[1].length > 0) {
      return match[1]
    }
    return url.length <= 40 ? url : `${url.slice(0, 40)}…`
  }

  private openNoteImageGallery(tappedSrc: string): void {
    const sources = NoteImageGalleryUtils.collectImageSources(this.previewBlocksState)
    if (sources.length === 0) {
      return
    }
    this.pendingRestorePreviewMode = this.previewMode
    const trimmed = tappedSrc.trim()
    const initialIndex = trimmed.length > 0 ? sources.indexOf(trimmed) : 0
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/NoteImageGallery',
        params: {
          imagesJson: JSON.stringify(sources),
          initialIndex: initialIndex >= 0 ? initialIndex : 0,
          filesDir: this.filesDirCache
        }
      }).catch((err: Error) => {
        Logger.warn('NoteEdit', `openNoteImageGallery: ${JSON.stringify(err)}`)
      })
    } catch (error) {
      Logger.warn('NoteEdit', `openNoteImageGallery: ${JSON.stringify(error)}`)
    }
  }

  private openPreviewLink(href: string): void {
    const url = href.trim()
    if (url.length === 0) {
      return
    }
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/H5WebContainer',
        params: {
          title: this.previewLinkPageTitle(url),
          url: url
        }
      }).catch((err: Error) => {
        Logger.warn('NoteEdit', `openPreviewLink: ${JSON.stringify(err)}`)
      })
    } catch (error) {
      Logger.warn('NoteEdit', `openPreviewLink: ${JSON.stringify(error)}`)
    }
  }

  private async insertImage(
    thenOptimize: boolean = false,
    switchToPreviewOnSuccess: boolean = false,
    fromCamera: boolean = false,
    bookExtract: boolean = false
  ): Promise<void> {
    if (thenOptimize) {
      if (!(await ensureAiMembershipAccess(this.getUIContext()))) {
        return
      }
      if (!AiNoteBackgroundTaskService.getInstance().ensureIdleOrNotifyBusy()) {
        return
      }
    }
    try {
      let uri: string = ''
      if (fromCamera) {
        const context = this.obtainUiAbilityContext()
        if (!context) {
          this.showPreviewMessage(EditorUiStrings.loc('无法打开相机', 'Unable to open camera', 'カメラを開けません'))
          return
        }
        const granted = await requestCameraPermission()
        if (!granted) {
          this.showPreviewMessage(EditorUiStrings.loc(
            '需要相机权限才能拍照',
            'Camera permission is required to take photos',
            '写真を撮るにはカメラ権限が必要です'
          ))
          return
        }
        uri = await capturePhotoUri(context)
        if (uri.length === 0) {
          return
        }
      } else {
        const photoSelectOptions: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions()
        photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
        photoSelectOptions.maxSelectNumber = 1
        const photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker()
        const result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(photoSelectOptions)
        uri = result.photoUris[0] ?? ''
        if (uri.length === 0) {
          return
        }
      }
      if (thenOptimize && !AiNoteBackgroundTaskService.getInstance().ensureIdleOrNotifyBusy()) {
        return
      }
      const base =
        this.filesDirCache.length > 0 ? this.filesDirCache : (this.obtainUiAbilityContext()?.filesDir ?? '')
      const imagesDir = `${base}/qingyu-note-image`
      if (!fileIo.accessSync(imagesDir)) {
        fileIo.mkdirSync(imagesDir, true)
      }
      const randomStr = Math.random().toString(36).slice(2, 8)
      const ext = '.png'
      const fileName = `${Date.now()}_${randomStr}${ext}`
      const destPath = `${imagesDir}/${fileName}`
      const srcFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const destFile = fileIo.openSync(destPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      await fileIo.copyFile(srcFile.fd, destFile.fd)
      fileIo.closeSync(srcFile)
      fileIo.closeSync(destFile)
      const relativePath = `qingyu-note-image/${fileName}`
      const imageMarkdown = `![图片](${relativePath})`
      const text = this.content
      if (text.length > 0 && !text.endsWith('\n')) {
        this.content = `${text}\n${imageMarkdown}\n`
      } else {
        this.content = `${text}${imageMarkdown}\n`
      }
      this.signalToolbarEmbed('image', '图片', relativePath)
      this.suppressContentCaretSync = true
      this.scheduleApplyCaret(this.content.length)
      this.scheduleSave()
      if (this.shouldRenderPreview()) {
        this.schedulePreviewRefresh()
      } else {
        this.previewDirty = true
      }
      if (thenOptimize && this.lifecycle.isActive()) {
        await this.onAiOptimizeContent(switchToPreviewOnSuccess, bookExtract)
      }
    } catch (error) {
      Logger.error('NoteEdit', `insertImage failed: ${JSON.stringify(error)}`)
      this.showPreviewMessage(fromCamera
        ? EditorUiStrings.loc('无法打开相机', 'Unable to open camera', 'カメラを開けません')
        : EditorUiStrings.loc('插入图片失败', 'Failed to insert image', '画像の挿入に失敗しました'))
    }
  }

  private async trimShareSlice(pm: image.PixelMap): Promise<image.PixelMap | null> {
    const ui = this.getUIContext()
    const contentPx = this.shareExportColumnVp > 0
      ? Math.max(1, Math.round(ui.vp2px(this.shareExportColumnVp)))
      : 0
    return trimShareTransparentVerticalEdges(pm, contentPx)
  }

  private async exportShareImageToCache(
    theme: ShareCardTheme = this.shareTheme,
    tone: ShareCardTone = this.shareTone
  ): Promise<string | null> {
    if (this.shareTheme !== theme) {
      this.shareTheme = theme
    }
    if (this.shareTone !== tone) {
      this.shareTone = tone
    }
    const palette = ShareThemeColors.resolve(theme, tone)
    Logger.info('NoteEdit',
      `exportShareImageToCache prepare theme=${theme} tone=${tone} ` +
      `bg=${palette.background} text=${palette.textPrimary} gradient=${palette.backgroundGradient?.join('->') ?? 'none'}`)
    this.refreshPreviewBlocks(this.content)
    const jinshuLight = theme === ShareCardTheme.JINSHU && tone === ShareCardTone.LIGHT
    await this.mountShareExportCard(theme, tone, false, false)
    try {
      let path = await this.offlineSnapshotCapture()
      if (!path && jinshuLight && !this.shareExportSnapshotCompatMode) {
        Logger.warn('NoteEdit',
          `exportShareImageToCache retry without jinshu light quote ` +
          `theme=${theme} tone=${tone} key=${this.shareCardCaptureKey}`)
        await this.mountShareExportCard(theme, tone, true, false)
        path = await this.offlineSnapshotCapture()
        Logger.info('NoteEdit',
          `exportShareImageToCache jinshu light compat retry result=${path !== null} ` +
          `theme=${theme} tone=${tone} key=${this.shareCardCaptureKey}`)
      }
      if (!path && jinshuLight && !this.shareExportSnapshotSkipQr) {
        Logger.warn('NoteEdit',
          `exportShareImageToCache retry without jinshu light qr ` +
          `theme=${theme} tone=${tone} key=${this.shareCardCaptureKey}`)
        await this.mountShareExportCard(theme, tone, true, true)
        path = await this.offlineSnapshotCapture()
        Logger.info('NoteEdit',
          `exportShareImageToCache jinshu light skip-qr retry result=${path !== null} ` +
          `theme=${theme} tone=${tone} key=${this.shareCardCaptureKey}`)
      }
      if (!path && !this.shareExportSnapshotSkipQr) {
        Logger.warn('NoteEdit',
          `exportShareImageToCache retry skip qr theme=${theme} tone=${tone} key=${this.shareCardCaptureKey}`)
        await this.mountShareExportCard(theme, tone, this.shareExportSnapshotCompatMode, true)
        path = await this.offlineSnapshotCapture()
        Logger.info('NoteEdit',
          `exportShareImageToCache skip-qr retry result=${path !== null} ` +
          `theme=${theme} tone=${tone} key=${this.shareCardCaptureKey}`)
      }
      return path
    } catch (error) {
      Logger.error('NoteEdit', `exportShareImageToCache failed: ${JSON.stringify(error)}`)
      return null
    } finally {
      this.shareExportActive = false
      Logger.info('NoteEdit', `exportShareImageToCache unmount key=${this.shareCardCaptureKey}`)
    }
  }

  /** 卸载后按目标主题/色调重新挂载，确保 NoteShareExportCard 首次 build 即为正确 palette。 */
  private async mountShareExportCard(
    theme: ShareCardTheme,
    tone: ShareCardTone,
    snapshotCompatMode: boolean = false,
    snapshotSkipQr: boolean = false
  ): Promise<void> {
    if (this.shareExportActive) {
      this.shareExportActive = false
      await noteEditDelayMs(48)
    }
    this.shareCardCaptureKey++
    const palette = ShareThemeColors.resolve(theme, tone)
    this.shareExportTheme = theme
    this.shareExportTone = tone
    this.shareExportSnapshotCompatMode = snapshotCompatMode
    this.shareExportSnapshotSkipQr = snapshotSkipQr
    this.shareExportScrollBg = palette.backgroundGradient?.[0] ?? palette.background
    this.shareExportColumnVp = 0
    this.shareCardHeight = 0
    this.shareExportActive = true
    const jinshuLight = theme === ShareCardTheme.JINSHU && tone === ShareCardTone.LIGHT
    Logger.info('NoteEdit',
      `mountShareExportCard key=${this.shareCardCaptureKey} theme=${theme} tone=${tone} ` +
      `compat=${snapshotCompatMode} skipQr=${snapshotSkipQr} scrollBg=${this.shareExportScrollBg}`)
    this.shareScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
    const hasImages = shareExportContentHasImages(
      this.previewBlocksState,
      this.shareAvatarUrlTrim()
    )
    const mountDelayMs = shareExportMountDelayMs(theme, tone, hasImages)
    await noteEditDelayMs(mountDelayMs)
    await MermaidRenderBarrier.waitUntilEmpty(8000)
  }

  /** 分享正文是否含 Markdown 图片块。 */
  private shareExportBodyHasImages(): boolean {
    return shareExportBodyHasImages(this.previewBlocksState)
  }

  private shareExportContentHasImages(): boolean {
    return shareExportContentHasImages(
      this.previewBlocksState,
      this.shareAvatarUrlTrim()
    )
  }

  private shareExportMountKey(): string {
    return shareExportMountKey(
      this.shareCardCaptureKey,
      this.shareExportTheme,
      this.shareExportTone,
      this.shareExportSnapshotCompatMode,
      this.shareExportSnapshotSkipQr,
      this.shareShowAppIcon
    )
  }

  /** 长内容优先截 Scroll 视口，避免整卡高度超过 ComponentSnapshot 底层限制（约 8614px）。 */
  private shareSnapshotPreferScrollViewport(): boolean {
    const columnVp = this.shareExportColumnVp
    if (columnVp <= 0) {
      return this.pageHeight > 0
    }
    const viewportVp = Math.max(this.pageHeight, this.shareCardHeight, 800)
    return columnVp > NoteEdit.SHARE_SNAPSHOT_MAX_FULL_CARD_VP ||
      columnVp > viewportVp * 0.92
  }

  private async offlineSnapshotCapture(): Promise<string | null> {
    const context = this.obtainUiAbilityContext()
    if (context === undefined) {
      return null
    }
    this.refreshPreviewBlocks(this.content)
    await new Promise<void>((resolve) => setTimeout(() => resolve(), 100))
    try {
      const pngBuf = await this.captureScrollingCardToImage()
      if (!pngBuf || pngBuf.byteLength === 0) {
        return null
      }
      const filePath: string = `${context.cacheDir}/note_share_${Date.now()}.png`
      const f: fileIo.File = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(f.fd, pngBuf)
      fileIo.closeSync(f)
      Logger.info('NoteEdit', `saved long image to ${filePath}, size: ${pngBuf.byteLength}`)
      return filePath
    } catch (err) {
      Logger.error('NoteEdit', `offlineSnapshotCapture failed: ${JSON.stringify(err)}`)
      return null
    }
  }

  /**
   * 对已挂载的导出节点分段截图并纵向拼接。
   * 不使用 createFromBuilder，避免 Builder 在隔离上下文中缺少 observeComponentCreation2。
   */
  private async captureScrollingCardToImage(): Promise<ArrayBuffer | null> {
    await noteEditDelayMs(240)
    return await this.captureScrollingCardToImageCore()
  }

  /**
   * 按候选 id 尝试抓取快照并打印详细日志，便于定位 100001 来源。
   */
  private async getShareSnapshotWithCandidates(
    opts: componentSnapshot.SnapshotOptions,
    phase: string
  ): Promise<image.PixelMap | null> {
    const snap = this.getUIContext().getComponentSnapshot()
    const preferScroll = this.shareSnapshotPreferScrollViewport()
    const candidates: string[] = preferScroll
      ? [NOTE_EDIT_SHARE_SCROLL_ID, NoteEdit.SHARE_CARD_ID]
      : [NoteEdit.SHARE_CARD_ID, NOTE_EDIT_SHARE_SCROLL_ID]
    for (const candidate of candidates) {
      if (preferScroll && candidate === NoteEdit.SHARE_CARD_ID &&
        this.shareExportColumnVp > NoteEdit.SHARE_SNAPSHOT_MAX_FULL_CARD_VP) {
        continue
      }
      try {
        Logger.info('NoteEdit',
          `snapshot try phase=${phase} candidate=${candidate} preferScroll=${preferScroll} ` +
          `columnVp=${this.shareExportColumnVp} key=${this.shareCardCaptureKey} ` +
          `theme=${this.shareExportTheme} tone=${this.shareExportTone} compat=${this.shareExportSnapshotCompatMode}`)
        const pm = await snap.get(candidate, opts)
        Logger.info('NoteEdit',
          `snapshot success phase=${phase} candidate=${candidate} key=${this.shareCardCaptureKey}`)
        return pm
      } catch (error) {
        Logger.warn('NoteEdit',
          `snapshot failed phase=${phase} candidate=${candidate} key=${this.shareCardCaptureKey}: ${JSON.stringify(error)}`)
      }
    }
    return null
  }

  /** ComponentSnapshot 需等待 Image 解码；长内容优先 Scroll 视口截图。 */
  private shareSnapshotWaitOpts(): componentSnapshot.SnapshotOptions {
    return { waitUntilRenderFinished: true }
  }

  private isJinshuLightExport(): boolean {
    return this.shareExportTheme === ShareCardTheme.JINSHU && this.shareExportTone === ShareCardTone.LIGHT
  }

  private jinshuLightExportTextLen(): number {
    return ShareThemeColors.stripMarkdown(this.content).length
  }

  private async snapshotShareNodeById(
    nodeId: string,
    opts: componentSnapshot.SnapshotOptions,
    _phase: string
  ): Promise<image.PixelMap | null> {
    const snap = this.getUIContext().getComponentSnapshot()
    try {
      return await snap.get(nodeId, opts)
    } catch (error) {
      Logger.warn('NoteEdit',
        `jinshuLight segment failed id=${nodeId} key=${this.shareCardCaptureKey}: ${JSON.stringify(error)}`)
      return null
    }
  }

  /**
   * 锦书浅色：整卡 snapshot 因 body 过高失败时，按 quote / 正文分块 / 页脚分段截图再纵向拼接。
   */
  private async captureJinshuLightSegmented(): Promise<ArrayBuffer | null> {
    const waitOpts = this.shareSnapshotWaitOpts()
    const textLen = this.jinshuLightExportTextLen()
    const includeQuote = !this.shareExportSnapshotCompatMode
    const segmentIds = buildJinshuLightSegmentCaptureIds(textLen, includeQuote)

    const slices: image.PixelMap[] = []
    for (const nodeId of segmentIds) {
      const pm = await this.snapshotShareNodeById(nodeId, waitOpts, 'segment')
      if (!pm) {
        for (const s of slices) {
          await s.release()
        }
        Logger.error('NoteEdit',
          `captureJinshuLightSegmented aborted at id=${nodeId} key=${this.shareCardCaptureKey}`)
        return null
      }
      slices.push(pm)
    }

    if (slices.length === 0) {
      return null
    }
    if (slices.length === 1) {
      const trimmed = await this.trimShareSlice(slices[0])
      await slices[0].release()
      if (!trimmed) {
        return null
      }
      const buf = await packSharePixelMapToPng(trimmed)
      await trimmed.release()
      return buf
    }

    let widthPx = 0
    let totalHeightPx = 0
    for (const s of slices) {
      const info = s.getImageInfoSync()
      widthPx = Math.max(widthPx, info.size.width)
      totalHeightPx += info.size.height
    }
    const sliceSkipTopPx: number[] = new Array(slices.length).fill(0)
    const normalized = await normalizeAllShareSlicesForMerge(slices)
    for (const s of slices) {
      await s.release()
    }
    if (!normalized) {
      Logger.error('NoteEdit', 'captureJinshuLightSegmented: normalizeAllSlicesForMerge failed')
      return null
    }
    let normHeightPx = 0
    for (const n of normalized) {
      normHeightPx += n.getImageInfoSync().size.height
    }
    const merged = await mergeSharePixelMapsVertical(normalized, widthPx, normHeightPx, 0, sliceSkipTopPx)
    if (!merged) {
      Logger.error('NoteEdit', 'captureJinshuLightSegmented: mergePixelMapsVertical returned null')
      return null
    }
    const buf = await packSharePixelMapToPng(merged)
    await merged.release()
    return buf
  }

  /** 滚动一遍并丢弃首帧截图，避免 Markdown 块仍显示上一套色调时分段截到旧帧。 */
  private async flushShareCardRenderSnapshot(): Promise<void> {
    const waitOpts = this.shareSnapshotWaitOpts()
    Logger.info('NoteEdit',
      `flushShareCardRenderSnapshot waitUntilRenderFinished=${waitOpts.waitUntilRenderFinished ?? false} ` +
      `theme=${this.shareExportTheme} tone=${this.shareExportTone} ` +
      `compat=${this.shareExportSnapshotCompatMode} skipQr=${this.shareExportSnapshotSkipQr}`)
    for (let round = 0; round < 2; round++) {
      this.shareScroller.scrollEdge(Edge.Bottom)
      await noteEditDelayMs(160)
      this.shareScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
      await noteEditDelayMs(160)
      try {
        const warmPm = await this.getShareSnapshotWithCandidates(waitOpts, `flush_round_${round}`)
        if (warmPm) {
          await warmPm.release()
        } else {
          Logger.warn('NoteEdit', `flushShareCardRenderSnapshot round=${round} no snapshot from all candidates`)
        }
        Logger.info('NoteEdit',
          `flushShareCardRenderSnapshot round=${round} key=${this.shareCardCaptureKey} ` +
          `theme=${this.shareExportTheme} tone=${this.shareExportTone}`)
      } catch (error) {
        Logger.warn('NoteEdit', `flushShareCardRenderSnapshot round=${round} failed: ${JSON.stringify(error)}`)
      }
    }
    await noteEditDelayMs(120)
  }

  private async captureScrollingCardToImageCore(): Promise<ArrayBuffer | null> {
    const waitOpts = this.shareSnapshotWaitOpts()
    const ui = this.getUIContext()
    const vpEps = 0.5
    const offsetWarnVp = 2.0

    this.shareScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
    await noteEditDelayMs(100)

    Logger.info('NoteEdit',
      `captureScrollingCardToImageCore start key=${this.shareCardCaptureKey} ` +
      `theme=${this.shareExportTheme} tone=${this.shareExportTone} targetCardId=${NoteEdit.SHARE_CARD_ID} ` +
      `targetScrollId=${NOTE_EDIT_SHARE_SCROLL_ID} ` +
      `waitUntilRenderFinished=${waitOpts.waitUntilRenderFinished ?? false}`)

    await this.flushShareCardRenderSnapshot()

    const jinshuLongBody =
      this.isJinshuLightExport() &&
      !this.shareExportBodyHasImages() &&
      this.jinshuLightExportTextLen() > ShareThemeColors.JINSHU_LIGHT_BODY_CHARS_PER_CHUNK
    if (jinshuLongBody) {
      return await this.captureJinshuLightSegmented()
    }

    // 长内容下 Column.onAreaChange 可能偏小；用 Scroller 最大偏移推算可滚范围（界面会先滚到底再回到顶部）。
    this.shareScroller.scrollEdge(Edge.Bottom)
    await noteEditDelayMs(120)
    const bottomOff = this.shareScroller.currentOffset()
    const maxScrollVp = Math.max(0, bottomOff.yOffset)

    this.shareScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
    await noteEditDelayMs(100)

    let firstPm: image.PixelMap | null = null
    try {
      Logger.info('NoteEdit',
        `captureScrollingCardToImageCore snapshot key=${this.shareCardCaptureKey} ` +
        `theme=${this.shareExportTheme} tone=${this.shareExportTone} ` +
        `compat=${this.shareExportSnapshotCompatMode} skipQr=${this.shareExportSnapshotSkipQr} scrollBg=${this.shareExportScrollBg}`)
      firstPm = await this.getShareSnapshotWithCandidates(waitOpts, 'first_frame')
    } catch (err) {
      Logger.error('NoteEdit',
        `snapshot get failed key=${this.shareCardCaptureKey} ` +
        `theme=${this.shareExportTheme} tone=${this.shareExportTone} compat=${this.shareExportSnapshotCompatMode}: ` +
        `${JSON.stringify(err)}`)
      return null
    }
    if (!firstPm) {
      if (this.isJinshuLightExport()) {
        Logger.warn('NoteEdit',
          `snapshot full card failed, try jinshu light segmented key=${this.shareCardCaptureKey} ` +
          `theme=${this.shareExportTheme} tone=${this.shareExportTone}`)
        return await this.captureJinshuLightSegmented()
      }
      Logger.error('NoteEdit',
        `snapshot get failed all candidates key=${this.shareCardCaptureKey} ` +
        `theme=${this.shareExportTheme} tone=${this.shareExportTone} compat=${this.shareExportSnapshotCompatMode}`)
      return null
    }

    let firstInfo: image.ImageInfo
    try {
      firstInfo = firstPm.getImageInfoSync()
    } catch (err) {
      Logger.error('NoteEdit', `getImageInfoSync failed: ${JSON.stringify(err)}`)
      await firstPm.release()
      return null
    }
    const widthPx = firstInfo.size.width
    const viewportPx = firstInfo.size.height
    // 视口步长必须与「实际截图像素高度」一致，否则长图拼接会出现重叠/错位。
    // 近期主题切换后，布局回调高度偶尔与 snapshot 高度不一致；这里统一以首帧截图高度为准。
    const stepVp = ui.px2vp(viewportPx)
    const rowStepPx = Math.max(1, Math.round(ui.vp2px(stepVp)))

    // Column.onAreaChange 得到的总高常以「内容真实高度」为准；Scroller.currentOffset 最大值有时偏小，
    // 若仅用 measured maxScrollVp，底部一段（常为 slogan+APP 说明）永远进不了视口。用布局推算的最小滚动行程兜底。
    const columnFromArea = this.shareExportColumnVp > 0 ? this.shareExportColumnVp : 0
    const columnTailVp = columnFromArea > 0 ? Math.max(0, columnFromArea - stepVp) : 0
    const scrollRangeVp = Math.max(maxScrollVp, columnTailVp)
    const extentVp = scrollRangeVp + stepVp
    const columnVp = Math.max(columnFromArea, extentVp, stepVp)
    const totalVp = Math.max(columnVp, stepVp)
    const totalPx = Math.max(Math.ceil(ui.vp2px(totalVp)), viewportPx)
    const extentPx = Math.ceil(ui.vp2px(extentVp))
    const mergeHeightPx = Math.min(totalPx, Math.max(viewportPx, extentPx))
    // 部分机型/版本上，snapshot.get(share card) 返回的是「整卡高度」而非 Scroll 视口高度。
    // 这时 firstPm 已是完整长图，若继续按滚动分片拼接会重复内容并出现错位。
    const snapshotCoversContent =
      columnFromArea > 0 && stepVp >= columnFromArea - vpEps

    const singleScreen = totalVp <= stepVp + vpEps

    if (singleScreen || snapshotCoversContent) {
      const trimmed = await this.trimShareSlice(firstPm)
      if (!trimmed) {
        return null
      }
      return await packSharePixelMapToPng(trimmed)
    }

    const slices: image.PixelMap[] = [firstPm]
    /** 每张截图对应的真实滚动偏移（vp），用于拼接去重；必须用 actualY，勿用目标 nextYVp（滚动可能被钳制）。 */
    const sliceScrollYVp: number[] = [this.shareScroller.currentOffset().yOffset]
    let yVp = 0
    while (true) {
      const nextYVp = Math.min(yVp + stepVp, scrollRangeVp)
      if (nextYVp <= yVp + vpEps) {
        break
      }
      // 目标超过 Scroller 初次测量的最大偏移时，先顶一次底再 scrollTo，便于引擎刷新可滚区域，露出末尾文案。
      if (nextYVp > maxScrollVp + vpEps) {
        this.shareScroller.scrollEdge(Edge.Bottom)
        await noteEditDelayMs(100)
      }
      this.shareScroller.scrollTo({ xOffset: 0, yOffset: nextYVp, animation: false })
      await noteEditDelayMs(150)
      let actualY = this.shareScroller.currentOffset().yOffset
      if (Math.abs(actualY - nextYVp) > offsetWarnVp) {
        this.shareScroller.scrollTo({ xOffset: 0, yOffset: nextYVp, animation: false })
        await noteEditDelayMs(80)
        actualY = this.shareScroller.currentOffset().yOffset
      }
      // scrollTo 可能被钳制，用小步 scrollBy 逼近目标，便于末尾 slogan 区域进入视口。
      let nudgeGuard = 0
      while (actualY < nextYVp - vpEps && nudgeGuard < 16) {
        const remainVp = nextYVp - actualY
        const stepNudge = Math.min(64, Math.max(1, remainVp))
        this.shareScroller.scrollBy(0, stepNudge)
        await noteEditDelayMs(45)
        const tryY = this.shareScroller.currentOffset().yOffset
        if (tryY <= actualY + 0.25) {
          break
        }
        actualY = tryY
        nudgeGuard++
      }
      let next: image.PixelMap | null = null
      try {
        next = await this.getShareSnapshotWithCandidates(waitOpts, `slice_target_${Math.round(nextYVp)}`)
      } catch (err) {
        Logger.error('NoteEdit',
          `snapshot get failed at targetYVp=${nextYVp} key=${this.shareCardCaptureKey} ` +
          `theme=${this.shareExportTheme} tone=${this.shareExportTone} compat=${this.shareExportSnapshotCompatMode}: ` +
          `${JSON.stringify(err)}`)
        break
      }
      if (!next) {
        Logger.warn('NoteEdit',
          `snapshot returned null at targetYVp=${nextYVp} key=${this.shareCardCaptureKey}`)
        break
      }
      slices.push(next)
      sliceScrollYVp.push(actualY)
      yVp = nextYVp
    }

    Logger.info('NoteEdit',
      `captureScrollingCardToImageCore slices=${slices.length} key=${this.shareCardCaptureKey} ` +
      `theme=${this.shareExportTheme} tone=${this.shareExportTone}`)

    const sliceSkipTopPx: number[] = []
    for (let i = 0; i < slices.length; i++) {
      if (i === 0) {
        sliceSkipTopPx.push(0)
      } else {
        const deltaVp = sliceScrollYVp[i] - sliceScrollYVp[i - 1]
        const deltaPx = Math.max(0, Math.round(ui.vp2px(deltaVp)))
        const skipTop = Math.max(0, viewportPx - deltaPx)
        sliceSkipTopPx.push(skipTop)
      }
    }
    if (slices.length === 1) {
      const trimmed = await this.trimShareSlice(slices[0])
      if (!trimmed) {
        return null
      }
      return await packSharePixelMapToPng(trimmed)
    }

    const normalized = await normalizeAllShareSlicesForMerge(slices)
    if (!normalized) {
      Logger.error('NoteEdit', 'shareLongImage: normalizeAllSlicesForMerge failed')
      return null
    }
    const merged =
      await mergeSharePixelMapsVertical(normalized, widthPx, mergeHeightPx, rowStepPx, sliceSkipTopPx)
    if (!merged) {
      Logger.error('NoteEdit', 'shareLongImage: mergePixelMapsVertical returned null')
      return null
    }
    return await packSharePixelMapToPng(merged)
  }

  private shareAvatarUrlTrim(): string {
    return (this.shareProfile?.avatar_url ?? '').trim()
  }

  /** 通过分享预览保存或分享长图。 */
  private async runShareNote(): Promise<void> {
    if (this.sharePreviewPreparing || this.sharePreviewRegenerating) {
      return
    }
    this.sharePreviewPreparing = true
    this.showPreviewMessage(EditorUiStrings.loc('正在生成长图…', 'Generating long image…', '長画像を生成中…'))
    try {
      this.shareAvatarNetworkFailed = false
      this.shareProfile = await NoteApiClient.getInstance().fetchProfile()
      if (this.shareAvatarUrlTrim().length > 0) {
        await ImageCacheService.getInstance().precache(this.shareAvatarUrlTrim())
      }
      await this.ensurePreferencesInitialized()
      const savedThemeRaw = await PreferencesService.getInstance().getShareCardTheme()
      const savedToneRaw = await PreferencesService.getInstance().getShareCardTone()
      const savedTheme = ShareThemeColors.parseTheme(savedThemeRaw)
      const savedTone = ShareThemeColors.parseTone(savedToneRaw)
      this.shareTheme = savedTheme
      this.shareTone = savedTone
      this.shareShowAppIcon = false
      const path = await this.exportShareImageToCache(savedTheme, savedTone)
      if (!path || path.length === 0) {
        this.showPreviewMessage(EditorUiStrings.loc('生成长图失败', 'Failed to generate long image', '長画像の生成に失敗しました'))
        return
      }
      this.sharePreviewPath = path
      this.sharePreviewImageHeightVp = await updateSharePreviewImageLayoutVp(path, this.pageWidth)
      this.sharePreviewVisible = true
      this.shareOptionsSheetVisible = true
      this.shareSheetRevision++
      Logger.info('NoteEdit',
        `runShareNote opened preview theme=${this.shareTheme} tone=${this.shareTone} revision=${this.shareSheetRevision}`)
    } finally {
      this.sharePreviewPreparing = false
    }
  }

  private async persistShareCardPreferences(
    theme: ShareCardTheme,
    tone: ShareCardTone
  ): Promise<void> {
    await this.ensurePreferencesInitialized()
    await PreferencesService.getInstance().setShareCardTheme(`${theme}`)
    await PreferencesService.getInstance().setShareCardTone(`${tone}`)
    Logger.info('NoteEdit', `persistShareCardPreferences theme=${theme} tone=${tone}`)
  }

  private async regenerateSharePreview(
    captureTheme?: ShareCardTheme,
    captureTone?: ShareCardTone
  ): Promise<void> {
    const theme = captureTheme ?? this.shareTheme
    const tone = captureTone ?? this.shareTone
    Logger.info('NoteEdit',
      `regenerateSharePreview start theme=${theme} tone=${tone} revision=${this.shareSheetRevision}`)
    this.shareTheme = theme
    this.shareTone = tone
    this.sharePreviewRegenerating = true
    const path = await this.exportShareImageToCache(theme, tone)
    this.sharePreviewRegenerating = false
    if (path && path.length > 0) {
      this.sharePreviewPath = path
      this.sharePreviewImageHeightVp = await updateSharePreviewImageLayoutVp(path, this.pageWidth)
      Logger.info('NoteEdit',
        `regenerateSharePreview done path=${path} theme=${theme} tone=${tone} revision=${this.shareSheetRevision}`)
    } else {
      Logger.warn('NoteEdit', 'regenerateSharePreview failed')
      this.showPreviewMessage(EditorUiStrings.loc('切换主题失败', 'Failed to switch theme', 'テーマの切り替えに失敗しました'))
    }
  }

  private closeSharePreview(): void {
    this.sharePreviewVisible = false
    this.shareOptionsSheetVisible = false
    this.sharePreviewPath = ''
    this.sharePreviewImageHeightVp = 0
  }

  private async onSharePreviewSave(): Promise<void> {
    if (this.sharePreviewPath.length === 0) {
      return
    }
    const context = this.obtainUiAbilityContext()
    if (context === undefined) {
      return
    }
    const ok = await saveShareCachePngToGallery(context, this.sharePreviewPath)
    this.showPreviewMessage(ok ? EditorUiStrings.loc('已保存到相册', 'Saved to album', 'アルバムに保存しました') : EditorUiStrings.loc('保存到相册失败', 'Failed to save to album', 'アルバムへの保存に失敗しました'))
    if (ok) {
      this.closeSharePreview()
    }
  }

  private async onSharePreviewShareOthers(): Promise<void> {
    if (this.sharePreviewPath.length === 0) {
      return
    }
    const context = this.obtainUiAbilityContext()
    if (context === undefined) {
      this.showPreviewMessage(EditorUiStrings.loc('分享失败', 'Share failed', '共有に失敗しました'))
      return
    }
    const cachePath = this.sharePreviewPath
    this.closeSharePreview()
    const ok = await sharePngFromCachePath(context, cachePath)
    if (!ok) {
      this.showPreviewMessage(EditorUiStrings.loc('分享失败', 'Share failed', '共有に失敗しました'))
    }
  }

  private sharePreviewSheetParams(): NoteSharePreviewSheetParams {
    return {
      onThemeChange: (theme: ShareCardTheme): void => {
        Logger.info('NoteEdit',
          `shareSheet button=theme label=${ShareThemeColors.label(theme)} ` +
          `from=${this.shareTheme} to=${theme} revision=${this.shareSheetRevision}`)
        if (this.shareTheme !== theme) {
          this.shareTheme = theme
          this.shareSheetRevision++
          void this.persistShareCardPreferences(theme, this.shareTone)
          void this.regenerateSharePreview(theme, this.shareTone)
        }
      },
      onToneChange: (tone: ShareCardTone): void => {
        Logger.info('NoteEdit',
          `shareSheet button=tone label=${ShareThemeColors.toneLabel(tone)} ` +
          `from=${this.shareTone} to=${tone} revision=${this.shareSheetRevision}`)
        if (this.shareTone !== tone) {
          this.shareTone = tone
          this.shareSheetRevision++
          void this.persistShareCardPreferences(this.shareTheme, tone)
          void this.regenerateSharePreview(this.shareTheme, tone)
        }
      },
      onFooterImageToggle: (): void => {
        this.shareShowAppIcon = !this.shareShowAppIcon
        Logger.info('NoteEdit',
          `shareSheet button=footerImage showAppIcon=${this.shareShowAppIcon}`)
        void this.regenerateSharePreview()
      },
      onSave: (): void => {
        Logger.info('NoteEdit', 'shareSheet button=action label=保存到相册')
        void this.onSharePreviewSave()
      },
      onShare: (): void => {
        Logger.info('NoteEdit', 'shareSheet button=action label=分享')
        void this.onSharePreviewShareOthers()
      },
      onCancel: (): void => {
        Logger.info('NoteEdit', 'shareSheet button=cancel label=取消')
        this.closeSharePreview()
      }
    }
  }

  @Builder
  private buildShareExportCard() {
    NoteShareExportCard({
      theme: this.shareExportTheme,
      tone: this.shareExportTone,
      snapshotCompatMode: this.shareExportSnapshotCompatMode,
      snapshotSkipQr: this.shareExportSnapshotSkipQr,
      showAppIcon: this.shareShowAppIcon,
      styleKey: `${this.shareCardCaptureKey}_${this.shareExportTheme}_${this.shareExportTone}`,
      title: this.title,
      content: this.content,
      previewBlocks: this.previewBlocksState,
      filesDirCache: this.filesDirCache,
      noteCreatedAt: this.noteCreatedAt,
      shareProfile: this.shareProfile,
      onLinkToast: (href: string): void => {
        this.showPreviewMessage(href)
      },
      onAreaHeight: (h: number): void => {
        const prev = this.shareExportColumnVp
        if (prev > 0 && Math.abs(prev - h) < 0.5) {
          return
        }
        this.shareExportColumnVp = h
        Logger.info('NoteEdit',
          `shareExportCard areaHeight=${h} key=${this.shareCardCaptureKey} ` +
          `theme=${this.shareExportTheme} tone=${this.shareExportTone}`)
      }
    })
      .key(`share_export_${this.shareExportMountKey()}`)
  }

  private syncAiWorkingFromBackgroundTask(): void {
    const svc = AiNoteBackgroundTaskService.getInstance()
    const busyHere = svc.isBusyForNote(this.noteId)
    if (busyHere || this.extractPollingActive) {
      this.aiNoteWorking = true
      this.aiWorkingOverlayMessage = busyHere
        ? svc.overlayMessage
        : EditorUiStrings.loc('AI 处理中…', 'AI working…', 'AI処理中…')
      return
    }
    if (this.aiNoteWorking) {
      this.aiNoteWorking = false
    }
  }

  private stopExtractPolling(): void {
    if (this.extractPollTimer !== -1) {
      clearInterval(this.extractPollTimer)
      this.extractPollTimer = -1
    }
    this.extractPollingActive = false
  }

  private async maybeStartExtractPolling(): Promise<void> {
    if (!this.lifecycle.isActive() || this.noteId.length === 0) {
      return
    }
    const note = await NoteRepository.getInstance().getNote(this.noteId)
    if (!this.lifecycle.isActive() || note === null || !isExtractStatusPending(note.extractStatus)) {
      this.stopExtractPolling()
      if (this.lifecycle.isActive() &&
        this.aiNoteWorking &&
        !AiNoteBackgroundTaskService.getInstance().isBusyForNote(this.noteId)) {
        this.aiNoteWorking = false
      }
      return
    }
    this.extractPollingActive = true
    if (!this.aiNoteWorking) {
      this.aiWorkingOverlayMessage = EditorUiStrings.loc('AI 处理中…', 'AI working…', 'AI処理中…')
      this.aiNoteWorking = true
    } else {
      this.aiWorkingOverlayMessage = EditorUiStrings.loc('AI 处理中…', 'AI working…', 'AI処理中…')
    }
    if (this.extractPollTimer === -1) {
      this.extractPollTimer = setInterval((): void => {
        void this.pollExtractOnce()
      }, 5000)
    }
    await this.pollExtractOnce()
  }

  private async pollExtractOnce(): Promise<void> {
    if (!this.lifecycle.isActive() || this.noteId.length === 0 || !this.extractPollingActive) {
      return
    }
    try {
      const updated = await NoteRepository.getInstance().refreshExtractJobForNote(this.noteId)
      if (!this.lifecycle.isActive() || updated === null) {
        return
      }
      if (isExtractStatusPending(updated.extractStatus)) {
        return
      }
      this.applyNoteContentFromExtractRefresh(updated)
      this.stopExtractPolling()
      this.aiNoteWorking = false
      if (updated.extractStatus === 'succeeded' || updated.extractStatus === 'partial') {
        this.maybeSwitchToPreviewAfterAiSuccess(true)
      } else if (updated.extractStatus === 'failed') {
        this.showPreviewMessage(EditorUiStrings.loc(
          'AI 提取链接失败，请稍后重试',
          'AI link extract failed; try again',
          'AIリンク抽出に失敗しました。後でもう一度お試しください'
        ))
      }
    } catch (_) {
      // ignore transient network errors; next poll will retry
    }
  }

  private applyNoteContentFromExtractRefresh(note: Note): void {
    if (!this.lifecycle.isActive() || note.id !== this.noteId) {
      return
    }
    if (note.title.trim().length > 0) {
      this.title = note.title
    }
    if (note.content.trim().length > 0) {
      this.content = note.content
      this.previousContent = note.content
      this.contentCaretIndex = note.content.length
    }
    this.saveStatus = '已保存'
    this.lastSavedAt = note.updatedAt
    this.handleContentChange()
  }

  private handleAiBackgroundTaskChanged(): void {
    if (!this.lifecycle.isActive()) {
      return
    }
    const svc = AiNoteBackgroundTaskService.getInstance()
    const result = svc.lastResult
    if (result !== null &&
      result.noteId === this.noteId &&
      result !== this.lastAppliedAiBgResult) {
      this.lastAppliedAiBgResult = result
      if (result.success) {
        this.applyAiBackgroundTaskResult(result)
        if (result.kind === 'extractLink') {
          void this.maybeStartExtractPolling()
        }
      }
    }
    this.syncAiWorkingFromBackgroundTask()
  }

  private applyAiBackgroundTaskResult(result: AiNoteBackgroundTaskResult): void {
    if (!this.lifecycle.isActive() || !result.success) {
      return
    }
    // 当 result.noteId 与 this.noteId 不一致时仍然尝试同步 title/content（占位提取任务结果），
    // 但 noteId 校验失败说明 listener 时机异常，仍在 onAiExtractLink 中做了磁盘重读兜底。
    if (result.noteId !== this.noteId && result.noteId.length > 0 && this.noteId.length > 0) {
      return
    }
    if (result.contentBefore !== undefined) {
      this.captureAiUndoBaseline(result.contentBefore)
    }
    if (result.title !== undefined && result.title !== this.title) {
      this.title = result.title
    }
    if (result.content !== undefined && result.content !== this.content) {
      this.content = result.content
      this.previousContent = result.content
      this.contentCaretIndex = result.content.length
    }
    if (result.audioId !== undefined && result.audioId.trim().length > 0) {
      this.audioId = result.audioId
    }
    this.saveStatus = '已保存'
    this.lastSavedAt = Date.now()
    this.handleContentChange()
    this.maybeSwitchToPreviewAfterAiSuccess(result.switchToPreviewOnSuccess)
  }

  private async onAiOptimizeContent(
    switchToPreviewOnSuccess: boolean = false,
    bookExtract: boolean = false
  ): Promise<void> {
    const svc = AiNoteBackgroundTaskService.getInstance()
    if (this.aiNoteWorking || svc.isBusy) {
      svc.ensureIdleOrNotifyBusy()
      return
    }
    if (!(await ensureAiMembershipAccess(this.getUIContext()))) {
      return
    }
    const trimmed = this.content.trim()
    const hasImageRefs = NoteStateCodec.extractImageRefs(this.content).length > 0
    const noteHasText = NoteStateCodec.hasSubstantiveNoteText(this.content)
    if (!noteHasText && !hasImageRefs) {
      this.showPreviewMessage(EditorUiStrings.loc('笔记正文为空，无法优化', 'Note is empty; cannot optimize', '本文が空のため最適化できません'))
      return
    }
    if (noteHasText && !hasImageRefs && Array.from(trimmed).length < AiNotePrompt.OPTIMIZE_MIN_RUNES) {
      this.showPreviewMessage(EditorUiStrings.loc('内容过少，无需AI优化', 'Too little content to optimize', '内容が少なすぎるため最適化不要です'))
      return
    }
    await this.ensureNoteIdForAiTask()
    if (this.noteId.length === 0) {
      return
    }
    if (!svc.ensureIdleOrNotifyBusy()) {
      return
    }
    const optimizeMessage = bookExtract
      ? EditorUiStrings.loc('正在识别书中文字…', 'Extracting text from book…', '書籍の文字を認識中…')
      : EditorUiStrings.loc(
        !noteHasText && hasImageRefs ? 'AI 生成笔记中…' : 'AI 处理中…',
        !noteHasText && hasImageRefs ? 'AI writing note…' : 'AI working…',
        !noteHasText && hasImageRefs ? 'AIがノートを生成中…' : 'AI処理中…'
      )
    this.aiWorkingOverlayMessage = optimizeMessage
    this.aiNoteWorking = true
    const filesDir = this.filesDirCache.length > 0
      ? this.filesDirCache
      : (this.obtainUiAbilityContext()?.filesDir ?? '')
    const started = await svc.runOptimize(
      this.noteId,
      this.content,
      this.title,
      filesDir,
      optimizeMessage,
      switchToPreviewOnSuccess,
      bookExtract
    )
    if (!started && !svc.isBusy) {
      this.aiNoteWorking = false
    }
  }

  private async openAiLinkExtractPage(): Promise<void> {
    if (!(await ensureAiMembershipAccess(this.getUIContext()))) {
      return
    }
    const svc = AiNoteBackgroundTaskService.getInstance()
    if (!svc.ensureIdleOrNotifyBusy()) {
      return
    }
    if (!(await svc.ensureNoPendingExtractOrNotify())) {
      return
    }
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/LinkExtract',
        params: {
          noteId: this.noteId.length > 0 ? this.noteId : undefined
        }
      })
    } catch (error) {
      Logger.warn('NoteEdit', `openAiLinkExtractPage: ${JSON.stringify(error)}`)
    }
  }

  private async onAiExtractLink(
    url: string,
    switchToPreviewOnSuccess: boolean = false,
    summarize: number = 1
  ): Promise<void> {
    const svc = AiNoteBackgroundTaskService.getInstance()
    if (this.aiNoteWorking || svc.isBusy || url.trim().length === 0) {
      if (svc.isBusy) {
        svc.ensureIdleOrNotifyBusy()
      }
      return
    }
    await this.ensureNoteIdForAiTask()
    if (this.noteId.length === 0) {
      return
    }
    if (!svc.ensureIdleOrNotifyBusy()) {
      return
    }
    if (!(await svc.ensureNoPendingExtractOrNotify())) {
      return
    }
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer)
      this.saveTimer = -1
    }
    this.aiWorkingOverlayMessage = EditorUiStrings.loc('AI 提交中…', 'Submitting…', '送信中…')
    this.aiNoteWorking = true
    // 记录跑 AI 前的原始 title/content：若用户原本就有内容，必须保留，绝不能被占位文本覆盖。
    const originalTitle = this.title
    const originalContent = this.content
    const editorHadContentBeforeAi = originalTitle.trim().length > 0 || originalContent.trim().length > 0
    const started = await svc.runExtractLink(
      this.noteId,
      url.trim(),
      summarize,
      this.title,
      this.content,
      switchToPreviewOnSuccess
    )
    if (started && this.lifecycle.isActive()) {
      // 不依赖磁盘读取，直接用代码里已知的占位文本同步控制器。
      // 这样无论 listener 是否触发、磁盘读取是否返回正确值，编辑器都能立即展示占位卡片。
      if (!editorHadContentBeforeAi) {
        this.title = EditorUiStrings.loc('AI提取链接中', 'AI is extracting the link', 'AIリンク抽出中')
        this.content = EditorUiStrings.loc(
          '已提交链接摘要，提取完成后会自动更新笔记',
          'Submitted; the note will update when extraction finishes.',
          '送信しました。抽出が完了するとノートが自動的に更新されます。'
        )
        this.previousContent = this.content
        this.contentCaretIndex = this.content.length
        this.saveStatus = '已保存'
        this.lastSavedAt = Date.now()
      } else if (this.title === originalTitle && this.content === originalContent) {
        // 编辑器原本有内容但 listener 这次漏写控制器；disk 上保留了用户内容，无需覆盖。
      }
      await this.maybeStartExtractPolling()
    }
    if (!started && !svc.isBusy) {
      this.aiNoteWorking = false
    }
  }

  @Builder
  buildAiWorkingOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.35)')
      Column({ space: 16 }) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(Color.White)
        Text(EditorUiStrings.loc(
          '关闭页面可在后台继续执行',
          'You can leave this page; the task continues in the background',
          'ページを閉じてもバックグラウンドで続行されます'
        ))
          .fontSize(13)
          .fontColor('#D9FFFFFF')
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(10005)
  }

  /**
   * 供 NoteEditPreviewPane 的 @BuilderParam 使用。
   * 传入子组件时必须用箭头函数包装（`(): void => { this.noteEditPreviewTagBarSlot() }`），
   * 不可直接传 `this.noteEditPreviewTagBarSlot`，否则子组件调用时 this 丢失。
   */
  @Builder
  noteEditPreviewTagBarSlot() {
    this.buildMobileTagBarWidget(this.noteTagsSafe())
  }

  @Builder
  buildMobileTagBarWidget(noteTags: string[]) {
    Row({ space: 4 }) {
      Row() {
        Row({ space: 4 }) {
          Text('#')
            .fontSize(14)
            .fontColor($r('app.color.secondary_text'))
            .fontWeight(FontWeight.Medium)
          if (noteTags.length === 0) {
            Text(EditorUiStrings.loc('标签', 'Tags', 'タグ'))
              .fontSize(12)
              .fontColor($r('app.color.secondary_text'))
          } else {
            NoteEditTagChip({ tag: noteTags[0] })
            if (noteTags.length > 1) {
              Text('...')
                .fontSize(12)
                .fontColor($r('app.color.secondary_text'))
            }
          }
        }
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(14)
          .fontColor([$r('app.color.secondary_text')])
      }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor($r('app.color.surface_muted'))
      .borderRadius(18)
      .onClick(() => {
        void this.refreshTagPool()
        this.tagMenuVisible = !this.tagMenuVisible
      })
    }
    .shadow({
      radius: 8,
      color: '#20000000',
      offsetX: 0,
      offsetY: 2
    })
  }

  private toggleTagMenu(): void {
    if (this.aiTagCreating) {
      return
    }
    const opening = !this.tagMenuVisible
    this.tagMenuVisible = opening
    if (opening) {
      void this.refreshTagPool()
    }
  }

  private beginEditTitle(): void {
    this.titleEditing = true
    // defaultFocus 仅在组件首次创建时生效；动态切换编辑态需主动 requestFocus。
    setTimeout((): void => {
      if (!this.titleEditing || !this.lifecycle.isActive()) {
        return
      }
      try {
        this.getUIContext().getFocusController().requestFocus('note_edit_title_input')
      } catch (error) {
        Logger.warn('NoteEdit', `requestFocus title failed: ${JSON.stringify(error)}`)
      }
    }, 32)
  }

  private dismissTitleEditing(): void {
    if (this.titleEditing) {
      this.titleEditing = false
      this.onTitleFieldBlur()
    }
  }

  /**
   * 视口 − Tab − 快捷栏：固定 Swiper 高，标题滚走后 Tab（及快捷栏）吸顶。
   */
  private swiperContentHeight(): number {
    const tabH = this.tabBarH > 0 ? this.tabBarH : 48
    const quickH = (this.shouldShowQuickActionBar() && this.contentTabIndex === 0)
      ? 40
      : 0
    const h = this.scrollViewportH - tabH - quickH
    return h > 120 ? h : 280
  }

  private onOuterScroll(): void {
    const y = this.outerScroller.currentOffset().yOffset
    this.lastOuterOffsetY = y
    this.updateToolbarTitleOpacity(y)
  }

  /** sticky 顶 padding 15 之后标题开始滑出；按标题高度线性映射透明度（与 VoiceNoteDetail 一致）。 */
  private updateToolbarTitleOpacity(scrollY: number): void {
    const fadeStart = 15
    const h = Math.max(1, this.titleBlockH)
    let opacity = (scrollY - fadeStart) / h
    if (opacity < 0) {
      opacity = 0
    } else if (opacity > 1) {
      opacity = 1
    }
    if (Math.abs(opacity - this.toolbarTitleOpacity) < 0.01) {
      return
    }
    this.toolbarTitleOpacity = opacity
  }

  /** 窄屏顶栏：返回、居中淡入标题、标签按钮、更多菜单（对齐 VoiceNoteDetail.buildHeader）。 */
  @Builder
  private buildMobileHeader() {
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
      .onClick((): void => {
        this.dismissTitleEditing()
        this.handleBack()
      })

      Row() {
        Text(this.title.trim().length > 0 ? this.title : $r('app.string.editor_title_placeholder'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width('100%')
          .opacity(this.toolbarTitleOpacity)
      }
      .layoutWeight(1)
      .height('100%')
      .padding({ left: 8, right: 8 })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Row() {
        if (this.aiTagCreating) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color($r('app.color.accent'))
        } else {
          SymbolGlyph($r('sys.symbol.label'))
            .fontSize(18)
            .fontColor([$r('app.color.primary_text')])
        }
      }
      .height('100%')
      .padding({
        left: $r('app.float.toolbar_icon_button_padding_h'),
        right: $r('app.float.toolbar_icon_button_padding_h')
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .enabled(!this.aiTagCreating)
      .onClick((): void => {
        this.dismissTitleEditing()
        this.toggleTagMenu()
      })
      .onAreaChange((_oldArea: Area, area: Area): void => {
        this.tagBarWidth = Number.parseFloat(`${area.width}`) || 36
        this.tagBarHeight = Number.parseFloat(`${area.height}`) || 36
        // position 相对父布局；外层窄屏内容左右 padding 6，叠加得到页内坐标。
        const localX = Number.parseFloat(`${area.position.x}`) || 0
        const localY = Number.parseFloat(`${area.position.y}`) || 0
        this.tagBarX = 6 + localX
        this.tagBarY = localY
      })

      Row() {
        SymbolGlyph($r('sys.symbol.more'))
          .fontSize(18)
          .fontColor([$r('app.color.primary_text')])
          .bindMenu(this.buildToolbarMoreMenuItems())
      }
      .height('100%')
      .padding({
        left: $r('app.float.toolbar_icon_button_padding_h'),
        right: $r('app.float.toolbar_icon_button_padding_h')
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        this.dismissTitleEditing()
      })
    }
    .width('100%')
    .height($r('app.float.toolbar_height'))
    .alignItems(VerticalAlign.Center)
    .padding({ left: 6, right: 6 })
  }

  /** 窄屏大标题：点击进入编辑（对齐 VoiceNoteDetail.buildTitleBlock）。 */
  @Builder
  private buildMobileTitleBlock() {
    Column() {
      if (this.titleEditing) {
        TextInput({ text: this.title, placeholder: $r('app.string.editor_title_placeholder') })
          .id('note_edit_title_input')
          .width('100%')
          .height(48)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .backgroundColor($r('app.color.surface_muted'))
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .border({ width: 1.5, color: $r('app.color.accent') })
          .borderRadius(8)
          .showUnderline(false)
          .caretColor($r('app.color.accent'))
          .clip(false)
          .defaultFocus(true)
          .enableKeyboardOnFocus(true)
          .focusable(true)
          .onChange((value: string): void => {
            this.title = value
            this.scheduleSave()
          })
          .onFocus((): void => {
            this.onTitleFieldFocus()
          })
          .onBlur((): void => {
            this.titleEditing = false
            this.onTitleFieldBlur()
          })
          .onSubmit((): void => {
            this.titleEditing = false
          })
      } else {
        Text(this.title.trim().length > 0 ? this.title : $r('app.string.editor_title_placeholder'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.title.trim().length > 0 ? $r('app.color.primary_text') : $r('app.color.tertiary_text'))
          .width('100%')
          .lineHeight(30)
          .onClick((): void => {
            this.beginEditTitle()
          })
      }
    }
    .width('100%')
    .onAreaChange((_oldArea: Area, area: Area): void => {
      const h = Number.parseFloat(`${area.height}`) || 48
      this.titleBlockH = h
      // 顶栏 40 + sticky padding 15 + 标题高度；不盖住标题本身。
      this.titleDismissTop = 40 + 15 + h
      this.updateToolbarTitleOpacity(this.lastOuterOffsetY)
    })
  }

  /** 窄屏标签 Chip。 */
  @Builder
  private buildMobileTagChips() {
    if (this.noteTagsSafe().length === 0) {
      Blank()
    } else {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
        ForEach(this.noteTagsSafe(), (tag: string) => {
          NoteEditTagChip({ tag: tag })
            .margin({ right: 8, bottom: 6 })
        }, (tag: string) => `note_edit_tag_${tag}`)
      }
    }
  }

  /**
   * 标签左、路径右（同行）。
   * 标签在左侧可换行；路径右侧贴边，过长时在 maxWidth 内跑马灯。
   * 不再用本征宽度测量锁宽，避免路径宽被算成 0 而消失。
   */
  @Builder
  private buildMobileTagsAndPath() {
    if (this.noteTagsSafe().length === 0 && this.sidebarFilterMode !== 'folder') {
      Blank()
    } else if (this.sidebarFilterMode !== 'folder') {
      Column() {
        this.buildMobileTagChips()
      }
      .width('100%')
      .margin({ top: 8 })
      .alignItems(HorizontalAlign.Start)
    } else if (this.noteTagsSafe().length === 0) {
      Row() {
        this.buildParentPathCaption()
      }
      .width('100%')
      .margin({ top: 8 })
      .justifyContent(FlexAlign.Start)
    } else {
      Row({ space: 12 }) {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
          ForEach(this.noteTagsSafe(), (tag: string) => {
            NoteEditTagChip({ tag: tag })
              .margin({ right: 8, bottom: 6 })
          }, (tag: string) => `note_edit_tag_row_${tag}`)
        }
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })

        Column() {
          this.buildParentPathCaption()
        }
        .flexShrink(0)
        .constraintSize({ maxWidth: '58%' })
      }
      .width('100%')
      .margin({ top: 8 })
      .alignItems(VerticalAlign.Top)
    }
  }

  /** 吸顶头部：大标题 + 标签/路径。 */
  @Builder
  private buildStickyHeaderBlock() {
    Column() {
      this.buildMobileTitleBlock()
      this.buildMobileTagsAndPath()
    }
    .width('100%')
    .padding({ top: 15 })
    .alignItems(HorizontalAlign.Start)
    .onAreaChange((_: Area, area: Area) => {
      const h = Number.parseFloat(`${area.height}`) || 0
      if (h > 0 && Math.abs(h - this.stickyHeaderH) >= 1) {
        this.stickyHeaderH = h
      }
    })
  }

  /** 编辑/预览 Tab（吸顶效果由 Swiper 固定高 = viewport - tabBar 实现，同 VoiceNoteDetail）。 */
  @Builder
  private buildMobileTabBar() {
    Row() {
      Column() {
        Text(EditorUiStrings.loc('编辑', 'Edit', '編集'))
          .fontSize(15)
          .fontWeight(this.contentTabIndex === 0 ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.contentTabIndex === 0 ? $r('app.color.accent') : $r('app.color.secondary_text'))
        Divider()
          .strokeWidth(this.contentTabIndex === 0 ? 2 : 0)
          .color($r('app.color.accent'))
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => {
        this.switchMode('edit')
      })

      Column() {
        Text(EditorUiStrings.loc('预览', 'Preview', 'プレビュー'))
          .fontSize(15)
          .fontWeight(this.contentTabIndex === 1 ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.contentTabIndex === 1 ? $r('app.color.accent') : $r('app.color.secondary_text'))
        Divider()
          .strokeWidth(this.contentTabIndex === 1 ? 2 : 0)
          .color($r('app.color.accent'))
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => {
        this.switchMode('preview')
      })
    }
    .width('100%')
    .padding({ top: 4 })
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_: Area, area: Area) => {
      const h = Number.parseFloat(`${area.height}`) || 0
      if (h > 0 && Math.abs(h - this.tabBarH) >= 1) {
        this.tabBarH = h
      }
    })
  }

  @Builder
  private buildMobileEditPage() {
    // 固定视口内滚正文；RichEditor 估高+拒竖滑；外层滚标题后 Tab/快捷栏吸顶（同预览 nestedScroll）。
    Scroll() {
      Column() {
        NoteEditEditorPane({
          title: $title,
          content: $content,
          enterEditToken: this.editorEnterEditToken,
          refreshToken: this.editorRefreshToken,
          toolbarSignal: this.editorToolbarSignal,
          colorModeToken: this.editorColorModeToken,
          filesDir: this.filesDirCache,
          textAreaController: this.textAreaController,
          includeTitle: false,
          flatChrome: true,
          minContentHeight: this.swiperContentHeight(),
          onTitleFocus: (): void => {
            this.onTitleFieldFocus()
          },
          onTitleBlur: (): void => {
            this.onTitleFieldBlur()
          },
          onTitleChange: (): void => {
            this.scheduleSave()
          },
          onContentSelectionChange: (selectionStart: number, selectionEnd: number): void => {
            this.rememberContentCaret(selectionStart, selectionEnd)
          },
          onContentChange: (): void => {
            this.handleContentChange()
          }
        })
          .width('100%')
        Column()
          .width('100%')
          .height(48)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.TopStart)
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST
    })
  }

  @Builder
  private buildMobilePreviewPage() {
    NoteEditPreviewPane({
      title: this.title,
      splitMode: false,
      includeTitle: false,
      flatChrome: true,
      showSplitTagRow: false,
      previewBlocks: this.previewBlocksState,
      filesDirCache: this.filesDirCache,
      imageRefreshKey: this.previewImageRefreshKey,
      onBackgroundTap: (): void => {
        if (this.tagMenuVisible) {
          this.tagMenuVisible = false
        }
      },
      onLinkToast: (href: string): void => {
        this.openPreviewLink(href)
      },
      onCheckboxToggle: (lineIndex: number, checked: boolean): void => {
        this.onPreviewCheckboxToggle(lineIndex, checked)
      },
      onImageTap: (src: string): void => {
        this.openNoteImageGallery(src)
      }
    })
  }

  @Builder
  private buildMobileTabbedContent() {
    Column() {
      this.buildMobileTabBar()
      if (this.shouldShowQuickActionBar() && this.contentTabIndex === 0) {
        EditorQuickActionBar({
          barWidthVp: this.pageWidth,
          onBeforeAction: (): void => {
            this.captureContentCaretFromSelection()
          },
          onAction: (action: EditorQuickActionType): void => {
            this.handleQuickAction(action)
          },
          onMermaidKindSelected: (kind: string): void => {
            this.insertMermaidTemplate(kind)
          }
        })
      }
      Swiper(this.swiperController) {
        this.buildMobileEditPage()
        this.buildMobilePreviewPage()
      }
      .index(this.contentTabIndex)
      .indicator(false)
      .loop(false)
      .width('100%')
      .height(this.swiperContentHeight())
      .onChange((index: number): void => {
        this.switchMode(index === 1 ? 'preview' : 'edit')
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 窄屏正文：外层 Scroll 滚完吸顶头后 Tab（及快捷栏）吸顶；Swiper 高 = viewport - tab - quick。 */
  @Builder
  private buildMobileBody() {
    Scroll(this.outerScroller) {
      Column() {
        this.buildStickyHeaderBlock()
        this.buildMobileTabbedContent()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    }
    .align(Alignment.TopStart)
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .onAreaChange((_: Area, area: Area) => {
      const h = Number.parseFloat(`${area.height}`) || 0
      if (h > 0 && Math.abs(h - this.scrollViewportH) >= 1) {
        this.scrollViewportH = h
      }
    })
    .onDidScroll((_scrollOffset: number, _scrollState: ScrollState): void => {
      this.onOuterScroll()
    })
    .onScrollStop((): void => {
      this.onOuterScroll()
    })
  }

  @Builder
  private buildTitleDismissOverlay() {
    // 仅覆盖标题以下区域，标题内可点击移动光标（同 VoiceNoteDetail）。
    if (this.titleEditing && !this.tagMenuVisible) {
      Column()
        .width('100%')
        .height(Math.max(0, this.pageHeight - Math.max(40, this.titleDismissTop)))
        .backgroundColor('#00000000')
        .position({ x: 0, y: Math.max(40, this.titleDismissTop) })
        .onClick((): void => {
          this.dismissTitleEditing()
        })
        .zIndex(50)
    }
  }

  @Builder
  private buildTagMenuOverlay() {
    if (this.tagMenuVisible && !this.isSplitMode()) {
      // 全屏透明层：点击弹窗外先关闭菜单。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .onClick((): void => {
          this.tagMenuVisible = false
        })
        .zIndex(998)

      Column() {
        NoteEditTagDropdown({
          tagPool: this.tagPool,
          noteTags: this.noteTagsSafe(),
          aiTagCreating: this.aiTagCreating,
          onTagChecked: (tag: string, selected: boolean) => {
            void this.onTagChecked(tag, selected)
          },
          onAiCreateTag: () => {
            void this.onAiCreateTag()
          },
          onOpenTagManage: () => {
            this.tagMenuVisible = false
            void this.openTagManage()
          }
        })
      }
      .position({ x: this.floatMenuPosX(), y: this.tagMenuPosY() })
      .zIndex(999)
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 0 }) {
        if (this.isSplitMode()) {
          Row() {
            Row() {
              SymbolGlyph($r('sys.symbol.arrow_left'))
                .fontSize(22)
                .fontColor([$r('app.color.primary_text')])
            }
            .height('100%')
            .constraintSize({ minWidth: 48 })
            .padding({
              top: 8,
              bottom: 8,
              left: 14,
              right: 14
            })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.pill_radius'))
            .onClick(() => {
              this.handleBack()
            })

            Column({ space: 4 }) {
              Text(EditorUiStrings.saveStatus(this.saveStatus))
                .fontSize($r('app.float.caption_font_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor(
                  this.saveStatus === '已保存' ? $r('app.color.success') :
                    (this.saveStatus === '保存失败' ? $r('app.color.danger') : $r('app.color.secondary_text'))
                )
                .textAlign(TextAlign.Start)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              if (this.lastSavedAt > 0) {
                Text(TimeUtils.format(this.lastSavedAt))
                  .fontSize(12)
                  .fontColor($r('app.color.tertiary_text'))
                  .textAlign(TextAlign.Start)
                  .width('100%')
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 8, right: 8 })

            if (!this.quickActionBarEnabled) {
              Row() {
                Text(EditorUiStrings.loc('图', 'Image', '画像'))
                  .fontSize(16)
                  .fontColor(Color.White)
                  .width(30)
                  .height(30)
                  .textAlign(TextAlign.Center)
                  .margin({ right: 5 })
                  .onClick(() => {
                    void this.insertImage()
                  })
              }
            }
          }
          .width('100%')
          .height($r('app.float.edit_note_toolbar_height'))
          .alignItems(VerticalAlign.Center)
          .padding({ left: 24, right: 24 })
        } else {
          this.buildMobileHeader()
        }

        Column({ space: $r('app.float.toolbar_spacing_content') }) {
        if (this.isSplitMode()) {
          Row({ space: 14 }) {
            NoteEditEditorPane({
              title: $title,
              content: $content,
              enterEditToken: this.editorEnterEditToken,
              refreshToken: this.editorRefreshToken,
              toolbarSignal: this.editorToolbarSignal,
              colorModeToken: this.editorColorModeToken,
              filesDir: this.filesDirCache,
              textAreaController: this.textAreaController,
              onTitleFocus: (): void => {
                this.onTitleFieldFocus()
              },
              onTitleBlur: (): void => {
                this.onTitleFieldBlur()
              },
              onTitleChange: (): void => {
                this.scheduleSave()
              },
              onContentSelectionChange: (selectionStart: number, selectionEnd: number): void => {
                this.rememberContentCaret(selectionStart, selectionEnd)
              },
              onContentChange: (): void => {
                this.handleContentChange()
              }
            })
            NoteEditPreviewPane({
              title: this.title,
              splitMode: this.isSplitMode(),
              showSplitTagRow: hasEditorTitleOrBody(this.title, this.content),
              previewBlocks: this.previewBlocksState,
              filesDirCache: this.filesDirCache,
              imageRefreshKey: this.previewImageRefreshKey,
              onBackgroundTap: (): void => {
                if (this.tagMenuVisible) {
                  this.tagMenuVisible = false
                }
              },
              onLinkToast: (href: string): void => {
                this.openPreviewLink(href)
              },
              onCheckboxToggle: (lineIndex: number, checked: boolean): void => {
                this.onPreviewCheckboxToggle(lineIndex, checked)
              },
              onImageTap: (src: string): void => {
                this.openNoteImageGallery(src)
              },
              tagBarSlot: (): void => {
                this.noteEditPreviewTagBarSlot()
              }
            })
          }
          .layoutWeight(1)
          .width('100%')
        } else {
          this.buildMobileBody()
        }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({
          left: this.pageWidth >= 600 ? 24 : 6,
          right: this.pageWidth >= 600 ? 24 : 6
        })

        if (this.audioId.trim().length > 0 && this.noteId.trim().length > 0) {
          NoteAudioPlayerBar({
            audioId: this.audioId,
            noteId: this.noteId
          })
            .width('100%')
            .padding({
              left: this.pageWidth >= 600 ? 24 : 6,
              right: this.pageWidth >= 600 ? 24 : 6
            })
        }
      }
      .width('100%')
      .height('100%')
      .padding({
        top: $r('app.float.toolbar_editor_page_padding_top')
      })
      .backgroundColor($r('app.color.app_background'))

      if (this.folderMovePopupVisible && this.folderModeEnabled) {
        Stack({ alignContent: Alignment.TopStart }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.3)')
            .onClick(() => {
              this.folderMovePopupVisible = false
            })
          Column() {
            NoteEditFolderMovePanel({
              noteId: this.noteId,
              parentId: this.parentId,
              allNotes: this.allNotes,
              entries: this.getMovePickerEntries(),
              expandedFolderIds: this.expandedFolderIds,
              onSelectFolder: (folderId: string) => {
                void this.onSelectMoveFolder(folderId)
              },
              onToggleExpand: (folderId: string) => {
                this.onToggleFolderExpand(folderId)
              }
            })
          }
          .width('100%')
          .padding({
            left: this.pageWidth >= 600 ? 24 : 6,
            right: this.pageWidth >= 600 ? 24 : 6,
            top: 35
          })
        }
        .width('100%')
        .height('100%')
        .zIndex(1000)
      }

      if (!this.isSplitMode()) {
        this.buildTitleDismissOverlay()
        this.buildTagMenuOverlay()
      }

      if (this.aiNoteWorking) {
        this.buildAiWorkingOverlay()
      }

      NoteEditShareExportMount({
        active: this.shareExportActive,
        scrollBg: this.shareExportScrollBg,
        mountKey: this.shareExportMountKey(),
        shareScroller: this.shareScroller,
        onCardHeightChange: (height: number): void => {
          this.shareCardHeight = height
        },
        exportCard: (): void => {
          this.buildShareExportCard()
        }
      })

      NoteEditSharePreviewOverlay({
        preparing: this.sharePreviewPreparing,
        visible: this.sharePreviewVisible,
        regenerating: this.sharePreviewRegenerating,
        previewPath: this.sharePreviewPath,
        previewImageHeightVp: this.sharePreviewImageHeightVp,
        pageWidth: this.pageWidth,
        optionsSheetVisible: this.shareOptionsSheetVisible,
        shareTheme: this.shareTheme,
        shareTone: this.shareTone,
        shareShowAppIcon: this.shareShowAppIcon,
        sheetRevision: this.shareSheetRevision,
        sheetParams: this.sharePreviewSheetParams(),
        onPreviewImageComplete: (width: number, height: number): void => {
          const previewW = Math.max(1, this.pageWidth)
          this.sharePreviewImageHeightVp = (height / width) * previewW
          Logger.info('NoteEdit',
            `share preview onComplete ${width}x${height} heightVp=${this.sharePreviewImageHeightVp}`)
        }
      })
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      if (this.sharePreviewVisible || this.sharePreviewRegenerating || this.sharePreviewPreparing) {
        return
      }
      if (this.tagMenuVisible) {
        this.tagMenuVisible = false
      }
      this.dismissTitleEditing()
    })
    .onAreaChange((_, value) => {
      const nextWidth = Number.parseFloat(`${value.width}`) || 360
      const nextHeight = Number.parseFloat(`${value.height}`) || 780
      const wasSplitMode = this.isSplitMode()
      if (Math.abs(this.pageWidth - nextWidth) >= 1) {
        this.pageWidth = nextWidth
      }
      if (Math.abs(this.pageHeight - nextHeight) >= 1) {
        this.pageHeight = nextHeight
      }
      const nextSplitMode = this.isSplitMode()
      const nextPreviewMode = nextSplitMode ? 'split' : (this.previewMode === 'preview' ? 'preview' : 'edit')
      if (this.previewMode !== nextPreviewMode) {
        this.previewMode = nextPreviewMode
      }
      this.syncContentTabIndexFromPreviewMode()
      if ((!wasSplitMode && nextSplitMode) || this.shouldRenderPreview()) {
        this.preparePreviewForCurrentMode(this.content, true)
      }
    })
  }
}
