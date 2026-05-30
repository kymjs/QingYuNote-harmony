import { SyncConstants } from '../constants/SyncConstants'

/** 未配置 WebDAV / 未开通轻羽云会员时的 UI 提示节流（跨 Toast、EventHub 共用）。 */
export class CloudSyncNotifyThrottle {
  private static lastNotConfiguredUiMs: number = 0
  private static lastQingyuSubscriptionDialogMs: number = 0
  private static readonly qingyuSubscriptionDialogIntervalMs: number = 2500

  static isNotConfiguredUserMessage(message: string): boolean {
    const trimmed = message.trim()
    if (trimmed === '当前未配置云服务') {
      return true
    }
    if (trimmed.includes('请先完成 WebDAV 配置')) {
      return true
    }
    if (trimmed.includes('请先完成云服务配置')) {
      return true
    }
    if (trimmed === '请开通轻羽云服务') {
      return true
    }
    return false
  }

  static tryConsumeNotConfiguredNotifySlot(): boolean {
    const now = Date.now()
    if (now - CloudSyncNotifyThrottle.lastNotConfiguredUiMs <
      SyncConstants.cloudSyncNotConfiguredNotifyIntervalMs) {
      return false
    }
    CloudSyncNotifyThrottle.lastNotConfiguredUiMs = now
    return true
  }

  static shouldSuppressUserMessage(message: string): boolean {
    if (!CloudSyncNotifyThrottle.isNotConfiguredUserMessage(message)) {
      return false
    }
    return !CloudSyncNotifyThrottle.tryConsumeNotConfiguredNotifySlot()
  }

  static tryConsumeQingyuSubscriptionDialogSlot(): boolean {
    const now = Date.now()
    if (now - CloudSyncNotifyThrottle.lastQingyuSubscriptionDialogMs <
      CloudSyncNotifyThrottle.qingyuSubscriptionDialogIntervalMs) {
      return false
    }
    CloudSyncNotifyThrottle.lastQingyuSubscriptionDialogMs = now
    return true
  }
}
