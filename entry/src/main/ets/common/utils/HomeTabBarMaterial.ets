import { deviceInfo } from '@kit.BasicServicesKit'
import { hdsMaterial, type SystemMaterialParams } from '@kit.UIDesignKit'

/** 首页悬浮 TabBar 沉浸光感材质（HdsTabs barFloatingStyle.systemMaterialEffect）。 */
export class HomeTabBarMaterial {
  /** 沉浸光感需 API 23（6.1.0）及以上。 */
  private static readonly MIN_SDK_FOR_SYSTEM_MATERIAL: number = 23

  static resolveAdaptiveMaterial(): SystemMaterialParams | undefined {
    const sdkApi = deviceInfo.sdkApiVersion
    if (sdkApi < HomeTabBarMaterial.MIN_SDK_FOR_SYSTEM_MATERIAL) {
      return undefined
    }
    try {
      const supported: hdsMaterial.MaterialType[] = hdsMaterial.getSystemMaterialTypes()
      if (supported.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0 ||
        supported.indexOf(hdsMaterial.MaterialType.ADAPTIVE) >= 0) {
        const params: SystemMaterialParams = {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
        return params
      }
    } catch (_e) {
      return undefined
    }
    return undefined
  }
}
