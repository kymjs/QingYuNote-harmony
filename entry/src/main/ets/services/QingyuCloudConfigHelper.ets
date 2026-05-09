import type { WebDAVConfig } from '../common/model/Note'
import { CryptoService } from './CryptoService'
import { NoteApiClient } from './NoteApiClient'
import { PreferencesService } from './PreferencesService'
import { Logger } from '../common/utils/Logger'

/** 并发合并：冷启动多处同时取配置时只打一条 GET /qingyu/webdav。 */
let qingyuBuildInflight: Promise<WebDAVConfig | null> | null = null

/** 轻羽云 WebDAV：凭 JWT 从 Note API 拉取 endpoint 与口令（不落本地 Preferences）。 */
export async function buildQingyuCloudWebDavConfig(): Promise<WebDAVConfig | null> {
  if (qingyuBuildInflight !== null) {
    return qingyuBuildInflight
  }
  qingyuBuildInflight = buildQingyuCloudWebDavConfigInner()
  try {
    return await qingyuBuildInflight
  } finally {
    qingyuBuildInflight = null
  }
}

async function buildQingyuCloudWebDavConfigInner(): Promise<WebDAVConfig | null> {
  try {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      Logger.warn('QingyuCloudConfigHelper', 'no Note API token')
      return null
    }
    const wd = await NoteApiClient.getInstance().fetchQingyuWebDAV()
    if (wd === null) {
      return null
    }
    const baseUrl = wd.base_url?.trim() ?? ''
    const password = wd.password ?? ''
    const username = wd.username?.trim() ?? ''
    const notesDir = wd.notes_dir?.trim() ?? ''
    if (baseUrl.length === 0 || password.length === 0 || notesDir.length === 0) {
      return null
    }
    const encryptedPassword = await CryptoService.getInstance().encryptText(password)
    return {
      baseUrl,
      username,
      encryptedPassword,
      notesDir,
      enabled: true,
      provider: 'qingyu_cloud'
    }
  } catch (e) {
    Logger.warn('QingyuCloudConfigHelper', `build failed: ${JSON.stringify(e)}`)
    return null
  }
}
