import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit'
import { camera, cameraPicker } from '@kit.CameraKit'
import { AppContextHolder } from '../../services/AppContextHolder'
import { Logger } from './Logger'

const TAG = 'NoteCameraCapture'

export async function requestCameraPermission(): Promise<boolean> {
  const ctx = AppContextHolder.tryGetContext()
  if (!ctx) {
    return false
  }
  const atManager = abilityAccessCtrl.createAtManager()
  const permission: Permissions = 'ohos.permission.CAMERA'
  const result = await atManager.requestPermissionsFromUser(ctx, [permission])
  return result.authResults.length > 0 &&
    result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
}

/** 打开系统相机拍照，成功返回图片 URI；取消或失败返回空串。调用前需已授权相机。 */
export async function capturePhotoUri(context: common.UIAbilityContext): Promise<string> {
  try {
    const pickerProfile: cameraPicker.PickerProfile = {
      cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
    }
    const pickerResult: cameraPicker.PickerResult = await cameraPicker.pick(
      context,
      [cameraPicker.PickerMediaType.PHOTO],
      pickerProfile
    )
    if (pickerResult.resultCode !== 0) {
      return ''
    }
    return pickerResult.resultUri ?? ''
  } catch (error) {
    Logger.warn(TAG, `pick failed: ${JSON.stringify(error)}`)
    return ''
  }
}
