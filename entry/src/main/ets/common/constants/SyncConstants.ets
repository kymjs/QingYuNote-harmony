/** 轻羽云同步相关常量（WebDAV 服务端 URL/账号口令不下发到客户端代码）。 */
export class SyncConstants {
  /** 同步目录根下元数据文件名，由服务端写失效日期，客户端仅合并三方标识字段。 */
  static readonly qingyuCloudMetaFile: string = '.qingyu-cloud.json'
  static readonly qingyuCloudFieldExpiresAt: string = 'expiresAt'
  static readonly qingyuCloudFieldPlatformUserId: string = 'platformUserId'
  /** 轻羽云未开通/过期时 `SyncService` 通过 EventHub 通知 UI 弹窗。 */
  static readonly qingyuSyncBlockedEvent: string = 'qingyu_sync_blocked'
  /** `.qingyu-index.json` 中已彻底删除笔记 id 列表。 */
  static readonly remoteIndexFieldPermanentlyDeletedNoteIds: string = 'permanentlyDeletedNoteIds'
  /** 解析失效日期时，年份 ≥ 此值视为终身 VIP（与 Flutter `qingyuLifetimeMinYear` 一致）。 */
  static readonly qingyuLifetimeMinYear: number = 2099
}
