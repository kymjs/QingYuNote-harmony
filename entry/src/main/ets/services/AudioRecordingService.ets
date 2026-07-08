import { audio } from '@kit.AudioKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit'
import { AppContextHolder } from './AppContextHolder'
import { AudioConstants } from '../common/constants/AudioConstants'
import { Logger } from '../common/utils/Logger'

const TAG = 'AudioRecording'
const SAMPLE_RATE = 16000
const NUM_CHANNELS = 1
const BITS_PER_SAMPLE = 16
const WAV_HEADER_SIZE = 44

export class AudioRecordingService {
  private static instance: AudioRecordingService = new AudioRecordingService()
  private audioCapturer: audio.AudioCapturer | null = null
  private outputPath: string = ''
  private fileHandle: fs.File | null = null
  private pcmDataSize: number = 0
  private amplitudeCallback: ((level: number) => void) | undefined = undefined
  private recording: boolean = false
  private readonly onReadData = (buffer: ArrayBuffer): void => {
    if (!this.recording || !this.fileHandle || buffer.byteLength <= 0) {
      return
    }
    try {
      fs.writeSync(this.fileHandle.fd, buffer)
      this.pcmDataSize += buffer.byteLength
      if (this.amplitudeCallback) {
        this.amplitudeCallback(this.computeAmplitudeFromPcm(buffer))
      }
    } catch (error) {
      Logger.warn(TAG, `write pcm failed: ${JSON.stringify(error)}`)
    }
  }

  static getInstance(): AudioRecordingService {
    return AudioRecordingService.instance
  }

  setAmplitudeCallback(callback: ((level: number) => void) | undefined): void {
    this.amplitudeCallback = callback
  }

  async requestPermission(): Promise<boolean> {
    const ctx = AppContextHolder.tryGetContext()
    if (!ctx) {
      return false
    }
    const atManager = abilityAccessCtrl.createAtManager()
    const permission: Permissions = 'ohos.permission.MICROPHONE'
    const result = await atManager.requestPermissionsFromUser(ctx, [permission])
    return result.authResults.length > 0 && result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
  }

  resolveOutputPath(noteId: string): string {
    const ctx = AppContextHolder.tryGetContext()
    const base = ctx?.filesDir ?? ''
    return `${base}/${AudioConstants.audioDirectory}/${AudioConstants.audioFileNameForNote(noteId)}`
  }

  private ensureAudioDir(): void {
    const ctx = AppContextHolder.tryGetContext()
    if (!ctx) {
      return
    }
    const dir = `${ctx.filesDir}/${AudioConstants.audioDirectory}`
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true)
      }
    } catch (_) {
      try {
        fs.mkdirSync(dir, true)
      } catch (error) {
        Logger.warn(TAG, `mkdir audio failed: ${JSON.stringify(error)}`)
      }
    }
  }

  async startRecording(outputPath: string): Promise<void> {
    const granted = await this.requestPermission()
    if (!granted) {
      throw new Error('microphone_permission_denied')
    }
    this.ensureAudioDir()
    await this.stopInternal(false)
    this.outputPath = outputPath
    this.pcmDataSize = 0
    this.fileHandle = fs.openSync(outputPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    fs.writeSync(this.fileHandle.fd, new ArrayBuffer(WAV_HEADER_SIZE))
    const capturerOptions: audio.AudioCapturerOptions = {
      streamInfo: {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      },
      capturerInfo: {
        source: audio.SourceType.SOURCE_TYPE_VOICE_RECOGNITION,
        capturerFlags: 0
      }
    }
    this.audioCapturer = await audio.createAudioCapturer(capturerOptions)
    this.audioCapturer.on('readData', this.onReadData)
    await this.audioCapturer.start()
    this.recording = true
  }

  private computeAmplitudeFromPcm(buffer: ArrayBuffer): number {
    const samples = new Int16Array(buffer)
    let max = 0
    for (let i = 0; i < samples.length; i++) {
      const abs = Math.abs(samples[i])
      if (abs > max) {
        max = abs
      }
    }
    return this.normalizeAmplitude(max)
  }

  private normalizeAmplitude(amplitude: number): number {
    if (amplitude >= 30000) {
      return 1
    }
    if (amplitude <= 500) {
      return 0.08
    }
    return Math.min(1, amplitude / 30000)
  }

  private writeWavHeader(fd: number, dataSize: number): void {
    const byteRate = SAMPLE_RATE * NUM_CHANNELS * BITS_PER_SAMPLE / 8
    const blockAlign = NUM_CHANNELS * BITS_PER_SAMPLE / 8
    const header = new ArrayBuffer(WAV_HEADER_SIZE)
    const view = new DataView(header)
    AudioRecordingService.writeAscii(view, 0, 'RIFF')
    view.setUint32(4, 36 + dataSize, true)
    AudioRecordingService.writeAscii(view, 8, 'WAVE')
    AudioRecordingService.writeAscii(view, 12, 'fmt ')
    view.setUint32(16, 16, true)
    view.setUint16(20, 1, true)
    view.setUint16(22, NUM_CHANNELS, true)
    view.setUint32(24, SAMPLE_RATE, true)
    view.setUint32(28, byteRate, true)
    view.setUint16(32, blockAlign, true)
    view.setUint16(34, BITS_PER_SAMPLE, true)
    AudioRecordingService.writeAscii(view, 36, 'data')
    view.setUint32(40, dataSize, true)
    fs.writeSync(fd, header, { offset: 0, length: WAV_HEADER_SIZE })
  }

  private static writeAscii(view: DataView, offset: number, text: string): void {
    for (let i = 0; i < text.length; i++) {
      view.setUint8(offset + i, text.charCodeAt(i))
    }
  }

  async stopRecording(): Promise<void> {
    await this.stopInternal(true)
  }

  async cancelRecording(outputPath: string): Promise<void> {
    await this.stopInternal(false)
    try {
      if (fs.accessSync(outputPath)) {
        fs.unlinkSync(outputPath)
      }
    } catch (_) {}
  }

  isRecording(): boolean {
    return this.recording
  }

  private async stopInternal(keepFile: boolean): Promise<void> {
    this.recording = false
    try {
      if (this.audioCapturer) {
        this.audioCapturer.off('readData', this.onReadData)
        await this.audioCapturer.stop()
        await this.audioCapturer.release()
      }
    } catch (_) {}
    this.audioCapturer = null
    if (this.fileHandle) {
      try {
        if (keepFile && this.pcmDataSize > 0) {
          this.writeWavHeader(this.fileHandle.fd, this.pcmDataSize)
        }
        fs.closeSync(this.fileHandle)
      } catch (_) {}
      this.fileHandle = null
    }
    if (!keepFile && this.outputPath.length > 0) {
      try {
        if (fs.accessSync(this.outputPath)) {
          fs.unlinkSync(this.outputPath)
        }
      } catch (_) {}
    }
    this.pcmDataSize = 0
    this.outputPath = ''
  }
}
