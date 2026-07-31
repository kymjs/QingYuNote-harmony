import http from '@ohos.net.http'
import { Logger } from '../common/utils/Logger'

export interface LinkOgMeta {
  title: string
  author: string
  date: string
  description: string
  imageUrl: string
  isFallback: boolean
}

export function linkOgMetaLine(meta: LinkOgMeta): string {
  return `${meta.author} · ${meta.date}`
}

export function linkOgFallback(): LinkOgMeta {
  return {
    title: '网页链接',
    author: '未知来源',
    date: '—',
    description: '暂时无法获取该链接的详细信息',
    imageUrl: '',
    isFallback: true
  }
}

export function linkOgLoading(anchorLabel: string): LinkOgMeta {
  const title = anchorLabel.trim().length > 0 ? anchorLabel.trim() : '加载中…'
  return {
    title: title,
    author: '未知来源',
    date: '—',
    description: '加载中…',
    imageUrl: '',
    isFallback: false
  }
}

const BROWSER_UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

/** 客户端直拉目标页解析 OG（失败走方案 A）。 */
export class LinkOgMetaService {
  private static instance?: LinkOgMetaService
  private cache: Map<string, LinkOgMeta> = new Map()
  private inflight: Map<string, Promise<LinkOgMeta>> = new Map()
  private static readonly MAX_CACHE: number = 64

  static getInstance(): LinkOgMetaService {
    if (!LinkOgMetaService.instance) {
      LinkOgMetaService.instance = new LinkOgMetaService()
    }
    return LinkOgMetaService.instance
  }

  async fetch(url: string, anchorLabel: string = ''): Promise<LinkOgMeta> {
    const trimmed = url.trim()
    if (trimmed.length === 0) {
      return linkOgFallback()
    }
    const cached = this.cache.get(trimmed)
    if (cached) {
      this.cache.delete(trimmed)
      this.cache.set(trimmed, cached)
      return cached
    }
    const existing = this.inflight.get(trimmed)
    if (existing) {
      return existing
    }
    const future = this.fetchUncached(trimmed, anchorLabel)
    this.inflight.set(trimmed, future)
    try {
      return await future
    } finally {
      this.inflight.delete(trimmed)
    }
  }

  private async fetchUncached(url: string, anchorLabel: string): Promise<LinkOgMeta> {
    try {
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        return linkOgFallback()
      }
      const req = http.createHttp()
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': BROWSER_UA,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 10000
      })
      req.destroy()
      const code = resp.responseCode
      const body = typeof resp.result === 'string' ? resp.result as string : ''
      if (code < 200 || code >= 400 || body.length === 0) {
        return linkOgFallback()
      }
      return this.storeIfSuccess(url, this.parseHtml(body, url, anchorLabel))
    } catch (e) {
      Logger.warn('LinkOgMetaService', `fetch failed: ${JSON.stringify(e)}`)
      return linkOgFallback()
    }
  }

  /** 仅缓存成功解析结果；fallback 不入缓存，便于下次重试。 */
  private storeIfSuccess(url: string, meta: LinkOgMeta): LinkOgMeta {
    if (meta.isFallback) {
      return meta
    }
    this.cache.set(url, meta)
    if (this.cache.size > LinkOgMetaService.MAX_CACHE) {
      const first = this.cache.keys().next().value as string
      this.cache.delete(first)
    }
    return meta
  }

  private parseHtml(html: string, pageUrl: string, anchorLabel: string): LinkOgMeta {
    const og = (prop: string): string => {
      const re1 = new RegExp(`property=["']og:${prop}["'][^>]*content=["']([^"']+)["']`, 'i')
      const re2 = new RegExp(`content=["']([^"']+)["'][^>]*property=["']og:${prop}["']`, 'i')
      const m1 = re1.exec(html)
      if (m1) {
        return m1[1]
      }
      const m2 = re2.exec(html)
      return m2 ? m2[1] : ''
    }
    const metaName = (name: string): string => {
      const re1 = new RegExp(`name=["']${name}["'][^>]*content=["']([^"']+)["']`, 'i')
      const re2 = new RegExp(`content=["']([^"']+)["'][^>]*name=["']${name}["']`, 'i')
      const m1 = re1.exec(html)
      if (m1) {
        return m1[1]
      }
      const m2 = re2.exec(html)
      return m2 ? m2[1] : ''
    }
    const titleMatch = /<title[^>]*>([^<]*)<\/title>/i.exec(html)
    let title = LinkOgMetaService.decodeHtml(og('title') || (titleMatch ? titleMatch[1] : '') ||
      anchorLabel).trim()
    let description = LinkOgMetaService.decodeHtml(og('description') || metaName('description')).trim()
    const imageUrl = LinkOgMetaService.resolveUrl(pageUrl, (og('image') || '').trim())
    let author = LinkOgMetaService.decodeHtml(
      og('site_name') || metaName('author') || metaName('article:author')
    ).trim()
    const dateRaw = (og('updated_time') || metaName('article:published_time') ||
      metaName('publish_date')).trim()
    let date = LinkOgMetaService.formatDate(dateRaw)
    if (title.length === 0 && description.length === 0 && imageUrl.length === 0) {
      return linkOgFallback()
    }
    const fb = linkOgFallback()
    return {
      title: title.length > 0 ? title : fb.title,
      author: author.length > 0 ? author : fb.author,
      date: date.length > 0 ? date : fb.date,
      description: description.length > 0 ? description : fb.description,
      imageUrl: imageUrl,
      isFallback: false
    }
  }

  private static resolveUrl(pageUrl: string, raw: string): string {
    if (raw.length === 0) {
      return ''
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw
    }
    try {
      // 简易相对路径解析：以页面目录为基准。
      if (raw.startsWith('//')) {
        const scheme = pageUrl.startsWith('https') ? 'https:' : 'http:'
        return scheme + raw
      }
      const schemeHostMatch = /^(https?:\/\/[^/?#]+)/i.exec(pageUrl)
      if (!schemeHostMatch) {
        return raw
      }
      const origin = schemeHostMatch[1]
      if (raw.startsWith('/')) {
        return origin + raw
      }
      const pathMatch = /^(https?:\/\/[^?#]*)/i.exec(pageUrl)
      const basePath = pathMatch ? pathMatch[1] : pageUrl
      const slash = basePath.lastIndexOf('/')
      const dir = slash > origin.length - 1 ? basePath.substring(0, slash + 1) : origin + '/'
      return dir + raw
    } catch (_) {
      return raw
    }
  }

  private static formatDate(raw: string): string {
    if (raw.length === 0) {
      return ''
    }
    if (raw.length >= 10 && raw.charAt(4) === '-' && raw.charAt(7) === '-') {
      return raw.substring(0, 10)
    }
    return raw.length > 10 ? raw.substring(0, 10) : raw
  }

  private static decodeHtml(input: string): string {
    return input
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&nbsp;/g, ' ')
  }
}
