import { http } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { LinkExtractConstants } from '../common/constants/LinkExtractConstants'
import { Logger } from '../common/utils/Logger'
import { PreferencesService } from './PreferencesService'

const TAG = 'VoiceTranscribe'

/** Result of a voice transcription request. */
export class VoiceTranscribeResult {
  text: string = ''
  summary: string = ''

  constructor(text: string = '', summary: string = '') {
    this.text = text
    this.summary = summary
  }
}

/** `POST /api/v1/transcribe/recording` */
interface TranscribeRecordingRequestBody {
  user_id: number
  filename: string
  language: string
  optimize: number
  summarize: number
}

/** `POST /api/v1/transcribe/summarize` */
interface SummarizeTextRequestBody {
  text: string
}

export class VoiceTranscribeClient {
  private static instance: VoiceTranscribeClient = new VoiceTranscribeClient()

  static getInstance(): VoiceTranscribeClient {
    return VoiceTranscribeClient.instance
  }

  /**
   * 直接上传本地录音转写（推荐）：不依赖 NAS 挂载，WAV/PCM 无需服务端 ffmpeg。
   */
  async transcribeLocalFile(
    localPath: string,
    language: string = 'Chinese',
    optimize: number = 1,
    summarize: number = 1
  ): Promise<VoiceTranscribeResult> {
    const token = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (token === null || token.trim().length === 0) {
      Logger.warn(TAG, 'transcribeLocalFile aborted: missing access token')
      throw new Error('未登录或服务不可用')
    }
    const trimmedPath = localPath.trim()
    if (trimmedPath.length === 0) {
      throw new Error('录音文件未找到，请稍后重试')
    }
    let fileSize = 0
    try {
      fileSize = fs.statSync(trimmedPath).size
    } catch (e) {
      Logger.error(TAG, `transcribeLocalFile stat failed path=${trimmedPath} err=${JSON.stringify(e)}`)
      throw new Error('录音文件未找到，请稍后重试')
    }
    if (fileSize <= 0) {
      throw new Error('录音文件未找到，请稍后重试')
    }
    const fileBuf = new ArrayBuffer(fileSize)
    try {
      const file = fs.openSync(trimmedPath, fs.OpenMode.READ_ONLY)
      try {
        fs.readSync(file.fd, fileBuf)
      } finally {
        fs.closeSync(file)
      }
    } catch (e) {
      Logger.error(TAG, `transcribeLocalFile read failed path=${trimmedPath} err=${JSON.stringify(e)}`)
      throw new Error('录音文件未找到，请稍后重试')
    }

    const base = LinkExtractConstants.baseUrl.replace(/\/+$/, '')
    const fullUrl = `${base}/api/v1/transcribe`
    const mime = VoiceTranscribeClient.guessAudioMime(trimmedPath)
    const boundary = `----VoiceTranscribe${Date.now()}`
    const body = VoiceTranscribeClient.buildTranscribeMultipartBody(
      fileBuf, mime, boundary, language, optimize, summarize
    )
    Logger.info(TAG,
      `transcribeLocalFile request url=${fullUrl} path=${trimmedPath} bytes=${fileSize} mime=${mime} optimize=${optimize} summarize=${summarize}`
    )
    const req = http.createHttp()
    try {
      const resp = await req.request(fullUrl, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${token}`,
          'Accept': 'application/json',
          'Content-Type': `multipart/form-data; boundary=${boundary}`
        },
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 20000,
        readTimeout: 600000
      })
      return VoiceTranscribeClient.parseTranscribeResponse(
        resp.responseCode, (resp.result as string) ?? '', 'transcribeLocalFile'
      )
    } catch (e) {
      if (e instanceof Error) {
        Logger.error(TAG, `transcribeLocalFile error message=${e.message}`)
        throw e
      }
      const be = e as BusinessError
      Logger.error(TAG, `transcribeLocalFile business error code=${be?.code} message=${be?.message}`)
      throw new Error(be?.message ?? '语音转文字失败，请稍后重试')
    } finally {
      req.destroy()
    }
  }

  async transcribeRecording(
    userId: number,
    filename: string,
    language: string = 'Chinese',
    optimize: number = 1,
    summarize: number = 1
  ): Promise<VoiceTranscribeResult> {
    const token = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (token === null || token.trim().length === 0) {
      Logger.warn(TAG, 'transcribeRecording aborted: missing access token')
      throw new Error('未登录或服务不可用')
    }

    const base = LinkExtractConstants.baseUrl.replace(/\/+$/, '')
    const fullUrl = `${base}/api/v1/transcribe/recording`
    const body: TranscribeRecordingRequestBody = {
      user_id: userId,
      filename: filename.trim(),
      language,
      optimize,
      summarize
    }
    Logger.info(TAG,
      `transcribeRecording request url=${fullUrl} userId=${userId} filename=${body.filename} language=${language} optimize=${optimize} summarize=${summarize}`
    )
    const req = http.createHttp()
    try {
      const resp = await req.request(fullUrl, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json'
        },
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 20000,
        readTimeout: 600000
      })
      return VoiceTranscribeClient.parseTranscribeResponse(
        resp.responseCode, (resp.result as string) ?? '', 'transcribeRecording'
      )
    } catch (e) {
      if (e instanceof Error) {
        Logger.error(TAG, `transcribeRecording error message=${e.message}`)
        throw e
      }
      const be = e as BusinessError
      Logger.error(TAG, `transcribeRecording business error code=${be?.code} message=${be?.message}`)
      throw new Error(be?.message ?? '语音转文字失败，请稍后重试')
    } finally {
      req.destroy()
    }
  }

  /** 对已有转写正文补生成摘要（不重传音频）。 */
  async summarizeText(text: string): Promise<string> {
    const cleaned = text.trim()
    if (cleaned.length === 0) {
      return ''
    }
    const token = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (token === null || token.trim().length === 0) {
      Logger.warn(TAG, 'summarizeText aborted: missing access token')
      throw new Error('未登录或服务不可用')
    }
    const base = LinkExtractConstants.baseUrl.replace(/\/+$/, '')
    const fullUrl = `${base}/api/v1/transcribe/summarize`
    const body: SummarizeTextRequestBody = { text: cleaned }
    Logger.info(TAG, `summarizeText request url=${fullUrl} textLength=${cleaned.length}`)
    const req = http.createHttp()
    try {
      const resp = await req.request(fullUrl, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json'
        },
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 20000,
        readTimeout: 120000
      })
      if (resp.responseCode === 401) {
        Logger.warn(TAG, 'summarizeText unauthorized')
        throw new Error('未登录或服务不可用')
      }
      if (resp.responseCode === 404) {
        Logger.error(TAG, `summarizeText endpoint missing code=404 body=${((resp.result as string) ?? '').slice(0, 500)}`)
        throw new Error('摘要服务不可用，请稍后重试')
      }
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        Logger.error(TAG, `summarizeText failed code=${resp.responseCode} body=${((resp.result as string) ?? '').slice(0, 500)}`)
        throw new Error('生成摘要失败，请稍后重试')
      }
      const obj = JSON.parse((resp.result as string) ?? '{}') as Record<string, Object>
      const summary = `${obj['summary'] ?? ''}`.trim()
      Logger.info(TAG, `summarizeText success summaryLength=${summary.length}`)
      return summary
    } catch (e) {
      if (e instanceof Error) {
        Logger.error(TAG, `summarizeText error message=${e.message}`)
        throw e
      }
      const be = e as BusinessError
      Logger.error(TAG, `summarizeText business error code=${be?.code} message=${be?.message}`)
      throw new Error(be?.message ?? '生成摘要失败，请稍后重试')
    } finally {
      req.destroy()
    }
  }

  private static parseTranscribeResponse(responseCode: number, raw: string, label: string): VoiceTranscribeResult {
    Logger.info(TAG, `${label} response code=${responseCode} bodyLength=${raw.length}`)
    if (responseCode === 401) {
      Logger.warn(TAG, `${label} unauthorized`)
      throw new Error('未登录或服务不可用')
    }
    if (responseCode === 404) {
      Logger.warn(TAG, `${label} recording not found`)
      throw new Error('录音文件未找到，请稍后重试')
    }
    if (responseCode === 400 && raw.includes('invalid_audio')) {
      Logger.error(TAG, `${label} invalid audio body=${raw.slice(0, 500)}`)
      throw new Error('录音格式无法识别，请重新录制')
    }
    if (responseCode < 200 || responseCode >= 300) {
      Logger.error(TAG, `${label} failed code=${responseCode} body=${raw.slice(0, 500)}`)
      throw new Error('语音转文字失败，请稍后重试')
    }
    const obj = JSON.parse(raw) as Record<string, Object>
    const text = `${obj['text'] ?? ''}`.trim()
    if (text.length === 0) {
      Logger.warn(TAG, `${label} empty text payload=${raw.slice(0, 500)}`)
      throw new Error('语音转文字未返回有效内容')
    }
    const summary = `${obj['summary'] ?? ''}`.trim()
    Logger.info(TAG, `${label} success textLength=${text.length} summaryLength=${summary.length}`)
    return new VoiceTranscribeResult(text, summary)
  }

  private static guessAudioMime(path: string): string {
    const lower = path.toLowerCase()
    if (lower.endsWith('.wav')) {
      return 'audio/wav'
    }
    if (lower.endsWith('.m4a')) {
      return 'audio/mp4'
    }
    if (lower.endsWith('.mp3')) {
      return 'audio/mpeg'
    }
    return 'application/octet-stream'
  }

  private static multipartAsciiBytes(s: string): Uint8Array {
    const out = new Uint8Array(s.length)
    for (let i = 0; i < s.length; i++) {
      out[i] = s.charCodeAt(i) & 0xff
    }
    return out
  }

  private static buildTranscribeMultipartBody(
    fileBuf: ArrayBuffer,
    mime: string,
    boundary: string,
    language: string,
    optimize: number,
    summarize: number
  ): ArrayBuffer {
    const crlf = '\r\n'
    const optimizePart =
      `--${boundary}${crlf}` +
      `Content-Disposition: form-data; name="optimize"${crlf}${crlf}` +
      `${optimize}${crlf}`
    const summarizePart =
      `--${boundary}${crlf}` +
      `Content-Disposition: form-data; name="summarize"${crlf}${crlf}` +
      `${summarize}${crlf}`
    const langPart =
      `--${boundary}${crlf}` +
      `Content-Disposition: form-data; name="language"${crlf}${crlf}` +
      `${language}${crlf}`
    const filePartHead =
      `--${boundary}${crlf}` +
      `Content-Disposition: form-data; name="file"; filename="recording.wav"${crlf}` +
      `Content-Type: ${mime}${crlf}${crlf}`
    const tailStr = `${crlf}--${boundary}--${crlf}`
    const optimizeBytes = VoiceTranscribeClient.multipartAsciiBytes(optimizePart)
    const summarizeBytes = VoiceTranscribeClient.multipartAsciiBytes(summarizePart)
    const langBytes = VoiceTranscribeClient.multipartAsciiBytes(langPart)
    const head = VoiceTranscribeClient.multipartAsciiBytes(filePartHead)
    const tail = VoiceTranscribeClient.multipartAsciiBytes(tailStr)
    const mid = new Uint8Array(fileBuf)
    const out = new Uint8Array(
      optimizeBytes.length + summarizeBytes.length + langBytes.length + head.length + mid.length + tail.length
    )
    let offset = 0
    out.set(optimizeBytes, offset)
    offset += optimizeBytes.length
    out.set(summarizeBytes, offset)
    offset += summarizeBytes.length
    out.set(langBytes, offset)
    offset += langBytes.length
    out.set(head, offset)
    offset += head.length
    out.set(mid, offset)
    offset += mid.length
    out.set(tail, offset)
    return out.buffer.slice(out.byteOffset, out.byteOffset + out.byteLength)
  }
}
