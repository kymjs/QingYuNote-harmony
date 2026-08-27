/** 历史版本「最后编辑自」所用的客户端平台，与 Flutter `NotePlatformSource` 对齐。 */
export class NotePlatformSource {
  static readonly android: string = 'Android'
  static readonly ios: string = 'iOS'
  static readonly iPad: string = 'iPad'
  static readonly macOS: string = 'macOS'
  static readonly linux: string = 'Linux'
  static readonly windows: string = 'Windows'
  static readonly harmonyOS: string = 'HarmonyOS'

  static current(): string {
    return NotePlatformSource.harmonyOS
  }

  static normalize(raw: string): string {
    const key = raw.trim().toLowerCase()
    if (key === 'android') {
      return NotePlatformSource.android
    }
    if (key === 'ios' || key === 'iphone') {
      return NotePlatformSource.ios
    }
    if (key === 'ipad') {
      return NotePlatformSource.iPad
    }
    if (key === 'macos' || key === 'mac') {
      return NotePlatformSource.macOS
    }
    if (key === 'linux') {
      return NotePlatformSource.linux
    }
    if (key === 'windows') {
      return NotePlatformSource.windows
    }
    if (key === 'harmony' || key === 'harmonyos') {
      return NotePlatformSource.harmonyOS
    }
    if (raw === NotePlatformSource.android ||
      raw === NotePlatformSource.ios ||
      raw === NotePlatformSource.iPad ||
      raw === NotePlatformSource.macOS ||
      raw === NotePlatformSource.linux ||
      raw === NotePlatformSource.windows ||
      raw === NotePlatformSource.harmonyOS) {
      return raw
    }
    return ''
  }
}
