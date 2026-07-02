import { ReleaseManifest } from '../services/AppUpdateService'
import {
  evaluateForceUpdateForGate,
  forceUpdateMessageFromManifest,
  openReleaseDownloadFromGate
} from '../services/AppUpdateUi'
import { AppContextHolder } from '../services/AppContextHolder'
import { PreferencesService } from '../services/PreferencesService'

type GatePhase = 'loading' | 'force' | 'routing'

@Entry
@Component
struct UpdateGate {
  @State phase: GatePhase = 'loading'
  @State forceManifest: ReleaseManifest | null = null

  aboutToAppear(): void {
    AppContextHolder.setLastUiContext(this.getUIContext())
    void this.bootstrap()
  }

  private async bootstrap(): Promise<void> {
    const force = await evaluateForceUpdateForGate()
    if (force !== null) {
      this.forceManifest = force
      this.phase = 'force'
      return
    }
    this.phase = 'routing'
    await this.routeToAppEntry()
  }

  private async routeToAppEntry(): Promise<void> {
    try {
      const context = AppContextHolder.tryGetContext()
      if (context) {
        await PreferencesService.getInstance().init(context)
      }
      const loggedIn = await PreferencesService.getInstance().isUserLoggedIn()
      const guest = await PreferencesService.getInstance().isGuestMode()
      const target = (loggedIn || guest) ? 'pages/Index' : 'pages/Login'
      await this.getUIContext().getRouter().replaceUrl({ url: target })
    } catch (e) {
      console.error(`UpdateGate routeToAppEntry: ${JSON.stringify(e)}`)
      await this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' })
    }
  }

  build() {
    Stack() {
      if (this.phase === 'loading') {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color($r('app.color.accent'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.app_background'))
      } else if (this.phase === 'force' && this.forceManifest !== null) {
        Column({ space: 16 }) {
          Text('需要更新')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
            .textAlign(TextAlign.Center)
          Scroll() {
            Text(forceUpdateMessageFromManifest(this.forceManifest))
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .lineHeight(22)
              .width('100%')
          }
          .width('100%')
          .layoutWeight(1)
          Button('立即更新')
            .width('100%')
            .fontSize($r('app.float.caption_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius($r('app.float.pill_radius'))
            .padding({ top: 12, bottom: 12 })
            .onClick(() => {
              if (this.forceManifest !== null) {
                openReleaseDownloadFromGate(this.forceManifest.downloadUrl)
              }
            })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 24, right: 24, top: 48, bottom: 32 })
        .backgroundColor($r('app.color.app_background'))
      } else {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color($r('app.color.accent'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.app_background'))
      }
    }
    .width('100%')
    .height('100%')
  }
}
