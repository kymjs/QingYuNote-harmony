import { ComponentContent, window } from '@kit.ArkUI'
import type { MarkdownBlock } from '../common/utils/MarkdownUtils'
import { MarkdownUtils, shouldPersistTodoNote } from '../common/utils/MarkdownUtils'
import {
  EditorMarkdownInsert,
  type EditorInsertResult,
  type EditorTextDiff
} from '../common/utils/EditorMarkdownInsert'
import { CachedNetworkImage } from '../components/CachedNetworkImage'
import { EditorQuickActionBar, type EditorQuickActionType } from '../components/EditorQuickActionBar'
import { ImageCacheService } from '../services/ImageCacheService'
import {
  buildEditorLinkInsertDialogContent,
  type EditorLinkInsertDialogParams
} from '../dialogs/EditorLinkInsertDialog'
import {
  buildEditorAiLinkExtractDialogContent,
  type EditorAiLinkExtractDialogParams
} from '../dialogs/EditorAiLinkExtractDialog'
import type { Note } from '../common/model/Note'
import { NoteRepository } from '../services/NoteRepository'
import { PreferencesService } from '../services/PreferencesService'
import { AppContextHolder } from '../services/AppContextHolder'
import { NoteImagesChangedEventPayload, SyncConstants } from '../common/constants/SyncConstants'
import { FileService } from '../services/FileService'
import { TimeUtils } from '../common/utils/TimeUtils'
import { Logger } from '../common/utils/Logger'
import componentSnapshot from '@ohos.arkui.componentSnapshot'
import { image } from '@kit.ImageKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { NoteEditEditorPane } from './NoteEditEditorPane'
import { NoteEditPreviewPane } from './NoteEditPreviewPane'
import { NoteEditMarkdownBlocksView } from './NoteEditMarkdownBlocksView'
import { NoteApiClient, type ProfileBody } from '../services/NoteApiClient'
import { AiTagService } from '../services/AiTagService'
import { AiNoteService } from '../services/AiNoteService'
import { AiNotePrompt } from '../services/AiNotePrompt'
import { UserFacingMessage } from '../common/utils/UserFacingMessage'
import { RemoteAppConfigService } from '../services/RemoteAppConfigService'
import { PageLifecycle } from '../common/utils/PageLifecycle'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'
import { NoteImageGalleryUtils } from '../common/utils/NoteImageGalleryUtils'
import { NoteStateCodec } from '../common/utils/NoteStateCodec'
import { NoteFolderTree, type FolderSidebarRow, type MovePickerEntry } from '../common/utils/NoteFolderTree'
import { type NoteEditorEntryAction } from '../common/model/NoteEditorEntryAction'
import { maybeShowMembershipExpiryReminderDialog } from '../common/utils/MembershipExpiryReminderNavigation'
import { ShareCardTheme, ShareCardTone, ShareThemeColors } from '../share/ShareTheme'
import {
  NoteShareExportCard,
  NOTE_SHARE_EXPORT_SNAPSHOT_ID,
  buildJinshuLightSegmentCaptureIds
} from '../share/NoteShareExportCard'
import { NoteSharePreviewSheet } from '../share/NoteSharePreviewSheet'
import { systemShare } from '@kit.ShareKit'
import { uniformTypeDescriptor as utd } from '@kit.ArkData'

interface NoteEditParams {
  noteId?: string
  /** 从首页点入且正文非空时置为 true，与 Flutter `openWithPreview` 对齐。 */
  openWithPreview?: boolean
  /** 从首页「更多方式」进入时，加载完成后自动触发的动作。 */
  initialAction?: NoteEditorEntryAction
}

interface TitleSaveResolution {
  title: string
  skipTitleAutoFill: boolean
}

/** 仅当标题和正文至少有一个非空时为 true（与 Flutter `_hasEditorTitleOrBody` 对齐）。 */
function hasEditorTitleOrBody(title: string, content: string): boolean {
  return title.trim().length > 0 || content.trim().length > 0
}

@Entry
@Component
struct NoteEdit {
  @State noteId: string = ''
  @State title: string = ''
  @State content: string = ''
  @State saveStatus: string = '未保存'
  @State previewMode: string = 'split'
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
  @State aiMenuVisible: boolean = false
  @State aiNoteWorking: boolean = false
  @State aiWorkingOverlayMessage: string = 'AI 处理中…'
  @State aiUndoAvailable: boolean = false
  private aiUndoBaselineContent: string | null = null
  @State parentId: string = ''
  @State allNotes: Note[] = []
  @State expandedFolderIds: string[] = []
  @State folderMovePopupVisible: boolean = false
  @State tagBarX: number = 0
  @State tagBarY: number = 0
  @State tagBarInitialized: boolean = false
  @State tagBarWidth: number = 120
  @State tagBarHeight: number = 32
  @State lastPanOffsetX: number = 0
  @State lastPanOffsetY: number = 0
  /** 标题输入框是否处于焦点（编辑）状态。 */
  @State titleFieldFocused: boolean = false
  /** 笔记设置：是否展示输入法上方快捷操作栏。 */
  @State quickActionBarEnabled: boolean = true
  @State folderModeEnabled: boolean = false
  /** 软键盘占用高度（vp），用于快捷栏贴键盘定位。 */
  @State keyboardHeightVp: number = 0
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
    this.keyboardHeightVp = heightPx > 0 ? this.getUIContext().px2vp(heightPx) : 0
  }
  private shareScroller: Scroller = new Scroller()
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
  /** 打开页面时待办笔记是否已有实质内容（避免清空后误删历史笔记）。 */
  private initialHadTodoContent: boolean = false
  private shareCardHeight: number = 0
  /** 缓存 ability `filesDir`，避免预览中多张图片重复解析上下文。 */
  private filesDirCache: string = ''
  private lifecycle = new PageLifecycle()
  private closeGuard = new PageCloseGuard()
  private static readonly SHARE_CARD_ID: string = NOTE_SHARE_EXPORT_SNAPSHOT_ID
  private static readonly SHARE_SCROLL_ID: string = 'note_share_export_scroll_capture'
  /** 超过此高度（vp）时整卡 snapshot 易触发 100001，改优先截 Scroll 视口再分段拼接。 */
  private static readonly SHARE_SNAPSHOT_MAX_FULL_CARD_VP: number = 2400
  private static readonly SHARE_AVATAR_SIZE: number = 48

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
    void this.onNoteEditPageShow()
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
    }
  }

  aboutToAppear(): void {
    this.lifecycle.appear()
    this.closeGuard.reset()
    const ctx = this.obtainUiAbilityContext()
    if (ctx !== undefined) {
      this.filesDirCache = ctx.filesDir
    }
    const params = this.getUIContext().getRouter().getParams() as NoteEditParams
    this.noteId = params?.noteId ?? ''
    this.preferPreviewOnOpen = params?.openWithPreview === true
    this.pendingInitialAction = params?.initialAction ?? null
    this.initialActionHandled = false
    void this.loadNote()
    void this.refreshAllNotes()
    void this.loadQuickActionBarPref()
    void this.loadFolderModePref()
    void this.loadAiFeatureConfig()
    void this.initKeyboardAvoidArea()
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
    if (nextNoteId === this.noteId &&
      nextPreview === this.preferPreviewOnOpen &&
      nextAction === this.pendingInitialAction) {
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
    void this.loadNote()
    void this.refreshAllNotes()
  }

  aboutToDisappear(): void {
    this.lifecycle.disappear()
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

  private async loadAiFeatureConfig(): Promise<void> {
    const filesDir = this.filesDirCache.length > 0
      ? this.filesDirCache
      : (this.obtainUiAbilityContext()?.filesDir ?? '')
    const enabled = await RemoteAppConfigService.readAiConfigFromCache(filesDir)
    if (this.lifecycle.isActive()) {
      this.aiFeatureEnabled = enabled
    }
  }

  private shouldShowMobileAiBar(): boolean {
    return !this.isSplitMode() &&
      this.previewMode === 'edit' &&
      this.aiFeatureEnabled &&
      hasEditorTitleOrBody(this.title, this.content)
  }

  private static readonly FLOAT_MENU_WIDTH: number = 154
  private static readonly FLOAT_MENU_GAP: number = 8
  private static readonly AI_MENU_HEIGHT: number = 96
  private static readonly TAG_MENU_ITEM_HEIGHT: number = 44
  private static readonly TAG_MENU_MAX_VISIBLE_ITEMS: number = 5

  /** 悬浮按钮在屏幕上半部时菜单向下展开，否则向上展开。 */
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

  private aiMenuPosY(): number {
    let menuHeight = NoteEdit.AI_MENU_HEIGHT
    if (this.aiUndoAvailable) {
      menuHeight += 44
    }
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
    this.aiMenuVisible = false
    this.handleContentChange()
    this.showPreviewMessage('已撤回 AI 修改')
  }

  private saveStatusBarClickable(): boolean {
    return this.folderModeEnabled && this.mobileFullPreviewChrome()
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

  /** 在快捷栏 TouchDown 或插入前抓取选区（失焦后 getCaretOffset 不可靠）。 */
  private captureContentCaretFromSelection(): void {
    try {
      const range = this.textAreaController.getSelection()
      const start = range.start !== undefined && range.start >= 0 ? range.start : 0
      const end = range.end !== undefined && range.end >= 0 ? range.end : start
      this.rememberContentCaret(start, end)
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

  private applyContentInsertViaController(diff: EditorTextDiff): boolean {
    if (diff.end > diff.start) {
      this.textAreaController.deleteText({ start: diff.start, end: diff.end })
    }
    if (diff.insert.length > 0) {
      this.textAreaController.addText(diff.insert, { offset: diff.start })
    }
    return true
  }

  private applyContentInsert(result: EditorInsertResult): void {
    const oldText = this.content
    const newText = result.text
    const caret = Math.max(0, Math.min(result.caret, newText.length))
    if (oldText === newText) {
      this.scheduleApplyCaret(caret, newText.length)
      return
    }

    const diff = EditorMarkdownInsert.computeTextDiff(oldText, newText)
    this.suppressContentCaretSync = true
    this.contentCaretIndex = caret
    let appliedByController = false
    try {
      appliedByController = this.applyContentInsertViaController(diff)
    } catch (_) {
      appliedByController = false
    }

    if (!appliedByController) {
      this.content = newText
    } else {
      setTimeout(() => {
        if (this.content !== newText) {
          this.suppressContentCaretSync = true
          this.content = newText
          this.scheduleApplyCaret(caret, newText.length)
        }
      }, 0)
    }
    this.scheduleApplyCaret(caret, newText.length)
    this.scheduleSave()
    if (this.shouldRenderPreview()) {
      this.schedulePreviewRefresh()
    } else {
      this.previewDirty = true
    }
  }

  private handleContentChange(): void {
    if (!this.suppressContentCaretSync && this.noteTagsSafe().includes('Todo')) {
      const oldText = this.previousContent
      const newText = this.content
      const caret = this.currentContentCaret()
      const result = MarkdownUtils.applyTodoCheckboxOnNewline(oldText, newText, caret)
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
      this.showPreviewMessage(isNew ? `已创建并应用标签：${resolved}` : `已应用标签：${resolved}`)
    } catch (e) {
      const detail = e instanceof Error
        ? e.message
        : AiTagService.describeError(e as Object)
      this.showPreviewMessage(
        UserFacingMessage.forAi(
          e instanceof Error ? e.message : undefined,
          'AI 创建标签失败，请稍后重试'
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
    const trimmedTitle = rawTitle.trim()
    if (trimmedTitle.length > 0) {
      return { title: trimmedTitle, skipTitleAutoFill: false }
    }
    if (this.titleFieldFocused) {
      return { title: '', skipTitleAutoFill: true }
    }
    if (content.trim().length === 0) {
      return { title: '', skipTitleAutoFill: false }
    }
    return { title: MarkdownUtils.editorAutoTitle(content), skipTitleAutoFill: false }
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
      this.showPreviewMessage('打开标签管理失败')
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
      this.preparePreviewForCurrentMode(this.content)
      void this.refreshAllNotes()
      this.runInitialActionIfNeeded()
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
      this.scheduleMembershipExpiryReminderIfNeeded()
      return
    }
    this.title = note.title
    this.content = note.content
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
    this.preparePreviewForCurrentMode(note.content)
    void this.refreshAllNotes()
    this.schedulePathCaptionMarquee()
    this.runInitialActionIfNeeded()
    this.scheduleMembershipExpiryReminderIfNeeded()
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
        this.openAiLinkExtractDialog()
      } else if (action === 'insertImage') {
        void this.insertImage()
      } else if (action === 'generateNoteFromImage') {
        void this.insertImage(true)
      } else if (action === 'todoList') {
        this.applyTodoListEntryDefaults()
      }
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
    const placeholderTodo =
      this.noteTagsSafe().includes('Todo') && !this.shouldPersistTodoNote()
    if ((this.title.trim().length === 0 && this.content.trim().length === 0) ||
      placeholderTodo) {
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
      Logger.info('NoteEdit',
        `handleAutoSave start: noteId=${this.noteId || 'new'}, titleLength=${this.title.length}, contentLength=${this.content.length}`)
      const rawTitle = this.title
      if (this.noteTagsSafe().includes('Todo') && !this.shouldPersistTodoNote()) {
        await this.abandonPlaceholderTodoIfNeeded()
        this.saveStatus = '未保存'
        Logger.info('NoteEdit', 'handleAutoSave skipped: placeholder todo note')
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
    try {
      await this.handleAutoSave()
    } catch (error) {
      Logger.warn('NoteEdit', `flushAndAutoSaveAfterLeave failed: ${JSON.stringify(error)}`)
    }
  }

  private mobileFullPreviewChrome(): boolean {
    return !this.isSplitMode() && this.previewMode === 'preview'
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

  private isMovePickerEntryExpanded(entry: MovePickerEntry): boolean {
    return this.expandedFolderIds.includes(entry.id)
  }

  /** 弹窗中标注当前笔记已所在的父文件夹（根目录 parentId 为空）。 */
  private isMovePickerCurrentParent(entry: MovePickerEntry): boolean {
    const current = `${this.parentId ?? ''}`.trim()
    if (!entry.isFolder) {
      return false
    }
    if (entry.id === NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID) {
      return current.length === 0
    }
    const target = `${entry.moveTargetParentId ?? ''}`.trim()
    return target.length > 0 && target === current
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
      if (token !== this.pathCaptionMarqueeToken || !this.mobileFullPreviewChrome()) {
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
    if (!this.mobileFullPreviewChrome()) {
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
  private buildMovePickerFileRow(entry: MovePickerEntry) {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(16)
        .fontColor([$r('app.color.accent')])
      Text(entry.title)
        .fontSize(14)
        .fontColor(
          NoteFolderTree.wouldCreateParentCycle(this.noteId, entry.id, this.allNotes) ?
            $r('app.color.tertiary_text') : $r('app.color.primary_text')
        )
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({
      left: 20 + entry.depth * 14,
      right: 16,
      top: 6,
      bottom: 6
    })
    .onClick(() => {
      if (!NoteFolderTree.wouldCreateParentCycle(this.noteId, entry.id, this.allNotes)) {
        void this.onSelectMoveFolder(entry.id)
      }
    })
  }

  @Builder
  private buildMovePickerFolderRow(entry: MovePickerEntry) {
    Row({ space: 0 }) {
      Image(this.isMovePickerEntryExpanded(entry) ? $r('app.media.ic_folder_open') : $r('app.media.ic_folder_closed'))
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
        .margin({ left: 8 + entry.depth * 14, right: 10 })
        .onClick(() => {
          if (entry.canExpand) {
            this.onToggleFolderExpand(entry.id)
          }
        })
      Text(entry.title)
        .fontSize($r('app.float.body_font_size'))
        .fontColor(
          this.isMovePickerCurrentParent(entry) ? $r('app.color.tertiary_text') :
            (entry.moveTargetParentId !== undefined &&
              entry.moveTargetParentId.length > 0 &&
              NoteFolderTree.wouldCreateParentCycle(this.noteId, entry.moveTargetParentId, this.allNotes) ?
              $r('app.color.tertiary_text') : $r('app.color.primary_text'))
        )
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .padding({ top: 10, bottom: 10, right: 12 })
        .onClick(() => {
          const target = entry.moveTargetParentId ?? ''
          if (target.length === 0 ||
            !NoteFolderTree.wouldCreateParentCycle(this.noteId, target, this.allNotes)) {
            void this.onSelectMoveFolder(target)
          }
        })
    }
    .width('100%')
  }

  @Builder
  private buildMovePickerEntryRow(entry: MovePickerEntry) {
    if (entry.isFolder) {
      this.buildMovePickerFolderRow(entry)
    } else {
      this.buildMovePickerFileRow(entry)
    }
  }

  @Builder
  private buildFolderMovePanel() {
    Column({ space: 0 }) {
      Text('将当前文件移动到')
        .fontSize($r('app.float.move_panel_hint_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 8 })
      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.getMovePickerEntries(), (entry: MovePickerEntry) => {
            this.buildMovePickerEntryRow(entry)
          }, (entry: MovePickerEntry) =>
            `pick_${entry.id}_${entry.depth}_${entry.isFolder}_${this.isMovePickerEntryExpanded(entry)}`)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: '50%' })
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.card_border') })
    .shadow({
      radius: 12,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 4
    })
  }

  @Builder
  private buildParentPathCaption() {
    Scroll(this.pathCaptionScroller) {
      Row({ space: 0 }) {
        Text('当前位置：/')
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .flexShrink(0)
        Text('根目录')
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
    .width('100%')
    .padding({ left: 13, bottom: 8 })
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

  /** 顶部保存状态 + 预览/编辑模式（与 Flutter `_saveStatusDisplay` 对齐）；中间为「空格减号空格」。 */
  private saveStatusDisplay(): string {
    const modeLabel = this.previewMode === 'preview' ? '预览模式' : '编辑模式'
    return `${this.saveStatus} - ${modeLabel}`
  }

  private switchMode(mode: string): void {
    if (this.previewMode === mode) {
      if (mode === 'preview') {
        this.preparePreviewForCurrentMode(this.content, true)
      }
      return
    }
    this.previewMode = mode
    if (mode === 'preview') {
      this.preparePreviewForCurrentMode(this.content, true)
      this.aiMenuVisible = false
    } else if (mode === 'edit') {
      this.tagMenuVisible = false
      this.aiMenuVisible = false
      this.folderMovePopupVisible = false
      this.stopPathCaptionMarquee()
    }
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

  private resolveImageSrc(src: string): string {
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return src
    }
    if (src.startsWith('file://')) {
      return src
    }
    if (src.startsWith('/')) {
      return fileUri.getUriFromPath(src)
    }
    const base =
      this.filesDirCache.length > 0 ? this.filesDirCache : (this.obtainUiAbilityContext()?.filesDir ?? '')
    const absPath = `${base}/${src}`
    return fileUri.getUriFromPath(absPath)
  }

  private async insertImage(thenOptimize: boolean = false): Promise<void> {
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
      this.suppressContentCaretSync = true
      this.scheduleApplyCaret(this.content.length)
      this.scheduleSave()
      if (this.shouldRenderPreview()) {
        this.schedulePreviewRefresh()
      } else {
        this.previewDirty = true
      }
      if (thenOptimize && this.lifecycle.isActive()) {
        await this.onAiOptimizeContent()
      }
    } catch (error) {
      Logger.error('NoteEdit', `insertImage failed: ${JSON.stringify(error)}`)
      this.showPreviewMessage('插入图片失败')
    }
  }

  private async saveCachePngToGallery(cachePath: string): Promise<boolean> {
    const context = this.obtainUiAbilityContext()
    if (context === undefined) {
      return false
    }
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context)
      const srcFileUris: Array<string> = [fileUri.getUriFromPath(cachePath)]
      const photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [
        {
          title: `note_share_${Date.now()}`,
          fileNameExtension: 'png',
          photoType: photoAccessHelper.PhotoType.IMAGE,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT
        }
      ]
      const destUris: Array<string> = await helper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs)
      if (destUris.length === 0) {
        return false
      }
      const src = fileIo.openSync(cachePath, fileIo.OpenMode.READ_ONLY)
      const dest = await fileIo.open(destUris[0], fileIo.OpenMode.WRITE_ONLY)
      await fileIo.copyFile(src.fd, dest.fd)
      fileIo.closeSync(src)
      fileIo.closeSync(dest)
      return true
    } catch (error) {
      Logger.error('NoteEdit', `saveCachePngToGallery failed: ${JSON.stringify(error)}`)
      return false
    }
  }

  private async updateSharePreviewImageLayout(path: string): Promise<void> {
    if (path.length === 0) {
      this.sharePreviewImageHeightVp = 0
      return
    }
    try {
      let src: image.ImageSource | null = null
      try {
        src = image.createImageSource(path)
      } catch (_) {
        src = image.createImageSource(`file://${path}`)
      }
      if (src === null) {
        return
      }
      const pm = await src.createPixelMap({
        desiredDynamicRange: image.DecodingDynamicRange.SDR,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      })
      const info = pm.getImageInfoSync()
      await pm.release()
      await src.release()
      const w = info.size.width
      const h = info.size.height
      if (w <= 0 || h <= 0) {
        return
      }
      const previewW = Math.max(1, this.pageWidth)
      this.sharePreviewImageHeightVp = (h / w) * previewW
      Logger.info('NoteEdit',
        `share preview layout ${w}x${h}px widthVp=${previewW} heightVp=${this.sharePreviewImageHeightVp}`)
    } catch (error) {
      Logger.warn('NoteEdit', `updateSharePreviewImageLayout failed: ${JSON.stringify(error)}`)
      this.sharePreviewImageHeightVp = 0
    }
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
      await NoteEdit.delayMs(48)
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
    const hasImages = this.shareExportContentHasImages()
    const mountDelayMs = jinshuLight ? 1100 : (hasImages ? 920 : 680)
    await NoteEdit.delayMs(mountDelayMs)
  }

  /** 分享正文是否含 Markdown 图片块。 */
  private shareExportBodyHasImages(): boolean {
    for (const block of this.previewBlocksState) {
      if (block.type === 'image') {
        return true
      }
    }
    return false
  }

  /** 分享导出内容是否含网络头像或 Markdown 图片（ComponentSnapshot checkImage 需更久渲染）。 */
  private shareExportContentHasImages(): boolean {
    if (this.shareAvatarUrlTrim().length > 0) {
      return true
    }
    return this.shareExportBodyHasImages()
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

  private static delayMs(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms))
  }

  /**
   * 与单屏分享一致：先 ImagePacker(SDR) 再解码，使每张滚动截图的 PixelMap 与 PNG 编解码管线对齐，
   * 避免 RS 离屏截图直接 readPixels + 手工合并时的 HDR/通道解读与相册「正常图」不一致。
   */
  private async normalizeSliceViaSdrPngRoundTrip(pm: image.PixelMap): Promise<image.PixelMap | null> {
    const packer = image.createImagePacker()
    let inputReleased = false
    try {
      try {
        await pm.convertPixelFormat(image.PixelMapFormat.RGBA_8888)
      } catch (_) {
        // 部分 RS 截图 convert 失败仍可走 packing
      }
      const pngBuf = await packer.packToData(pm, {
        format: 'image/png',
        quality: 100,
        desiredDynamicRange: image.PackingDynamicRange.SDR
      })
      await pm.release()
      inputReleased = true
      const src = image.createImageSource(pngBuf)
      try {
        return await src.createPixelMap({
          desiredDynamicRange: image.DecodingDynamicRange.SDR,
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888
        })
      } finally {
        await src.release()
      }
    } catch (e) {
      Logger.error('NoteEdit', `normalizeSliceViaSdrPngRoundTrip failed: ${JSON.stringify(e)}`)
      if (!inputReleased) {
        try {
          await pm.release()
        } catch (_) {
        }
      }
      return null
    }
  }

  /** 全部转为「SDR PNG 往返」后的 PixelMap；失败时释放已分配资源与剩余原始切片。 */
  private async normalizeAllSlicesForMerge(slices: image.PixelMap[]): Promise<image.PixelMap[] | null> {
    const out: image.PixelMap[] = []
    for (let i = 0; i < slices.length; i++) {
      const n = await this.normalizeSliceViaSdrPngRoundTrip(slices[i])
      if (!n) {
        for (const p of out) {
          await p.release()
        }
        for (let j = i + 1; j < slices.length; j++) {
          await slices[j].release()
        }
        return null
      }
      out.push(n)
    }
    return out
  }

  private async packPixelMapToPng(pm: image.PixelMap): Promise<ArrayBuffer | null> {
    const packer = image.createImagePacker()
    try {
      try {
        await pm.convertPixelFormat(image.PixelMapFormat.RGBA_8888)
      } catch (_) {
        // 部分 PixelMap 与 convert 不兼容时仍可 packing
      }
      const buf = await packer.packToData(pm, {
        format: 'image/png',
        quality: 100,
        desiredDynamicRange: image.PackingDynamicRange.SDR
      })
      await pm.release()
      return buf
    } catch (err) {
      Logger.error('NoteEdit', `packPixelMapToPng failed: ${JSON.stringify(err)}`)
      await pm.release()
      return null
    }
  }

  /**
   * 单屏分享截图：裁掉上下透明留白（Scroll 视口高于卡片内容时常见）。
   * 优先按 alpha 检测内容边界；辅以 shareExportColumnVp 限制高度。
   */
  private async trimTransparentVerticalEdges(pm: image.PixelMap): Promise<image.PixelMap | null> {
    try {
      const info = pm.getImageInfoSync()
      const widthPx = info.size.width
      const srcH = info.size.height
      if (srcH <= 1) {
        return pm
      }
      const stride = info.stride
      const srcBuf = new ArrayBuffer(pm.getPixelBytesNumber())
      pm.readPixelsToBufferSync(srcBuf)
      const srcView = new Uint8Array(srcBuf)
      const alphaThreshold = 8
      let top = -1
      let bottom = -1
      for (let r = 0; r < srcH; r++) {
        const rowStart = r * stride
        let rowOpaque = false
        for (let x = 0; x < widthPx; x++) {
          const si = rowStart + x * 4
          if (srcView[si + 3] > alphaThreshold) {
            rowOpaque = true
            break
          }
        }
        if (rowOpaque) {
          if (top < 0) {
            top = r
          }
          bottom = r
        }
      }
      const ui = this.getUIContext()
      const contentPx = this.shareExportColumnVp > 0
        ? Math.max(1, Math.round(ui.vp2px(this.shareExportColumnVp)))
        : 0
      if (top < 0) {
        if (contentPx > 0 && contentPx < srcH) {
          top = 0
          bottom = contentPx - 1
        } else {
          return pm
        }
      } else if (contentPx > 0) {
        const contentBottom = top + contentPx - 1
        if (contentBottom < bottom) {
          bottom = contentBottom
        }
      }
      const cropH = bottom - top + 1
      if (cropH <= 0 || cropH >= srcH) {
        return pm
      }
      const headAlpha = info.alphaType
      const mergeAlphaType =
        headAlpha === image.AlphaType.UNKNOWN ? image.AlphaType.PREMUL : headAlpha
      const rowBytes = widthPx * 4
      const dstBuf = new ArrayBuffer(rowBytes * cropH)
      const dstView = new Uint8Array(dstBuf)
      for (let r = 0; r < cropH; r++) {
        const srcRow = top + r
        const srcLineStart = srcRow * stride
        const dstLineStart = r * rowBytes
        for (let x = 0; x < widthPx; x++) {
          const si = srcLineStart + x * 4
          const di = dstLineStart + x * 4
          dstView[di] = srcView[si + 2]
          dstView[di + 1] = srcView[si + 1]
          dstView[di + 2] = srcView[si]
          dstView[di + 3] = srcView[si + 3]
        }
      }
      await pm.release()
      return await image.createPixelMap(dstBuf, {
        size: { width: widthPx, height: cropH },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        alphaType: mergeAlphaType
      })
    } catch (err) {
      Logger.error('NoteEdit', `trimTransparentVerticalEdges failed: ${JSON.stringify(err)}`)
      return null
    }
  }

  /**
   * 将多张纵向分段截图合并为一张 PixelMap。
   * - rowStepPx：单屏在物理像素上的高度上限，用于裁掉比视口「更高」的截图底部。
   * - sliceSkipTopPx：每张切片从像素矩阵顶部跳过的行数；除首张外一般为「视口高度 − 与上一张之间的滚动增量(px)」，
   *   用于去掉相邻截图在纵向的重叠（若滚动增量小于视口高度，下一张顶部会与上一张底部重复）。
   * - 调用方应在拼接前经 normalizeAllSlicesForMerge，使每张切片与单屏导出同源（SDR PNG 往返后的 RGBA）。
   * - readPixelsToBufferSync 在本机为 **BGRA** 字节序（与 readPixelsSync 的 RGBA 语义差一次 R/B 交换）。
   *   逐像素 **BGRA→RGBA** 写入合并缓冲，再以 **RGBA_8888** 建 PixelMap，与单屏 snapshot 直打包路径一致。
   *   仅用 BGRA 建 PixelMap 再 ImagePacker 仍可能偏色。
   */
  private async mergePixelMapsVertical(slices: image.PixelMap[], widthPx: number,
    totalHeightPx: number, rowStepPx: number, sliceSkipTopPx: number[]): Promise<image.PixelMap | null> {
    if (slices.length === 0 || totalHeightPx <= 0 || sliceSkipTopPx.length !== slices.length) {
      Logger.warn('NoteEdit',
        `mergePixelMapsVertical: bad args slices=${slices.length} totalH=${totalHeightPx} skipLen=${sliceSkipTopPx.length}`)
      return null
    }
    try {
      const headInfo = slices[0].getImageInfoSync()
      const headAlpha = headInfo.alphaType
      const mergeAlphaType =
        headAlpha === image.AlphaType.UNKNOWN ? image.AlphaType.PREMUL : headAlpha
      const mergeBufferPixelFormat = image.PixelMapFormat.RGBA_8888
      const rowBytes = widthPx * 4
      const dstBuf = new ArrayBuffer(rowBytes * totalHeightPx)
      const dstView = new Uint8Array(dstBuf)
      let dstRowTop = 0
      for (let s = 0; s < slices.length && dstRowTop < totalHeightPx; s++) {
        const pm = slices[s]
        const info = pm.getImageInfoSync()
        const srcStride = info.stride
        const srcH = info.size.height
        const srcBuf = new ArrayBuffer(pm.getPixelBytesNumber())
        pm.readPixelsToBufferSync(srcBuf)
        const srcView = new Uint8Array(srcBuf)
        let skipTop = Math.max(0, Math.floor(sliceSkipTopPx[s]))
        if (skipTop >= srcH) {
          Logger.warn('NoteEdit', `mergePixelMapsVertical: slice[${s}] skipped skipTop=${skipTop}>=srcH=${srcH}`)
          continue
        }
        const availAfterSkip = srcH - skipTop
        const cap = rowStepPx > 0 ? Math.min(availAfterSkip, rowStepPx) : availAfterSkip
        const rowsToCopy = Math.min(cap, totalHeightPx - dstRowTop)
        for (let r = 0; r < rowsToCopy; r++) {
          const srcRow = skipTop + r
          const srcLineStart = srcRow * srcStride
          const dstLineStart = (dstRowTop + r) * rowBytes
          if (srcLineStart + rowBytes > srcView.byteLength) {
            Logger.warn('NoteEdit',
              `mergePixelMapsVertical: slice[${s}] row=${r} src overflow srcLineStart=${srcLineStart}`)
            break
          }
          for (let x = 0; x < widthPx; x++) {
            const si = srcLineStart + x * 4
            const di = dstLineStart + x * 4
            dstView[di] = srcView[si + 2]
            dstView[di + 1] = srcView[si + 1]
            dstView[di + 2] = srcView[si]
            dstView[di + 3] = srcView[si + 3]
          }
        }
        dstRowTop += rowsToCopy
      }
      const actualHeight = Math.max(1, Math.min(dstRowTop, totalHeightPx))
      const trimmedBuf =
        actualHeight === totalHeightPx ? dstBuf : dstBuf.slice(0, rowBytes * actualHeight)
      const mergedPm = await image.createPixelMap(trimmedBuf, {
        size: { width: widthPx, height: actualHeight },
        pixelFormat: mergeBufferPixelFormat,
        alphaType: mergeAlphaType
      })
      return mergedPm
    } catch (err) {
      Logger.error('NoteEdit', `mergePixelMapsVertical failed: ${JSON.stringify(err)}`)
      return null
    } finally {
      for (const pm of slices) {
        await pm.release()
      }
    }
  }

  /**
   * 对已挂载的导出节点分段截图并纵向拼接。
   * 不使用 createFromBuilder，避免 Builder 在隔离上下文中缺少 observeComponentCreation2。
   */
  private async captureScrollingCardToImage(): Promise<ArrayBuffer | null> {
    await NoteEdit.delayMs(240)
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
      ? [NoteEdit.SHARE_SCROLL_ID, NoteEdit.SHARE_CARD_ID]
      : [NoteEdit.SHARE_CARD_ID, NoteEdit.SHARE_SCROLL_ID]
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
      const trimmed = await this.trimTransparentVerticalEdges(slices[0])
      await slices[0].release()
      if (!trimmed) {
        return null
      }
      const buf = await this.packPixelMapToPng(trimmed)
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
    const normalized = await this.normalizeAllSlicesForMerge(slices)
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
    const merged = await this.mergePixelMapsVertical(normalized, widthPx, normHeightPx, 0, sliceSkipTopPx)
    if (!merged) {
      Logger.error('NoteEdit', 'captureJinshuLightSegmented: mergePixelMapsVertical returned null')
      return null
    }
    const buf = await this.packPixelMapToPng(merged)
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
      await NoteEdit.delayMs(160)
      this.shareScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
      await NoteEdit.delayMs(160)
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
    await NoteEdit.delayMs(120)
  }

  private async captureScrollingCardToImageCore(): Promise<ArrayBuffer | null> {
    const waitOpts = this.shareSnapshotWaitOpts()
    const ui = this.getUIContext()
    const vpEps = 0.5
    const offsetWarnVp = 2.0

    this.shareScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
    await NoteEdit.delayMs(100)

    Logger.info('NoteEdit',
      `captureScrollingCardToImageCore start key=${this.shareCardCaptureKey} ` +
      `theme=${this.shareExportTheme} tone=${this.shareExportTone} targetCardId=${NoteEdit.SHARE_CARD_ID} ` +
      `targetScrollId=${NoteEdit.SHARE_SCROLL_ID} ` +
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
    await NoteEdit.delayMs(120)
    const bottomOff = this.shareScroller.currentOffset()
    const maxScrollVp = Math.max(0, bottomOff.yOffset)

    this.shareScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
    await NoteEdit.delayMs(100)

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
      const trimmed = await this.trimTransparentVerticalEdges(firstPm)
      if (!trimmed) {
        return null
      }
      return await this.packPixelMapToPng(trimmed)
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
        await NoteEdit.delayMs(100)
      }
      this.shareScroller.scrollTo({ xOffset: 0, yOffset: nextYVp, animation: false })
      await NoteEdit.delayMs(150)
      let actualY = this.shareScroller.currentOffset().yOffset
      if (Math.abs(actualY - nextYVp) > offsetWarnVp) {
        this.shareScroller.scrollTo({ xOffset: 0, yOffset: nextYVp, animation: false })
        await NoteEdit.delayMs(80)
        actualY = this.shareScroller.currentOffset().yOffset
      }
      // scrollTo 可能被钳制，用小步 scrollBy 逼近目标，便于末尾 slogan 区域进入视口。
      let nudgeGuard = 0
      while (actualY < nextYVp - vpEps && nudgeGuard < 16) {
        const remainVp = nextYVp - actualY
        const stepNudge = Math.min(64, Math.max(1, remainVp))
        this.shareScroller.scrollBy(0, stepNudge)
        await NoteEdit.delayMs(45)
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
      const trimmed = await this.trimTransparentVerticalEdges(slices[0])
      if (!trimmed) {
        return null
      }
      return await this.packPixelMapToPng(trimmed)
    }

    const normalized = await this.normalizeAllSlicesForMerge(slices)
    if (!normalized) {
      Logger.error('NoteEdit', 'shareLongImage: normalizeAllSlicesForMerge failed')
      return null
    }
    const merged =
      await this.mergePixelMapsVertical(normalized, widthPx, mergeHeightPx, rowStepPx, sliceSkipTopPx)
    if (!merged) {
      Logger.error('NoteEdit', 'shareLongImage: mergePixelMapsVertical returned null')
      return null
    }
    return await this.packPixelMapToPng(merged)
  }

  private formatShareCreatedAt(timestamp: number): string {
    const ms = timestamp > 0 ? timestamp : Date.now()
    const date = new Date(ms)
    return `创作于${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()}`
  }

  private shareDisplayName(): string {
    const name = (this.shareProfile?.username ?? '').trim()
    return name.length > 0 ? name : '轻羽云笔记用户'
  }

  private shareAvatarUrlTrim(): string {
    return (this.shareProfile?.avatar_url ?? '').trim()
  }

  @Builder
  private buildShareAvatar() {
    if (this.shareAvatarUrlTrim().length > 0 && !this.shareAvatarNetworkFailed) {
      CachedNetworkImage({
        url: this.shareAvatarUrlTrim(),
        imageWidth: NoteEdit.SHARE_AVATAR_SIZE,
        imageHeight: NoteEdit.SHARE_AVATAR_SIZE,
        imageBorderRadius: NoteEdit.SHARE_AVATAR_SIZE / 2,
        objectFit: ImageFit.Cover,
        showLoading: false,
        onError: () => {
          this.shareAvatarNetworkFailed = true
        }
      })
    } else {
      Image($r('app.media.icon_app'))
        .width(NoteEdit.SHARE_AVATAR_SIZE)
        .height(NoteEdit.SHARE_AVATAR_SIZE)
        .borderRadius(NoteEdit.SHARE_AVATAR_SIZE / 2)
        .objectFit(ImageFit.Cover)
    }
  }

  /** 通过分享预览保存或分享长图。 */
  private async runShareNote(): Promise<void> {
    if (this.sharePreviewPreparing || this.sharePreviewRegenerating) {
      return
    }
    this.sharePreviewPreparing = true
    this.showPreviewMessage('正在生成长图…')
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
      const path = await this.exportShareImageToCache(savedTheme, savedTone)
      if (!path || path.length === 0) {
        this.showPreviewMessage('生成长图失败')
        return
      }
      this.sharePreviewPath = path
      await this.updateSharePreviewImageLayout(path)
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
      await this.updateSharePreviewImageLayout(path)
      Logger.info('NoteEdit',
        `regenerateSharePreview done path=${path} theme=${theme} tone=${tone} revision=${this.shareSheetRevision}`)
    } else {
      Logger.warn('NoteEdit', 'regenerateSharePreview failed')
      this.showPreviewMessage('切换主题失败')
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
    const ok = await this.saveCachePngToGallery(this.sharePreviewPath)
    this.showPreviewMessage(ok ? '已保存到相册' : '保存到相册失败')
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
      this.showPreviewMessage('分享失败')
      return
    }
    const cachePath = this.sharePreviewPath
    this.closeSharePreview()
    try {
      const uri = fileUri.getUriFromPath(cachePath)
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.PNG,
        uri: uri
      })
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData)
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      })
    } catch (error) {
      Logger.error('NoteEdit', `onSharePreviewShareOthers failed: ${JSON.stringify(error)}`)
      this.showPreviewMessage('分享失败')
    }
  }

  /** @deprecated 保留兼容；请使用 [runShareNote]。 */
  private async runSaveLongImageToGallery(): Promise<void> {
    await this.runShareNote()
  }

  @Builder
  private buildShareOptionsSheet() {
    NoteSharePreviewSheet({
      theme: this.shareTheme,
      tone: this.shareTone,
      sheetRevision: this.shareSheetRevision,
      params: {
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
        onSave: (): void => {
          Logger.info('NoteEdit', 'shareSheet button=action label=保存到相册')
          void this.onSharePreviewSave()
        },
        onShare: (): void => {
          Logger.info('NoteEdit', 'shareSheet button=action label=分享到其他')
          void this.onSharePreviewShareOthers()
        },
        onCancel: (): void => {
          Logger.info('NoteEdit', 'shareSheet button=cancel label=取消')
          this.closeSharePreview()
        }
      }
    })
  }

  private shareExportMountKey(): string {
    return `${this.shareCardCaptureKey}_${this.shareExportTheme}_${this.shareExportTone}_` +
      `${this.shareExportSnapshotCompatMode ? 'compat' : 'normal'}_` +
      `${this.shareExportSnapshotSkipQr ? 'noqr' : 'qr'}`
  }

  @Builder
  private buildShareExportCard() {
    NoteShareExportCard({
      theme: this.shareExportTheme,
      tone: this.shareExportTone,
      snapshotCompatMode: this.shareExportSnapshotCompatMode,
      snapshotSkipQr: this.shareExportSnapshotSkipQr,
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

  @Builder
  private buildTagChip(tag: string) {
    Stack(){
      Text(tag)
        .fontSize(12)
        .fontColor(0X00FFFFFF)
        .padding({ left: 8, right: 8, top: 3, bottom: 4 })
        .backgroundColor($r('app.color.tag_text_accent'))
        .opacity(0.12)
        .borderRadius(10)
      Text(tag)
        .fontSize(12)
        .fontColor($r('app.color.primary_text'))
        .padding({ left: 8, right: 8, top: 3, bottom: 4 })
        .borderRadius(10)
    }
  }

  @Builder
  private buildTagDropdownItem(tag: string) {
    Row() {
      Checkbox()
        .select(this.noteTagsSafe().includes(tag))
        .selectedColor($r('app.color.accent'))
        .onChange((value: boolean) => {
          void this.onTagChecked(tag, value)
        })
      Text(tag)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(NoteEdit.TAG_DROPDOWN_ITEM_HEIGHT_VP)
    .padding({ left: 12, right: 12 })
    .onClick(() => {
      const selected = !this.noteTagsSafe().includes(tag)
      void this.onTagChecked(tag, selected)
    })
  }

  @Builder
  private buildTagDropdownTagList() {
    if (this.tagPool.length === 0) {
      Text('暂无可用标签')
        .fontSize($r('app.float.caption_font_size'))
        .fontColor($r('app.color.tertiary_text'))
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    } else if (this.tagPool.length > NoteEdit.TAG_DROPDOWN_MAX_VISIBLE_ITEMS) {
      Scroll() {
        Column() {
          ForEach(this.tagPool, (tag: string) => {
            this.buildTagDropdownItem(tag)
          }, (tag: string) => `tag_item_${tag}`)
        }
      }
      .width('100%')
      .height(NoteEdit.TAG_DROPDOWN_ITEM_HEIGHT_VP * NoteEdit.TAG_DROPDOWN_MAX_VISIBLE_ITEMS)
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
    } else {
      ForEach(this.tagPool, (tag: string) => {
        this.buildTagDropdownItem(tag)
      }, (tag: string) => `tag_item_${tag}`)
    }
  }

  @Builder
  private buildTagDropdown() {
    Column() {
      this.buildTagDropdownTagList()
      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'))
        .margin({ top: 4, bottom: 4 })
      Row() {
        if (this.aiTagCreating) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color($r('app.color.accent'))
        } else {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(16)
            .fontColor([$r('app.color.accent')])
        }
        Text(this.aiTagCreating ? 'AI 生成中…' : 'AI创建标签')
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.accent'))
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .onClick(() => {
        if (!this.aiTagCreating) {
          void this.onAiCreateTag()
        }
      })
      Row() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(16)
          .fontColor([$r('app.color.accent')])
        Text('添加标签')
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.accent'))
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .onClick(() => {
        this.tagMenuVisible = false
        void this.openTagManage()
      })
    }
    .width(154)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.card_border') })
    .shadow({
      radius: 12,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 4
    })
  }

  @Builder
  buildAiDropdown() {
    Column() {
      Row() {
        if (this.aiNoteWorking) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color($r('app.color.accent'))
        } else {
          SymbolGlyph($r('sys.symbol.wand_and_stars'))
            .fontSize(16)
            .fontColor([$r('app.color.accent')])
        }
        Text(this.aiNoteWorking ? 'AI 处理中…' : 'AI优化语句')
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.accent'))
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .onClick(() => {
        if (!this.aiNoteWorking) {
          void this.onAiOptimizeContent()
        }
      })
      Divider()
        .color($r('app.color.card_border'))
        .strokeWidth(1)
      Row() {
        SymbolGlyph($r('sys.symbol.link'))
          .fontSize(16)
          .fontColor([$r('app.color.accent')])
        Text('AI提取链接')
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.accent'))
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .onClick(() => {
        if (!this.aiNoteWorking) {
          this.aiMenuVisible = false
          this.openAiLinkExtractDialog()
        }
      })
      if (this.aiUndoAvailable) {
        Divider()
          .color($r('app.color.card_border'))
          .strokeWidth(1)
        Row() {
          SymbolGlyph($r('sys.symbol.undo'))
            .fontSize(16)
            .fontColor([$r('app.color.accent')])
          Text('撤回AI修改')
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.accent'))
            .margin({ left: 8 })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onClick(() => {
          if (!this.aiNoteWorking) {
            this.onAiUndo()
          }
        })
      }
    }
    .width(154)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.card_border') })
    .shadow({
      radius: 12,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 4
    })
  }

  private async onAiOptimizeContent(): Promise<void> {
    if (this.aiNoteWorking) {
      return
    }
    const trimmed = this.content.trim()
    const hasImageRefs = NoteStateCodec.extractImageRefs(this.content).length > 0
    const noteHasText = NoteStateCodec.hasSubstantiveNoteText(this.content)
    if (!noteHasText && !hasImageRefs) {
      this.showPreviewMessage('笔记正文为空，无法优化')
      return
    }
    if (noteHasText && !hasImageRefs && Array.from(trimmed).length < AiNotePrompt.OPTIMIZE_MIN_RUNES) {
      this.showPreviewMessage('内容过少，无需AI优化')
      return
    }
    this.aiWorkingOverlayMessage =
      !noteHasText && hasImageRefs ? 'AI 生成笔记中…' : 'AI 处理中…'
    this.aiNoteWorking = true
    this.aiMenuVisible = false
    const before = this.content
    const filesDir = this.filesDirCache.length > 0
      ? this.filesDirCache
      : (this.obtainUiAbilityContext()?.filesDir ?? '')
    try {
      const optimized = await AiNoteService.getInstance().optimizeContent(this.content, filesDir)
      const parts = MarkdownUtils.splitLinkSummary(optimized)
      this.captureAiUndoBaseline(before)
      if (hasImageRefs && parts.title.trim().length > 0) {
        this.title = parts.title.trim()
        this.content = parts.body
      } else {
        this.content = optimized
      }
      this.handleContentChange()
      this.showPreviewMessage(noteHasText ? 'AI 已优化笔记正文' : 'AI 已根据图片生成笔记')
    } catch (e) {
      const msg = UserFacingMessage.forAi(
        e instanceof Error ? e.message : undefined,
        'AI 优化失败，请稍后重试'
      )
      this.showPreviewMessage(msg)
      Logger.error('NoteEdit', `onAiOptimizeContent failed: ${e instanceof Error ? e.message : JSON.stringify(e)}`)
    } finally {
      this.aiNoteWorking = false
    }
  }

  private openAiLinkExtractDialog(): void {
    const ui = this.getUIContext()
    let holder: ComponentContent<EditorAiLinkExtractDialogParams> | undefined = undefined
    const params: EditorAiLinkExtractDialogParams = {
      onCancel: (): void => {
        if (holder !== undefined) {
          try {
            ui.getPromptAction().closeCustomDialog(holder)
          } catch (_) {
            // ignore
          }
        }
      },
      onConfirm: (url: string): void => {
        if (holder !== undefined) {
          try {
            ui.getPromptAction().closeCustomDialog(holder)
          } catch (_) {
            // ignore
          }
        }
        void this.onAiExtractLink(url)
      }
    }
    holder = new ComponentContent(ui, wrapBuilder(buildEditorAiLinkExtractDialogContent), params)
    try {
      ui.getPromptAction().openCustomDialog(holder, {
        alignment: DialogAlignment.Center,
        autoCancel: false
      })
    } catch (error) {
      Logger.warn('NoteEdit', `openAiLinkExtractDialog: ${JSON.stringify(error)}`)
    }
  }

  private async onAiExtractLink(url: string): Promise<void> {
    if (this.aiNoteWorking || url.trim().length === 0) {
      return
    }
    this.aiNoteWorking = true
    this.aiMenuVisible = false
    const before = this.content
    try {
      const result = await AiNoteService.getInstance().summarizeLink(url.trim())
      this.captureAiUndoBaseline(before)
      const existing = this.content
      const separator = existing.trim().length === 0 ? '' : '\n\n'
      const trimmedUrl = url.trim()
      const linkLine = `完整文章链接为：[${trimmedUrl}](${trimmedUrl})`
      this.content = `${existing}${separator}${result.body}\n\n${linkLine}`
      if (this.title.trim().length === 0 && result.title.trim().length > 0) {
        this.title = result.title.trim()
      }
      this.handleContentChange()
      this.showPreviewMessage('AI 已生成链接摘要并写入正文')
    } catch (e) {
      const msg = UserFacingMessage.forAi(
        e instanceof Error ? e.message : undefined,
        'AI 提取链接失败，请稍后重试'
      )
      this.showPreviewMessage(msg)
      Logger.error('NoteEdit', `onAiExtractLink failed: ${e instanceof Error ? e.message : JSON.stringify(e)}`)
    } finally {
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
          .color($r('app.color.accent'))
        Text(this.aiWorkingOverlayMessage)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(10005)
  }

  @Builder
  buildDraggableAiBar() {
    Stack() {
      Row({ space: 4 }) {
        Row() {
          Stack({ alignContent: Alignment.Center }) {
            if (this.aiNoteWorking) {
              LoadingProgress()
                .width(22)
                .height(22)
                .color($r('app.color.accent'))
            } else {
              Image($r('app.media.ic_ai_float'))
                .width(24)
                .height(24)
                .objectFit(ImageFit.Contain)
            }
          }
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(18)
        .onClick(() => {
          if (this.aiNoteWorking) {
            return
          }
          this.aiMenuVisible = !this.aiMenuVisible
          if (this.aiMenuVisible) {
            this.tagMenuVisible = false
          }
        })
        .shadow({
          radius: 18,
          color: '#2A000000',
          offsetX: 0,
          offsetY: 3
        })
      }
      .onAreaChange((_, currentArea: Area) => {
        this.tagBarWidth = Number.parseFloat(`${currentArea.width}`) || 120
        this.tagBarHeight = Number.parseFloat(`${currentArea.height}`) || 32
        if (!this.tagBarInitialized) {
          const cardPadding = 18
          const toolbarHeight = 69
          const safeAreaTop = 44
          const defaultRight = 8
          this.tagBarX = this.pageWidth - this.tagBarWidth - cardPadding - defaultRight
          this.tagBarY = toolbarHeight + safeAreaTop - 1.5 * this.tagBarHeight
          this.tagBarInitialized = true
        }
      })
      .position({ x: this.tagBarX, y: this.tagBarY })
      .gesture(
        PanGesture()
          .onActionStart((event: GestureEvent) => {
            this.lastPanOffsetX = event.offsetX
            this.lastPanOffsetY = event.offsetY
          })
          .onActionUpdate((event: GestureEvent) => {
            const safeAreaTop = 44
            const safeAreaBottom = 34
            const screenHeight = this.pageHeight > 0 ? this.pageHeight : 780
            const deltaX = event.offsetX - this.lastPanOffsetX
            const deltaY = event.offsetY - this.lastPanOffsetY
            this.lastPanOffsetX = event.offsetX
            this.lastPanOffsetY = event.offsetY
            let newX = this.tagBarX + deltaX
            let newY = this.tagBarY + deltaY
            if (newX < 0) {
              newX = 0
            }
            if (newX > this.pageWidth - this.tagBarWidth) {
              newX = this.pageWidth - this.tagBarWidth
            }
            if (newY < safeAreaTop) {
              newY = safeAreaTop
            }
            if (newY > screenHeight - this.tagBarHeight - safeAreaBottom) {
              newY = screenHeight - this.tagBarHeight - safeAreaBottom
            }
            this.tagBarX = newX
            this.tagBarY = newY
          })
          .onActionEnd((_: GestureEvent) => {
            this.lastPanOffsetX = 0
            this.lastPanOffsetY = 0
          })
      )

      if (this.aiMenuVisible) {
        Column() {
          this.buildAiDropdown()
        }
        .position({ x: this.floatMenuPosX(), y: this.aiMenuPosY() })
        .zIndex(999)
      }
    }
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
            Text('标签')
              .fontSize(12)
              .fontColor($r('app.color.secondary_text'))
          } else {
            this.buildTagChip(noteTags[0])
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
        if (this.tagMenuVisible) {
          this.aiMenuVisible = false
        }
      })
    }
    .shadow({
      radius: 8,
      color: '#20000000',
      offsetX: 0,
      offsetY: 2
    })
  }

  @Builder
  buildDraggableTagBar() {
    Stack() {
      Row({ space: 4 }) {
        Row() {
          if (this.aiTagCreating) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color($r('app.color.accent'))
          } else {
            Row({ space: 4 }) {
              Text('#')
                .fontSize(14)
                .fontColor($r('app.color.secondary_text'))
                .fontWeight(FontWeight.Medium)
              if (this.noteTagsSafe().length === 0) {
                Text('标签')
                  .fontSize(12)
                  .fontColor($r('app.color.secondary_text'))
              } else {
                this.buildTagChip(this.noteTagsSafe()[0])
                if (this.noteTagsSafe().length > 1) {
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
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(18)
        .onClick(() => {
          if (this.aiTagCreating) {
            return
          }
          void this.refreshTagPool()
          this.tagMenuVisible = !this.tagMenuVisible
          if (this.tagMenuVisible) {
            this.aiMenuVisible = false
          }
        })
        .shadow({
          radius: 18,
          color: '#2A000000',
          offsetX: 0,
          offsetY: 3
        })
      }

      .onAreaChange((_, currentArea: Area) => {
        this.tagBarWidth = Number.parseFloat(`${currentArea.width}`) || 120
        this.tagBarHeight = Number.parseFloat(`${currentArea.height}`) || 32
        if (!this.tagBarInitialized) {
          const cardPadding = 18
          const toolbarHeight = 69
          const safeAreaTop = 44
          const defaultRight = 8
          this.tagBarX = this.pageWidth - this.tagBarWidth - cardPadding - defaultRight
          this.tagBarY = toolbarHeight + safeAreaTop - 1.5 * this.tagBarHeight
          this.tagBarInitialized = true
        }
      })
      .position({ x: this.tagBarX, y: this.tagBarY })
      .gesture(
        PanGesture()
          .onActionStart((event: GestureEvent) => {
            this.lastPanOffsetX = event.offsetX
            this.lastPanOffsetY = event.offsetY
          })
          .onActionUpdate((event: GestureEvent) => {
            const safeAreaTop = 44
            const safeAreaBottom = 34
            const screenHeight = this.pageHeight > 0 ? this.pageHeight : 780
            // 计算增量：当前偏移 - 上次偏移
            const deltaX = event.offsetX - this.lastPanOffsetX
            const deltaY = event.offsetY - this.lastPanOffsetY
            this.lastPanOffsetX = event.offsetX
            this.lastPanOffsetY = event.offsetY
            let newX = this.tagBarX + deltaX
            let newY = this.tagBarY + deltaY
            if (newX < 0) {
              newX = 0
            }
            if (newX > this.pageWidth - this.tagBarWidth) {
              newX = this.pageWidth - this.tagBarWidth
            }
            if (newY < safeAreaTop) {
              newY = safeAreaTop
            }
            if (newY > screenHeight - this.tagBarHeight - safeAreaBottom) {
              newY = screenHeight - this.tagBarHeight - safeAreaBottom
            }
            this.tagBarX = newX
            this.tagBarY = newY
          })
          .onActionEnd((_: GestureEvent) => {
            this.lastPanOffsetX = 0
            this.lastPanOffsetY = 0
          })
      )

      if (this.tagMenuVisible) {
        Column() {
          this.buildTagDropdown()
        }
        .position({ x: this.floatMenuPosX(), y: this.tagMenuPosY() })
        .zIndex(999)
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 0 }) {
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
            if (this.saveStatusBarClickable()) {
              Text() {
                Span(`${this.saveStatus} - `)
                  .fontSize($r('app.float.caption_font_size'))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(
                    this.saveStatus === '已保存' ? $r('app.color.success') :
                      (this.saveStatus === '保存失败' ? $r('app.color.danger') : $r('app.color.secondary_text'))
                  )
                Span('预览模式')
                  .fontSize($r('app.float.caption_font_size'))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(
                    this.saveStatus === '已保存' ? $r('app.color.success') :
                      (this.saveStatus === '保存失败' ? $r('app.color.danger') : $r('app.color.secondary_text'))
                  )
                Span('▼')
                  .fontSize($r('app.float.caption_font_size'))
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.secondary_text'))
              }
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .onClick(() => {
                if (this.folderMovePopupVisible) {
                  this.folderMovePopupVisible = false
                } else {
                  this.folderMovePopupVisible = true
                  if (!this.expandedFolderIds.includes(NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID)) {
                    this.expandedFolderIds = [
                      ...this.expandedFolderIds,
                      NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID
                    ]
                  }
                }
              })
            } else if (this.mobileFullPreviewChrome()) {
              Text(this.saveStatusDisplay())
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
            } else {
              Text(this.saveStatusDisplay())
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
            }
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

          if (this.isSplitMode() && !this.quickActionBarEnabled) {
            Row() {
              Text('图')
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

          if (!this.isSplitMode()) {
            Row({ space: 6 }) {
              if (this.previewMode === 'preview') {
                Button('编辑')
                  .fontSize($r('app.float.caption_font_size'))
                  .fontWeight(FontWeight.Medium)
                  .height(30)
                  .padding({ left: 12, right: 12 })
                  .borderRadius(18)
                  .backgroundColor(Color.Transparent)
                  .fontColor($r('app.color.accent'))
                  .border({ width: 1, color: $r('app.color.accent') })
                  .onClick(() => {
                    this.switchMode('edit')
                  })
              } else {
                Button('预览')
                  .fontSize($r('app.float.caption_font_size'))
                  .fontWeight(FontWeight.Medium)
                  .height(30)
                  .padding({ left: 12, right: 12 })
                  .borderRadius(18)
                  .backgroundColor($r('app.color.accent'))
                  .fontColor(Color.White)
                  .onClick(() => {
                    this.switchMode('preview')
                  })
                if (!this.quickActionBarEnabled) {
                  SymbolGlyph($r('sys.symbol.picture'))
                    .fontSize(22)
                    .fontColor([$r('app.color.primary_text')])
                    .margin({ right: 5, left: 5 })
                    .padding(3)
                    .onClick(() => {
                      void this.insertImage()
                    })
                }
              }
              SymbolGlyph($r('sys.symbol.share'))
                .fontSize(22)
                .fontColor([$r('app.color.primary_text')])
                .margin({ right: 5, left: 5 })
                .padding(3)
                .onClick(() => {
                  void this.runSaveLongImageToGallery()
                })
            }
            .alignItems(VerticalAlign.Center)
          }
        }
        .width('100%')
        .height($r('app.float.edit_note_toolbar_height'))
        .alignItems(VerticalAlign.Center)
        .padding({
          left: this.pageWidth >= 600 ? 24 : 6,
          right: this.pageWidth >= 600 ? 24 : 6
        })

        if (this.shouldShowQuickActionBar()) {
          EditorQuickActionBar({
            barWidthVp: this.pageWidth,
            onBeforeAction: (): void => {
              this.captureContentCaretFromSelection()
            },
            onAction: (action: EditorQuickActionType): void => {
              this.handleQuickAction(action)
            }
          })
        }

        Column({ space: $r('app.float.toolbar_spacing_content') }) {
        if (this.isSplitMode()) {
          Row({ space: 14 }) {
            NoteEditEditorPane({
              title: $title,
              content: $content,
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
        } else if (this.previewMode === 'preview') {
          Column({ space: 0 }) {
            if (this.folderModeEnabled && this.mobileFullPreviewChrome()) {
              this.buildParentPathCaption()
            }
            NoteEditPreviewPane({
              title: this.title,
              splitMode: this.isSplitMode(),
              includeTitle: true,
              showSplitTagRow: hasEditorTitleOrBody(this.title, this.content) && !this.mobileFullPreviewChrome(),
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
              .layoutWeight(1)
          }
          .layoutWeight(1)
          .width('100%')
        } else {
          NoteEditEditorPane({
            title: $title,
            content: $content,
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
        }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({
          left: this.pageWidth >= 600 ? 24 : 6,
          right: this.pageWidth >= 600 ? 24 : 6
        })
      }
      .width('100%')
      .height('100%')
      .padding({
        top: $r('app.float.toolbar_editor_page_padding_top')
      })
      .backgroundColor($r('app.color.app_background'))

      if (this.folderMovePopupVisible && this.saveStatusBarClickable()) {
        Stack({ alignContent: Alignment.TopStart }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.3)')
            .onClick(() => {
              this.folderMovePopupVisible = false
            })
          Column() {
            this.buildFolderMovePanel()
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

      // 移动端预览模式下的可拖动悬浮标签栏（编辑模式隐藏）
      if (!this.isSplitMode() && this.previewMode === 'preview' && hasEditorTitleOrBody(this.title, this.content)) {
        Stack() {
          this.buildDraggableTagBar()
        }
          .position({ x: 0, y: 0 })
          .zIndex(998)
      }

      // 移动端编辑模式下的可拖动悬浮 AI 按钮（预览模式隐藏）
      if (this.shouldShowMobileAiBar()) {
        Stack() {
          this.buildDraggableAiBar()
        }
          .position({ x: 0, y: 0 })
          .zIndex(998)
      }

      if (this.aiNoteWorking) {
        this.buildAiWorkingOverlay()
      }

      if (this.shareExportActive) {
        Scroll(this.shareScroller) {
          this.buildShareExportCard()
        }
        .id(NoteEdit.SHARE_SCROLL_ID)
        .key(`share_scroll_${this.shareExportMountKey()}`)
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        .constraintSize({ minHeight: 800 })
        .backgroundColor(this.shareExportScrollBg)
        .onAreaChange((_, value) => {
          this.shareCardHeight = Number.parseFloat(`${value.height}`) || 0
        })
        .position({ x: 0, y: 0 })
        .opacity(0.01)
        .hitTestBehavior(HitTestMode.None)
        .zIndex(10003)
      }

      if (this.sharePreviewPreparing && !this.sharePreviewVisible) {
        Stack({ alignContent: Alignment.TopStart }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.92)')
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(Color.White)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height('100%')
        .zIndex(10004)
      }

      if (this.sharePreviewVisible) {
        Column() {
          Stack({ alignContent: Alignment.TopStart }) {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(this.sharePreviewRegenerating ? 'rgba(0,0,0,0.92)' : 'rgba(0,0,0,0.55)')
            if (this.sharePreviewRegenerating) {
              Column() {
                LoadingProgress()
                  .width(40)
                  .height(40)
                  .color(Color.White)
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
            } else if (this.sharePreviewPath.length > 0) {
              Scroll() {
                Image(`file://${this.sharePreviewPath}`)
                  .width('100%')
                  .height(this.sharePreviewImageHeightVp > 0 ? this.sharePreviewImageHeightVp : '100%')
                  .objectFit(ImageFit.Contain)
                  .onComplete((event) => {
                    if (this.sharePreviewImageHeightVp > 0) {
                      return
                    }
                    const w = Number(event?.width ?? 0)
                    const h = Number(event?.height ?? 0)
                    if (w > 0 && h > 0) {
                      const previewW = Math.max(1, this.pageWidth)
                      this.sharePreviewImageHeightVp = (h / w) * previewW
                      Logger.info('NoteEdit',
                        `share preview onComplete ${w}x${h} heightVp=${this.sharePreviewImageHeightVp}`)
                    }
                  })
              }
              .scrollable(ScrollDirection.Vertical)
              .scrollBar(BarState.Off)
              .width('100%')
              .height('100%')
              .padding({ top: 48, bottom: 8 })
            }
          }
          .layoutWeight(1)
          .width('100%')
          .height('100%')

          if (this.shareOptionsSheetVisible) {
            this.buildShareOptionsSheet()
          }
        }
        .width('100%')
        .height('100%')
        .zIndex(10004)
      }
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
      if (this.aiMenuVisible) {
        this.aiMenuVisible = false
      }
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
      if ((!wasSplitMode && nextSplitMode) || this.shouldRenderPreview()) {
        this.preparePreviewForCurrentMode(this.content, true)
      }
    })
  }
}
