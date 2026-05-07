import { ComponentContent, UIContext } from '@kit.ArkUI'
import { Want } from '@kit.AbilityKit'
import promptAction from '@ohos.promptAction'
import { AppContextHolder } from './AppContextHolder'
import { ForceUpdateDialog, ForceUpdateDialogParams } from '../dialogs/ForceUpdateDialog'
import {
  ReleaseManifest,
  compareSemanticVersions,
  fetchReleaseManifest,
  getAppVersionName,
  manifestUsable
} from './AppUpdateService'

/** 本会话内可选更新仅提示一次（与 Flutter 一致）；强更不受限。 */
let optionalPromptShownThisSession: boolean = false

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

function showForceUpdateDialog(uiContext: UIContext, manifest: ReleaseManifest): void {
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
    /**
     * 注册后返回键/蒙层/侧滑等不会立即关闭弹窗；仅在调用 dismissDialogAction.dismiss() 时关闭。
     * 强更场景不得关闭，故不调用 dismiss。
     */
    onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
      // 不调用 dismissDialogAction.dismiss()，禁止通过返回、点蒙层、侧滑、ESC 关闭
    }
  }
  void uiContext.getPromptAction().openCustomDialog(content, dialogOpts)
}

function buildOptionalMessage(manifest: ReleaseManifest): string {
  return [
    `检测到新版本v${manifest.latestRelease}，是否更新？`,
    '',
    '更新内容：',
    manifest.upgradeText
  ].join('\n')
}

async function showOptionalUpdateDialog(
  uiContext: UIContext,
  manifest: ReleaseManifest
): Promise<void> {
  const prompt = uiContext.getPromptAction()
  const message = buildOptionalMessage(manifest)
  const dialogOpts: promptAction.ShowDialogOptions = {
    title: '发现新版本',
    message,
    buttons: [
      { text: '暂不更新', color: '#6B7280' },
      { text: '立即更新', color: '#0DAA4A' }
    ]
  }
  try {
    const result: promptAction.ShowDialogSuccessResponse = await prompt.showDialog(dialogOpts)
    if (result.index === 1) {
      openDownloadUri(manifest.downloadUrl)
    }
  } catch (e) {
    console.error(`showOptionalUpdateDialog: ${JSON.stringify(e)}`)
  }
}

/**
 * 应用进入首页并完成首屏加载后调用；网络错误静默。
 */
export async function runAppUpdateCheckOnLaunch(uiContext: UIContext): Promise<void> {
  const manifest = await fetchReleaseManifest()
  if (manifest === null || !manifestUsable(manifest)) {
    return
  }
  const current = await getAppVersionName()
  const needForce = compareSemanticVersions(current, manifest.latestVersion) < 0
  const needOptional = compareSemanticVersions(current, manifest.latestRelease) < 0
  if (needForce) {
    showForceUpdateDialog(uiContext, manifest)
    return
  }
  if (!needOptional) {
    return
  }
  if (optionalPromptShownThisSession) {
    return
  }
  optionalPromptShownThisSession = true
  await showOptionalUpdateDialog(uiContext, manifest)
}

/**
 * 关于页「检查更新」。
 */
export async function runAppUpdateCheckManually(uiContext: UIContext): Promise<void> {
  const prompt = uiContext.getPromptAction()
  const manifest = await fetchReleaseManifest()
  if (manifest === null || !manifestUsable(manifest)) {
    const toastOpts: promptAction.ShowToastOptions = {
      message: '无法获取更新信息，请检查网络后重试',
      duration: 2200
    }
    prompt.showToast(toastOpts)
    return
  }
  const current = await getAppVersionName()
  const needForce = compareSemanticVersions(current, manifest.latestVersion) < 0
  const needOptional = compareSemanticVersions(current, manifest.latestRelease) < 0
  if (!needForce && !needOptional) {
    const toastOpts: promptAction.ShowToastOptions = {
      message: `当前已是最新版本`,
      duration: 2000
    }
    prompt.showToast(toastOpts)
    return
  }
  if (needForce) {
    showForceUpdateDialog(uiContext, manifest)
    return
  }
  await showOptionalUpdateDialog(uiContext, manifest)
}
