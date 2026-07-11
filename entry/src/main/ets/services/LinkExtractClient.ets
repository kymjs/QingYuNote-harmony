import { http } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { LinkExtractConstants } from '../common/constants/LinkExtractConstants'
import { PreferencesService } from './PreferencesService'

const TAG = 'LinkExtract'

export interface LinkExtractResult {
  title: string
  content: string
}

export interface SubmitJobResult {
  jobId: string
  noteId: string
  status: 'queued' | 'running' | 'succeeded' | 'failed' | 'partial'
  deduped: boolean
}

export interface JobResultPayload {
  title: string
  content: string
  platform: string
  sourceUrl: string
  description: string
}

export interface JobErrorPayload {
  code: string
  message: string
}

export interface JobStatusResult {
  jobId: string
  noteId: string
  url: string
  status: 'queued' | 'running' | 'succeeded' | 'failed' | 'partial'
  stage: string
  progress: number
  result: JobResultPayload | null
  error: JobErrorPayload | null
  createdAt: number
  updatedAt: number
  finishedAt: number | null
  attempt: number
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

  // ---------- Legacy sync endpoint ----------

  async extractLink(url: string, prompt: string, summarize: number = 0): Promise<LinkExtractResult> {
    const token = await this.requireToken()
    const base = LinkExtractConstants.baseUrl.replace(/\/+$/, '')
    const fullUrl = `${base}/api/v1/extract`
    const req = http.createHttp()
    try {
      const resp = await req.request(fullUrl, {
        method: http.RequestMethod.POST,
        header: this.headers(token),
        extraData: JSON.stringify({
          url: url.trim(),
          prompt: prompt.trim(),
          summarize: summarize
        }),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 20000,
        readTimeout: 600000
      })
      const code = resp.responseCode
      if (code === 410) {
        throw new Error('请升级到最新版本')
      }
      if (code === 401) {
        throw new Error('未登录或服务不可用')
      }
      if (code < 200 || code >= 300) {
        throw new Error('AI 提取链接失败，请稍后重试')
      }
      const obj = this.parseJson(resp.result as string)
      const title = `${obj['title'] ?? ''}`.trim()
      const content = `${obj['content'] ?? ''}`.trim()
      if (title.length === 0 && content.length === 0) {
        throw new Error('AI 未返回有效内容')
      }
      return { title, content }
    } finally {
      req.destroy()
    }
  }

  // ---------- Async job endpoints ----------

  async submitJob(
    url: string,
    prompt: string,
    summarize: number,
    noteId: string
  ): Promise<SubmitJobResult> {
    const token = await this.requireToken()
    const base = LinkExtractConstants.baseUrl.replace(/\/+$/, '')
    const fullUrl = `${base}/api/v1/extract/jobs`
    const req = http.createHttp()
    try {
      const resp = await req.request(fullUrl, {
        method: http.RequestMethod.POST,
        header: this.headers(token),
        extraData: JSON.stringify({
          url: url.trim(),
          prompt: prompt.trim(),
          summarize: summarize,
          note_id: noteId
        }),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 15000
      })
      const code = resp.responseCode
      if (code === 401) {
        throw new Error('未登录或服务不可用')
      }
      if (code < 200 || code >= 300) {
        console.error(`${TAG} submitJob status=${code} body=${(resp.result as string ?? '').substring(0, 500)}`)
        throw new Error('AI 提取链接失败，请稍后重试')
      }
      const obj = this.parseJson(resp.result as string)
      return {
        jobId: `${obj['job_id'] ?? ''}`,
        noteId: `${obj['note_id'] ?? noteId}`,
        status: (obj['status'] as SubmitJobResult['status']) ?? 'queued',
        deduped: obj['deduped'] === true
      }
    } finally {
      req.destroy()
    }
  }

  async getJob(jobId: string): Promise<JobStatusResult> {
    const token = await this.requireToken()
    const base = LinkExtractConstants.baseUrl.replace(/\/+$/, '')
    const fullUrl = `${base}/api/v1/extract/jobs/${jobId}`
    const req = http.createHttp()
    try {
      const resp = await req.request(fullUrl, {
        method: http.RequestMethod.GET,
        header: this.headers(token),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 15000
      })
      const code = resp.responseCode
      if (code === 401) {
        throw new Error('未登录或服务不可用')
      }
      if (code === 404) {
        throw new Error('job_not_found')
      }
      if (code < 200 || code >= 300) {
        throw new Error('AI 提取链接失败，请稍后重试')
      }
      const obj = this.parseJson(resp.result as string)
      let result: JobResultPayload | null = null
      const rawResult = obj['result']
      if (rawResult && typeof rawResult === 'object') {
        const r = rawResult as Record<string, Object>
        result = {
          title: `${r['title'] ?? ''}`,
          content: `${r['content'] ?? ''}`,
          platform: `${r['platform'] ?? ''}`,
          sourceUrl: `${r['source_url'] ?? ''}`,
          description: `${r['description'] ?? ''}`
        }
      }
      let error: JobErrorPayload | null = null
      const rawError = obj['error']
      if (rawError && typeof rawError === 'object') {
        const e = rawError as Record<string, Object>
        error = {
          code: `${e['code'] ?? ''}`,
          message: `${e['message'] ?? ''}`
        }
      }
      const numOr = (v: Object, fallback: number) => (typeof v === 'number') ? v : fallback
      return {
        jobId: `${obj['job_id'] ?? ''}`,
        noteId: `${obj['note_id'] ?? ''}`,
        url: `${obj['url'] ?? ''}`,
        status: (obj['status'] as JobStatusResult['status']) ?? 'queued',
        stage: `${obj['stage'] ?? ''}`,
        progress: numOr(obj['progress'] as Object, 0),
        result,
        error,
        createdAt: numOr(obj['created_at'] as Object, 0),
        updatedAt: numOr(obj['updated_at'] as Object, 0),
        finishedAt: (typeof obj['finished_at'] === 'number') ? (obj['finished_at'] as number) : null,
        attempt: numOr(obj['attempt'] as Object, 1)
      }
    } finally {
      req.destroy()
    }
  }

  // ---------- internals ----------

  private async requireToken(): Promise<string> {
    const token = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (token === null || token.trim().length === 0) {
      throw new Error('未登录或服务不可用')
    }
    return token.trim()
  }

  private headers(token: string): Record<string, string> {
    return {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json'
    }
  }

  private parseJson(text: string): Record<string, Object> {
    if (!text) {
      throw new Error('AI 提取链接失败，请稍后重试')
    }
    try {
      return JSON.parse(text) as Record<string, Object>
    } catch (_) {
      throw new Error('AI 提取链接失败，请稍后重试')
    }
  }
}
