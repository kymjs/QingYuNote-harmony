import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { PreferencesService } from '../services/PreferencesService'
import { buildQingyuCloudWebDavConfig } from '../services/QingyuCloudConfigHelper'
import { CryptoService } from '../services/CryptoService'
import { NoteRepository } from '../services/NoteRepository'
import { SyncService } from '../services/SyncService'
import { AppScheduler } from '../services/AppScheduler'
import { AppContextHolder } from '../services/AppContextHolder'
import { RemoteAppConfigService } from '../services/RemoteAppConfigService'
import { LocaleService, APP_LOCALE_REVISION_KEY } from '../services/LocaleService'

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
    AppStorage.setOrCreate(APP_LOCALE_REVISION_KEY, 0)
    void LocaleService.getInstance().load(this.context)
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

  onNewWant(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'noteTag', '%{public}s', 'Ability onWindowStageCreate')
    void this.bootstrapWindow(windowStage)
  }

  private async bootstrapWindow(windowStage: window.WindowStage): Promise<void> {
    try {
      await PreferencesService.getInstance().init(this.context)
      await LocaleService.getInstance().load(this.context)
      await PreferencesService.getInstance().repairAbnormalLoginSessionIfNeeded()
      const loggedIn = await PreferencesService.getInstance().isUserLoggedIn()
      const guest = await PreferencesService.getInstance().isGuestMode()
      if (!loggedIn && !guest) {
        await PreferencesService.getInstance().clearLoginReturnTarget()
      }
      const entryPage = (loggedIn || guest) ? 'pages/Index' : 'pages/Login'
      windowStage.loadContent(entryPage, (err) => {
        if (err.code) {
          hilog.error(DOMAIN, 'noteTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err))
          return
        }
        hilog.info(DOMAIN, 'noteTag', 'Succeeded in loading the content.')
      })
    } catch (error) {
      hilog.error(DOMAIN, 'noteTag', 'bootstrapWindow failed: %{public}s', JSON.stringify(error))
      windowStage.loadContent('pages/Login', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, 'noteTag', 'Failed to load fallback Login. Cause: %{public}s', JSON.stringify(err))
        }
      })
    }
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
    const filesDir = this.context.filesDir ?? ''
    void RemoteAppConfigService.fetchAndCacheToFilesDir(filesDir).catch((error: Error) => {
      hilog.info(DOMAIN, 'noteTag', 'RemoteAppConfig fetch failed: %{public}s', JSON.stringify(error))
    })
    await CryptoService.getInstance().init()
    await NoteRepository.getInstance().init(this.context)
    await SyncService.getInstance().init()
    await AppScheduler.getInstance().init()
    void this.prefetchQingyuWebDavIfNeeded()
  }

  /** 应用启动预热：与 Preferences/Sync 等处共用 QingyuCloudConfigHelper 合并并发，避免重复 GET /qingyu/webdav。 */
  private async prefetchQingyuWebDavIfNeeded(): Promise<void> {
    try {
      const provider = await PreferencesService.getInstance().getSyncProvider()
      if (provider !== 'qingyu_cloud') {
        return
      }
      const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
      if (tok === null || tok.length === 0) {
        return
      }
      await buildQingyuCloudWebDavConfig()
    } catch (_) {
      // 后续同步与设置页会再次请求
    }
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