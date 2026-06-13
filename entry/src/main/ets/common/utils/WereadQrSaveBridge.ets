/** Web 内微信读书登录二维码长按保存（供 H5WebContainer javaScriptProxy 调用）。 */
export class WereadQrSaveBridge {
  private saveHandler: (payload: string) => void = () => {
  }

  bind(saveHandler: (payload: string) => void): void {
    this.saveHandler = saveHandler
  }

  saveQrImage(payload: string): void {
    this.saveHandler(payload)
  }
}
