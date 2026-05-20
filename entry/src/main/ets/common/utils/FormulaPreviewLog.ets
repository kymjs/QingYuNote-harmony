import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0000
const TAG = 'FormulaPreview'

/** 公式预览 Web/KaTeX 调试日志，过滤 HiLog：`FormulaPreview`。 */
export class FormulaPreviewLog {
  static info(message: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', message)
  }

  static warn(message: string): void {
    hilog.warn(DOMAIN, TAG, '%{public}s', message)
  }

  static error(message: string): void {
    hilog.error(DOMAIN, TAG, '%{public}s', message)
  }
}
