import { fileIo as fs } from '@kit.CoreFileKit'
import { media } from '@kit.MediaKit'
import { Logger } from '../common/utils/Logger'

const TAG = 'AudioPlayback'

export class AudioPlaybackService {
  private static instance: AudioPlaybackService = new AudioPlaybackService()
  private avPlayer: media.AVPlayer | null = null
  private fileHandle: fs.File | null = null
  private positionCallback: ((positionMs: number, durationMs: number) => void) | undefined = undefined
  private stateCallback: ((playing: boolean, completed: boolean) => void) | undefined = undefined
  private positionTimer: number = -1

  static getInstance(): AudioPlaybackService {
    return AudioPlaybackService.instance
  }

  setCallbacks(
    positionCallback: ((positionMs: number, durationMs: number) => void) | undefined,
    stateCallback: ((playing: boolean, completed: boolean) => void) | undefined
  ): void {
    this.positionCallback = positionCallback
    this.stateCallback = stateCallback
  }

  async load(localPath: string): Promise<void> {
    await this.release()
    const stat = fs.statSync(localPath)
    if (stat.size <= 0) {
      throw new Error('audio file is empty')
    }
    this.fileHandle = fs.openSync(localPath, fs.OpenMode.READ_ONLY)
    this.avPlayer = await media.createAVPlayer()

    await new Promise<void>((resolve, reject) => {
      let settled = false
      const finish = (error?: Error): void => {
        if (settled) {
          return
        }
        settled = true
        clearTimeout(timeout)
        if (error) {
          reject(error)
        } else {
          resolve()
        }
      }
      const timeout = setTimeout((): void => {
        finish(new Error('AVPlayer prepare timeout'))
      }, 20000)

      this.avPlayer!.on('stateChange', async (state: media.AVPlayerState): Promise<void> => {
        Logger.info(TAG, `stateChange: ${state}`)
        if (this.stateCallback) {
          if (state === 'playing') {
            this.stateCallback(true, false)
          } else if (state === 'completed') {
            if (this.positionCallback && this.avPlayer) {
              const duration = this.avPlayer.duration
              this.positionCallback(duration > 0 ? duration : this.avPlayer.currentTime, duration)
            }
            this.stateCallback(false, true)
          } else if (state === 'paused' || state === 'stopped') {
            this.stateCallback(false, false)
          }
        }
        if (state === 'playing') {
          this.startPositionTimer()
        } else if (state === 'paused' || state === 'completed' || state === 'stopped') {
          this.stopPositionTimer()
        }
        try {
          if (state === 'initialized') {
            await this.avPlayer!.prepare()
          } else if (state === 'prepared') {
            finish()
          } else if (state === 'error') {
            finish(new Error('AVPlayer entered error state'))
          }
        } catch (error) {
          finish(error instanceof Error ? error : new Error(`${error}`))
        }
      })

      this.avPlayer!.on('error', (error: Object): void => {
        Logger.warn(TAG, `AVPlayer error: ${JSON.stringify(error)}`)
        finish(new Error('AVPlayer error'))
      })

      this.avPlayer!.fdSrc = {
        fd: this.fileHandle!.fd,
        offset: 0,
        length: stat.size
      }
    })
  }

  async play(): Promise<void> {
    await this.avPlayer?.play()
  }

  async pause(): Promise<void> {
    await this.avPlayer?.pause()
  }

  async setPlaying(playing: boolean): Promise<void> {
    if (playing) {
      await this.play()
    } else {
      await this.pause()
    }
  }

  async seekTo(ms: number): Promise<void> {
    if (this.avPlayer) {
      await this.avPlayer.seek(ms)
    }
  }

  async seekRelative(deltaMs: number): Promise<void> {
    if (!this.avPlayer) {
      return
    }
    const current = this.avPlayer.currentTime
    const duration = this.avPlayer.duration
    let target = current + deltaMs
    if (target < 0) {
      target = 0
    }
    if (duration > 0 && target > duration) {
      target = duration
    }
    await this.avPlayer.seek(target)
  }

  async setSpeed(rate: number): Promise<void> {
    if (this.avPlayer) {
      await this.avPlayer.setSpeed(rate)
    }
  }

  getDurationMs(): number {
    return this.avPlayer?.duration ?? 0
  }

  private startPositionTimer(): void {
    this.stopPositionTimer()
    this.positionTimer = setInterval(() => {
      if (this.avPlayer && this.positionCallback) {
        this.positionCallback(this.avPlayer.currentTime, this.avPlayer.duration)
      }
    }, 200)
    if (this.avPlayer && this.positionCallback) {
      this.positionCallback(this.avPlayer.currentTime, this.avPlayer.duration)
    }
  }

  private stopPositionTimer(): void {
    if (this.positionTimer >= 0) {
      clearInterval(this.positionTimer)
      this.positionTimer = -1
    }
  }

  private async release(): Promise<void> {
    this.stopPositionTimer()
    try {
      await this.avPlayer?.release()
    } catch (error) {
      Logger.warn(TAG, `release failed: ${JSON.stringify(error)}`)
    }
    this.avPlayer = null
    if (this.fileHandle) {
      try {
        fs.closeSync(this.fileHandle)
      } catch (error) {
        Logger.warn(TAG, `close file failed: ${JSON.stringify(error)}`)
      }
      this.fileHandle = null
    }
  }
}
