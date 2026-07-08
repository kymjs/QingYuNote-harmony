export class AudioConstants {
  static readonly audioDirectory: string = 'audio'
  /** 语音转写使用 WAV/PCM，ASR 容器无需 ffmpeg 即可解码；m4a 在服务端常解码失败。 */
  static readonly audioFileExtension: string = '.wav'

  static audioFileNameForNote(noteId: string): string {
    return `${noteId}${AudioConstants.audioFileExtension}`
  }
}
