/** Web 内 MathJax 渲染完成后回传页面高度（供 javaScriptProxy 调用）。 */
export class MathJaxHeightBridge {
  private onHeightChanged: (height: number) => void = () => {
  }

  bind(onHeightChanged: (height: number) => void): void {
    this.onHeightChanged = onHeightChanged
  }

  postMessage(message: string): void {
    const parsed = parseFloat(message)
    if (!isNaN(parsed) && parsed > 0) {
      this.onHeightChanged(parsed)
    }
  }
}
