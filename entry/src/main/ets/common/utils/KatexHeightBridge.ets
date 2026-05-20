/** Web 内 KaTeX 渲染完成后回传页面高度（供 javaScriptProxy 调用）。 */
export class KatexHeightBridge {
  private onHeightChanged: (message: string) => void = () => {
  }

  bind(onHeightChanged: (message: string) => void): void {
    this.onHeightChanged = onHeightChanged
  }

  postMessage(message: string): void {
    if (message.startsWith('ok:') || message.startsWith('error:')) {
      this.onHeightChanged(message)
      return
    }
    const parsed = parseFloat(message)
    if (!isNaN(parsed) && parsed > 0) {
      this.onHeightChanged(`ok:${parsed}`)
    }
  }
}
