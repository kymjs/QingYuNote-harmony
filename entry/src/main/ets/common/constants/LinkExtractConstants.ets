/** 链接抓取与摘要服务（与 Flutter `AppConst.linkExtractApiBaseUrl` 保持一致；经 nginx /note 反代）。 */
export class LinkExtractConstants {
  static readonly baseUrl: string = 'https://ragflow.therouter.cn:8443/note'
}
