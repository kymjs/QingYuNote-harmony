import { url } from '@kit.ArkTS'

/** Utilities for extracting a usable URL from pasted sharing text. */
export class LinkUrlUtils {
  private static readonly urlPattern: RegExp = /https?:\/\/[^\s<>"']+/ig
  private static readonly trailingPunctuation: string = '.,!?;:，。！？；：、)]}'

  /** Returns the first valid HTTP(S) URL in the pasted text. */
  static extractFirstUrl(input: string): string | null {
    const matches = input.match(LinkUrlUtils.urlPattern)
    if (matches === null) {
      return null
    }
    for (const match of matches) {
      const candidate = LinkUrlUtils.trimTrailingPunctuation(match)
      try {
        const parsed: url.URL = url.URL.parseURL(candidate)
        if ((parsed.protocol === 'http:' || parsed.protocol === 'https:') &&
            parsed.hostname.length > 0) {
          return candidate
        }
      } catch (_err) {
        // Continue searching if a malformed candidate was found.
      }
    }
    return null
  }

  private static trimTrailingPunctuation(value: string): string {
    let result = value
    while (result.length > 0 &&
      LinkUrlUtils.trailingPunctuation.includes(result[result.length - 1])) {
      result = result.substring(0, result.length - 1)
    }
    return result
  }
}
