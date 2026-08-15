export type SyncStatus = 'synced' | 'pending' | 'conflict' | 'error'

/** 异步链接提取任务状态。 */
export type ExtractStatus =
  | 'none'
  | 'queued'
  | 'running'
  | 'succeeded'
  | 'failed'
  | 'partial'

export const EXTRACT_STATUS_VALUES: ExtractStatus[] = [
  'none',
  'queued',
  'running',
  'succeeded',
  'failed',
  'partial'
]

export type VoiceTranscribeStatus = 'none' | 'running' | 'succeeded' | 'failed'

export const VOICE_TRANSCRIBE_STATUS_VALUES: VoiceTranscribeStatus[] = [
  'none',
  'running',
  'succeeded',
  'failed'
]

export function isExtractStatusPending(s: ExtractStatus): boolean {
  return s === 'queued' || s === 'running'
}

export function isExtractStatusTerminal(s: ExtractStatus): boolean {
  return s === 'succeeded' || s === 'failed' || s === 'partial'
}

export interface NoteStateBlock {
  id: string
  title: string
  tags: string[]
  parentId: string
  createdAt: number
  updatedAt: number
  isConflict: number
  latitude: number
  longitude: number
  altitude: number
  author: string
  sourceUrl: string
  /** 是否收藏：0/1，写入 NOTE_STATE `is_favorite`。 */
  isFavorite: number
  /** 笔记类型：0 普通 / 1 日程 / 2 待办，写入 NOTE_STATE `is_todo`。 */
  isTodo: number
  todoDue: number
  todoCompleted: number
  /**
   * 待办优先级：0=无, 1=低, 2=中, 3=高, 4=紧急，写入 NOTE_STATE `todo_priority`。
   */
  todoPriority: number
  /**
   * 待办状态：0=进行中, 1=已完成，写入 NOTE_STATE `todo_status`。
   * 与 [todoCompleted]（兼容旧字段）并存，新建待办以本字段为准。
   */
  todoStatus: number
  /**
   * 待办提醒提前分钟数：0=不提醒, 否则提前 N 分钟（基于 [todoDue]/[endTime]），
   * 写入 NOTE_STATE `todo_reminder_minutes`。
   */
  todoReminderMinutes: number
  /**
   * 日程开始时间（毫秒，NOTE_STATE `start_time`）。
   * 当 [isTodo] = 1 时作为日程起止；待办（is_todo=2）作为可选开始时间。
   */
  startTime: number
  /**
   * 日程结束时间（毫秒，NOTE_STATE `end_time`）。
   * 当 [isTodo] = 1 时作为日程起止；待办（is_todo=2）作为截止时间（与 [todoDue] 同步）。
   */
  endTime: number
  source: string
  order: number
  userData: string
  rsa: number
  imageRefs: string[]
  audioId: string
  deletedTime: number
  type_: number
  /** 异步链接提取任务状态（与 server2 同步）。 */
  extractStatus: ExtractStatus
  /** server2 任务 id；空字符串表示无任务。 */
  extractJobId: string
  /** 任务失败时的 error code（如 scrape_failed / video_download_failed）。 */
  extractError: string
  /** 任务成功/失败的服务器时间戳（毫秒）；0 表示无。 */
  extractedAt: number
  /** 粗粒度进度 0~1，前端可仅用于图标旋转。 */
  extractProgress: number
  /** 语音笔记 AI 摘要（NOTE_STATE `voice_summary`）。 */
  voiceSummary: string
  /** 语音转写分段 JSON（NOTE_STATE `voice_segments_json`）。 */
  voiceSegmentsJson: string
  /** 语音转写任务状态。 */
  voiceTranscribeStatus: VoiceTranscribeStatus
}

export interface NoteSyncState {
  noteId: string
  remoteModified: number
  deleted: boolean
  deletedAt: number
  lastOperationAt: number
  syncStatus: SyncStatus
}

export interface Note {
  id: string
  title: string
  content: string
  tags: string[]
  summary: string
  localModified: number
  remoteModified: number
  deleted: boolean
  deletedAt: number
  lastOperationAt: number
  syncStatus: SyncStatus
  filePath: string
  createdAt: number
  updatedAt: number
  parentId: string
  isConflict: number
  latitude: number
  longitude: number
  altitude: number
  author: string
  sourceUrl: string
  /** 是否收藏：0/1，写入 NOTE_STATE `is_favorite`。 */
  isFavorite: number
  /** 笔记类型：0 普通 / 1 日程 / 2 待办，写入 NOTE_STATE `is_todo`。 */
  isTodo: number
  todoDue: number
  todoCompleted: number
  /** 待办优先级：0=无, 1=低, 2=中, 3=高, 4=紧急。 */
  todoPriority: number
  /** 待办状态：0=进行中, 1=已完成。 */
  todoStatus: number
  /** 待办提醒提前分钟数：0=不提醒。 */
  todoReminderMinutes: number
  /** 日程开始时间（毫秒）。仅当 [isTodo] = 1 时使用。 */
  startTime: number
  /** 日程结束时间（毫秒）。仅当 [isTodo] = 1 时使用。 */
  endTime: number
  source: string
  order: number
  userData: string
  rsa: number
  imageRefs: string[]
  audioId: string
  deletedTime: number
  type_: number
  /** 异步链接提取任务状态。 */
  extractStatus: ExtractStatus
  extractJobId: string
  extractError: string
  extractedAt: number
  extractProgress: number
  voiceSummary: string
  voiceSegmentsJson: string
  voiceTranscribeStatus: VoiceTranscribeStatus
}

export interface NoteFilePayload {
  content: string
  rawContent: string
  state: NoteStateBlock
  hasStateBlock: boolean
  filePath: string
  modifiedAt: number
}

export type WebDAVProvider = 'webdav' | 'qingyu_cloud'

export interface WebDAVConfig {
  baseUrl: string
  username: string
  encryptedPassword: string
  notesDir: string
  enabled: boolean
  provider: WebDAVProvider
}

export interface SyncPolicy {
  autoSync: boolean
  syncIntervalMinutes: number
  wifiOnly: boolean
  debounceSeconds: number
}

export interface RemoteNoteStat {
  exists: boolean
  remoteModified: number
  eTag: string
  contentLength: number
}

export type SyncAction = 'upload' | 'download' | 'delete' | 'skip' | 'restore'

export interface SyncResult {
  noteId: string
  success: boolean
  action: SyncAction
  message: string
  remoteModified: number
}

export interface CreateNoteInput {
  title: string
  content: string
  tags: string[]
  /** 为 true 且 title 为空时，不调用 MarkdownUtils.extractTitle。 */
  skipTitleAutoFill?: boolean
  /** 写入笔记 state 的 userData JSON 字符串。 */
  userData?: string
  /** 链接来源 URL；写入 state `source_url`，用于 AI 链接提取等需要回溯链接的场景。 */
  sourceUrl?: string
  /**
   * 笔记类型：0 普通 / 1 日程 / 2 待办。
   * 不传时按 0 处理；为 1 时应同时给出 [startTime] / [endTime]；为 2 时使用 [todoDue]。
   */
  isTodo?: number
  /** 日程 / 待办开始时间（毫秒）。日程（is_todo=1）作为日程起止；待办（is_todo=2）作为可选开始时间。写入 NOTE_STATE `start_time`。 */
  startTime?: number
  /** 日程 / 待办结束时间（毫秒）。日程（is_todo=1）作为日程起止；待办（is_todo=2）作为截止时间（与 todoDue 同步）。写入 NOTE_STATE `end_time`。 */
  endTime?: number
  /** 待办优先级：0=无, 1=低, 2=中, 3=高, 4=紧急；写入 NOTE_STATE `todo_priority`。 */
  todoPriority?: number
  /** 待办状态：0=进行中, 1=已完成；写入 NOTE_STATE `todo_status`。 */
  todoStatus?: number
  /** 待办提醒提前分钟数：0=不提醒；写入 NOTE_STATE `todo_reminder_minutes`。 */
  todoReminderMinutes?: number
}

export interface UpdateNoteInput {
  title?: string
  content?: string
  tags?: string[]
  /** 为 undefined 时不修改；空字符串表示移到根目录。 */
  parentId?: string
  /** 为 true 且 title 为空时，不调用 MarkdownUtils.extractTitle。 */
  skipTitleAutoFill?: boolean
  /** 关联录音文件名（如 `{noteId}.m4a`）；undefined 时不修改。 */
  audioId?: string
  /** 链接来源 URL；undefined 时不修改。 */
  sourceUrl?: string
  voiceSummary?: string
  voiceSegmentsJson?: string
  voiceTranscribeStatus?: VoiceTranscribeStatus
  /** 是否收藏：0/1；undefined 时不修改。 */
  isFavorite?: number
  /** 笔记类型：0 普通 / 1 日程 / 2 待办；undefined 时不修改。 */
  isTodo?: number
  /** 日程 / 待办开始时间（毫秒）；undefined 时不修改。 */
  startTime?: number
  /** 日程 / 待办结束时间（毫秒）；undefined 时不修改。 */
  endTime?: number
  /** 待办优先级：0=无, 1=低, 2=中, 3=高, 4=紧急；undefined 时不修改。 */
  todoPriority?: number
  /** 待办状态：0=进行中, 1=已完成；undefined 时不修改。 */
  todoStatus?: number
  /** 待办提醒提前分钟数：0=不提醒；undefined 时不修改。 */
  todoReminderMinutes?: number
}

/** 仅更新异步链接提取相关字段的 patch。 */
export interface UpdateExtractInfo {
  noteId: string
  jobId?: string
  status?: ExtractStatus
  error?: string
  extractedAt?: number
  progress?: number
  /** 任务到达终态时，可选择覆盖笔记标题（来自 server2 result.title）。 */
  title?: string
  /** 任务到达终态时，可选择覆盖笔记正文（来自 server2 result.content）。 */
  content?: string
  audioId?: string
  voiceSummary?: string
  voiceTranscribeStatus?: VoiceTranscribeStatus
  /** server2 AI 标签；undefined 表示不改 note.tags。 */
  tags?: string[]
}

/** 回收站列表加载结果（含仅存在于远端、尚未写入本地的条目 id）。 */
export interface RecycleBinLoadResult {
  notes: Note[]
  remoteOnlyIds: string[]
}
