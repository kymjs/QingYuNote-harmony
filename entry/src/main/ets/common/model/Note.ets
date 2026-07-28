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
  isTodo: number
  todoDue: number
  todoCompleted: number
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
  isTodo: number
  todoDue: number
  todoCompleted: number
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
}

/** 回收站列表加载结果（含仅存在于远端、尚未写入本地的条目 id）。 */
export interface RecycleBinLoadResult {
  notes: Note[]
  remoteOnlyIds: string[]
}
