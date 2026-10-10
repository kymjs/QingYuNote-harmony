import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import { LinkExtractConstants } from '../common/constants/LinkExtractConstants'
import { Logger } from '../common/utils/Logger'
import { VoiceTranscriptSegment } from '../common/utils/VoiceSegmentSplitter'
import { PreferencesService } from './PreferencesService'

const TAG = 'VoiceTts'

export class VoiceTtsResult {
  audioBytes: Uint8Array = new Uint8Array(0)
  segments: VoiceTranscriptSegment[] = []

  constructor(audioBytes: Uint8Array = new Uint8Array(0), segments: VoiceTranscriptSegment[] = []) {
    this.audioBytes = audioBytes
    this.segments = segments
  }
}

interface TtsRequestBody {
  text: string
}

export class VoiceTtsClient {
  private static instance: VoiceTtsClient = new VoiceTtsClient()
  private readonly base64: util.Base64Helper = new util.Base64Helper()

  static getInstance(): VoiceTtsClient {
    return VoiceTtsClient.instance
  }

  async synthesize(text: string): Promise<VoiceTtsResult> {
    const cleaned = text.trim()
    if (cleaned.length === 0) {
      throw new Error('转语音笔记失败')
    }
    const token = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (token === null || token.trim().length === 0) {
      Logger.warn(TAG, 'synthesize aborted: missing access token')
      throw new Error('未登录或服务不可用')
    }
    const base = LinkExtractConstants.baseUrl.replace(/\/+$/, '')
    const fullUrl = `${base}/api/v1/tts`
    const body: TtsRequestBody = { text: cleaned }
    Logger.info(TAG, `synthesize request url=${fullUrl} textLength=${cleaned.length}`)
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
        readTimeout: 30000
      })
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        Logger.error(TAG,
          `synthesize failed code=${resp.responseCode} body=${((resp.result as string) ?? '').slice(0, 500)}`)
        throw new Error('转语音笔记失败')
      }
      const obj = JSON.parse((resp.result as string) ?? '{}') as Record<string, Object>
      const b64 = `${obj['audio_base64'] ?? ''}`.trim()
      if (b64.length === 0) {
        throw new Error('转语音笔记失败')
      }
      let audioBytes: Uint8Array
      try {
        audioBytes = this.base64.decodeSync(b64)
      } catch (e) {
        Logger.error(TAG, `synthesize base64 decode failed: ${JSON.stringify(e)}`)
        throw new Error('转语音笔记失败')
      }
      if (audioBytes.length === 0) {
        throw new Error('转语音笔记失败')
      }
      const segments = VoiceTtsClient.parseSegments(obj['segments'])
      if (segments.length > 0 && segments[0].startMs !== 0) {
        segments[0] = { startMs: 0, text: segments[0].text }
      }
      Logger.info(TAG,
        `synthesize success bytes=${audioBytes.length} segments=${segments.length}`)
      return new VoiceTtsResult(audioBytes, segments)
    } catch (e) {
      if (e instanceof Error) {
        Logger.error(TAG, `synthesize error message=${e.message}`)
        throw e
      }
      const be = e as BusinessError
      Logger.error(TAG, `synthesize business error code=${be?.code} message=${be?.message}`)
      throw new Error(be?.message ?? '转语音笔记失败')
    } finally {
      req.destroy()
    }
  }

  private static parseSegments(raw: Object | undefined | null): VoiceTranscriptSegment[] {
    if (raw === undefined || raw === null || !Array.isArray(raw)) {
      return []
    }
    const list = raw as Object[]
    const segments: VoiceTranscriptSegment[] = []
    for (let i = 0; i < list.length; i++) {
      const item = list[i]
      if (typeof item !== 'object' || item === null) {
        continue
      }
      const map = item as Record<string, Object>
      const text = `${map['text'] ?? ''}`.trim()
      if (text.length === 0) {
        continue
      }
      const startRaw = map['start_ms']
      let startMs = 0
      if (typeof startRaw === 'number') {
        startMs = Math.floor(startRaw)
      } else {
        const parsed = Number(`${startRaw ?? 0}`)
        startMs = Number.isFinite(parsed) ? Math.floor(parsed) : 0
      }
      if (startMs < 0) {
        startMs = 0
      }
      segments.push({ startMs: startMs, text: text })
    }
    return segments
  }
}
