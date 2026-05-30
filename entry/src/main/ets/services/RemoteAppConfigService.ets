import fs from '@ohos.file.fs'
import http from '@ohos.net.http'
import { Logger } from '../common/utils/Logger'
import { compareSemanticVersions, getAppVersionName } from './AppUpdateService'

interface VersionRangeBounds {
  min: string
  max: string
}

/** 解析版本闭区间字符串，如 `"1.0.0-1.0.83"`。 */
function parseVersionRangeBounds(raw: Object | undefined): VersionRangeBounds | null {
  if (raw === undefined || raw === null) {
    return null
  }
  const s = String(raw).trim()
  if (s.length === 0) {
    return null
  }
  const dash = s.indexOf('-')
  if (dash <= 0 || dash >= s.length - 1) {
    return null
  }
  const min = s.substring(0, dash).trim()
  const max = s.substring(dash + 1).trim()
  if (min.length === 0 || max.length === 0) {
    return null
  }
  return { min, max }
}

function isVersionInClosedInterval(current: string, min: string, max: string): boolean {
  return compareSemanticVersions(current, min) >= 0 &&
    compareSemanticVersions(current, max) <= 0
}

/** 与 Flutter `RemoteAppConfigService.configUrl` 一致。 */
const REMOTE_APP_CONFIG_URL = 'https://cdn.kymjs.com:8843/note/config_hw.json'

/** 与 Flutter `note_remote_config.json` 缓存文件名一致。 */
const REMOTE_APP_CONFIG_CACHE_FILE = 'note_remote_config.json'

export class RemoteAppConfigService {
  static async fetchAndCacheToFilesDir(filesDir: string): Promise<void> {
    if (filesDir.length === 0) {
      Logger.warn('RemoteAppConfigService', 'filesDir empty, skip fetch')
      return
    }
    const req = http.createHttp()
    try {
      const response = await req.request(REMOTE_APP_CONFIG_URL, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 15000
      })
      if (response.responseCode !== 200) {
        Logger.warn('RemoteAppConfigService',
          `HTTP ${response.responseCode}, skip write`)
        return
      }
      const body = response.result as string
      if (body === null || body.trim().length === 0) {
        return
      }
      JSON.parse(body)
      const path = `${filesDir}/${REMOTE_APP_CONFIG_CACHE_FILE}`
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      try {
        await fs.write(file.fd, body, { encoding: 'utf-8' })
      } finally {
        fs.closeSync(file)
      }
    } catch (error) {
      Logger.warn('RemoteAppConfigService',
        `fetch/cache failed: ${JSON.stringify(error)}`)
    } finally {
      req.destroy()
    }
  }

  static async readPayConfigFromCache(filesDir: string): Promise<boolean> {
    if (filesDir.length === 0) {
      return false
    }
    const path = `${filesDir}/${REMOTE_APP_CONFIG_CACHE_FILE}`
    try {
      if (!fs.accessSync(path)) {
        return false
      }
      const stat = fs.statSync(path)
      if (stat.size <= 0) {
        return false
      }
      const content = fs.readTextSync(path, { encoding: 'utf-8' })
      const config = JSON.parse(content) as Record<string, Object>
      const bounds = parseVersionRangeBounds(config['pay_version'])
      if (bounds === null) {
        return false
      }
      const current = (await getAppVersionName()).trim()
      if (current.length === 0) {
        return false
      }
      if (!isVersionInClosedInterval(current, bounds.min, bounds.max)) {
        return false
      }
      const pay = config['pay']
      return pay === true
    } catch (_) {
      return false
    }
  }

  /** 笔记 AI：先校验 `ai_version` 闭区间，命中且 `ai == true` 时展示 AI 入口。 */
  static async readAiConfigFromCache(filesDir: string): Promise<boolean> {
    if (filesDir.length === 0) {
      return false
    }
    const path = `${filesDir}/${REMOTE_APP_CONFIG_CACHE_FILE}`
    try {
      if (!fs.accessSync(path)) {
        return false
      }
      const stat = fs.statSync(path)
      if (stat.size <= 0) {
        return false
      }
      const content = fs.readTextSync(path, { encoding: 'utf-8' })
      const config = JSON.parse(content) as Record<string, Object>
      const bounds = parseVersionRangeBounds(config['ai_version'])
      if (bounds === null) {
        return false
      }
      const current = (await getAppVersionName()).trim()
      if (current.length === 0) {
        return false
      }
      if (!isVersionInClosedInterval(current, bounds.min, bounds.max)) {
        return false
      }
      return config['ai'] === true
    } catch (_) {
      return false
    }
  }

  /** 内测邀请：先校验 `beta_test_version` 闭区间，命中且 `beta_test == true` 时开启。 */
  static async readBetaTestConfigFromCache(filesDir: string): Promise<boolean> {
    if (filesDir.length === 0) {
      return false
    }
    const path = `${filesDir}/${REMOTE_APP_CONFIG_CACHE_FILE}`
    try {
      if (!fs.accessSync(path)) {
        return false
      }
      const stat = fs.statSync(path)
      if (stat.size <= 0) {
        return false
      }
      const content = fs.readTextSync(path, { encoding: 'utf-8' })
      const config = JSON.parse(content) as Record<string, Object>
      const bounds = parseVersionRangeBounds(config['beta_test_version'])
      if (bounds === null) {
        return false
      }
      const current = (await getAppVersionName()).trim()
      if (current.length === 0) {
        return false
      }
      if (!isVersionInClosedInterval(current, bounds.min, bounds.max)) {
        return false
      }
      return config['beta_test'] === true
    } catch (_) {
      return false
    }
  }

  static isCacheFileExists(filesDir: string): boolean {
    if (filesDir.length === 0) {
      return false
    }
    const path = `${filesDir}/${REMOTE_APP_CONFIG_CACHE_FILE}`
    try {
      return fs.accessSync(path)
    } catch (_) {
      return false
    }
  }
}
