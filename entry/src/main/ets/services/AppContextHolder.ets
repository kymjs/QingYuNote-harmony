import type common from '@ohos.app.ability.common'

export class AppContextHolder {
  private static abilityContext?: common.UIAbilityContext

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
}
