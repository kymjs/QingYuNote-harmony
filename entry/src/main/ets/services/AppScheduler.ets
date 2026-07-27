import { connection } from '@kit.NetworkKit'
import { PreferencesService } from './PreferencesService'
import { SyncService } from './SyncService'
import { Logger } from '../common/utils/Logger'

export class AppScheduler {
  private static instance: AppScheduler = new AppScheduler()
  private syncIntervalId: number = -1
  private networkPollId: number = -1
  private wasNetworkAvailable: boolean = false
  private initialized: boolean = false

  static getInstance(): AppScheduler {
    return AppScheduler.instance
  }

  async init(): Promise<void> {
    if (this.initialized) {
      return
    }
    await SyncService.getInstance().init()
    this.wasNetworkAvailable = this.isNetworkAvailable()
    this.startIntervalSchedule()
    this.startNetworkPolling()
    this.initialized = true
  }

  async onForeground(): Promise<void> {
    if (!await this.canAutoSync()) {
      return
    }
    await SyncService.getInstance().retryFailedNotes()
  }

  private startIntervalSchedule(): void {
    if (this.syncIntervalId !== -1) {
      clearInterval(this.syncIntervalId)
    }
    this.syncIntervalId = setInterval(() => {
      void this.runPeriodicSync()
    }, 60 * 1000)
  }

  private startNetworkPolling(): void {
    if (this.networkPollId !== -1) {
      clearInterval(this.networkPollId)
    }
    this.networkPollId = setInterval(() => {
      const available = this.isNetworkAvailable()
      if (available && !this.wasNetworkAvailable) {
        void SyncService.getInstance().onNetworkRestored()
      }
      this.wasNetworkAvailable = available
    }, 30 * 1000)
  }

  private async runPeriodicSync(): Promise<void> {
    try {
      if (!await this.canAutoSync()) {
        return
      }
      const policy = await PreferencesService.getInstance().getSyncPolicy()
      const lastSyncTime = await PreferencesService.getInstance().getLastSyncTime()
      if (Date.now() - lastSyncTime < policy.syncIntervalMinutes * 60 * 1000) {
        return
      }
      await SyncService.getInstance().syncNow()
    } catch (error) {
      Logger.warn('AppScheduler', `runPeriodicSync failed: ${JSON.stringify(error)}`)
    }
  }

  private async canAutoSync(): Promise<boolean> {
    const policy = await PreferencesService.getInstance().getSyncPolicy()
    if (!policy.autoSync || await PreferencesService.getInstance().isAuthInvalid()) {
      return false
    }
    if (!(await PreferencesService.getInstance().canRunCloudSync())) {
      return false
    }
    if (!this.isNetworkAvailable()) {
      return false
    }
    if (!policy.wifiOnly) {
      return true
    }
    return this.isWifi()
  }

  private isNetworkAvailable(): boolean {
    try {
      const netHandle = connection.getDefaultNetSync()
      return !!netHandle
    } catch (error) {
      Logger.warn('AppScheduler', `isNetworkAvailable failed: ${JSON.stringify(error)}`)
      return false
    }
  }

  private isWifi(): boolean {
    try {
      const netHandle = connection.getDefaultNetSync()
      const capabilities = connection.getNetCapabilitiesSync(netHandle)
      const bearerTypes = capabilities?.bearerTypes ?? []
      return bearerTypes.includes(connection.NetBearType.BEARER_WIFI)
    } catch (error) {
      Logger.warn('AppScheduler', `isWifi failed: ${JSON.stringify(error)}`)
      return false
    }
  }
}
