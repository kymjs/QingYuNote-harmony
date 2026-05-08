/** 轻羽云 WebDAV 固定端点与鉴权（命名与 Flutter `lib/sync_constants.dart` 一致）。 */
export class SyncConstants {
  static readonly qingyuWebDavBaseUrl: string = 'https://nas.therouter.cn:5006/QingYuYun'
  static readonly qingyuWebDavUsername: string = 'qingyu'
  static readonly qingyuWebDavPassword: string = 'P@ssw0rd'
  /** 同步目录根下元数据文件名，由服务端写失效日期，客户端仅合并三方标识字段。 */
  static readonly qingyuCloudMetaFile: string = '.qingyu-cloud.json'
  static readonly qingyuCloudFieldExpiresAt: string = 'expiresAt'
  static readonly qingyuCloudFieldHuaweiUser: string = 'huaweiThirdPartyUserId'
  static readonly qingyuCloudFieldWechatUser: string = 'wechatThirdPartyUserId'
  /** 轻羽云未开通/过期时 `SyncService` 通过 EventHub 通知 UI 弹窗。 */
  static readonly qingyuSyncBlockedEvent: string = 'qingyu_sync_blocked'
  /** `.qingyu-index.json` 中已彻底删除笔记 id 列表。 */
  static readonly remoteIndexFieldPermanentlyDeletedNoteIds: string = 'permanentlyDeletedNoteIds'
  /** 解析失效日期时，年份 ≥ 此值视为终身 VIP（与 Flutter `qingyuLifetimeMinYear` 一致）。 */
  static readonly qingyuLifetimeMinYear: number = 2099
}
