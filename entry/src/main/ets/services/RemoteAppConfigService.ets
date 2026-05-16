import fs from '@ohos.file.fs'
import http from '@ohos.net.http'
import { Logger } from '../common/utils/Logger'

/** 与 Flutter `RemoteAppConfigService.configUrl` 一致。 */
const REMOTE_APP_CONFIG_URL = 'https://cdn.kymjs.com:8843/note/config.json'

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
      const pay = config['pay']
      return pay === true
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
