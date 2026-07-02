import type common from '@ohos.app.ability.common'
import { UIContext } from '@kit.ArkUI'

export class AppContextHolder {
  private static abilityContext?: common.UIAbilityContext
  private static lastUiContext?: UIContext

  static setContext(context: common.UIAbilityContext): void {
    AppContextHolder.abilityContext = context
  }

  static getContext(): common.UIAbilityContext {
    if (!AppContextHolder.abilityContext) {
      throw new Error('Ability context has not been initialized')
    }
    return AppContextHolder.abilityContext
  }

  static tryGetContext(): common.UIAbilityContext | undefined {
    return AppContextHolder.abilityContext
  }

  /** 供非页面代码（如 API 426）获取最近活跃页的 UIContext。 */
  static setLastUiContext(context: UIContext): void {
    AppContextHolder.lastUiContext = context
  }

  static tryGetLastUiContext(): UIContext | undefined {
    return AppContextHolder.lastUiContext
  }
}
