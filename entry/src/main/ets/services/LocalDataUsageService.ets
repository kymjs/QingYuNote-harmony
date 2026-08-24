import fs from '@ohos.file.fs'
import { AppContextHolder } from './AppContextHolder'
import { AudioConstants } from '../common/constants/AudioConstants'
import { Logger } from '../common/utils/Logger'

/** 本地笔记 + 图片 + 音频 + 网络图缓存占用汇总（含 `.qy` 与回收站文件）。 */
export class LocalDataUsageService {
  private static instance: LocalDataUsageService = new LocalDataUsageService()
  static readonly QUOTA_GB: number = 50
  private static readonly NOTES_DIR: string = 'notes'
  private static readonly IMAGES_DIR: string = 'qingyu-note-image'
  private static readonly CACHE_DIR: string = 'url_image_cache'

  static getInstance(): LocalDataUsageService {
    return LocalDataUsageService.instance
  }

  /** 递归统计本地数据总字节数；失败或目录不存在按 0。 */
  async calculateTotalBytes(): Promise<number> {
    try {
      const ctx = AppContextHolder.tryGetContext()
      if (ctx === undefined) {
        return 0
      }
      const filesDir = ctx.filesDir ?? ''
      const cacheDir = ctx.cacheDir ?? ''
      const roots: string[] = [
        `${filesDir}/${LocalDataUsageService.NOTES_DIR}`,
        `${filesDir}/qingyu-note-history`,
        `${filesDir}/${LocalDataUsageService.IMAGES_DIR}`,
        `${filesDir}/${AudioConstants.audioDirectory}`,
        `${cacheDir}/${LocalDataUsageService.CACHE_DIR}`
      ]
      let total = 0
      for (let i = 0; i < roots.length; i++) {
        total += this.directoryBytes(roots[i])
      }
      return total
    } catch (error) {
      Logger.warn('LocalDataUsageService', `calculateTotalBytes failed: ${JSON.stringify(error)}`)
      return 0
    }
  }

  /** 将字节转为 GB 字符串：进一法保留 1 位小数（0 字节为 `0.0`）。 */
  static formatUsedGbCeil1(bytes: number): string {
    if (bytes <= 0) {
      return '0.0'
    }
    const gb = bytes / (1024 * 1024 * 1024)
    const ceil1 = Math.ceil(gb * 10) / 10
    return ceil1.toFixed(1)
  }

  private directoryBytes(dirPath: string): number {
    try {
      if (!fs.accessSync(dirPath)) {
        return 0
      }
      const stat = fs.statSync(dirPath)
      if (!stat.isDirectory()) {
        return typeof stat.size === 'number' ? stat.size : 0
      }
    } catch (_) {
      return 0
    }
    let total = 0
    const stack: string[] = [dirPath]
    while (stack.length > 0) {
      const current = stack.pop() as string
      let names: string[] = []
      try {
        names = fs.listFileSync(current, {
          recursion: false,
          listNum: 0
        }) as string[]
      } catch (_) {
        continue
      }
      for (let i = 0; i < names.length; i++) {
        const name = names[i]
        if (!name || name.length === 0) {
          continue
        }
        const full = current.endsWith('/') ? `${current}${name}` : `${current}/${name}`
        try {
          const st = fs.statSync(full)
          if (st.isDirectory()) {
            stack.push(full)
          } else if (typeof st.size === 'number' && st.size > 0) {
            total += st.size
          }
        } catch (_) {
          // skip
        }
      }
    }
    return total
  }
}
