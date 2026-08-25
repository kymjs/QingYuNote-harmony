import { ComponentContent, UIContext } from '@kit.ArkUI'
import { Want } from '@kit.AbilityKit'
import { updateManager } from '@kit.AppGalleryKit'
import promptAction from '@ohos.promptAction'
import { AppContextHolder } from './AppContextHolder'
import { NoteApiClient } from './NoteApiClient'
import { ForceUpdateDialog, ForceUpdateDialogParams } from '../dialogs/ForceUpdateDialog'
import {
  ReleaseManifest,
  fetchReleaseManifestWithCache,
  getAppVersionNameForCompare,
  manifestUsable,
  needsForceUpdate
} from './AppUpdateService'

/** 本会话内应用市场普通更新仅提示一次；强更不受限。 */
let appGalleryPromptShownThisSession: boolean = false
let appGalleryUpdateCheckInFlight: boolean = false
let forceUpdateDialogVisible: boolean = false

const FORCE_DIALOG_MAX_ATTEMPTS = 3
const FORCE_DIALOG_RETRY_MS = 400
type AppGalleryUpdateCheckResult = 'shown' | 'noUpdate' | 'failed' | 'checking'

@Builder
function buildForceUpdateDialogContent(params: ForceUpdateDialogParams) {
  ForceUpdateDialog({
    message: params.message,
    downloadUrl: params.downloadUrl
  })
}

function openDownloadUri(downloadUrl: string): void {
  const context = AppContextHolder.tryGetContext()
  if (context === undefined) {
    return
  }
  const want: Want = {
    action: 'ohos.want.action.viewData',
    entities: ['entity.system.browsable'],
    uri: downloadUrl
  }
  context.startAbility(want).catch((err: Error) => {
    console.error(`openDownloadUri: ${JSON.stringify(err)}`)
  })
}

function terminateAppAfterForceDialogFailure(): void {
  const context = AppContextHolder.tryGetContext()
  if (context === undefined) {
    return
  }
  context.terminateSelf().catch((err: Error) => {
    console.error(`terminateSelf after force dialog failure: ${JSON.stringify(err)}`)
  })
}

function showForceUpdateDialog(uiContext: UIContext, manifest: ReleaseManifest, attempt: number = 0): void {
  if (forceUpdateDialogVisible) {
    return
  }
  const body = manifest.forceUpgradeText.length > 0
    ? manifest.forceUpgradeText
    : manifest.upgradeText
  const params: ForceUpdateDialogParams = {
    message: body,
    downloadUrl: manifest.downloadUrl
  }
  const content = new ComponentContent(uiContext, wrapBuilder(buildForceUpdateDialogContent), params)
  const dialogOpts: promptAction.BaseDialogOptions = {
    autoCancel: false,
    alignment: DialogAlignment.Center,
    isModal: true,
    onWillDismiss: (_dismissDialogAction: DismissDialogAction) => {
      // 强更不得关闭
    }
  }
  try {
    forceUpdateDialogVisible = true
    void uiContext.getPromptAction().openCustomDialog(content, dialogOpts)
  } catch (err) {
    forceUpdateDialogVisible = false
    console.error(`openCustomDialog failed (attempt ${attempt}): ${JSON.stringify(err)}`)
    if (attempt + 1 < FORCE_DIALOG_MAX_ATTEMPTS) {
      setTimeout(() => {
        showForceUpdateDialog(uiContext, manifest, attempt + 1)
      }, FORCE_DIALOG_RETRY_MS)
      return
    }
    terminateAppAfterForceDialogFailure()
  }
}

/**
 * 由应用市场判断普通更新并展示其系统弹窗。
 * 非应用市场安装、无新版本和调用失败时均不展示自定义弹窗。
 */
async function checkAndShowAppGalleryUpdate(): Promise<AppGalleryUpdateCheckResult> {
  if (appGalleryUpdateCheckInFlight) {
    return 'checking'
  }
  const context = AppContextHolder.tryGetContext()
  if (context === undefined) {
    console.error('checkAndShowAppGalleryUpdate: ability context unavailable')
    return 'failed'
  }
  appGalleryUpdateCheckInFlight = true
  try {
    const checkResult = await updateManager.checkAppUpdate(context)
    if (checkResult.updateAvailable !== updateManager.UpdateAvailableCode.LATER_VERSION_EXIST) {
      return 'noUpdate'
    }
    // 服务端版本同步只允许由应用市场明确检测到有更新的分支触发。
    void NoteApiClient.getInstance().reportAppMarketUpdateDetected()
    const showResult = await updateManager.showUpdateDialog(context)
    if (showResult === updateManager.ShowUpdateResultCode.SHOW_DIALOG_SUCCESS) {
      return 'shown'
    }
    console.error(`showUpdateDialog failed: result=${showResult}`)
    return 'failed'
  } catch (e) {
    console.error(`checkAndShowAppGalleryUpdate: ${JSON.stringify(e)}`)
    return 'failed'
  } finally {
    appGalleryUpdateCheckInFlight = false
  }
}

/** 启动门禁：需强更则返回 manifest，否则 null。 */
export async function evaluateForceUpdateForGate(): Promise<ReleaseManifest | null> {
  const manifest = await fetchReleaseManifestWithCache()
  if (manifest === null) {
    return null
  }
  const current = await getAppVersionNameForCompare()
  if (!needsForceUpdate(current, manifest)) {
    return null
  }
  return manifest
}

/**
 * 应用进入首页并完成首屏加载后调用；网络错误时用缓存判定强更。
 */
export async function runAppUpdateCheckOnLaunch(uiContext: UIContext): Promise<void> {
  const manifest = await fetchReleaseManifestWithCache()
  if (manifest === null || !manifestUsable(manifest)) {
    return
  }
  const current = await getAppVersionNameForCompare()
  if (needsForceUpdate(current, manifest)) {
    showForceUpdateDialog(uiContext, manifest)
    return
  }
  if (appGalleryPromptShownThisSession) {
    return
  }
  const result = await checkAndShowAppGalleryUpdate()
  if (result === 'shown') {
    appGalleryPromptShownThisSession = true
  }
}

/** 前后台恢复或回首页时仅复检强更（应用市场普通更新仍本会话一次）。 */
export async function recheckForceUpdateOnResume(uiContext: UIContext): Promise<void> {
  const manifest = await fetchReleaseManifestWithCache()
  if (manifest === null) {
    return
  }
  const current = await getAppVersionNameForCompare()
  if (needsForceUpdate(current, manifest)) {
    showForceUpdateDialog(uiContext, manifest)
  }
}

/** WebDAV 同步前版本门禁；需强更时弹窗并返回 true（应中止同步）。 */
export async function blockWebDavSyncIfForceUpdateRequired(): Promise<boolean> {
  const manifest = await fetchReleaseManifestWithCache()
  if (manifest === null) {
    return false
  }
  const current = await getAppVersionNameForCompare()
  if (!needsForceUpdate(current, manifest)) {
    return false
  }
  const ctx = AppContextHolder.tryGetLastUiContext()
  if (ctx !== undefined) {
    showForceUpdateDialog(ctx, manifest)
  }
  return true
}

/** 服务端 426 upgrade_required。 */
export async function handleServerUpgradeRequired(
  uiContext: UIContext | undefined,
  minVersion?: string,
  downloadUrl?: string
): Promise<void> {
  let manifest = await fetchReleaseManifestWithCache()
  if (manifest !== null && minVersion !== undefined && minVersion.length > 0 &&
    manifest.latestVersion !== minVersion) {
    manifest = {
      latestVersion: minVersion,
      downloadUrl: (downloadUrl !== undefined && downloadUrl.length > 0)
        ? downloadUrl
        : manifest.downloadUrl,
      upgradeText: manifest.upgradeText,
      forceUpgradeText: manifest.forceUpgradeText.length > 0
        ? manifest.forceUpgradeText
        : `当前版本已不再可用，请更新至 v${minVersion} 或更高版本。`
    }
  }
  if (manifest === null) {
    const fallbackVersion = minVersion ?? ''
    manifest = {
      latestVersion: fallbackVersion,
      downloadUrl: downloadUrl ?? '',
      upgradeText: '',
      forceUpgradeText: fallbackVersion.length > 0
        ? `当前版本已不再可用，请更新至 v${fallbackVersion} 或更高版本。`
        : '当前版本已不再可用，请更新应用。'
    }
  }
  const ctx = uiContext ?? AppContextHolder.tryGetLastUiContext()
  if (ctx === undefined) {
    return
  }
  showForceUpdateDialog(ctx, manifest)
}

/**
 * 关于页「检查更新」。
 */
export async function runAppUpdateCheckManually(uiContext: UIContext): Promise<void> {
  const prompt = uiContext.getPromptAction()
  const manifest = await fetchReleaseManifestWithCache()
  if (manifest === null || !manifestUsable(manifest)) {
    const toastOpts: promptAction.ShowToastOptions = {
      message: '无法获取更新信息，请检查网络后重试',
      duration: 2200
    }
    try {
      prompt.showToast(toastOpts)
    } catch (err) {
      console.error(`showToast failed: ${JSON.stringify(err)}`)
    }
    return
  }
  const current = await getAppVersionNameForCompare()
  if (needsForceUpdate(current, manifest)) {
    showForceUpdateDialog(uiContext, manifest)
    return
  }
  const result = await checkAndShowAppGalleryUpdate()
  if (result === 'shown' || result === 'checking') {
    return
  }
  const toastOpts: promptAction.ShowToastOptions = {
    message: result === 'noUpdate'
      ? '当前已是最新版本'
      : '无法通过应用市场检查更新，请稍后重试',
    duration: 2200
  }
  try {
    prompt.showToast(toastOpts)
  } catch (err) {
    console.error(`showToast failed: ${JSON.stringify(err)}`)
  }
}

/** 启动门禁全屏强更页用：打开应用市场/下载页。 */
export function openReleaseDownloadFromGate(downloadUrl: string): void {
  openDownloadUri(downloadUrl)
}

/** 供 UpdateGate 全屏展示文案。 */
export function forceUpdateMessageFromManifest(manifest: ReleaseManifest): string {
  return manifest.forceUpgradeText.length > 0
    ? manifest.forceUpgradeText
    : manifest.upgradeText
}
