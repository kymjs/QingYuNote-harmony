import type { WebDAVConfig } from '../common/model/Note'
import { PreferencesService } from './PreferencesService'
import { WebDAVClient } from './WebDAVClient'
import { buildQingyuCloudWebDavConfig } from './QingyuCloudConfigHelper'
import { Logger } from '../common/utils/Logger'

/** 首页工具栏云同步入口显隐与自动开通逻辑共用。 */
export const previewQingyuForHomeSubscription: WebDAVConfig = {
  baseUrl: '',
  username: '',
  encryptedPassword: '',
  notesDir: '/qingyu-notes/',
  enabled: true,
  provider: 'qingyu_cloud'
}

/** 进入首页：尚无同步方案且订阅仍有效时，自动保存为轻羽云同步（与 Flutter 对齐）。 */
export async function tryAutoProvisionQingyuCloudOnHomeEntry(): Promise<void> {
  try {
    if (!(await PreferencesService.getInstance().shouldAttemptAutoQingyuCloudProvisioning())) {
      return
    }
    const status =
      await WebDAVClient.getInstance().fetchQingyuCloudSubscriptionStatus(previewQingyuForHomeSubscription)
    if (status.kind !== 'lifetime' && status.kind !== 'active') {
      return
    }
    const built = await buildQingyuCloudWebDavConfig()
    const config: WebDAVConfig =
      built !== null
        ? built
        : {
            baseUrl: '',
            username: '',
            encryptedPassword: '',
            notesDir: '/qingyu-notes/',
            enabled: true,
            provider: 'qingyu_cloud'
          }
    await PreferencesService.getInstance().saveWebDAVConfig(config)
    await PreferencesService.getInstance().setAuthInvalid(false)
  } catch (e) {
    Logger.warn('QingyuCloudAutoProvision',
      `tryAutoProvisionQingyuCloudOnHomeEntry failed: ${JSON.stringify(e)}`)
  }
}
