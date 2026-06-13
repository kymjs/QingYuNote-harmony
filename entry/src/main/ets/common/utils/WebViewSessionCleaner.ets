import { webview } from '@kit.ArkWeb'

/** 退出登录时清空 WebView 缓存与 Cookie（与 Flutter `WebViewSessionCleaner.dart` 对齐）。
 *
 * - Cookie 全局清理：通过 `webview.WebCookieManager.clearAllCookies` 清空所有 WebView 共享的 Cookie 存储。
 * - 缓存清理：所有活动 `WebviewController` 在 `registerController` 时登记，`clearAll` 时逐个调用
 *   `WebviewController.removeCache(true)`。
 *
 * 调用方：在 `PreferencesService.clearLoginSession` 等所有登出/鉴权失效入口统一调用。 */
export class WebViewSessionCleaner {
  private static activeControllers: webview.WebviewController[] = []

  /** 注册一个 WebView 控制器，登出时会统一清空其缓存。 */
  static registerController(controller: webview.WebviewController): void {
    if (!WebViewSessionCleaner.activeControllers.includes(controller)) {
      WebViewSessionCleaner.activeControllers.push(controller)
    }
  }

  /** 反注册一个 WebView 控制器（页面 aboutToDisappear 时调用）。 */
  static unregisterController(controller: webview.WebviewController): void {
    const idx = WebViewSessionCleaner.activeControllers.indexOf(controller)
    if (idx >= 0) {
      WebViewSessionCleaner.activeControllers.splice(idx, 1)
    }
  }

  /** 清空所有 WebView 的 Cookie、HTTP 缓存与 LocalStorage/IndexedDB。
   *
   * 任意步骤失败不会中断后续清理（仅记录日志），保证登出流程不会被 WebView 异常阻塞。 */
  static async clearAll(): Promise<void> {
    // 1. 全局 Cookie 清理（覆盖 H5 容器、MathJax/KaTeX 预览等所有 WebView）。
    try {
      webview.WebCookieManager.clearAllCookies()
    } catch (error) {
      console.error(`WebViewSessionCleaner clearAllCookies failed: ${JSON.stringify(error)}`)
    }

    // 2. 逐个清空活动控制器的缓存。
    //    复制一份后再遍历，避免清理过程中发生反注册导致并发修改。
    const snapshot = WebViewSessionCleaner.activeControllers.slice()
    for (const controller of snapshot) {
      try {
        controller.removeCache(true)
      } catch (error) {
        console.error(`WebViewSessionCleaner removeCache failed: ${JSON.stringify(error)}`)
      }
    }
  }
}