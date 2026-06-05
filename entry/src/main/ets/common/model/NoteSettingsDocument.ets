/** 笔记设置页开关的跨端 JSON（与 Flutter `NoteSettingsDocument` 对齐）。 */
export class NoteSettingsDocument {
  static readonly currentVersion: number = 1
  /** 自旧 Preferences 迁移、尚未被用户在本机修改过的文档时间戳。 */
  static readonly pristineUpdatedAt: number = 0

  version: number
  updatedAt: number
  quickActionBarEnabled: boolean
  folderModeEnabled: boolean
  /** 用户在本机通过设置页改过开关；迁移文档为 `false`。 */
  locallyModified: boolean

  constructor(
    updatedAt: number,
    quickActionBarEnabled: boolean = true,
    folderModeEnabled: boolean = false,
    version: number = NoteSettingsDocument.currentVersion,
    locallyModified: boolean = false
  ) {
    this.version = version
    this.updatedAt = updatedAt
    this.quickActionBarEnabled = quickActionBarEnabled
    this.folderModeEnabled = folderModeEnabled
    this.locallyModified = locallyModified
  }

  static defaults(updatedAt?: number): NoteSettingsDocument {
    const ts = updatedAt !== undefined ? updatedAt : NoteSettingsDocument.pristineUpdatedAt
    return new NoteSettingsDocument(ts)
  }

  contentEquals(other: NoteSettingsDocument): boolean {
    return this.quickActionBarEnabled === other.quickActionBarEnabled &&
      this.folderModeEnabled === other.folderModeEnabled
  }

  static fromJsonRecord(json: Record<string, Object>): NoteSettingsDocument {
    return new NoteSettingsDocument(
      NoteSettingsDocument.asInt(json['updatedAt'], 0),
      NoteSettingsDocument.asBool(json['quickActionBarEnabled'], true),
      NoteSettingsDocument.asBool(json['folderModeEnabled'], false),
      NoteSettingsDocument.asInt(json['version'], NoteSettingsDocument.currentVersion),
      NoteSettingsDocument.asBool(json['locallyModified'], false)
    )
  }

  toJsonRecord(): Record<string, Object> {
    const out: Record<string, Object> = {}
    out['version'] = this.version <= 0 ? NoteSettingsDocument.currentVersion : this.version
    out['updatedAt'] = this.updatedAt
    out['quickActionBarEnabled'] = this.quickActionBarEnabled
    out['folderModeEnabled'] = this.folderModeEnabled
    out['locallyModified'] = this.locallyModified
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
