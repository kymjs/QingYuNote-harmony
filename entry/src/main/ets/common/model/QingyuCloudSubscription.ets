/**
 * 轻羽云：通过 WebDAV 拉取 `.qingyu-cloud.json` 判断订阅状态；文件内容不落本地磁盘。
 */
export interface QingyuCloudStatusNotConfigured {
  kind: 'not_configured'
}

export interface QingyuCloudStatusNotQingyu {
  kind: 'not_qingyu'
}

export interface QingyuCloudStatusNotPurchased {
  kind: 'not_purchased'
}

export interface QingyuCloudStatusFetchFailed {
  kind: 'fetch_failed'
}

export interface QingyuCloudStatusMalformed {
  kind: 'malformed'
}

export interface QingyuCloudStatusLifetime {
  kind: 'lifetime'
}

export interface QingyuCloudStatusExpired {
  kind: 'expired'
  expiresDisplayYmd: string
}

export interface QingyuCloudStatusActive {
  kind: 'active'
  expiresDisplayYmd: string
}

export type QingyuCloudSubscriptionStatus =
  | QingyuCloudStatusNotConfigured
  | QingyuCloudStatusNotQingyu
  | QingyuCloudStatusNotPurchased
  | QingyuCloudStatusFetchFailed
  | QingyuCloudStatusMalformed
  | QingyuCloudStatusLifetime
  | QingyuCloudStatusExpired
  | QingyuCloudStatusActive
