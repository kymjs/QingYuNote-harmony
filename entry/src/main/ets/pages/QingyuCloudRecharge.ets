import { PageLifecycle } from '../common/utils/PageLifecycle'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'
import { openQingyuVipPage } from '../common/utils/OpenQingyuVipPage'
import { APP_LOCALE_REVISION_KEY, LocaleService } from '../services/LocaleService'

/**
 * 已废弃：会员开通改走 H5 VIP 页（openQingyuVipPage）。
 * 保留路由以免旧入口瞬间断裂；进入后立即打开 VIP 并返回。
 */
@Entry
@Component
struct QingyuCloudRecharge {
  @StorageProp(APP_LOCALE_REVISION_KEY) localeRevision: number = 0
  private lifecycle = new PageLifecycle()
  private closeGuard = new PageCloseGuard()
  private redirected: boolean = false

  aboutToAppear(): void {
    this.lifecycle.appear()
    this.closeGuard.reset()
    if (this.redirected) {
      return
    }
    this.redirected = true
    void this.redirectToVip()
  }

  aboutToDisappear(): void {
    this.lifecycle.disappear()
  }

  private async redirectToVip(): Promise<void> {
    try {
      await openQingyuVipPage(this.getUIContext())
    } catch (e) {
      console.error(`QingyuCloudRecharge redirect: ${JSON.stringify(e)}`)
    }
    if (!this.lifecycle.isActive()) {
      return
    }
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'QingyuCloudRecharge')
  }

  build() {
    Column() {
      Text(LocaleService.loc('加载中…', 'Loading…', '読み込み中…'))
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.app_background'))
  }
}
