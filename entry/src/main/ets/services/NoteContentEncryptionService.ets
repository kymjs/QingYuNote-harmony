import type { Note, NoteFilePayload } from '../common/model/Note'
import { CryptoService } from './CryptoService'
import { AppContextHolder } from './AppContextHolder'
import { PreferencesService } from './PreferencesService'

export class NoteContentEncryptionService {
  private static instance: NoteContentEncryptionService = new NoteContentEncryptionService()

  static getInstance(): NoteContentEncryptionService {
    return NoteContentEncryptionService.instance
  }

  async resolveUserId(): Promise<string | null> {
    const ctx = AppContextHolder.getContext()
    if (ctx) {
      await PreferencesService.getInstance().init(ctx)
    }
    const userId = (await PreferencesService.getInstance().getNoteApiUserId()).trim()
    return userId.length > 0 ? userId : null
  }

  static isRsaEncrypted(rsa: number): boolean {
    return rsa !== 0
  }

  needsEncryptionMigration(rsa: number, title: string, content: string): boolean {
    if (NoteContentEncryptionService.isRsaEncrypted(rsa)) {
      return false
    }
    return true
  }

  needsRsaFlagRepair(rsa: number, title: string, content: string): boolean {
    if (NoteContentEncryptionService.isRsaEncrypted(rsa)) {
      return false
    }
    return NoteContentEncryptionService.looksLikeNoteCipher(title) ||
      NoteContentEncryptionService.looksLikeNoteCipher(content)
  }

  /** 从未加密或缺少 `rsa` 的磁盘原文得到写入前明文（老笔记迁移用）。 */
  async plaintextPayloadFromRaw(payload: NoteFilePayload, userId: string): Promise<NoteFilePayload> {
    if (NoteContentEncryptionService.isRsaEncrypted(payload.state.rsa)) {
      return payload
    }
    if (this.needsRsaFlagRepair(payload.state.rsa, payload.state.title, payload.content)) {
      return this.decryptPayloadForDisplay(payload, userId)
    }
    return payload
  }

  async ensurePlaintextForStorage(note: Note, userId: string): Promise<Note> {
    if (!this.shouldDecryptFields(note.rsa, note.title, note.content)) {
      return note
    }
    const copied = this.copyNote(note)
    const force = NoteContentEncryptionService.isRsaEncrypted(note.rsa)
    copied.title = await this.decryptFieldFully(note.title, userId, force)
    copied.content = await this.decryptFieldFully(note.content, userId, force)
    return copied
  }

  async encryptNoteForStorage(note: Note, userId: string): Promise<Note> {
    const plain = await this.ensurePlaintextForStorage(note, userId)
    const crypto = CryptoService.getInstance()
    const copied = this.copyNote(plain)
    copied.title = await crypto.encryptNoteText(plain.title, userId)
    copied.content = await crypto.encryptNoteText(plain.content, userId)
    copied.rsa = 1
    return copied
  }

  async decryptNoteForDisplay(note: Note, userId: string): Promise<Note> {
    if (!this.shouldDecryptFields(note.rsa, note.title, note.content)) {
      return note
    }
    const copied = this.copyNote(note)
    const force = NoteContentEncryptionService.isRsaEncrypted(note.rsa)
    copied.title = await this.decryptFieldFully(note.title, userId, force)
    copied.content = await this.decryptFieldFully(note.content, userId, force)
    return copied
  }

  async decryptPayloadForDisplay(payload: NoteFilePayload, userId: string): Promise<NoteFilePayload> {
    if (!this.shouldDecryptFields(payload.state.rsa, payload.state.title, payload.content)) {
      return payload
    }
    const force = NoteContentEncryptionService.isRsaEncrypted(payload.state.rsa)
    payload.state.title = await this.decryptFieldFully(payload.state.title, userId, force)
    return {
      content: await this.decryptFieldFully(payload.content, userId, force),
      rawContent: payload.rawContent,
      state: payload.state,
      hasStateBlock: payload.hasStateBlock,
      filePath: payload.filePath,
      modifiedAt: payload.modifiedAt
    }
  }

  private shouldDecryptFields(rsa: number, title: string, content: string): boolean {
    if (NoteContentEncryptionService.isRsaEncrypted(rsa)) {
      return true
    }
    return NoteContentEncryptionService.looksLikeNoteCipher(title) ||
      NoteContentEncryptionService.looksLikeNoteCipher(content)
  }

  private static normalizeCipherCandidate(value: string): string {
    return value.replace(/\s+/g, '')
  }

  static looksLikeNoteCipher(value: string): boolean {
    const normalized = NoteContentEncryptionService.normalizeCipherCandidate(value)
    if (normalized.length === 0) {
      return false
    }
    return /^[A-Za-z0-9+/]+=*(\.[A-Za-z0-9+/=_-]+){1,2}$/.test(normalized)
  }

  private async decryptFieldFully(value: string, userId: string, forceDecrypt: boolean = false): Promise<string> {
    if (value.length === 0) {
      return value
    }
    let current = value.replace(/\r/g, '')
    let force = forceDecrypt
    const crypto = CryptoService.getInstance()
    for (let pass = 0; pass < 4; pass++) {
      const candidate = NoteContentEncryptionService.normalizeCipherCandidate(current)
      const shouldTry = force || NoteContentEncryptionService.looksLikeNoteCipher(candidate)
      if (!shouldTry) {
        return current
      }
      force = false
      const next = await crypto.decryptNoteText(candidate, userId)
      if (next.length === 0) {
        break
      }
      if (next === candidate) {
        return current
      }
      current = next
    }
    if (NoteContentEncryptionService.looksLikeNoteCipher(
      NoteContentEncryptionService.normalizeCipherCandidate(current))) {
      return ''
    }
    return current
  }

  private copyNote(note: Note): Note {
    return {
      id: note.id,
      title: note.title,
      content: note.content,
      tags: [...note.tags],
      imageRefs: [...note.imageRefs],
      audioId: note.audioId,
      summary: note.summary,
      localModified: note.localModified,
      remoteModified: note.remoteModified,
      deleted: note.deleted,
      deletedAt: note.deletedAt,
      lastOperationAt: note.lastOperationAt,
      syncStatus: note.syncStatus,
      filePath: note.filePath,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      parentId: note.parentId,
      isConflict: note.isConflict,
      latitude: note.latitude,
      longitude: note.longitude,
      altitude: note.altitude,
      author: note.author,
      sourceUrl: note.sourceUrl,
      isFavorite: note.isFavorite,
      isTodo: note.isTodo,
      todoDue: note.todoDue,
      todoCompleted: note.todoCompleted,
      todoPriority: note.todoPriority,
      todoStatus: note.todoStatus,
      todoReminderMinutes: note.todoReminderMinutes,
      source: note.source,
      order: note.order,
      userData: note.userData,
      rsa: note.rsa,
      deletedTime: note.deletedTime,
      type_: note.type_,
      extractStatus: note.extractStatus,
      extractJobId: note.extractJobId,
      extractError: note.extractError,
      extractedAt: note.extractedAt,
      extractProgress: note.extractProgress,
      voiceSummary: note.voiceSummary,
      voiceSegmentsJson: note.voiceSegmentsJson,
      voiceTranscribeStatus: note.voiceTranscribeStatus
    }
  }
}
