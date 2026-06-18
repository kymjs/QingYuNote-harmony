import { preferences } from '@kit.ArkData'
import { i18n } from '@kit.LocalizationKit'
import type common from '@ohos.app.ability.common'
import { LOCALE_JA_MAP } from '../common/utils/LocaleJaStrings'
import { LOCALE_ZH_TW_MAP } from '../common/utils/LocaleZhTwStrings'
import { AppContextHolder } from './AppContextHolder'

/** 与 Flutter `AppConst.prefAppLanguageKey` 一致：`zh` | `zh-Hant` | `en` | `ja`，默认 `zh`。 */
export const APP_LANGUAGE_KEY = 'app_language'

export const LOCALE_CHANGED_EVENT = 'app_locale_changed'

/** 全局语言版本号，递增后触发依赖语言的 UI 重建。 */
export const APP_LOCALE_REVISION_KEY = 'appLocaleRevision'

export type AppLanguage = 'zh' | 'zh-Hant' | 'en' | 'ja'

/**
 * 应用语言服务：持久化用户选择，调用系统 API 切换资源语言，并广播变更。
 */
export class LocaleService {
  private static instance: LocaleService = new LocaleService()
  private language: AppLanguage = 'zh'
  private loaded: boolean = false

  static getInstance(): LocaleService {
    return LocaleService.instance
  }

  isEnglish(): boolean {
    return this.language === 'en'
  }

  isJapanese(): boolean {
    return this.language === 'ja'
  }

  isTraditionalChinese(): boolean {
    return this.language === 'zh-Hant'
  }

  getLanguage(): AppLanguage {
    return this.language
  }

  /** 无上下文的文案选择（Toast、服务等）。 */
  static loc(zh: string, en: string, ja?: string): string {
    const lang = LocaleService.getInstance().getLanguage()
    if (lang === 'en') {
      return en
    }
    if (lang === 'ja') {
      return ja ?? LOCALE_JA_MAP[zh] ?? en
    }
    if (lang === 'zh-Hant') {
      return LOCALE_ZH_TW_MAP[zh] ?? zh
    }
    return zh
  }

  async load(context?: common.Context): Promise<void> {
    if (this.loaded) {
      return
    }
    const ctx = context ?? AppContextHolder.tryGetContext()
    if (ctx) {
      const prefs = preferences.getPreferencesSync(ctx, { name: 'qingyu_preferences' })
      const raw = (prefs.getSync(APP_LANGUAGE_KEY, 'zh') as string).trim()
      this.language = raw === 'en' ? 'en' : raw === 'ja' ? 'ja' : raw === 'zh-Hant' ? 'zh-Hant' : 'zh'
    }
    this.applySystemLanguage()
    this.loaded = true
  }

  async setLanguage(language: AppLanguage, context?: common.Context): Promise<void> {
    if (this.language === language) {
      return
    }
    this.language = language
    const ctx = context ?? AppContextHolder.tryGetContext()
    if (ctx) {
      const prefs = preferences.getPreferencesSync(ctx, { name: 'qingyu_preferences' })
      prefs.putSync(APP_LANGUAGE_KEY, language)
      prefs.flush()
    }
    this.applySystemLanguage()
    this.bumpRevision()
    try {
      const hub = AppContextHolder.tryGetContext()?.eventHub
      hub?.emit(LOCALE_CHANGED_EVENT)
    } catch (_) {
      // ignore
    }
  }

  private applySystemLanguage(): void {
    try {
      const tag = this.language === 'en'
        ? 'en-US'
        : this.language === 'ja'
          ? 'ja-JP'
          : this.language === 'zh-Hant'
            ? 'zh-Hant'
            : 'zh-Hans'
      i18n.System.setAppPreferredLanguage(tag)
    } catch (e) {
      console.error(`LocaleService applySystemLanguage: ${JSON.stringify(e)}`)
    }
  }

  private bumpRevision(): void {
    const current = AppStorage.get<number>(APP_LOCALE_REVISION_KEY) ?? 0
    AppStorage.setOrCreate(APP_LOCALE_REVISION_KEY, current + 1)
  }
}
