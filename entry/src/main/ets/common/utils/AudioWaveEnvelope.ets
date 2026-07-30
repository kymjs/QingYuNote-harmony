import { fileIo as fs } from '@kit.CoreFileKit'
import { Logger } from './Logger'

const TAG = 'AudioWaveEnvelope'
const BAR_COUNT = 48
const SILENCE_FLOOR = 0.08
const SILENCE_PEAK_THRESHOLD = 500

/**
 * Extracts a fixed-length loudness envelope from a local PCM WAV file.
 * Returns null when the bytes are not a supported PCM WAV (or parse fails).
 */
export class AudioWaveEnvelope {
  static readonly barCount: number = BAR_COUNT
  static readonly silenceFloor: number = SILENCE_FLOOR

  static extractFromFile(path: string, bars: number = BAR_COUNT): number[] | null {
    try {
      if (!fs.accessSync(path)) {
        return null
      }
      const size = fs.statSync(path).size
      if (size < 44) {
        return null
      }
      const buf = new ArrayBuffer(size)
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY)
      try {
        fs.readSync(file.fd, buf)
      } finally {
        fs.closeSync(file)
      }
      return AudioWaveEnvelope.extractFromBytes(buf, bars)
    } catch (e) {
      Logger.warn(TAG, `extractFromFile failed: ${JSON.stringify(e)}`)
      return null
    }
  }

  static extractFromBytes(buffer: ArrayBuffer, bars: number = BAR_COUNT): number[] | null {
    if (bars <= 0 || buffer.byteLength < 44) {
      return null
    }
    const view = new DataView(buffer)
    if (AudioWaveEnvelope.readAscii(view, 0, 4) !== 'RIFF' ||
      AudioWaveEnvelope.readAscii(view, 8, 4) !== 'WAVE') {
      return null
    }

    let offset = 12
    let audioFormat = 0
    let numChannels = 0
    let bitsPerSample = 0
    let dataOffset = -1
    let dataSize = 0
    const len = buffer.byteLength

    while (offset + 8 <= len) {
      const chunkId = AudioWaveEnvelope.readAscii(view, offset, 4)
      const chunkSize = view.getUint32(offset + 4, true)
      const bodyStart = offset + 8
      if (chunkId === 'fmt ' && bodyStart + 16 <= len) {
        audioFormat = view.getUint16(bodyStart, true)
        numChannels = view.getUint16(bodyStart + 2, true)
        bitsPerSample = view.getUint16(bodyStart + 14, true)
      } else if (chunkId === 'data') {
        dataOffset = bodyStart
        dataSize = chunkSize
        break
      }
      offset = bodyStart + chunkSize + (chunkSize % 2)
    }

    if (audioFormat !== 1 ||
      numChannels <= 0 ||
      bitsPerSample !== 16 ||
      dataOffset < 0 ||
      dataSize <= 0) {
      return null
    }

    const bytesPerFrame = numChannels * (bitsPerSample / 8)
    if (bytesPerFrame <= 0) {
      return null
    }
    const available = Math.min(dataSize, len - dataOffset)
    if (available < bytesPerFrame) {
      return null
    }
    const frameCount = Math.floor(available / bytesPerFrame)
    if (frameCount <= 0) {
      return null
    }

    const peaks: number[] = []
    for (let i = 0; i < bars; i++) {
      peaks.push(0)
    }
    for (let frame = 0; frame < frameCount; frame++) {
      const barIndex = Math.floor((frame * bars) / frameCount)
      const sampleOffset = dataOffset + frame * bytesPerFrame
      let framePeak = 0
      for (let ch = 0; ch < numChannels; ch++) {
        const sample = Math.abs(view.getInt16(sampleOffset + ch * 2, true))
        if (sample > framePeak) {
          framePeak = sample
        }
      }
      if (framePeak > peaks[barIndex]) {
        peaks[barIndex] = framePeak
      }
    }

    let globalMax = 0
    for (let i = 0; i < peaks.length; i++) {
      if (peaks[i] > globalMax) {
        globalMax = peaks[i]
      }
    }
    if (globalMax <= SILENCE_PEAK_THRESHOLD) {
      const silent: number[] = []
      for (let i = 0; i < bars; i++) {
        silent.push(SILENCE_FLOOR)
      }
      return silent
    }

    const result: number[] = []
    for (let i = 0; i < bars; i++) {
      const raw = peaks[i]
      if (raw <= SILENCE_PEAK_THRESHOLD) {
        result.push(SILENCE_FLOOR)
        continue
      }
      const normalized = raw / globalMax
      if (normalized < SILENCE_FLOOR) {
        result.push(SILENCE_FLOOR)
      } else {
        result.push(Math.min(1.0, Math.max(SILENCE_FLOOR, normalized)))
      }
    }
    return result
  }

  private static readAscii(view: DataView, offset: number, length: number): string {
    let out = ''
    for (let i = 0; i < length; i++) {
      out += String.fromCharCode(view.getUint8(offset + i))
    }
    return out
  }
}
