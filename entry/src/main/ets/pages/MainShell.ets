import { common } from '@kit.AbilityKit'
import { fileUri } from '@kit.CoreFileKit'

import { Note, isExtractStatusPending } from '../common/model/Note'
import type { SyncResult } from '../common/model/Note'
import { NoteStateCodec } from '../common/utils/NoteStateCodec'
import { navigateToNoteEdit } from '../common/utils/NoteEditNavigation'
import { navigateToTodoEditor } from '../common/utils/TodoEditorNavigation'
import { navigateToFlowchart } from '../common/utils/FlowchartNavigation'
import { IdUtils } from '../common/utils/IdUtils'
import { usePcStyleLayoutWithSize } from '../common/utils/DesktopLayout'
import {
  formatDashboardDateLine,
  greetingWithName
} from '../common/utils/GreetingAndLunar'
import { navigateToBindPhoneIfNeeded } from '../common/utils/BindPhoneNavigation'
import { maybeShowReferralInviteDialog } from '../common/utils/ReferralInviteNavigation'
import { AppContextHolder } from '../services/AppContextHolder'
import { PreferencesService } from '../services/PreferencesService'
import { NoteRepository } from '../services/NoteRepository'
import { SyncService } from '../services/SyncService'
import { FileService } from '../services/FileService'
import { SyncSettingsRemoteReport } from '../services/SyncSettingsRemoteReport'
import { LocaleService } from '../services/LocaleService'
import { NoteApiClient, type ProfileBody } from '../services/NoteApiClient'
import {
  previewQingyuForHomeSubscription,
  tryAutoProvisionQingyuCloudOnHomeEntry
} from '../services/QingyuCloudAutoProvision'
import { runAppUpdateCheckOnLaunch, recheckForceUpdateOnResume } from '../services/AppUpdateUi'
import { WebDAVClient } from '../services/WebDAVClient'
import { NOTE_TYPE_FLOWCHART } from '../common/model/FlowchartGraph'
import { Logger } from '../common/utils/Logger'
import { CryptoService } from '../services/CryptoService'
import { DashboardNotesTab } from './dashboard/DashboardNotesTab'
import { DashboardTodoTab } from './dashboard/DashboardTodoTab'
import { DashboardCalendarTab } from './dashboard/DashboardCalendarTab'
import { DashboardMineTab } from './dashboard/DashboardMineTab'
import { CalendarProjector } from './dashboard/calendar/CalendarProjector'
import type { CalendarItemKind } from './dashboard/calendar/CalendarModels'
import { FlowchartService } from '../services/FlowchartService'
import { FlowchartMindMap } from '../common/utils/FlowchartMindMap'

const ACCENT = '#0DAA4A'
const BLUE = '#3B82F6'
const PURPLE = '#8B5CF6'
const ORANGE = '#F59E0B'
const CARD_RADIUS = 16
const SECTION_GAP = 14
/** 同步状态条：圆角矩形（非胶囊）。 */
const SYNC_PILL_RADIUS = 10
/**
 * 手机端「未来待办 / 日程清单」两张卡的固定高度（vp）：不随内容多少变化，
 * 空态与 3 条内容态一样高，两张卡也始终等高。与 Flutter 端
 * `DashboardStyle.mobileAgendaCardHeight` 保持同值。
 *
 * 取值按内容最多（3 条）时两卡所需高度的较大者 + 余量：
 *   - 未来待办：14×2 卡内边距 + 20 标题 + 8 space + 3×27 待办行 + 4 底距
 *               + 18 链接 ≈ 163
 *   - 日程清单：14×2 卡内边距 + 20 标题 + 6 space + 3×25 日程行 + 4 底距
 *               + 18 链接 ≈ 155
 * PC / iPad 横屏不受影响（`pcLayout` 时不加这条约束，仍按内容自适应）。
 */
const MOBILE_AGENDA_CARD_HEIGHT = 184
/** 「未来待办 / 日程清单」卡的内边距（vp）。 */
const AGENDA_CARD_PADDING = 14

class DashNoteRow {
  id: string = ''
  title: string = ''
  snippet: string = ''
  timeLabel: string = ''
  isFlowchart: boolean = false
  /** flowchart | mp3 | extract | document */
  leadingKind: string = 'document'
  thumbUri: string = ''
  openWithPreview: boolean = false
  updatedAt: number = 0

  updatedKey(): string {
    return `${this.timeLabel}|${this.title}|${this.thumbUri.length}|${this.leadingKind}|${this.updatedAt}`
  }
}

/** 「未来待办 / 日程清单」卡专用：复用了 title / timeLabel，
 * 不需要 snippet / leadingKind / thumbUri。 */
class DashAgendaRow {
  id: string = ''
  title: string = ''
  /** todo 卡：HH:mm；schedule 卡：HH:mm-HHmm。 */
  timeLabel: string = ''
  isDone: boolean = false
  /** schedule 卡左侧小圆点颜色（HEX）。todo 卡恒为空字符串。 */
  dotColor: string = ''
}

@Entry
@Component
struct MainShell {
  @State shellTabIndex: number = 0
  /** 从子页返回时递增，驱动笔记 Tab 静默刷新。 */
  @State notesShellRefreshNonce: number = 0
  /** 从子页返回时递增，驱动「我的」Tab 刷新。 */
  @State mineShellRefreshNonce: number = 0
  /** 从子页返回时递增，驱动待办 Tab 静默刷新（与笔记 Tab 同一事件，独立 nonce 便于各自演进）。 */
  @State todoShellRefreshNonce: number = 0
  @State pcLayout: boolean = false
  @State pageWidth: number = 360
  @State pageHeight: number = 800
  @State username: string = '轻羽'
  @State greeting: string = ''
  @State dateLine: string = ''
  @State continueEditing: DashNoteRow[] = []
  @State recentNotes: DashNoteRow[] = []
  @State upcomingTodos: DashAgendaRow[] = []
  @State upcomingSchedules: DashAgendaRow[] = []
  @State noteCount: number = 0
  @State todoCount: number = 0
  @State tagCount: number = 0
  @State graphCount: number = 0
  @State cloudConfigured: boolean = true
  @State syncing: boolean = false
  @State lastSyncMs: number = 0
  @State syncTitle: string = ''
  @State syncSubtitle: string = ''
  @State syncAction: string = ''
  @State syncDetail: string = ''
  @State syncProgress: number = 0
  @StorageLink('appLocaleRevision') localeRevision: number = 0
  private startupSyncHandled: boolean = false
  private filesDir: string = ''
  /** bootstrap 完成前忽略 onPageShow 触发的刷新，避免与首启竞态。 */
  private bootstrapReady: boolean = false
  /** 丢弃过期的 reloadDashboard 结果，防止慢请求覆盖新数据。 */
  private reloadGeneration: number = 0
  /** 串行化 reload，避免 onAreaChange / onPageShow / bootstrap 并发互相冲掉列表。 */
  private reloadChain: Promise<void> = Promise.resolve()
  /** 已预扫的「思维导图」笔记 id 集合（`.qy` 边车
   * `metadata.layoutMode == 'mindMapLinear'`），用于让首页 / 笔记 / 日历
   * 三个 tab 的 leading icon 区分思维导图（蓝）与知识图谱（绿）。 */
  private mindMapNoteIds: Set<string> = new Set()

  aboutToAppear(): void {
    AppContextHolder.setLastUiContext(this.getUIContext())
    Logger.info('DashHomeLoad', 'aboutToAppear -> bootstrap')
    void this.bootstrap()
  }

  onPageShow(): void {
    void recheckForceUpdateOnResume(this.getUIContext())
    if (!this.bootstrapReady) {
      Logger.info('DashHomeLoad', 'onPageShow skipped (bootstrap not ready)')
      return
    }
    Logger.info('DashHomeLoad', 'onPageShow -> reloadDashboard + notes/mine refresh')
    this.notesShellRefreshNonce += 1
    this.mineShellRefreshNonce += 1
    this.todoShellRefreshNonce += 1
    // 兜底：同步写一次 AppStorage 刷新信号。待办 Tab 的 @StorageLink('appShellRefreshNonce')
    //  watcher 依赖它；编辑页内自动保存完成时写入的信号可能赶在 MainShell 被覆盖期间触发，
    // 被 ArkUI 吞掉，这里在页面回到前台时补一次，保证待办列表一定拿到刷新触发。
    try {
      const cur = (AppStorage.get('appShellRefreshNonce') as number | undefined) ?? 0
      AppStorage.setOrCreate('appShellRefreshNonce', cur + 1)
    } catch (_) {
    }
    void this.reloadDashboard()
  }

  private async bootstrap(): Promise<void> {
    const t0 = Date.now()
    Logger.info('DashHomeLoad', `bootstrap start t=${t0}`)
    const context = AppContextHolder.tryGetContext()
    Logger.info('DashHomeLoad',
      `bootstrap context=${context ? 'ok' : 'null'} filesDirHint=${context ? ((context as common.UIAbilityContext).filesDir ?? '') : ''}`)
    if (context) {
      await PreferencesService.getInstance().init(context)
      this.filesDir = (context as common.UIAbilityContext).filesDir ?? ''
      try {
        await CryptoService.getInstance().init()
        Logger.info('DashHomeLoad', `CryptoService.init ok +${Date.now() - t0}ms`)
      } catch (e) {
        Logger.error('MainShell', `CryptoService.init failed: ${JSON.stringify(e)}`)
      }
      try {
        await NoteRepository.getInstance().init(context)
        await SyncService.getInstance().init()
        Logger.info('DashHomeLoad',
          `repo/sync init ok +${Date.now() - t0}ms notesDir=${FileService.getInstance().getNotesBaseDir()}`)
      } catch (e) {
        Logger.error('MainShell', `repo/sync init failed: ${JSON.stringify(e)}`)
      }
      NoteRepository.getInstance().invalidateCachesForIdentityChange()
      Logger.info('DashHomeLoad',
        `caches invalidated notesVersion=${NoteRepository.getInstance().getNotesVersion()}`)
    }
    await LocaleService.getInstance().load(context ?? undefined)
    await this.reloadDashboard()
    Logger.info('DashHomeLoad',
      `after first reload continue=${this.continueEditing.length} recent=${this.recentNotes.length} ` +
      `noteCount=${this.noteCount} +${Date.now() - t0}ms`)

    await tryAutoProvisionQingyuCloudOnHomeEntry()
    Logger.info('DashHomeLoad', `autoProvision done +${Date.now() - t0}ms`)
    await SyncSettingsRemoteReport.getInstance().reportCurrentIfPossible()

    const runSync = !this.startupSyncHandled && await this.shouldRunStartupSync()
    Logger.info('DashHomeLoad',
      `shouldRunStartupSync=${runSync} handled=${this.startupSyncHandled} +${Date.now() - t0}ms`)
    if (runSync) {
      this.startupSyncHandled = true
      await this.runStartupSync()
      Logger.info('DashHomeLoad',
        `startup sync finished continue=${this.continueEditing.length} recent=${this.recentNotes.length} ` +
        `noteCount=${this.noteCount} +${Date.now() - t0}ms`)
    }

    await runAppUpdateCheckOnLaunch(this.getUIContext())
    void navigateToBindPhoneIfNeeded(this.getUIContext())
    void maybeShowReferralInviteDialog(this.getUIContext())
    await this.reloadDashboard()
    if (this.continueEditing.length === 0 && this.recentNotes.length === 0) {
      Logger.info('DashHomeLoad', 'still empty after bootstrap sync path, retry after 400ms')
      await new Promise<void>((resolve) => setTimeout(resolve, 400))
      NoteRepository.getInstance().discardCachedNoteLists()
      await this.reloadDashboard()
      Logger.info('DashHomeLoad',
        `retry result continue=${this.continueEditing.length} recent=${this.recentNotes.length} noteCount=${this.noteCount}`)
    }
    this.bootstrapReady = true
    Logger.info('DashHomeLoad',
      `bootstrap ready continue=${this.continueEditing.length} recent=${this.recentNotes.length} ` +
      `noteCount=${this.noteCount} total=+${Date.now() - t0}ms`)
  }

  private async shouldRunStartupSync(): Promise<boolean> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    // 与 Index.shouldRunStartupSync 对齐，避免未配 WebDAV 时空转，或条件过宽导致异常路径。
    if (!(await PreferencesService.getInstance().canRunCloudSync())) {
      Logger.info('DashHomeLoad', 'shouldRunStartupSync=false (canRunCloudSync)')
      return false
    }
    const config = await PreferencesService.getInstance().getWebDAVConfig()
    if (!config || !config.enabled) {
      Logger.info('DashHomeLoad', 'shouldRunStartupSync=false (webdav disabled/null)')
      return false
    }
    const authInvalid = await PreferencesService.getInstance().isAuthInvalid()
    Logger.info('DashHomeLoad', `shouldRunStartupSync authInvalid=${authInvalid}`)
    return !authInvalid
  }

  private async runStartupSync(): Promise<void> {
    this.syncing = true
    this.refreshSyncCopy()
    try {
      Logger.info('DashHomeLoad', 'runStartupSync syncNow begin')
      const results = await SyncService.getInstance().syncNow()
      Logger.info('DashHomeLoad',
        `runStartupSync syncNow done results=${results.length} ` +
        `fail=${results.filter((r: SyncResult) => !r.success).length}`)
    } catch (e) {
      Logger.error('MainShell', `startup sync failed: ${JSON.stringify(e)}`)
    } finally {
      this.syncing = false
      NoteRepository.getInstance().discardCachedNoteLists()
      await this.reloadDashboard()
    }
  }

  private async reloadDashboard(): Promise<void> {
    const run = async (): Promise<void> => {
      const generation = ++this.reloadGeneration
      const t0 = Date.now()
      Logger.info('DashHomeLoad',
        `reloadDashboard start gen=${generation} pc=${this.pcLayout} bootstrapReady=${this.bootstrapReady}`)
      try {
        const context = AppContextHolder.tryGetContext()
        if (context) {
          await NoteRepository.getInstance().init(context)
        } else {
          await NoteRepository.getInstance().init()
        }
        if (generation !== this.reloadGeneration) {
          Logger.info('DashHomeLoad', `reloadDashboard abort after init gen=${generation} cur=${this.reloadGeneration}`)
          return
        }
        NoteRepository.getInstance().discardCachedNoteLists()
        const notes = await NoteRepository.getInstance().listNotes()
        if (generation !== this.reloadGeneration) {
          Logger.info('DashHomeLoad',
            `reloadDashboard abort after listNotes gen=${generation} cur=${this.reloadGeneration} ` +
            `notesWouldBe=${notes.length}`)
          return
        }
        const storedTags = await PreferencesService.getInstance().getNoteTags()
        const tagSet = new Set<string>()
        for (const n of notes) {
          for (const t of n.tags) {
            if (t.trim().length > 0) {
              tagSet.add(t.trim())
            }
          }
        }
        for (const t of storedTags) {
          if (t.trim().length > 0) {
            tagSet.add(t.trim())
          }
        }
        const byUpdated = notes.slice().sort((a: Note, b: Note) => b.updatedAt - a.updatedAt)
        const byCreated = notes.slice().sort((a: Note, b: Note) => b.createdAt - a.createdAt)
        const continueHiddenRaw = await PreferencesService.getInstance().getDashHomeContinueHidden()
        const continueHidden = await this.pruneContinueHidden(notes, continueHiddenRaw)
        const latestHiddenList = await PreferencesService.getInstance().getDashHomeLatestHidden()
        const latestHidden = new Set<string>(latestHiddenList)
        // 一次性预扫描所有 flowchart 笔记，识别「思维导图」子集。
        // 区分思维导图（蓝）与知识图谱（绿）的关键数据。
        const mindMapIds = await this.detectMindMapNoteIds(notes)
        this.mindMapNoteIds = mindMapIds
        const continueNotes = byUpdated.filter((n: Note) => {
          const hiddenAt = continueHidden[n.id]
          if (hiddenAt === undefined) {
            return true
          }
          return n.updatedAt > hiddenAt
        })
        const latestNotes = byCreated.filter((n: Note) => !latestHidden.has(n.id))
        const continueRows = this.mapRows(continueNotes.slice(0, 4), true, mindMapIds)
        const recentRows = this.mapRows(latestNotes.slice(0, 4), false, mindMapIds)
        // 「未来待办 / 日程清单」卡：复用日历周视图投影（已应用 isTodo=1
        // startTime/endTime 与 isTodo=2 todoDue-1h 的渲染规则）。
        //   - 日程清单卡：今天及之后所有未完成的 schedule occurrences，
        //     按 anchorMs 升序、最多 3 条；跨度可超过一天。
        //   - 未来待办卡：今天及之后所有未完成的 todo occurrences，按 anchorMs
        //     升序、最多 3 条；跨度可超过一天。
        const today = new Date()
        const todayY = today.getFullYear()
        const todayM = today.getMonth() + 1
        const todayD = today.getDate()
        const upcomingSchedules = this.mapAgendaRows(
          this.upcomingScheduleOccurrences(CalendarProjector.projectNotes(notes), 3),
          'schedule'
        )
        const upcomingTodos = this.mapAgendaRows(
          this.upcomingTodoOccurrences(CalendarProjector.projectNotes(notes), 3),
          'todo'
        )

        if (generation !== this.reloadGeneration) {
          Logger.info('DashHomeLoad',
            `reloadDashboard abort before apply gen=${generation} cur=${this.reloadGeneration} ` +
            `continueWouldBe=${continueRows.length} recentWouldBe=${recentRows.length}`)
          return
        }
        // 防止过期的空结果覆盖已展示的非空列表（并发 reload 常见）。
        if (continueRows.length === 0 && recentRows.length === 0 &&
          (this.continueEditing.length > 0 || this.recentNotes.length > 0) &&
          notes.length === 0) {
          Logger.warn('DashHomeLoad',
            `reloadDashboard skip empty overwrite gen=${generation} keep continue=${this.continueEditing.length}`)
        } else {
          // 笔记数量 = 全部笔记数 - 流程图（思维导图 + 知识图谱）数量。
          const nonFlowchartCount = notes.filter((n: Note) => n.type_ !== NOTE_TYPE_FLOWCHART).length
          // 「图谱」数量 = 思维导图 + 知识图谱（即 type_ == NOTE_TYPE_FLOWCHART 笔记总数）。
          const graphCount = notes.filter((n: Note) => n.type_ === NOTE_TYPE_FLOWCHART).length
          this.noteCount = nonFlowchartCount
          this.todoCount = await this.countTodoAndScheduleItems(notes)
          this.tagCount = tagSet.size
          this.graphCount = graphCount
          this.continueEditing = continueRows
          this.recentNotes = recentRows
          this.upcomingTodos = upcomingTodos
          this.upcomingSchedules = upcomingSchedules
          Logger.info('DashStats',
            `APPLIED gen=${generation} notes=${notes.length} noteCount=${this.noteCount} ` +
            `todoCount=${this.todoCount} tagCount=${this.tagCount} graphCount=${this.graphCount} ` +
            `continue=${continueRows.length} recent=${recentRows.length} +${Date.now() - t0}ms`)
          this.logTodoScanSample(notes)
        }

        let profile: ProfileBody | null = null
        try {
          const cachedRaw = await PreferencesService.getInstance().getCachedUserProfile()
          const cached = cachedRaw !== null ? cachedRaw as ProfileBody : null
          profile = cached
          const remote = await NoteApiClient.getInstance().fetchProfile()
          if (remote !== null) {
            profile = remote
          }
        } catch (_) {
        }
        if (generation !== this.reloadGeneration) {
          return
        }
        const name = (profile?.username ?? '').trim()
        this.username = name.length > 0 ? name : LocaleService.loc('轻羽', 'Qingyu', 'QingYu')
        Logger.info('DashStats',
          `profile name=${name.length > 0 ? name : '(empty)'} ` +
          `UI-bind note=${this.noteCount} todo=${this.todoCount} tags=${this.tagCount} graphCount=${this.graphCount}`)

        this.cloudConfigured = await this.resolveCloudConfigured()
        if (generation !== this.reloadGeneration) {
          return
        }
        this.lastSyncMs = await PreferencesService.getInstance().getLastSyncTime()
        this.greeting = greetingWithName(this.username)
        this.dateLine = formatDashboardDateLine(new Date())
        this.refreshSyncCopy()
        Logger.info('DashHomeLoad',
          `reloadDashboard finish gen=${generation} cloudConfigured=${this.cloudConfigured} ` +
          `lastSyncMs=${this.lastSyncMs} +${Date.now() - t0}ms`)
      } catch (e) {
        Logger.error('MainShell', `reloadDashboard failed: ${JSON.stringify(e)}`)
      }
    }
    const next = this.reloadChain.then(run, run)
    this.reloadChain = next.then(() => {}, () => {})
    await next
  }

  private mapRows(notes: Note[], useUpdated: boolean, mindMapNoteIds: Set<string> = new Set()): DashNoteRow[] {
    const rows: DashNoteRow[] = []
    for (const n of notes) {
      const row = new DashNoteRow()
      row.id = n.id
      row.title = n.title.trim().length > 0 ? n.title.trim() :
        LocaleService.loc('无标题', 'Untitled', '無題')
      const sn = n.summary.trim().length > 0 ? n.summary.trim() : n.content.trim()
      row.snippet = sn.replace(/\s+/g, ' ')
      const ms = useUpdated ? n.updatedAt : n.createdAt
      row.timeLabel = this.relativeTime(ms)
      row.isFlowchart = n.type_ === NOTE_TYPE_FLOWCHART
      row.leadingKind = this.leadingKindFor(n, mindMapNoteIds)
      row.openWithPreview = n.content.trim().length > 0
      row.updatedAt = n.updatedAt
      const refs = NoteStateCodec.extractImageRefs(n.content)
      if (refs.length > 0 && this.filesDir.length > 0) {
        const parts = refs[0].split('/')
        const fileName = parts[parts.length - 1]
        const full = `${this.filesDir}/qingyu-note-image/${fileName}`
        try {
          row.thumbUri = fileUri.getUriFromPath(full)
        } catch (_) {
          row.thumbUri = ''
        }
      }
      rows.push(row)
    }
    return rows
  }

  /**
   * 把日历投影后的 occurrence 映射成首页「未来待办 / 日程清单」卡的数据行。
   * - todo: timeLabel = endMs 的 HH:mm，dotColor 留空（圆点用 ORANGE，但用整行 done 状态区分）。
   * - schedule: 当天 → HH:mm-HHmm；其它日期 → X月X日（隐藏具体时间），dotColor = PURPLE。
   */
  private mapAgendaRows(
    occurrences: import('./dashboard/calendar/CalendarModels').CalendarOccurrence[],
    kind: CalendarItemKind
  ): DashAgendaRow[] {
    const now = new Date()
    const todayY = now.getFullYear()
    const todayM = now.getMonth() + 1
    const todayD = now.getDate()
    const rows: DashAgendaRow[] = []
    for (const o of occurrences) {
      if (o.kind !== kind) {
        continue
      }
      const row = new DashAgendaRow()
      row.id = o.noteId
      const trimmedTitle = (o.note.title ?? '').trim()
      row.title = trimmedTitle.length > 0 ? trimmedTitle :
        LocaleService.loc('无标题', 'Untitled', '無題')
      row.isDone = (o.note.todoCompleted ?? 0) !== 0
      if (kind === 'schedule') {
        if (o.dayY === todayY && o.dayM === todayM && o.dayD === todayD) {
          row.timeLabel = `${this.hhmm(o.anchorMs)}-${this.hhmm(o.endMs)}`
        } else {
          // 未来日：只展示日期，不展示具体时间。
          row.timeLabel = `${o.dayM}月${o.dayD}日`
        }
        row.dotColor = PURPLE
      } else {
        row.timeLabel = this.hhmm(o.endMs)
        row.dotColor = ''
      }
      rows.push(row)
    }
    return rows
  }

  /**
   * 「未来待办」卡专用：从所有 occurrence 中挑出今天及以后、未完成的 todo 项。
   *
   * 规则：
   *   1. `kind === 'todo'`（含 isTodo=2 与带 `Todo` 兼容 tag 的旧笔记）；
   *   2. `note.todoCompleted === 0`（未完成；兼容字段，逻辑同首页其它卡片）；
   *   3. `endMs >= todayMs`（结束时间在今天 00:00 之后；含今天 + 未来）；
   *   4. 按 `anchorMs` 升序、时间越早越靠上；
   *   5. 最多 `limit` 条。
   *
   * 与三端 Flutter `dashboard_loader.dart::_upcomingTodoOccurrences` 等价。
   */
  private upcomingTodoOccurrences(
    occurrences: import('./dashboard/calendar/CalendarModels').CalendarOccurrence[],
    limit: number
  ): import('./dashboard/calendar/CalendarModels').CalendarOccurrence[] {
    const now = new Date()
    const todayMs = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
    const filtered: import('./dashboard/calendar/CalendarModels').CalendarOccurrence[] = []
    for (let i = 0; i < occurrences.length; i++) {
      const o = occurrences[i]
      if (o.kind !== 'todo') {
        continue
      }
      if ((o.note.todoCompleted ?? 0) !== 0) {
        continue
      }
      if (o.endMs < todayMs) {
        continue
      }
      filtered.push(o)
    }
    filtered.sort((a, b) => {
      if (a.anchorMs !== b.anchorMs) {
        return a.anchorMs - b.anchorMs
      }
      return a.noteId.localeCompare(b.noteId)
    })
    return filtered.length > limit ? filtered.slice(0, limit) : filtered
  }

  /**
   * 「日程清单」卡专用：从所有 occurrence 中挑出今天及以后、未结束的 schedule 项。
   *
   * 规则：
   *   1. `kind === 'schedule'`（isTodo=1 + tag Schedule 的笔记）；
   *   2. `endMs >= todayMs`（结束时间在今天 00:00 之后；含今天 + 未来）；
   *   3. 按 `anchorMs` 升序、时间越早越靠上；
   *   4. 最多 `limit` 条。
   *
   * 与三端 Flutter `dashboard_loader.dart::_upcomingScheduleOccurrences` 等价。
   */
  private upcomingScheduleOccurrences(
    occurrences: import('./dashboard/calendar/CalendarModels').CalendarOccurrence[],
    limit: number
  ): import('./dashboard/calendar/CalendarModels').CalendarOccurrence[] {
    const now = new Date()
    const todayMs = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
    const filtered: import('./dashboard/calendar/CalendarModels').CalendarOccurrence[] = []
    for (let i = 0; i < occurrences.length; i++) {
      const o = occurrences[i]
      if (o.kind !== 'schedule') {
        continue
      }
      if (o.endMs < todayMs) {
        continue
      }
      filtered.push(o)
    }
    filtered.sort((a, b) => {
      if (a.anchorMs !== b.anchorMs) {
        return a.anchorMs - b.anchorMs
      }
      return a.noteId.localeCompare(b.noteId)
    })
    return filtered.length > limit ? filtered.slice(0, limit) : filtered
  }

  private hhmm(ms: number): string {
    if (ms <= 0) {
      return ''
    }
    const dt = new Date(ms)
    return `${dt.getHours().toString().padStart(2, '0')}:${dt.getMinutes().toString().padStart(2, '0')}`
  }

  private relativeTime(ms: number): string {
    if (ms <= 0) {
      return ''
    }
    const dt = new Date(ms)
    const hm =
      `${dt.getHours().toString().padStart(2, '0')}:${dt.getMinutes().toString().padStart(2, '0')}`
    const now = new Date()
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
    const that = new Date(dt.getFullYear(), dt.getMonth(), dt.getDate()).getTime()
    const diff = Math.floor((today - that) / 86400000)
    if (diff === 0) {
      return `${LocaleService.loc('今天', 'Today', '今日')} ${hm}`
    }
    if (diff === 1) {
      return `${LocaleService.loc('昨天', 'Yesterday', '昨日')} ${hm}`
    }
    return `${dt.getMonth() + 1}月${dt.getDate()}日`
  }

  /** 列表左侧图标：思维导图 > 知识图谱 > 待办 > 日程 > mp3 波形 > wav/普通文档 > 提取中链接。 */
  private leadingKindFor(n: Note, mindMapNoteIds: Set<string> = new Set()): string {
    // 待办 / 日程沿用日历 tab 列表中的样式；放最前避免被流程图分支吞掉。
    if (n.isTodo === 2) {
      return 'todo'
    }
    if (n.isTodo === 1) {
      return 'schedule'
    }
    if (n.type_ === NOTE_TYPE_FLOWCHART) {
      // 流程图需要根据 `.qy` 边车里的 `layoutMode` 区分思维导图 / 知识图谱；
      // 集合由 detectMindMapNoteIds 预扫填充，命中即为思维导图。
      if (mindMapNoteIds.has(n.id)) {
        return 'flowchart'
      }
      return 'knowledgeGraph'
    }
    const audio = `${n.audioId ?? ''}`.trim().toLowerCase()
    if (audio.endsWith('.mp3')) {
      return 'mp3'
    }
    if (audio.endsWith('.wav')) {
      return 'document'
    }
    if (isExtractStatusPending(n.extractStatus)) {
      return 'extract'
    }
    return 'document'
  }

  private async pruneContinueHidden(
    notes: Note[],
    continueHidden: Record<string, number>
  ): Promise<Record<string, number>> {
    const keys = Object.keys(continueHidden)
    if (keys.length === 0) {
      return continueHidden
    }
    const byId = new Map<string, Note>()
    for (const n of notes) {
      byId.set(n.id, n)
    }
    const next: Record<string, number> = {}
    let changed = false
    for (const id of keys) {
      const hiddenAt = continueHidden[id]
      const note = byId.get(id)
      if (note === undefined) {
        changed = true
        continue
      }
      if (note.updatedAt > hiddenAt) {
        changed = true
        continue
      }
      next[id] = hiddenAt
    }
    if (changed) {
      await PreferencesService.getInstance().setDashHomeContinueHidden(next)
      return next
    }
    return continueHidden
  }

  /**
   * 统计「待办事项 + 待办日程」总数。
   *
   * 规则：笔记隐藏字段 `is_todo` 不为 0（参考 CLAUDE.md
   * 「日历日程 / 待办事项 隐藏字段规则」），且不是流程图、也不是思维导图。
   * 流程图直接按 `type_ === NOTE_TYPE_FLOWCHART` 过滤；思维导图是流程图中
   * `metadata.layoutMode == 'mindMapLinear'` 的子集，需要解析 `.qy` 边车
   * 才能识别，所以单独再走 `FlowchartService.load`。
   *
   * 只对「命中 is_todo 的流程图」按需加载 `.qy`，避免对所有流程图都做磁盘 IO。
   */
  private async countTodoAndScheduleItems(notes: Note[]): Promise<number> {
    let total = 0
    for (const n of notes) {
      const isTodo = (n.isTodo ?? 0) !== 0 ? 1 : 0
      if (isTodo !== 1) {
        continue
      }
      if (n.type_ === NOTE_TYPE_FLOWCHART) {
        // 流程图（包括思维导图）都不计入；其中思维导图要额外 `.qy` 解析。
        try {
          const graph = await FlowchartService.getInstance().load(n.id)
          if (FlowchartMindMap.isMindMapMode(graph)) {
            continue
          }
        } catch (e) {
          // 解析失败 / 边车缺失 → 当流程图排除。
          Logger.warn('MainShell', `countTodo mindMap load failed: ${JSON.stringify(e)}`)
          continue
        }
        continue
      }
      total += 1
    }
    return total
  }

  /**
   * 扫描所有 flowchart 笔记，收集处于「思维导图」模式（`.qy` 边车
   * `metadata.layoutMode == 'mindMapLinear'`）的 note id 集合。
   * 仅对 `type_ === NOTE_TYPE_FLOWCHART` 的笔记做磁盘 IO；非流程图直接跳过。
   * 解析失败时（边车缺失 / 损坏）按流程图处理（即不进入集合），
   * 保证首页 / 笔记 / 日历三端 leading icon 不会卡死。
   */
  private async detectMindMapNoteIds(notes: Note[]): Promise<Set<string>> {
    const result = new Set<string>()
    for (const n of notes) {
      if (n.type_ !== NOTE_TYPE_FLOWCHART) {
        continue
      }
      try {
        const graph = await FlowchartService.getInstance().load(n.id)
        if (FlowchartMindMap.isMindMapMode(graph)) {
          result.add(n.id)
        }
      } catch (e) {
        // 解析失败时保持知识图谱语义，不影响其它笔记。
      }
    }
    return result
  }

  /** 排查用：抽样打印命中「is_todo 不为 0」的笔记，与新版 todoCount 规则同步。 */
  private logTodoScanSample(notes: Note[]): void {
    let withFlag = 0
    let emptyContent = 0
    let logged = 0
    for (const n of notes) {
      const content = n.content ?? ''
      if (content.trim().length === 0) {
        emptyContent += 1
      }
      const isTodo = ((n.isTodo ?? 0) !== 0)
      if (!isTodo) {
        continue
      }
      withFlag += 1
      if (logged < 3) {
        const snippet = content.replace(/\s+/g, ' ').substring(0, 80)
        Logger.info('DashStats',
          `todoSample id=${n.id} isTodo=${n.isTodo ?? 0} type_=${n.type_} ` +
          `titleLen=${(n.title ?? '').length} contentLen=${content.length} snippet=${snippet}`)
        logged += 1
      }
    }
    Logger.info('DashStats',
      `todoScan notes=${notes.length} withIsTodo=${withFlag} emptyContent=${emptyContent} todoCount=${this.todoCount}`)
  }

  private async resolveCloudConfigured(): Promise<boolean> {
    try {
      if (await PreferencesService.getInstance().hasEnabledCustomWebDAVConfig()) {
        return true
      }
      const status =
        await WebDAVClient.getInstance().fetchQingyuCloudSubscriptionStatus(previewQingyuForHomeSubscription)
      return status.kind === 'lifetime' || status.kind === 'active'
    } catch (_) {
      return false
    }
  }

  private refreshSyncCopy(): void {
    if (!this.cloudConfigured) {
      this.syncTitle = LocaleService.loc('尚未开启云同步', 'Cloud sync not enabled', 'クラウド同期未設定')
      this.syncSubtitle = LocaleService.loc('尚未同步过', 'Never synced', '未同期')
      this.syncAction = LocaleService.loc('去配置', 'Set up', '設定へ')
      this.syncDetail = LocaleService.loc('已完成', 'Done', '完了')
      this.syncProgress = 0
      return
    }
    if (this.syncing) {
      this.syncTitle = LocaleService.loc('正在同步', 'Syncing', '同期中')
      this.syncSubtitle =
        LocaleService.loc('正在上传与下载笔记…', 'Uploading and downloading notes…', 'ノートを送受信中…')
      this.syncAction = LocaleService.loc('同步中…', 'Syncing…', '同期中…')
      this.syncDetail = LocaleService.loc('进行中', 'In progress', '進行中')
      this.syncProgress = 0.5
      return
    }
    this.syncTitle = LocaleService.loc('云端同步正常', 'Cloud sync OK', 'クラウド同期正常')
    this.syncSubtitle = this.formatLastSync(this.lastSyncMs)
    this.syncAction = LocaleService.loc('立即同步', 'Sync now', '今すぐ同期')
    this.syncDetail = LocaleService.loc('已完成', 'Done', '完了')
    this.syncProgress = this.lastSyncMs > 0 ? 1 : 0
  }

  private formatLastSync(ms: number): string {
    if (ms <= 0) {
      return LocaleService.loc('尚未同步过', 'Never synced', '未同期')
    }
    const dt = new Date(ms)
    const hm =
      `${dt.getHours().toString().padStart(2, '0')}:${dt.getMinutes().toString().padStart(2, '0')}`
    const now = new Date()
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
    const that = new Date(dt.getFullYear(), dt.getMonth(), dt.getDate()).getTime()
    const diff = Math.floor((today - that) / 86400000)
    if (diff === 0) {
      return `${LocaleService.loc('上次同步：今天', 'Last sync: today', '前回同期：今日')} ${hm}`
    }
    if (diff === 1) {
      return `${LocaleService.loc('上次同步：昨天', 'Last sync: yesterday', '前回同期：昨日')} ${hm}`
    }
    return `${LocaleService.loc('上次同步：', 'Last sync: ', '前回同期：')}${dt.getMonth() + 1}月${dt.getDate()}日 ${hm}`
  }

  private selectTab(index: number): void {
    this.shellTabIndex = index
    if (index === 0) {
      void this.reloadDashboard()
    } else if (index === 4) {
      this.mineShellRefreshNonce += 1
    }
  }

  private async onSyncAction(): Promise<void> {
    if (!this.cloudConfigured) {
      await this.getUIContext().getRouter().pushUrl({ url: 'pages/CloudSyncSettings' })
      return
    }
    if (this.syncing) {
      return
    }
    this.syncing = true
    this.refreshSyncCopy()
    try {
      await SyncService.getInstance().syncNow()
    } catch (_) {
    } finally {
      this.syncing = false
      await this.reloadDashboard()
    }
  }

  private async openNote(row: DashNoteRow): Promise<void> {
    if (row.isFlowchart) {
      await navigateToFlowchart(this.getUIContext(), { noteId: row.id })
      void this.reloadDashboard()
      return
    }
    const note = await NoteRepository.getInstance().getNote(row.id)
    if (note === null) {
      await navigateToNoteEdit(this.getUIContext(), {
        noteId: row.id,
        openWithPreview: row.openWithPreview
      })
      void this.reloadDashboard()
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
      } catch (e) {
        Logger.error('MainShell', `open LinkExtractProgress failed: ${JSON.stringify(e)}`)
      }
      void this.reloadDashboard()
      return
    }
    if (`${note.audioId ?? ''}`.trim().length > 0) {
      try {
        await this.getUIContext().getRouter().pushUrl({
          url: 'pages/VoiceNoteDetail',
          params: { noteId: note.id }
        })
      } catch (e) {
        Logger.error('MainShell', `open VoiceNoteDetail failed: ${JSON.stringify(e)}`)
      }
      void this.reloadDashboard()
      return
    }
    await navigateToNoteEdit(this.getUIContext(), {
      noteId: note.id,
      openWithPreview: `${note.content ?? ''}`.trim().length > 0
    })
    void this.reloadDashboard()
  }

  private async removeFromDashList(row: DashNoteRow, fromContinue: boolean): Promise<void> {
    if (fromContinue) {
      await PreferencesService.getInstance().hideDashHomeContinueNote(row.id, row.updatedAt)
    } else {
      await PreferencesService.getInstance().hideDashHomeLatestNote(row.id)
    }
    await this.reloadDashboard()
  }

  private async deleteDashNote(row: DashNoteRow): Promise<void> {
    try {
      await NoteRepository.getInstance().deleteNote(row.id, Date.now())
      await PreferencesService.getInstance().clearDashHomeHiddenForNote(row.id)
      try {
        this.getUIContext().getPromptAction().showToast({
          message: LocaleService.loc('已删除', 'Deleted', '削除しました'),
          duration: 2500
        })
      } catch (_) {
      }
      await this.reloadDashboard()
    } catch (e) {
      Logger.error('MainShell', `deleteDashNote failed: ${JSON.stringify(e)}`)
      try {
        this.getUIContext().getPromptAction().showToast({
          message: LocaleService.loc('删除失败', 'Delete failed', '削除失敗'),
          duration: 2500
        })
      } catch (_) {
      }
    }
  }

  private async quickWrite(): Promise<void> {
    await navigateToNoteEdit(this.getUIContext(), {})
  }

  private async quickVoice(): Promise<void> {
    await this.getUIContext().getRouter().pushUrl({ url: 'pages/VoiceNote' })
  }

  private async quickLink(): Promise<void> {
    await this.getUIContext().getRouter().pushUrl({ url: 'pages/LinkExtract' })
  }

  private async quickImage(): Promise<void> {
    await navigateToNoteEdit(this.getUIContext(), { initialAction: 'generateNoteFromImage' })
  }

  private async quickTodo(): Promise<void> {
    await navigateToTodoEditor(this.getUIContext(), {})
  }

  private async quickBook(): Promise<void> {
    await navigateToNoteEdit(this.getUIContext(), { initialAction: 'bookScan' })
  }

  private async quickGraph(): Promise<void> {
    await navigateToFlowchart(this.getUIContext(), { noteId: IdUtils.uuid() })
  }

  private async quickMindMap(): Promise<void> {
    await navigateToFlowchart(this.getUIContext(), {
      noteId: IdUtils.uuid(),
      initialMindMap: true
    })
  }

  build() {
    Column() {
      // 与 Flutter IndexedStack 一致：Tab 保活，避免切回笔记页反复销毁重建并闪「加载中」。
      Stack() {
        // 首页 tab：保留自上而下的绿色渐变背景。
        Column() {
          this.buildDashboard()
        }
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [
            [$r('app.color.dashboard_header_top'), 0.0],
            [$r('app.color.dashboard_header_mid'), 0.32],
            [$r('app.color.app_background'), 0.55]
          ]
        })
        .visibility(this.shellTabIndex === 0 ? Visibility.Visible : Visibility.None)

        // 笔记 / 待办 / 日历 / 我的 tab：背景固定纯白（参考 Flutter PC 端，对齐
        // card_background #FFFFFFFF），不再使用 app_background 浅灰，也不叠首页的渐变绿。
        DashboardNotesTab({
          visible: this.shellTabIndex === 1,
          shellRefreshNonce: this.notesShellRefreshNonce
        })
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.card_background'))
          .visibility(this.shellTabIndex === 1 ? Visibility.Visible : Visibility.None)

        DashboardTodoTab({
          visible: this.shellTabIndex === 2,
          shellRefreshNonce: this.todoShellRefreshNonce
        })
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.card_background'))
          .visibility(this.shellTabIndex === 2 ? Visibility.Visible : Visibility.None)

        DashboardCalendarTab({ visible: this.shellTabIndex === 3 })
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.card_background'))
          .visibility(this.shellTabIndex === 3 ? Visibility.Visible : Visibility.None)

        DashboardMineTab({
          visible: this.shellTabIndex === 4,
          shellRefreshNonce: this.mineShellRefreshNonce
        })
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.card_background'))
          .visibility(this.shellTabIndex === 4 ? Visibility.Visible : Visibility.None)
      }
      .width('100%')
      .layoutWeight(1)
      this.buildBottomBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_old, area) => {
      const w = Number(area.width)
      const h = Number(area.height)
      this.pageWidth = w
      this.pageHeight = h
      const next = usePcStyleLayoutWithSize(w, h)
      if (next !== this.pcLayout) {
        Logger.info('DashHomeLoad', `onAreaChange pcLayout ${this.pcLayout} -> ${next}, reload`)
        this.pcLayout = next
        void this.reloadDashboard()
      }
    })
  }

  @Builder
  buildBottomBar() {
    Row() {
      this.tabItem(0, $r('sys.symbol.house'), LocaleService.loc('首页', 'Home', 'ホーム'))
      this.tabItem(1, $r('sys.symbol.doc_text'), LocaleService.loc('笔记', 'Notes', 'ノート'))
      // 待办 tab 用自定义 SVG（app.media.ic_quick_todo），按选中态切色，文字也跟着选中态。
      this.tabItemImage(2, $r('app.media.ic_quick_todo'), LocaleService.loc('待办', 'Todos', 'ToDo'))
      this.tabItem(3, $r('sys.symbol.calendar'), LocaleService.loc('日历', 'Calendar', 'カレンダー'))
      this.tabItem(4, $r('sys.symbol.person'), LocaleService.loc('我的', 'Mine', 'マイページ'))
    }
    .width('100%')
    .height(64)
    .padding({ bottom: 4 })
    .backgroundColor($r('app.color.card_background'))
    .border({ width: { top: 1 }, color: '#470DAA4A' })
  }

  @Builder
  tabItem(index: number, symbol: Resource, label: string) {
    Column({ space: 2 }) {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor([this.shellTabIndex === index ? ACCENT : $r('app.color.secondary_text')])
      Text(label)
        .fontSize(11)
        .fontColor(this.shellTabIndex === index ? ACCENT : $r('app.color.secondary_text'))
    }
    .width('20%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.selectTab(index)
    })
  }

  /** 待办 tab 专用：用 Image 渲染 app.media.ic_quick_todo（与首页「待办事项」快捷卡片同图），
   * SVG 用 fill=currentColor，fillColor 跟随选中态：选中=ACCENT(#0DAA4A)，未选=secondary_text(#6B7280)。 */
  @Builder
  tabItemImage(index: number, icon: Resource, label: string) {
    Column({ space: 2 }) {
      Image(icon)
        .width(22)
        .height(22)
        .objectFit(ImageFit.Contain)
        .fillColor(this.shellTabIndex === index ? ACCENT : $r('app.color.secondary_text'))
      Text(label)
        .fontSize(11)
        .fontColor(this.shellTabIndex === index ? ACCENT : $r('app.color.secondary_text'))
    }
    .width('20%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.selectTab(index)
    })
  }

  @Builder
  buildDashboard() {
    Scroll() {
      Column({ space: SECTION_GAP }) {
        this.buildHeader()
        this.buildQuickCreate()
        if (this.pcLayout) {
          this.buildPcBody()
        } else {
          this.buildMobileBody()
        }
      }
      .padding({
        left: this.pcLayout ? 24 : 16,
        right: this.pcLayout ? 24 : 16,
        top: 12,
        bottom: 24
      })
      .width('100%')
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  buildHeader() {
    if (this.pcLayout) {
      Row() {
        Column({ space: 4 }) {
          Text(this.greeting)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          Text(this.dateLine)
            .fontSize(13)
            .fontColor($r('app.color.secondary_text'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        this.buildPcSyncCard()
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(22)
          .fontColor([$r('app.color.secondary_text')])
          .margin({ left: 8 })
      }
      .width('100%')
    } else {
      Row() {
        Column({ space: 4 }) {
          Text(this.greeting)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          Text(this.dateLine)
            .fontSize(13)
            .fontColor($r('app.color.secondary_text'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Column({ space: 2 }) {
          Text(this.syncTitle)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(ACCENT)
          Text(this.syncSubtitle)
            .fontSize(10)
            .fontColor($r('app.color.secondary_text'))
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(SYNC_PILL_RADIUS)
        .shadow({ radius: 10, color: '#14000000', offsetX: 0, offsetY: 3 })
        .onClick(() => {
          void this.onSyncAction()
        })
      }
      .width('100%')
    }
  }

  @Builder
  buildPcSyncCard() {
    Row({ space: 8 }) {
      Progress({ value: this.syncProgress * 100, total: 100, type: ProgressType.Ring })
        .width(40)
        .height(40)
        .color(ACCENT)
      Column({ space: 2 }) {
        Text(this.syncTitle)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
        Text(this.syncSubtitle)
          .fontSize(10)
          .fontColor($r('app.color.secondary_text'))
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(this.syncAction)
        .fontSize(12)
        .fontColor(ACCENT)
    }
    .width(260)
    .padding(12)
    .borderRadius(14)
    .backgroundColor($r('app.color.card_background'))
    .shadow({ radius: 12, color: '#14000000', offsetX: 0, offsetY: 3 })
    .onClick(() => {
      void this.onSyncAction()
    })
  }

  @Builder
  buildQuickCreate() {
    Column() {
      if (this.pcLayout) {
        Scroll() {
          Row({ space: 10 }) {
            this.quickCard(LocaleService.loc('写笔记', 'Write note', 'ノート作成'), ACCENT,
              (): void => { void this.quickWrite() }, $r('sys.symbol.square_and_pencil'))
            this.quickCard(LocaleService.loc('语音笔记', 'Voice note', '音声ノート'), '#34C759',
              (): void => { void this.quickVoice() }, $r('sys.symbol.mic'))
            this.quickCard(LocaleService.loc('链接导入', 'Import link', 'リンク取込'), '#2BB673',
              (): void => { void this.quickLink() }, $r('sys.symbol.link'))
            this.quickCard(LocaleService.loc('照片笔记', 'Photo note', '写真ノート'), '#1FA85A',
              (): void => { void this.quickImage() }, $r('sys.symbol.picture'))
            this.quickCardAsset(LocaleService.loc('纸书记录', 'Paper book', '紙の本'), ACCENT,
              (): void => { void this.quickBook() }, $r('app.media.ic_quick_book'))
            this.quickCardAsset(LocaleService.loc('待办事项', 'To-do', 'ToDo'), ACCENT,
              (): void => { void this.quickTodo() }, $r('app.media.ic_quick_todo'))
            this.quickCardAsset(LocaleService.loc('知识图谱', 'Knowledge graph', '知識グラフ'), PURPLE,
              (): void => { void this.quickGraph() }, $r('app.media.ic_note_knowledge_graph'))
            this.quickCardAsset(LocaleService.loc('思维导图', 'Mind map', 'マインドマップ'), PURPLE,
              (): void => { void this.quickMindMap() }, $r('app.media.ic_quick_mindmap'))
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
      } else {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            this.quickCardFlex(LocaleService.loc('写笔记', 'Write note', 'ノート作成'), ACCENT,
              (): void => { void this.quickWrite() }, $r('sys.symbol.square_and_pencil'))
            this.quickCardFlex(LocaleService.loc('语音笔记', 'Voice note', '音声ノート'), '#34C759',
              (): void => { void this.quickVoice() }, $r('sys.symbol.mic'))
            this.quickCardFlex(LocaleService.loc('链接导入', 'Import link', 'リンク取込'), '#2BB673',
              (): void => { void this.quickLink() }, $r('sys.symbol.link'))
            this.quickCardFlex(LocaleService.loc('照片笔记', 'Photo note', '写真ノート'), '#1FA85A',
              (): void => { void this.quickImage() }, $r('sys.symbol.picture'))
          }
          .width('100%')
          Row({ space: 8 }) {
            this.quickCardFlexAsset(LocaleService.loc('纸书记录', 'Paper book', '紙の本'), ACCENT,
              (): void => { void this.quickBook() }, $r('app.media.ic_quick_book'))
            this.quickCardFlexAsset(LocaleService.loc('待办事项', 'To-do', 'ToDo'), ACCENT,
              (): void => { void this.quickTodo() }, $r('app.media.ic_quick_todo'))
            this.quickCardFlexAsset(LocaleService.loc('知识图谱', 'Knowledge graph', '知識グラフ'), PURPLE,
              (): void => { void this.quickGraph() }, $r('app.media.ic_note_knowledge_graph'))
            this.quickCardFlexAsset(LocaleService.loc('思维导图', 'Mind map', 'マインドマップ'), PURPLE,
              (): void => { void this.quickMindMap() }, $r('app.media.ic_quick_mindmap'))
          }
          .width('100%')
        }
        .width('100%')
      }
    }
    .padding(14)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .shadow({ radius: 16, color: '#14000000', offsetX: 0, offsetY: 4 })
    .width('100%')
  }

  @Builder
  quickCard(label: string, color: string, onTap: () => void, symbol: Resource) {
    Column({ space: 6 }) {
      SymbolGlyph(symbol)
        .fontSize(26)
        .fontColor([color])
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(76)
    .padding({ top: 10, bottom: 10 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(14)
    .backgroundColor($r('app.color.card_background'))
    .shadow({ radius: 10, color: '#0F000000', offsetX: 0, offsetY: 3 })
    .onClick(onTap)
  }

  @Builder
  quickCardAsset(label: string, color: string, onTap: () => void, icon: Resource) {
    Column({ space: 6 }) {
      Image(icon)
        .width(26)
        .height(26)
        .objectFit(ImageFit.Contain)
        .fillColor(color)
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(76)
    .padding({ top: 10, bottom: 10 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(14)
    .backgroundColor($r('app.color.card_background'))
    .shadow({ radius: 10, color: '#0F000000', offsetX: 0, offsetY: 3 })
    .onClick(onTap)
  }

  @Builder
  quickCardFlex(label: string, color: string, onTap: () => void, symbol: Resource) {
    Column({ space: 6 }) {
      SymbolGlyph(symbol)
        .fontSize(24)
        .fontColor([color])
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 10 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(14)
    .backgroundColor($r('app.color.card_background'))
    .shadow({ radius: 10, color: '#0F000000', offsetX: 0, offsetY: 3 })
    .onClick(onTap)
  }

  @Builder
  quickCardFlexAsset(label: string, color: string, onTap: () => void, icon: Resource) {
    Column({ space: 6 }) {
      Image(icon)
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .fillColor(color)
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 10 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(14)
    .backgroundColor($r('app.color.card_background'))
    .shadow({ radius: 10, color: '#0F000000', offsetX: 0, offsetY: 3 })
    .onClick(onTap)
  }

  @Builder
  buildMobileBody() {
    Column({ space: 16 }) {
      this.noteSection('continue', false)
      this.todoScheduleRow()
      this.noteSection('recent', true)
      this.statsCard()
    }
    .width('100%')
  }

  @Builder
  buildPcBody() {
    Row({ space: 16 }) {
      Column({ space: 16 }) {
        this.noteSection('continue', false)
      }
      .layoutWeight(4)
      Column({ space: 12 }) {
        this.todoCard()
        this.scheduleCard()
      }
      .layoutWeight(3)
      Column({ space: 16 }) {
        this.noteSection('recent', false)
        this.statsCard()
      }
      .layoutWeight(3)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  /**
   * 注意：不要把 @State 数组作为 @Builder 参数传入，否则状态更新后 ForEach 不刷新
   *（日志里 continue=4 但 UI 仍显示空，进旧首页返回才刷新，就是这个原因）。
   */
  @Builder
  noteSection(kind: string, showThumb: boolean) {
    Column({ space: 4 }) {
      Row() {
        Text(kind === 'continue' ?
          LocaleService.loc('最近编辑', 'Recently edited', '最近の編集') :
          LocaleService.loc('最新笔记', 'Latest notes', '最新のノート'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Text(LocaleService.loc('全部笔记 >', 'All notes >', 'すべてのノート >'))
          .fontSize(13)
          .fontColor(ACCENT)
          .onClick(() => {
            this.selectTab(1)
          })
      }
      .width('100%')
      .margin({ bottom: 4 })
      if (kind === 'continue') {
        if (this.continueEditing.length === 0) {
          Text(LocaleService.loc('暂无笔记', 'No notes yet', 'ノートがありません'))
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
            .margin({ top: 12, bottom: 12 })
        } else {
          ForEach(this.continueEditing, (row: DashNoteRow) => {
            this.noteRow(row, showThumb, true)
          }, (row: DashNoteRow) => `c-${row.id}-${row.updatedKey()}`)
        }
      } else {
        if (this.recentNotes.length === 0) {
          Text(LocaleService.loc('暂无笔记', 'No notes yet', 'ノートがありません'))
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
            .margin({ top: 12, bottom: 12 })
        } else {
          ForEach(this.recentNotes, (row: DashNoteRow) => {
            this.noteRow(row, showThumb, false)
          }, (row: DashNoteRow) => `r-${row.id}-${row.updatedKey()}`)
        }
      }
    }
    .padding(14)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .shadow({ radius: 16, color: '#14000000', offsetX: 0, offsetY: 4 })
    .width('100%')
  }

  @Builder
  dashNoteContextMenu(row: DashNoteRow, fromContinue: boolean) {
    Menu() {
      MenuItem({
        content: fromContinue ?
          LocaleService.loc('从最近编辑列表移除', 'Remove from recently edited', '最近の編集から削除') :
          LocaleService.loc('从最新笔记列表移除', 'Remove from latest notes', '最新ノートから削除')
      })
        .onClick(() => {
          void this.removeFromDashList(row, fromContinue)
        })
      MenuItem({
        content: LocaleService.loc('编辑笔记', 'Edit note', 'ノートを編集')
      })
        .onClick(() => {
          void this.openNote(row)
        })
      MenuItem({
        content: LocaleService.loc('删除笔记', 'Delete note', 'ノートを削除')
      })
        .onClick(() => {
          void this.deleteDashNote(row)
        })
    }
  }

  @Builder
  noteRow(row: DashNoteRow, showThumb: boolean, fromContinue: boolean) {
    // 与笔记统计卡 stat 同款 80% → 95% 白色径向渐变。
    // 与笔记 tab noteTileBody 对齐：边框与图标本身同色（4 种语义笔记按类型上色）。
    Row({ space: 10 }) {
      Column() {
        if (row.leadingKind === 'mp3') {
          // mp3 音频笔记：图标复用笔记统计卡「图谱」旧版（sys.symbol.shareplay），按主题 accent 绿色上色，
          // 三个 tab（首页 / 笔记 / 日历）共用。
          SymbolGlyph($r('sys.symbol.shareplay'))
            .fontSize(18)
            .fontColor([ACCENT])
        } else if (row.leadingKind === 'flowchart') {
          // 思维导图：与首页快捷创建卡「思维导图」入口同图，三个 tab 共用紫色。
          Image($r('app.media.ic_quick_mindmap'))
            .width(18)
            .height(18)
            .objectFit(ImageFit.Contain)
            .fillColor(this.noteLeadingColor(row.leadingKind))
        } else if (row.leadingKind === 'knowledgeGraph') {
          // 知识图谱：图一 SVG，三个 tab 共用紫色。
          Image($r('app.media.ic_note_knowledge_graph'))
            .width(18)
            .height(18)
            .objectFit(ImageFit.Contain)
            .fillColor(this.noteLeadingColor(row.leadingKind))
        } else if (row.leadingKind === 'todo') {
          // 待办事项：与首页快捷创建卡「待办事项」入口同图（ic_quick_todo.svg），三个 tab 共用橙色。
          Image($r('app.media.ic_quick_todo'))
            .width(18)
            .height(18)
            .objectFit(ImageFit.Contain)
            .fillColor(this.noteLeadingColor(row.leadingKind))
        } else if (row.leadingKind === 'schedule') {
          // 待办日程：三个 tab 共用紫色。
          SymbolGlyph($r('sys.symbol.calendar'))
            .fontSize(18)
            .fontColor([this.noteLeadingColor(row.leadingKind)])
        } else if (row.leadingKind === 'extract') {
          SymbolGlyph($r('sys.symbol.link'))
            .fontSize(18)
            .fontColor([this.noteLeadingColor(row.leadingKind)])
        } else {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(18)
            .fontColor([this.noteLeadingColor(row.leadingKind)])
        }
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .borderRadius(10)
      // 边框与图标本身同色（与笔记 tab 保持一致语义，4 种语义笔记按类型上色）。
      .border({ width: 1.2, color: this.noteLeadingColor(row.leadingKind) })
      // 中心到边缘的径向渐变（与首页 tab 笔记统计卡 stat 同款 80% → 95% 白色）。
      .radialGradient({
        center: [20, 20],
        radius: 24,
        colors: [
          [this.noteRowSoftInner(row.leadingKind), 0.0],
          [this.noteRowSoftOuter(row.leadingKind), 1.0]
        ]
      })
      Column({ space: 3 }) {
        Text(row.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(row.snippet)
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(row.timeLabel)
        .fontSize(11)
        .fontColor($r('app.color.secondary_text'))
      if (showThumb && row.thumbUri.length > 0) {
        Image(row.thumbUri)
          .width(52)
          .height(40)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .margin({ left: 8 })
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .onClick(() => {
      void this.openNote(row)
    })
    .bindContextMenu(this.dashNoteContextMenu(row, fromContinue), ResponseType.LongPress)
  }

  /**
   * 「未来待办 / 日程清单」卡的高度约束：
   *   - 手机端：min = max = MOBILE_AGENDA_CARD_HEIGHT，锁成固定高度，
   *     两张卡等高且不随内容条数变化；
   *   - PC / iPad 横屏：返回空约束，维持原来的内容自适应高度。
   */
  private agendaCardConstraint(): ConstraintSizeOptions {
    if (this.pcLayout) {
      // minHeight 0 = 不加约束，等价于原来的内容自适应高度。
      return { minHeight: 0 }
    }
    return { minHeight: MOBILE_AGENDA_CARD_HEIGHT, maxHeight: MOBILE_AGENDA_CARD_HEIGHT }
  }

  /**
   * 卡片正文 Column 的高度约束。外层 Stack 是 `Alignment.BottomStart`
   * （为了把入口链接钉到左下角），正文 Column 若按内容高度收缩，就会被
   * 一起压到卡片底部——标题悬空、正文和链接重叠。
   *
   * 所以手机端把正文 Column 的 minHeight 撑到卡片内容区高度
   * （固定高 − 上下 padding），让它填满 Stack，子元素自然从顶部开始排；
   * PC / iPad 横屏 Stack 本就是内容高，不需要也不能撑（无确定父高）。
   */
  private agendaCardBodyConstraint(): ConstraintSizeOptions {
    if (this.pcLayout) {
      return { minHeight: 0 }
    }
    return { minHeight: MOBILE_AGENDA_CARD_HEIGHT - AGENDA_CARD_PADDING * 2 }
  }

  @Builder
  todoScheduleRow() {
    Row({ space: 10 }) {
      Column() {
        this.todoCard()
      }
      .layoutWeight(1)
      Column() {
        this.scheduleCard()
      }
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  todoCard() {
    // 标题上下左右内边距与「最近编辑」标题一致：
    //   - 移动端：LTRB(0,0,0,0)
    //   - PC / iPad 横屏：LTRB(6,6,6,0)
    // 内容部分在标题对齐基础上左右各 +8vp。
    Stack({ alignContent: Alignment.BottomStart }) {
      Column({ space: 8 }) {
        Row() {
          Text(LocaleService.loc('未来待办', 'Future todos', '未来のToDo'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
          Text(`${this.upcomingTodos.length}`)
            .fontSize(11)
            .padding({ left: 6, right: 6 })
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius(8)
        }
        .padding({ left: this.pcLayout ? 6 : 0, right: this.pcLayout ? 6 : 0, top: this.pcLayout ? 6 : 0 })
        .width('100%')
        // 内容部分：在标题对齐基础上，左右各 +8vp；底部预留足够空间，
        // 避免和底部钉住的「查看全部」链接重叠。
        Column() {
          if (this.upcomingTodos.length === 0) {
            Text(LocaleService.loc('暂无待办', 'No todos', 'ToDoなし'))
              .fontSize(12)
              .fontColor($r('app.color.secondary_text'))
              .padding({ top: 12, bottom: 12 })
              .width('100%')
          } else {
            ForEach(this.upcomingTodos, (row: DashAgendaRow) => {
              this.todoRow(row)
            }, (row: DashAgendaRow) => `upcoming-todo-${row.id}-${row.isDone}`)
          }
        }
        .padding({ left: (this.pcLayout ? 6 : 0) + 8, right: (this.pcLayout ? 6 : 0) + 8, bottom: 4 })
        .width('100%')
      }
      .width('100%')
      // 撑满卡片内容区，避免被 BottomStart 的 Stack 压到底部（标题必须贴顶）。
      .constraintSize(this.agendaCardBodyConstraint())
      // 入口链接：钉到卡片左下角；左边距 = 标题 L（PC 6 / 移动 0），
      // 下边距 = 标题 T（与标题距离卡片顶部一致，视觉与标题顶对齐）。
      Text(LocaleService.loc('查看全部 >', 'View all >', 'すべて見る >'))
        .fontSize(13)
        .fontColor(ACCENT)
        .padding({ left: this.pcLayout ? 6 : 0, bottom: this.pcLayout ? 6 : 0 })
        .onClick(() => {
          this.selectTab(2)
        })
    }
    .padding(14)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .shadow({ radius: 16, color: '#14000000', offsetX: 0, offsetY: 4 })
    .width('100%')
    // 手机端锁死高度，与「日程清单」卡等高且不随待办条数变化。
    .constraintSize(this.agendaCardConstraint())
  }

  @Builder
  todoRow(row: DashAgendaRow) {
    Row({ space: 6 }) {
      SymbolGlyph(row.isDone ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
        .fontSize(16)
        .fontColor([row.isDone ? ACCENT : $r('app.color.secondary_text')])
      Text(row.title)
        .fontSize(12)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .decoration({ type: row.isDone ? TextDecorationType.LineThrough : TextDecorationType.None })
      Text(row.timeLabel)
        .fontSize(11)
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
  }

  @Builder
  scheduleCard() {
    // 标题上下左右内边距与「最近编辑」标题一致：
    //   - 移动端：LTRB(0,0,0,0)
    //   - PC / iPad 横屏：LTRB(6,6,6,0)
    // 内容部分在标题对齐基础上左右各 +8vp。
    Stack({ alignContent: Alignment.BottomStart }) {
      Column({ space: 6 }) {
        Text(LocaleService.loc('日程清单', 'Schedule list', '予定一覧'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .width('100%')
        // 标题应用与「最近编辑」一致的上下左右内边距。
        .padding({ left: this.pcLayout ? 6 : 0, right: this.pcLayout ? 6 : 0, top: this.pcLayout ? 6 : 0 })
        // 内容部分：在标题对齐基础上，左右各 +8vp；底部预留足够空间，
        // 避免和底部钉住的「查看完整日程」链接重叠。
        Column() {
          if (this.upcomingSchedules.length === 0) {
            Text(LocaleService.loc('暂无日程', 'No schedule', '予定なし'))
              .fontSize(12)
              .fontColor($r('app.color.secondary_text'))
              .padding({ top: 24, bottom: 24 })
              .width('100%')
          } else {
            ForEach(this.upcomingSchedules, (row: DashAgendaRow) => {
              this.scheduleRow(row)
            }, (row: DashAgendaRow) => `upcoming-sched-${row.id}-${row.timeLabel}`)
          }
        }
        .padding({ left: (this.pcLayout ? 6 : 0) + 8, right: (this.pcLayout ? 6 : 0) + 8, bottom: 4 })
        .width('100%')
      }
      .width('100%')
      // 撑满卡片内容区，避免被 BottomStart 的 Stack 压到底部（标题必须贴顶）。
      .constraintSize(this.agendaCardBodyConstraint())
      // 入口链接：钉到卡片左下角；左边距 = 标题 L（PC 6 / 移动 0），
      // 下边距 = 标题 T（与标题距离卡片顶部一致，视觉与标题顶对齐）。
      Text(LocaleService.loc('查看完整日程 >', 'Full schedule >', 'すべての予定 >'))
        .fontSize(13)
        .fontColor(ACCENT)
        .padding({ left: this.pcLayout ? 6 : 0, bottom: this.pcLayout ? 6 : 0 })
        .onClick(() => {
          this.selectTab(2)
        })
    }
    .padding(14)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .shadow({ radius: 16, color: '#14000000', offsetX: 0, offsetY: 4 })
    .width('100%')
    // 手机端锁死高度，与「未来待办」卡等高且不随日程条数变化。
    .constraintSize(this.agendaCardConstraint())
  }

  @Builder
  scheduleRow(row: DashAgendaRow) {
    Row({ space: 6 }) {
      Circle({ width: 8, height: 8 }).fill(row.dotColor.length > 0 ? row.dotColor : PURPLE)
      Text(row.timeLabel)
        .fontSize(11)
        .fontColor($r('app.color.secondary_text'))
      Text(row.title)
        .fontSize(12)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  syncStatusCard() {
    Row({ space: 16 }) {
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.icloud'))
            .fontSize(20)
            .fontColor([ACCENT])
          Text(this.syncTitle)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
        }
        Text(this.syncSubtitle)
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
        Progress({ value: this.syncProgress * 100, total: 100, type: ProgressType.Linear })
          .height(6)
          .color(ACCENT)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Column({ space: 4 }) {
        this.syncDetailRow(LocaleService.loc('笔记同步', 'Notes sync', 'ノート同期'))
        this.syncDetailRow(LocaleService.loc('资源文件', 'Media files', 'メディア'))
        this.syncDetailRow(LocaleService.loc('知识图谱', 'Knowledge graph', '知識グラフ'))
      }
    }
    .padding(14)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .shadow({ radius: 16, color: '#14000000', offsetX: 0, offsetY: 4 })
    .width('100%')
  }

  @Builder
  syncDetailRow(label: string) {
    Row({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
        .fontSize(12)
        .fontColor([ACCENT])
      Text(label)
        .fontSize(11)
      Text(this.syncDetail)
        .fontSize(11)
        .fontColor($r('app.color.secondary_text'))
    }
  }

  /**
   * 注意：不要把 @State 数值/数组作为 @Builder 参数传入，否则状态更新后 Text 不刷新
   *（统计卡会一直显示初始 0；与 noteSection 空列表同根因）。
   */
  @Builder
  statsCard() {
    Column({ space: 16 }) {
      Text(LocaleService.loc('笔记统计', 'Note stats', 'ノート統計'))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
        .textAlign(TextAlign.Start)
      Row() {
        this.statCell('notes', ACCENT, $r('sys.symbol.doc_text'))
        // 待办图标：与首页快捷创建卡「待办事项」入口同图（ic_quick_todo.svg）。
        this.statCell('todos', ORANGE, $r('sys.symbol.checkmark_circle'), $r('app.media.ic_quick_todo'))
        // 图谱图标：与笔记 tab 日历 tab 「知识图谱」笔记同图（ic_note_knowledge_graph.svg）。
        this.statCell('graphs', PURPLE, $r('sys.symbol.shareplay'), $r('app.media.ic_note_knowledge_graph'))
        this.statCell('tags', BLUE, $r('sys.symbol.label'))
      }
      .width('100%')
    }
    .padding(14)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .shadow({ radius: 16, color: '#14000000', offsetX: 0, offsetY: 4 })
    .width('100%')
  }

  @Builder
  statCell(kind: string, color: string, symbol: Resource, svgRes?: Resource) {
    Column({ space: 6 }) {
      Column() {
        if (svgRes) {
          // SVG 图标（fill="currentColor"）可被 fillColor 整体着色，
          // 与 SymbolGlyph 同尺寸 22，避免圆形底径向渐变偏移。
          Image(svgRes)
            .width(22)
            .height(22)
            .objectFit(ImageFit.Contain)
            .fillColor(color)
        } else {
          SymbolGlyph(symbol)
            .fontSize(22)
            .fontColor([color])
        }
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .borderRadius(22)
      .radialGradient({
        center: [22, 22],
        radius: 22,
        colors: [
          [this.statSoftInner(color), 0.0],
          [this.statSoftOuter(color), 1.0]
        ]
      })
      .onClick(() => {
        this.handleStatTap(kind)
      })
      // 必须在 Builder 内直接读 @State，勿经参数/间接封装，否则 UI 不刷新。
      Text(kind === 'notes' ? `${this.noteCount}` :
        (kind === 'todos' ? `${this.todoCount}` :
          (kind === 'graphs' ? `${this.graphCount}` : `${this.tagCount}`)))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
      Text(kind === 'notes' ? LocaleService.loc('笔记', 'Notes', 'ノート') :
        (kind === 'todos' ? LocaleService.loc('待办', 'To-do', 'ToDo') :
          (kind === 'graphs' ? LocaleService.loc('图谱', 'Graphs', 'グラフ') :
            LocaleService.loc('标签', 'Tags', 'タグ'))))
        .fontSize(11)
        .fontColor($r('app.color.secondary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 笔记统计卡四个图标的点击分发：
   *   notes / graphs → 笔记 Tab；todos → 待办 Tab；tags → 标签管理页。
   * 与 Flutter `dashboard_home_page.dart` 同名回调语义保持一致。
   */
  private handleStatTap(kind: string): void {
    if (kind === 'notes') {
      this.selectTab(1)
      return
    }
    if (kind === 'todos') {
      this.selectTab(2)
      return
    }
    if (kind === 'graphs') {
      this.selectTab(1)
      return
    }
    if (kind === 'tags') {
      void this.openTagManageFromStats()
    }
  }

  private async openTagManageFromStats(): Promise<void> {
    try {
      await this.getUIContext().getRouter().pushUrl({ url: 'pages/TagManage' })
      void this.reloadDashboard()
    } catch (e) {
      Logger.warn('MainShell', `openTagManage failed: ${JSON.stringify(e)}`)
    }
  }

  /** 统计图标底：同色系内深（80% 白混）。 */
  /**
   * 笔记列表 leading icon 的「主色」：与首页 / 笔记 / 日历三个 tab 共用，
   * 4 种语义图标（思维导图 / 知识图谱 / 待办 / 日程）使用对应主题色，
   * 其它类型（mp3 / 提取中链接 / 普通文档）走主题 accent。
   * 用于外层 icon 盒子的径向渐变底色（与笔记统计卡 stat 同款）。
   */
  private noteLeadingColor(leadingKind: string): string {
    if (leadingKind === 'flowchart') {
      // 思维导图：与日历 tab 图例一致，三个 tab 视觉同源（紫 #8B5CF6）。
      return PURPLE
    }
    // 知识图谱：与日历 tab 图例一致，三个 tab 视觉同源（紫 #8B5CF6）。
    if (leadingKind === 'knowledgeGraph') {
      return PURPLE
    }
    if (leadingKind === 'todo') {
      return ORANGE
    }
    if (leadingKind === 'schedule') {
      // 待办日程与待办事项共用同一抹橙（与 todo 完全一致），三个 tab 视觉同源。
      return ORANGE
    }
    return ACCENT
  }

  private statSoftInner(color: string): string {
    if (color === ACCENT) {
      return '#CFEEDB'
    }
    if (color === ORANGE) {
      return '#FDECCE'
    }
    if (color === BLUE) {
      return '#D8E6FD'
    }
    if (color === PURPLE) {
      return '#E8DEFD'
    }
    return `${color}33`
  }

  /** 统计图标底：同色系外浅（95% 白混）。 */
  private statSoftOuter(color: string): string {
    if (color === ACCENT) {
      return '#F3FBF6'
    }
    if (color === ORANGE) {
      return '#FFFAF3'
    }
    if (color === BLUE) {
      return '#F5F9FF'
    }
    if (color === PURPLE) {
      return '#F9F7FF'
    }
    return `${color}0D`
  }

  /** 笔记列表 icon 盒子径向渐变内层（按 leadingKind 分支）。 */
  private noteRowSoftInner(leadingKind: string): string {
    // 思维导图 / 知识图谱共用紫色（与日历 tab 图例一致 = #8B5CF6），
    // 共用紫色径向渐变内/外圈，保持三个 tab 视觉同源。
    if (leadingKind === 'flowchart' || leadingKind === 'knowledgeGraph') {
      return '#E8DEFD'
    }
    if (leadingKind === 'todo') {
      return '#FDECCE'
    }
    if (leadingKind === 'schedule') {
      // 待办日程与待办事项共用 todo 同款橙色径向渐变底色。
      return '#FDECCE'
    }
    return '#CFEEDB'
  }

  /** 笔记列表 icon 盒子径向渐变外层（按 leadingKind 分支）。 */
  private noteRowSoftOuter(leadingKind: string): string {
    if (leadingKind === 'flowchart' || leadingKind === 'knowledgeGraph') {
      return '#F9F7FF'
    }
    if (leadingKind === 'todo') {
      return '#FFFAF3'
    }
    if (leadingKind === 'schedule') {
      // 待办日程与待办事项共用 todo 同款橙色径向渐变底色。
      return '#FFFAF3'
    }
    return '#F3FBF6'
  }
}
