/** 轻羽云同步相关常量（WebDAV 服务端 URL/账号口令不下发到客户端代码）。 */
export class SyncConstants {
  /** 同步目录根下元数据文件名，由服务端写失效日期，客户端仅合并三方标识字段。 */
  static readonly qingyuCloudMetaFile: string = '.qingyu-cloud.json'
  /** 笔记设置页开关 JSON，与 Flutter `SyncConstants.noteSettingsFile` 一致。 */
  static readonly noteSettingsFile: string = '.qingyu-note-settings.json'
  static readonly qingyuCloudFieldExpiresAt: string = 'expiresAt'
  static readonly qingyuCloudFieldPlatformUserId: string = 'platformUserId'
  /** 轻羽云未开通/过期时 `SyncService` 通过 EventHub 通知 UI 弹窗。 */
  static readonly qingyuSyncBlockedEvent: string = 'qingyu_sync_blocked'
  /** 既未开通轻羽云、也未配置完整自建 WebDAV 时，仅 Toast，不弹开通弹窗。 */
  static readonly cloudSyncNotConfiguredToastEvent: string = 'cloud_sync_not_configured_toast'
  /** `.qingyu-index.json` 中已彻底删除笔记 id 列表。 */
  static readonly remoteIndexFieldPermanentlyDeletedNoteIds: string = 'permanentlyDeletedNoteIds'
  /** 彻底删除 id 超过该数量时裁剪最老条目（与 Flutter 对齐）。 */
  static readonly permanentlyDeletedNoteIdsPruneThreshold: number = 30
  /** 每次裁剪移除的最老彻底删除 id 条数。 */
  static readonly permanentlyDeletedNoteIdsPruneCount: number = 10
  /** 解析失效日期时，年份 ≥ 此值视为终身 VIP（与 Flutter `qingyuLifetimeMinYear` 一致）。 */
  static readonly qingyuLifetimeMinYear: number = 2099
  /** 单次全量同步最多处理条目数，与 Flutter `maxNotesPerFullSyncPass` 对齐。 */
  static readonly maxNotesPerFullSyncPass: number = 120
  /** 一次 `syncNow` 后台最多连续批次轮数，与 Flutter `maxFullSyncPassesPerUserAction` 对齐。 */
  static readonly maxFullSyncPassesPerUserAction: number = 64
}
