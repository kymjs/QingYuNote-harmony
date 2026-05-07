/** 轻羽云 WebDAV 固定端点与鉴权（由应用内建，不通过设置项修改）。 */
export class SyncConstants {
  static readonly QINGYU_WEBDAV_BASE_URL: string = 'https://nas.therouter.cn:5006/QingYuYun'
  static readonly QINGYU_WEBDAV_USERNAME: string = 'qingyu'
  static readonly QINGYU_WEBDAV_PASSWORD: string = 'P@ssw0rd'
  /** 同步目录根下元数据文件名，由服务端写失效日期，客户端仅合并三方标识字段。 */
  static readonly QINGYU_CLOUD_META_FILE: string = '.qingyu-cloud.json'
  static readonly QINGYU_CLOUD_FIELD_EXPIRES_AT: string = 'expiresAt'
  static readonly QINGYU_CLOUD_FIELD_HUAWEI_USER: string = 'huaweiThirdPartyUserId'
  static readonly QINGYU_CLOUD_FIELD_WECHAT_USER: string = 'wechatThirdPartyUserId'
  /** 轻羽云未开通/过期时 `SyncService` 通过 EventHub 通知 UI 弹窗。 */
  static readonly QINGYU_SYNC_BLOCKED_EVENT: string = 'qingyu_sync_blocked'
}
