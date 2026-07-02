import { pasteboard } from '@kit.BasicServicesKit'

/** 轮询系统剪贴板读取 API Key；可选 [prefix] 前缀校验。 */
export async function pollSystemClipboardToken(
  prefix?: string,
  attempts: number = 5,
  delayMs: number = 120
): Promise<string> {
  let trimmed: string = ''
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard()
      const data = await systemPasteboard.getData()
      const text = data.getPrimaryText()
      trimmed = `${text ?? ''}`.trim()
    } catch (_) {
      return ''
    }
    if (prefix !== undefined && prefix.length > 0) {
      if (trimmed.length > 0 && trimmed.startsWith(prefix)) {
        break
      }
    } else if (trimmed.length > 0) {
      break
    }
    await new Promise<void>((resolve) => setTimeout(resolve, delayMs))
  }
  if (trimmed.length === 0) {
    return ''
  }
  if (prefix !== undefined && prefix.length > 0 && !trimmed.startsWith(prefix)) {
    return ''
  }
  return trimmed
}

/** 从 AppStorage 读取并清除 pending API Key（H5 WebView 写入）。 */
export function takePendingApiKeyFromAppStorage(storageKey: string): string {
  try {
    const stored: string | undefined = AppStorage.get<string>(storageKey)
    if (stored && stored.length > 0) {
      AppStorage.delete(storageKey)
      return stored.trim()
    }
  } catch (_) {
  }
  return ''
}
