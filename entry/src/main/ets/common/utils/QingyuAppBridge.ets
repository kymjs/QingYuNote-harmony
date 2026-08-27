/** 活动 H5 ↔ 原生 Bridge（H5WebContainer javaScriptProxy）。 */
export class QingyuAppBridge {
  private openInviteHandler: () => void = () => {
  }
  private openStoreReviewHandler: () => void = () => {
  }
  private openMineTabHandler: () => void = () => {
  }

  bindOpenInvite(handler: () => void): void {
    this.openInviteHandler = handler
  }

  bindOpenStoreReview(handler: () => void): void {
    this.openStoreReviewHandler = handler
  }

  bindOpenMineTab(handler: () => void): void {
    this.openMineTabHandler = handler
  }

  openInvite(): void {
    this.openInviteHandler()
  }

  openStoreReview(): void {
    this.openStoreReviewHandler()
  }

  openMineTab(): void {
    this.openMineTabHandler()
  }
}
