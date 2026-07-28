/** 语音笔记页完成/取消时由 EventHub 投递；NoteEdit 一次性监听。 */
export const VOICE_NOTE_RESULT_EVENT = 'note_voice_note_result'

/** EventHub 载荷（禁止匿名对象字面量，满足 arkts-no-untyped-obj-literals） */
export class VoiceNoteEmitComplete {
  path: string = ''

  constructor(p: string) {
    this.path = p
  }
}

export class VoiceNoteEmitCancel {
  cancelled: boolean = true
}
