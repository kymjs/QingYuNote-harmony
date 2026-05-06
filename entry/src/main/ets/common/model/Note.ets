export type SyncStatus = 'synced' | 'pending' | 'conflict' | 'error'

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
  imageRefs: string[]
  deletedTime: number
  type_: number
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
  imageRefs: string[]
  deletedTime: number
  type_: number
}

export interface NoteFilePayload {
  content: string
  rawContent: string
  state: NoteStateBlock
  hasStateBlock: boolean
  filePath: string
  modifiedAt: number
}

export interface WebDAVConfig {
  baseUrl: string
  username: string
  encryptedPassword: string
  notesDir: string
  enabled: boolean
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
}

export interface UpdateNoteInput {
  title?: string
  content?: string
  tags?: string[]
}

/** 回收站列表加载结果（含仅存在于远端、尚未写入本地的条目 id）。 */
export interface RecycleBinLoadResult {
  notes: Note[]
  remoteOnlyIds: string[]
}
