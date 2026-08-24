import { SyncConstants } from '../constants/SyncConstants'

export class NoteHistoryReason {
  static readonly auto: string = 'auto'
  static readonly editorLeave: string = 'editorLeave'
  static readonly remoteClobber: string = 'remoteClobber'
  static readonly remoteOverwrite: string = 'remoteOverwrite'
  static readonly restore: string = 'restore'
  static readonly agentWrite: string = 'agentWrite'
  static readonly aiReplace: string = 'aiReplace'
  static readonly userManual: string = 'userManual'

  static isForced(reason: string): boolean {
    return reason !== NoteHistoryReason.auto
  }
}

export class NoteHistoryEntry {
  id: string = ''
  createdAt: number = 0
  contentHash: string = ''
  contentLength: number = 0
  reason: string = NoteHistoryReason.auto
  title: string = ''
  hasFlowchart: boolean = false

  toJson(): Record<string, Object> {
    const map: Record<string, Object> = {}
    map['id'] = this.id
    map['createdAt'] = this.createdAt
    map['contentHash'] = this.contentHash
    map['contentLength'] = this.contentLength
    map['reason'] = this.reason
    map['title'] = this.title
    map['hasFlowchart'] = this.hasFlowchart
    return map
  }

  static fromJson(raw: Record<string, Object>): NoteHistoryEntry {
    const entry = new NoteHistoryEntry()
    entry.id = `${raw['id'] ?? ''}`
    entry.createdAt = Number(raw['createdAt'] ?? 0)
    entry.contentHash = `${raw['contentHash'] ?? ''}`
    entry.contentLength = Number(raw['contentLength'] ?? 0)
    entry.reason = `${raw['reason'] ?? NoteHistoryReason.auto}`
    entry.title = `${raw['title'] ?? ''}`
    entry.hasFlowchart = raw['hasFlowchart'] === true
    return entry
  }
}

export class NoteHistoryManifest {
  schema: number = 1
  noteId: string = ''
  versions: NoteHistoryEntry[] = []

  toJson(): Record<string, Object> {
    const list: Record<string, Object>[] = []
    for (let i = 0; i < this.versions.length; i++) {
      list.push(this.versions[i].toJson())
    }
    const map: Record<string, Object> = {}
    map['schema'] = this.schema
    map['noteId'] = this.noteId
    map['versions'] = list
    return map
  }

  static empty(noteId: string): NoteHistoryManifest {
    const manifest = new NoteHistoryManifest()
    manifest.noteId = noteId
    return manifest
  }

  static fromJson(raw: Record<string, Object>, fallbackNoteId: string): NoteHistoryManifest {
    const manifest = new NoteHistoryManifest()
    manifest.schema = Number(raw['schema'] ?? 1)
    manifest.noteId = `${raw['noteId'] ?? fallbackNoteId}`
    const versions: NoteHistoryEntry[] = []
    const rawVersions: Object | undefined = raw['versions']
    const list: Object[] = Array.isArray(rawVersions) ? (rawVersions as Object[]) : []
    for (let i = 0; i < list.length; i++) {
      const item: Object = list[i]
      if (typeof item !== 'object' || item === null) {
        continue
      }
      const entry = NoteHistoryEntry.fromJson(item as Record<string, Object>)
      if (entry.id.length > 0) {
        versions.push(entry)
      }
    }
    manifest.versions = versions
    return manifest
  }
}

export class NoteHistoryLogic {
  static contentHashSource(title: string, content: string): string {
    return `${title.trim()}\n${content}`
  }

  static isNoteEmpty(title: string, content: string): boolean {
    return title.trim().length === 0 && content.trim().length === 0
  }

  static shouldCapture(titleOrContentChanged: boolean, isEmpty: boolean, bulkImport: boolean, newHash: string,
    latestHash: string, nowMs: number, latestCreatedAt: number, reason: string): boolean {
    if (bulkImport) {
      return false
    }
    if (!titleOrContentChanged && !NoteHistoryReason.isForced(reason)) {
      return false
    }
    if (isEmpty) {
      return false
    }
    if (newHash.length > 0 && newHash === latestHash) {
      return false
    }
    if (NoteHistoryReason.isForced(reason)) {
      return true
    }
    if (latestCreatedAt <= 0) {
      return true
    }
    return nowMs - latestCreatedAt >= SyncConstants.noteHistoryThrottleMs
  }

  static mergeAndPrune(local: NoteHistoryEntry[], remote: NoteHistoryEntry[]): NoteHistoryEntry[] {
    const byId: Map<string, NoteHistoryEntry> = new Map()
    for (let i = 0; i < local.length; i++) {
      if (local[i].id.length > 0) {
        byId.set(local[i].id, local[i])
      }
    }
    for (let i = 0; i < remote.length; i++) {
      const entry = remote[i]
      if (entry.id.length === 0) {
        continue
      }
      const existing = byId.get(entry.id)
      if (existing === undefined || entry.createdAt >= existing.createdAt) {
        byId.set(entry.id, entry)
      }
    }
    const merged: NoteHistoryEntry[] = []
    byId.forEach((entry: NoteHistoryEntry) => {
      merged.push(entry)
    })
    merged.sort((a: NoteHistoryEntry, b: NoteHistoryEntry) => b.createdAt - a.createdAt)
    if (merged.length <= SyncConstants.noteHistoryMaxVersions) {
      return merged
    }
    return merged.slice(0, SyncConstants.noteHistoryMaxVersions)
  }

  static prune(versions: NoteHistoryEntry[]): NoteHistoryEntry[] {
    const sorted = versions.slice()
    sorted.sort((a: NoteHistoryEntry, b: NoteHistoryEntry) => b.createdAt - a.createdAt)
    if (sorted.length <= SyncConstants.noteHistoryMaxVersions) {
      return sorted
    }
    return sorted.slice(0, SyncConstants.noteHistoryMaxVersions)
  }
}
