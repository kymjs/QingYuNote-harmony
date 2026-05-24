/** 标记页面是否仍在前台；异步任务更新 @State 前应检查，避免快速返回后崩溃。 */
export class PageLifecycle {
  private active: boolean = false

  appear(): void {
    this.active = true
  }

  disappear(): void {
    this.active = false
  }

  isActive(): boolean {
    return this.active
  }
}
