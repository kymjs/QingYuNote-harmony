/** 笔记设置页开关的跨端 JSON（与 Flutter `NoteSettingsDocument` 对齐）。 */
export class NoteSettingsDocument {
  static readonly currentVersion: number = 1

  version: number
  updatedAt: number
  quickActionBarEnabled: boolean
  folderModeEnabled: boolean

  constructor(
    updatedAt: number,
    quickActionBarEnabled: boolean = true,
    folderModeEnabled: boolean = true,
    version: number = NoteSettingsDocument.currentVersion
  ) {
    this.version = version
    this.updatedAt = updatedAt
    this.quickActionBarEnabled = quickActionBarEnabled
    this.folderModeEnabled = folderModeEnabled
  }

  static defaults(updatedAt?: number): NoteSettingsDocument {
    const ts = updatedAt !== undefined ? updatedAt : Date.now()
    return new NoteSettingsDocument(ts)
  }

  static fromJsonRecord(json: Record<string, Object>): NoteSettingsDocument {
    return new NoteSettingsDocument(
      NoteSettingsDocument.asInt(json['updatedAt'], 0),
      NoteSettingsDocument.asBool(json['quickActionBarEnabled'], true),
      NoteSettingsDocument.asBool(json['folderModeEnabled'], true),
      NoteSettingsDocument.asInt(json['version'], NoteSettingsDocument.currentVersion)
    )
  }

  toJsonRecord(): Record<string, Object> {
    const out: Record<string, Object> = {}
    out['version'] = this.version <= 0 ? NoteSettingsDocument.currentVersion : this.version
    out['updatedAt'] = this.updatedAt
    out['quickActionBarEnabled'] = this.quickActionBarEnabled
    out['folderModeEnabled'] = this.folderModeEnabled
    return out
  }

  private static asInt(value: Object | undefined, fallback: number): number {
    if (value === undefined || value === null) {
      return fallback
    }
    if (typeof value === 'number') {
      return Math.trunc(value)
    }
    const parsed = parseInt(`${value}`, 10)
    return Number.isNaN(parsed) ? fallback : parsed
  }

  private static asBool(value: Object | undefined, fallback: boolean): boolean {
    if (value === undefined || value === null) {
      return fallback
    }
    if (typeof value === 'boolean') {
      return value
    }
    if (`${value}` === 'true') {
      return true
    }
    if (`${value}` === 'false') {
      return false
    }
    return fallback
  }
}
