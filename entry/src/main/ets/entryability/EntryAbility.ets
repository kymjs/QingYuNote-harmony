import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { PreferencesService } from '../services/PreferencesService'
import { CryptoService } from '../services/CryptoService'
import { NoteRepository } from '../services/NoteRepository'
import { SyncService } from '../services/SyncService'
import { AppScheduler } from '../services/AppScheduler'
import { AppContextHolder } from '../services/AppContextHolder'

const DOMAIN = 0x0000
const DEFERRED_SERVICES_DELAY_MS = 1500

export default class EntryAbility extends UIAbility {
  private deferredServicesPrepared: boolean = false

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
    } catch (err) {
      hilog.error(DOMAIN, 'noteTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err))
    }
    AppContextHolder.setContext(this.context)
    void this.prepareCriticalServices().then(() => {
      this.scheduleDeferredServices()
    }).catch((error: Error) => {
      hilog.error(DOMAIN, 'noteTag', 'Failed to prepare critical services. Cause: %{public}s', JSON.stringify(error))
    })
    hilog.info(DOMAIN, 'noteTag', '%{public}s', 'Ability onCreate')
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'noteTag', '%{public}s', 'Ability onDestroy')
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'noteTag', '%{public}s', 'Ability onWindowStageCreate')

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'noteTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err))
        return
      }
      hilog.info(DOMAIN, 'noteTag', 'Succeeded in loading the content.')
    })
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'noteTag', '%{public}s', 'Ability onWindowStageDestroy')
  }

  onForeground(): void {
    void AppScheduler.getInstance().onForeground()
    hilog.info(DOMAIN, 'noteTag', '%{public}s', 'Ability onForeground')
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'noteTag', '%{public}s', 'Ability onBackground')
  }

  private async prepareCriticalServices(): Promise<void> {
    await PreferencesService.getInstance().init(this.context)
    await CryptoService.getInstance().init()
    await NoteRepository.getInstance().init(this.context)
    await SyncService.getInstance().init()
    await AppScheduler.getInstance().init()
  }

  private scheduleDeferredServices(): void {
    if (this.deferredServicesPrepared) {
      return
    }
    this.deferredServicesPrepared = true
    setTimeout(() => {
      void this.prepareDeferredServices().catch((error: Error) => {
        hilog.error(DOMAIN, 'noteTag', 'Failed to prepare deferred services. Cause: %{public}s', JSON.stringify(error))
      })
    }, DEFERRED_SERVICES_DELAY_MS)
  }

  private async prepareDeferredServices(): Promise<void> {
    await NoteRepository.getInstance().startupRepair()
    await SyncService.getInstance().restorePendingAfterLaunch()
  }
}