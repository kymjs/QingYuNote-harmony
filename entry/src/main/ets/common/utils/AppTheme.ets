import { ConfigurationConstant } from '@kit.AbilityKit'
import { AppContextHolder } from '../../services/AppContextHolder'
import { PreferencesService } from '../../services/PreferencesService'
import { Logger } from './Logger'

/** App 外观模式，与 Flutter ThemeMode / PreferencesService 一致。 */
export type AppThemeMode = 'system' | 'light' | 'dark'

export function normalizeAppThemeMode(raw: string): AppThemeMode {
  if (raw === 'light' || raw === 'dark' || raw === 'system') {
    return raw
  }
  return 'system'
}

/**
 * 将外观模式应用到 ApplicationContext.setColorMode。
 * `system` → COLOR_MODE_NOT_SET（跟随系统）。
 */
export function applyAppColorMode(mode: string): void {
  const normalized = normalizeAppThemeMode(mode)
  let colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
  if (normalized === 'light') {
    colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
  } else if (normalized === 'dark') {
    colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK
  }
  try {
    const ctx = AppContextHolder.tryGetContext()
    if (ctx === undefined) {
      Logger.warn('AppTheme', 'applyAppColorMode skipped: no ability context')
      return
    }
    ctx.getApplicationContext().setColorMode(colorMode)
  } catch (error) {
    Logger.warn('AppTheme', `applyAppColorMode failed: ${JSON.stringify(error)}`)
  }
}

/** 持久化并立即应用外观。 */
export async function setAndApplyAppThemeMode(mode: string): Promise<AppThemeMode> {
  const normalized = normalizeAppThemeMode(mode)
  await PreferencesService.getInstance().setAppThemeMode(normalized)
  applyAppColorMode(normalized)
  return normalized
}
