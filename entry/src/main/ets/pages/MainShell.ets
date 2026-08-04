import { common } from '@kit.AbilityKit'
import { fileUri } from '@kit.CoreFileKit'

import { Note, isExtractStatusPending } from '../common/model/Note'
import type { SyncResult } from '../common/model/Note'
import { NoteStateCodec } from '../common/utils/NoteStateCodec'
import { navigateToNoteEdit } from '../common/utils/NoteEditNavigation'
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
import { DashboardCalendarTab } from './dashboard/DashboardCalendarTab'
import { DashboardMineTab } from './dashboard/DashboardMineTab'

const ACCENT = '#0DAA4A'
const BLUE = '#3B82F6'
const PURPLE = '#8B5CF6'
const ORANGE = '#F59E0B'
const CARD_RADIUS = 16
const SECTION_GAP = 14
/** 同步状态条：圆角矩形（非胶囊）。 */
const SYNC_PILL_RADIUS = 10

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

@Entry
@Component
struct MainShell {
  @State shellTabIndex: number = 0
  /** 从子页返回时递增，驱动笔记 Tab 静默刷新。 */
  @State notesShellRefreshNonce: number = 0
  /** 从子页返回时递增，驱动「我的」Tab 刷新。 */
  @State mineShellRefreshNonce: number = 0
  @State pcLayout: boolean = false
  @State pageWidth: number = 360
  @State pageHeight: number = 800
  @State username: string = '轻羽'
  @State greeting: string = ''
  @State dateLine: string = ''
  @State continueEditing: DashNoteRow[] = []
  @State recentNotes: DashNoteRow[] = []
  @State noteCount: number = 0
  @State todoCount: number = 0
  @State tagCount: number = 0
  @State registrationDays: number = 0
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
        const continueNotes = byUpdated.filter((n: Note) => {
          const hiddenAt = continueHidden[n.id]
          if (hiddenAt === undefined) {
            return true
          }
          return n.updatedAt > hiddenAt
        })
        const latestNotes = byCreated.filter((n: Note) => !latestHidden.has(n.id))
        const continueRows = this.mapRows(continueNotes.slice(0, 4), true)
        const recentRows = this.mapRows(latestNotes.slice(0, 4), false)

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
          this.noteCount = notes.length
          this.todoCount = this.countTodoItems(notes)
          this.tagCount = tagSet.size
          this.continueEditing = continueRows
          this.recentNotes = recentRows
          Logger.info('DashStats',
            `APPLIED gen=${generation} notes=${notes.length} noteCount=${this.noteCount} ` +
            `todoCount=${this.todoCount} tagCount=${this.tagCount} ` +
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
        this.registrationDays = this.calcRegistrationDays(profile?.registered_at ?? '')
        Logger.info('DashStats',
          `profile name=${name.length > 0 ? name : '(empty)'} ` +
          `registered_at=${profile?.registered_at ?? '(null)'} ` +
          `registrationDays=${this.registrationDays} ` +
          `UI-bind note=${this.noteCount} todo=${this.todoCount} days=${this.registrationDays} tags=${this.tagCount}`)

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

  private mapRows(notes: Note[], useUpdated: boolean): DashNoteRow[] {
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
      row.leadingKind = this.leadingKindFor(n)
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

  /** 列表左侧图标：流程图 > mp3 波形 > wav/普通文档 > 提取中链接。 */
  private leadingKindFor(n: Note): string {
    if (n.type_ === NOTE_TYPE_FLOWCHART) {
      return 'flowchart'
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

  private calcRegistrationDays(registeredAt: string): number {
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

  /** 统计带标签 Todo 的笔记篇数（一篇待办笔记计 1）。 */
  private countTodoItems(notes: Note[]): number {
    let total = 0
    for (const n of notes) {
      if ((n.tags ?? []).some((t: string) => `${t ?? ''}`.trim() === 'Todo')) {
        total += 1
      }
    }
    return total
  }

  /** 排查用：抽样打印带标签 Todo 的笔记。 */
  private logTodoScanSample(notes: Note[]): void {
    let withFlag = 0
    let emptyContent = 0
    let logged = 0
    for (const n of notes) {
      const content = n.content ?? ''
      if (content.trim().length === 0) {
        emptyContent += 1
      }
      const hasTodoTag = (n.tags ?? []).some((t: string) => `${t ?? ''}`.trim() === 'Todo')
      if (!hasTodoTag) {
        continue
      }
      withFlag += 1
      if (logged < 3) {
        const snippet = content.replace(/\s+/g, ' ').substring(0, 80)
        Logger.info('DashStats',
          `todoSample id=${n.id} titleLen=${(n.title ?? '').length} contentLen=${content.length} snippet=${snippet}`)
        logged += 1
      }
    }
    Logger.info('DashStats',
      `todoScan notes=${notes.length} withTodoTag=${withFlag} emptyContent=${emptyContent} todoCount=${this.todoCount}`)
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
    } else if (index === 3) {
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
    await navigateToNoteEdit(this.getUIContext(), { initialAction: 'todoList' })
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
        Column() {
          this.buildDashboard()
        }
        .width('100%')
        .height('100%')
        .visibility(this.shellTabIndex === 0 ? Visibility.Visible : Visibility.None)

        DashboardNotesTab({
          visible: this.shellTabIndex === 1,
          shellRefreshNonce: this.notesShellRefreshNonce
        })
          .width('100%')
          .height('100%')
          .visibility(this.shellTabIndex === 1 ? Visibility.Visible : Visibility.None)

        DashboardCalendarTab({ visible: this.shellTabIndex === 2 })
          .width('100%')
          .height('100%')
          .visibility(this.shellTabIndex === 2 ? Visibility.Visible : Visibility.None)

        DashboardMineTab({
          visible: this.shellTabIndex === 3,
          shellRefreshNonce: this.mineShellRefreshNonce
        })
          .width('100%')
          .height('100%')
          .visibility(this.shellTabIndex === 3 ? Visibility.Visible : Visibility.None)
      }
      .width('100%')
      .layoutWeight(1)
      .linearGradient({
        angle: 180,
        colors: [
          [$r('app.color.dashboard_header_top'), 0.0],
          [$r('app.color.dashboard_header_mid'), 0.32],
          [$r('app.color.app_background'), 0.55]
        ]
      })
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
      this.tabItem(2, $r('sys.symbol.calendar'), LocaleService.loc('日历', 'Calendar', 'カレンダー'))
      this.tabItem(3, $r('sys.symbol.person'), LocaleService.loc('我的', 'Mine', 'マイページ'))
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
    .width('25%')
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
            this.quickCardAsset(LocaleService.loc('待办事项', 'To-do', 'ToDo'), '#3CB371',
              (): void => { void this.quickTodo() }, $r('app.media.ic_quick_todo'))
            this.quickCard(LocaleService.loc('知识图谱', 'Knowledge graph', '知識グラフ'), ACCENT,
              (): void => { void this.quickGraph() }, $r('sys.symbol.shareplay'))
            this.quickCardAsset(LocaleService.loc('思维导图', 'Mind map', 'マインドマップ'), ACCENT,
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
            this.quickCardFlexAsset(LocaleService.loc('待办事项', 'To-do', 'ToDo'), '#3CB371',
              (): void => { void this.quickTodo() }, $r('app.media.ic_quick_todo'))
            this.quickCardFlex(LocaleService.loc('知识图谱', 'Knowledge graph', '知識グラフ'), ACCENT,
              (): void => { void this.quickGraph() }, $r('sys.symbol.shareplay'))
            this.quickCardFlexAsset(LocaleService.loc('思维导图', 'Mind map', 'マインドマップ'), ACCENT,
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
    Row({ space: 10 }) {
      Column() {
        if (row.leadingKind === 'mp3') {
          Image($r('app.media.ic_note_mp3_wave'))
            .width(18)
            .height(18)
            .objectFit(ImageFit.Contain)
        } else if (row.leadingKind === 'flowchart') {
          SymbolGlyph($r('sys.symbol.shareplay'))
            .fontSize(18)
            .fontColor([ACCENT])
        } else if (row.leadingKind === 'extract') {
          SymbolGlyph($r('sys.symbol.link'))
            .fontSize(18)
            .fontColor([ACCENT])
        } else {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(18)
            .fontColor([ACCENT])
        }
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .borderRadius(10)
      .backgroundColor($r('app.color.surface_muted'))
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
    Column({ space: 8 }) {
      Row() {
        Text(LocaleService.loc('今日待办', "Today's todos", '今日のToDo'))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Text('3')
          .fontSize(11)
          .padding({ left: 6, right: 6 })
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius(8)
      }
      this.stubTodo(true, LocaleService.loc('完善产品设计规范', 'Finalize design specs', 'デザイン仕様を仕上げる'), '09:00')
      this.stubTodo(false, LocaleService.loc('整理会议纪要', 'Organize meeting notes', '議事録を整理'), '14:00')
      this.stubTodo(false, LocaleService.loc('准备周例会材料', 'Prepare weekly materials', '週次資料を準備'), '16:30')
      Text(LocaleService.loc('查看全部 >', 'View all >', 'すべて見る >'))
        .fontSize(13)
        .fontColor(ACCENT)
        .onClick(() => {
          this.selectTab(2)
        })
    }
    .padding(14)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .shadow({ radius: 16, color: '#14000000', offsetX: 0, offsetY: 4 })
    .width('100%')
  }

  @Builder
  stubTodo(done: boolean, title: string, time: string) {
    Row({ space: 6 }) {
      SymbolGlyph(done ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
        .fontSize(16)
        .fontColor([done ? ACCENT : $r('app.color.secondary_text')])
      Text(title)
        .fontSize(12)
        .layoutWeight(1)
        .maxLines(1)
        .decoration({ type: done ? TextDecorationType.LineThrough : TextDecorationType.None })
      Text(time)
        .fontSize(11)
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
  }

  @Builder
  scheduleCard() {
    Column({ space: 6 }) {
      Row() {
        Text(LocaleService.loc('待办日程预览', 'Schedule preview', '予定プレビュー'))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Text(LocaleService.loc('日历 >', 'Calendar >', 'カレンダー >'))
          .fontSize(13)
          .fontColor(ACCENT)
          .onClick(() => {
            this.selectTab(2)
          })
      }
      Text(`${LocaleService.loc('今天', 'Today', '今日')} ${new Date().getMonth() + 1}月${new Date().getDate()}日`)
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
      this.stubEvent(ACCENT, '09:00', LocaleService.loc('产品设计评审', 'Design review', 'デザインレビュー'))
      this.stubEvent(ORANGE, '14:00', LocaleService.loc('团队周会', 'Team standup', 'チーム定例'))
      this.stubEvent(PURPLE, '16:30', LocaleService.loc('客户沟通', 'Client call', '顧客ミーティング'))
      Text(LocaleService.loc('查看完整日程 >', 'Full schedule >', 'すべての予定 >'))
        .fontSize(13)
        .fontColor(ACCENT)
        .onClick(() => {
          this.selectTab(2)
        })
    }
    .padding(14)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .shadow({ radius: 16, color: '#14000000', offsetX: 0, offsetY: 4 })
    .width('100%')
  }

  @Builder
  stubEvent(color: string, time: string, title: string) {
    Row({ space: 6 }) {
      Circle({ width: 8, height: 8 }).fill(color)
      Text(time)
        .fontSize(11)
        .fontColor($r('app.color.secondary_text'))
      Text(title)
        .fontSize(12)
        .layoutWeight(1)
        .maxLines(1)
    }
    .width('100%')
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
        this.statCell('todos', ORANGE, $r('sys.symbol.checkmark_circle'))
        this.statCell('days', BLUE, $r('sys.symbol.calendar'))
        this.statCell('tags', PURPLE, $r('sys.symbol.label'))
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
  statCell(kind: string, color: string, symbol: Resource) {
    Column({ space: 6 }) {
      Column() {
        SymbolGlyph(symbol)
          .fontSize(22)
          .fontColor([color])
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
      // 必须在 Builder 内直接读 @State，勿经参数/间接封装，否则 UI 不刷新。
      Text(kind === 'notes' ? `${this.noteCount}` :
        (kind === 'todos' ? `${this.todoCount}` :
          (kind === 'days' ? `${this.registrationDays}` : `${this.tagCount}`)))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
      Text(kind === 'notes' ? LocaleService.loc('笔记数量', 'Notes', 'ノート数') :
        (kind === 'todos' ? LocaleService.loc('待办事项', 'To-do', 'ToDo') :
          (kind === 'days' ? LocaleService.loc('注册天数', 'Days since signup', '登録日数') :
            LocaleService.loc('标签数量', 'Tags', 'タグ数'))))
        .fontSize(11)
        .fontColor($r('app.color.secondary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  /** 统计图标底：同色系内深（80% 白混）。 */
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
}
