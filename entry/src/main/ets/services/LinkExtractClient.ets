import { http } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { LinkExtractConstants } from '../common/constants/LinkExtractConstants'
import { PreferencesService } from './PreferencesService'

const TAG = 'LinkExtract'

export interface LinkExtractResult {
  title: string
  content: string
}

export class LinkExtractClient {
  private static instance: LinkExtractClient = new LinkExtractClient()

  static getInstance(): LinkExtractClient {
    return LinkExtractClient.instance
  }

  static isVideoPlatformUrl(url: string): boolean {
    const lower = url.trim().toLowerCase()
    const hosts = [
      'douyin.com',
      'iesdouyin.com',
      'bilibili.com',
      'b23.tv',
      'xiaohongshu.com',
      'xhslink.com'
    ]
    for (let i = 0; i < hosts.length; i++) {
      if (lower.includes(hosts[i])) {
        return true
      }
    }
    return false
  }

  async extractLink(url: string, prompt: string, summarize: number = 0): Promise<LinkExtractResult> {
    const token = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (token === null || token.trim().length === 0) {
      console.error(`${TAG} no access token`)
      throw new Error('未登录或服务不可用')
    }

    const base = LinkExtractConstants.baseUrl.replace(/\/+$/, '')
    const fullUrl = `${base}/api/v1/extract`
    console.info(`${TAG} request url=${fullUrl} tokenLen=${token.trim().length} target=${url.trim()} summarize=${summarize}`)
    const req = http.createHttp()
    try {
      const resp = await req.request(fullUrl, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json'
        },
        extraData: JSON.stringify({
          url: url.trim(),
          prompt: prompt.trim(),
          summarize: summarize
        }),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 20000,
        readTimeout: 600000
      })
      const text = (resp.result as string) ?? ''
      console.info(`${TAG} responseCode=${resp.responseCode} bodyLen=${text.length}`)
      console.info(`${TAG} bodyHead=${text.substring(0, 800)}`)
      if (resp.responseCode === 401) {
        throw new Error('未登录或服务不可用')
      }
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error('AI 提取链接失败，请稍后重试')
      }
      let obj: Record<string, Object> | null = null
      try {
        obj = JSON.parse(text) as Record<string, Object>
      } catch (_) {
        console.error(`${TAG} json parse failed`)
        throw new Error('AI 提取链接失败，请稍后重试')
      }
      const title = `${obj['title'] ?? ''}`.trim()
      const content = `${obj['content'] ?? ''}`.trim()
      if (title.length === 0 && content.length === 0) {
        console.error(`${TAG} empty title & content`)
        throw new Error('AI 未返回有效内容')
      }
      if (content.length === 0 && LinkExtractClient.isVideoPlatformUrl(url)) {
        console.error(`${TAG} video platform returned empty content`)
        throw new Error('AI 提取链接失败，请稍后重试')
      }
      console.info(`${TAG} success titleLen=${title.length} contentLen=${content.length}`)
      return { title, content }
    } catch (e) {
      const be = e as BusinessError
      console.error(`${TAG} request error code=${be?.code} message=${be?.message} raw=${JSON.stringify(e)}`)
      throw e instanceof Error ? e : new Error(be?.message ?? 'AI 提取链接失败，请稍后重试')
    } finally {
      req.destroy()
    }
  }
}
