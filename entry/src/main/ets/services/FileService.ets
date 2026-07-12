import fs from '@ohos.file.fs'
import type common from '@ohos.app.ability.common'
import type { Note, NoteFilePayload } from '../common/model/Note'
import { Logger } from '../common/utils/Logger'
import { NoteStateCodec } from '../common/utils/NoteStateCodec'
import { NoteContentEncryptionService } from './NoteContentEncryptionService'

const NOTES_DIR = 'notes'
const NOTE_FILE_SUFFIX = '.md'
const FLOWCHART_FILE_SUFFIX = '.qy'
const NOTE_FILE_NAME_REGEX = /^[a-f0-9-]{36}\.md$/i

export class FileService {
  private static instance: FileService = new FileService()
  private context?: common.UIAbilityContext
  private baseDir: string = ''

  static getInstance(): FileService {
    return FileService.instance
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.baseDir.length > 0) {
      return
    }
    this.context = context
    const filesDir = this.context.filesDir ?? ''
    this.baseDir = `${filesDir}/${NOTES_DIR}`
    await this.ensureBaseDir()
  }

  async ensureBaseDir(): Promise<void> {
    try {
      if (!fs.accessSync(this.baseDir)) {
        fs.mkdirSync(this.baseDir, true)
      }
    } catch (error) {
      Logger.warn('FileService', `ensureBaseDir failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  getNotePath(noteId: string): string {
    return `${this.baseDir}/${noteId}${NOTE_FILE_SUFFIX}`
  }

  getFlowchartPath(noteId: string): string {
    return `${this.baseDir}/${noteId}${FLOWCHART_FILE_SUFFIX}`
  }

  flowchartFileExists(noteId: string): boolean {
    try {
      return fs.accessSync(this.getFlowchartPath(noteId))
    } catch (_) {
      return false
    }
  }

  async readFlowchartFile(noteId: string): Promise<string> {
    try {
      const filePath = this.getFlowchartPath(noteId)
      if (!fs.accessSync(filePath)) {
        return ''
      }
      return await fs.readText(filePath, { encoding: 'utf-8' })
    } catch (error) {
      Logger.warn('FileService', `readFlowchartFile failed: noteId=${noteId}`)
      return ''
    }
  }

  async writeFlowchartFile(noteId: string, content: string): Promise<void> {
    await this.ensureBaseDir()
    const filePath = this.getFlowchartPath(noteId)
    const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    try {
      await fs.write(file.fd, content, { encoding: 'utf-8' })
    } finally {
      fs.closeSync(file)
    }
  }

  async deleteFlowchartFile(noteId: string): Promise<void> {
    try {
      const filePath = this.getFlowchartPath(noteId)
      if (fs.accessSync(filePath)) {
        fs.unlinkSync(filePath)
      }
    } catch (_) {
    }
  }

  async readNoteFile(noteId: string): Promise<string> {
    try {
      const filePath = this.getNotePath(noteId)
      if (!fs.accessSync(filePath)) {
        Logger.warn('FileService', `readNoteFile missing file: noteId=${noteId}, path=${filePath}`)
        return ''
      }
      const content = await fs.readText(filePath, { encoding: 'utf-8' })
      Logger.info('FileService',
        `readNoteFile success: noteId=${noteId}, path=${filePath}, contentLength=${content.length}`)
      return content
    } catch (error) {
      Logger.warn('FileService', `readNoteFile failed: noteId=${noteId}, error=${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async readRawParsedNote(noteId: string): Promise<NoteFilePayload | null> {
    try {
      const filePath = this.getNotePath(noteId)
      if (!fs.accessSync(filePath)) {
        return null
      }
      const rawContent = await this.readNoteFile(noteId)
      const modifiedAt = this.readModifiedAt(filePath)
      const payload = NoteStateCodec.parseNoteFile(rawContent, noteId, modifiedAt)
      payload.filePath = filePath
      payload.modifiedAt = modifiedAt
      return payload
    } catch (error) {
      Logger.warn('FileService', `readRawParsedNote failed: noteId=${noteId}, error=${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async readParsedNote(noteId: string): Promise<NoteFilePayload | null> {
    try {
      const filePath = this.getNotePath(noteId)
      if (!fs.accessSync(filePath)) {
        Logger.warn('LinkExtractDebug', `readParsedNote missing file: noteId=${noteId}, path=${filePath}`)
        return null
      }
      const rawContent = await this.readNoteFile(noteId)
      const modifiedAt = this.readModifiedAt(filePath)
      const payload = NoteStateCodec.parseNoteFile(rawContent, noteId, modifiedAt)
      payload.filePath = filePath
      payload.modifiedAt = modifiedAt
      Logger.info('LinkExtractDebug',
        `readParsedNote noteId=${noteId} extractStatus=${payload.state.extractStatus} ` +
        `extractJobId=${payload.state.extractJobId} rawHasExtractStatus=${rawContent.includes('extract_status:')} ` +
        `rawHasExtractJobId=${rawContent.includes('extract_job_id:')}`
      )
      const userId = await NoteContentEncryptionService.getInstance().resolveUserId()
      if (userId === null) {
        return payload
      }
      return NoteContentEncryptionService.getInstance().decryptPayloadForDisplay(payload, userId)
    } catch (error) {
      Logger.warn('LinkExtractDebug', `readParsedNote failed: noteId=${noteId}, error=${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async readNoteContent(noteId: string): Promise<string> {
    const payload = await this.readParsedNote(noteId)
    return payload?.content ?? ''
  }

  async writeNoteFile(note: Note): Promise<void> {
    try {
      const filePath = this.getNotePath(note.id)
      let storageNote = note
      const userId = await NoteContentEncryptionService.getInstance().resolveUserId()
      Logger.info('LinkExtractDebug',
        `writeNoteFile pre-serialize noteId=${note.id} extractStatus=${note.extractStatus} ` +
        `extractJobId=${note.extractJobId} extractProgress=${note.extractProgress} ` +
        `titleLen=${note.title.length} contentLen=${note.content.length} userId=${userId ?? 'null'}`
      )
      if (userId !== null) {
        storageNote = await NoteContentEncryptionService.getInstance().encryptNoteForStorage(note, userId)
        Logger.info('LinkExtractDebug',
          `writeNoteFile post-encrypt noteId=${note.id} extractStatus=${storageNote.extractStatus} ` +
          `extractJobId=${storageNote.extractJobId}`
        )
      }
      const serialized = NoteStateCodec.serializeNoteFile(storageNote)
      // 原子写：写到 .tmp 后 rename 覆盖目标文件。避免「OPEN+TRUNC 已把文件清空，
      // 但 await fs.write 还没完成」导致的并发读 readParsedNote 看到文件 missing。
      const tmpPath = `${filePath}.tmp`
      const file = fs.openSync(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      try {
        Logger.info('LinkExtractDebug',
          `writeNoteFile start: noteId=${note.id}, path=${filePath}, contentLength=${serialized.length} ` +
          `serializedHasExtractStatus=${serialized.includes('extract_status:')} ` +
          `serializedHasExtractJobId=${serialized.includes('extract_job_id:')}`
        )
        await fs.write(file.fd, serialized, { encoding: 'utf-8' })
        await fs.fsync(file.fd)
      } finally {
        fs.closeSync(file)
      }
      // 原子替换。rename 在同一文件系统下是原子操作，读端要么看到旧内容要么看到新内容，看不到 0 字节中间态。
      fs.renameSync(tmpPath, filePath)
      const persisted = await fs.readText(filePath, { encoding: 'utf-8' })
      Logger.info('LinkExtractDebug',
        `writeNoteFile finish: noteId=${note.id}, path=${filePath}, persistedLength=${persisted.length} ` +
        `persistedHasExtractStatus=${persisted.includes('extract_status:')} ` +
        `persistedHasExtractJobId=${persisted.includes('extract_job_id:')}`
      )
    } catch (error) {
      Logger.warn('FileService', `writeNoteFile failed: noteId=${note.id}, error=${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async writeNoteContent(noteId: string, content: string): Promise<void> {
    const payload = await this.readParsedNote(noteId)
    const fallbackTs = payload?.modifiedAt ?? Date.now()
    const state = payload?.state ?? NoteStateCodec.createDefaultState(noteId, '', fallbackTs)
    const filePath = this.getNotePath(noteId)
    const savedAt = Date.now()
    const createdAt = state.createdAt > 0 ? state.createdAt : savedAt
    const imageRefs: string[] = NoteStateCodec.extractImageRefs(content)
    await this.writeNoteFile({
      id: state.id.length > 0 ? state.id : noteId,
      title: state.title,
      content,
      tags: [...state.tags],
      imageRefs,
      audioId: state.audioId ?? '',
      summary: '',
      localModified: savedAt,
      remoteModified: 0,
      deleted: false,
      deletedAt: 0,
      lastOperationAt: savedAt,
      syncStatus: 'pending',
      filePath,
      createdAt,
      updatedAt: savedAt,
      parentId: state.parentId,
      isConflict: state.isConflict,
      latitude: state.latitude,
      longitude: state.longitude,
      altitude: state.altitude,
      author: state.author,
      sourceUrl: state.sourceUrl,
      isTodo: state.isTodo,
      todoDue: state.todoDue,
      todoCompleted: state.todoCompleted,
      source: state.source,
      order: state.order,
      userData: state.userData,
      rsa: state.rsa,
      deletedTime: state.deletedTime,
      type_: state.type_,
      extractStatus: state.extractStatus,
      extractJobId: state.extractJobId,
      extractError: state.extractError,
      extractedAt: state.extractedAt,
      extractProgress: state.extractProgress
    })
  }

  async listNoteIds(): Promise<string[]> {
    try {
      await this.ensureBaseDir()
      if (!fs.accessSync(this.baseDir)) {
        return []
      }
      const entries = fs.listFileSync(this.baseDir, {
        recursion: false,
        listNum: 0
      }) as string[]
      const noteIds: string[] = []
      for (const entry of entries) {
        if (!NOTE_FILE_NAME_REGEX.test(entry)) {
          continue
        }
        noteIds.push(entry.slice(0, -NOTE_FILE_SUFFIX.length))
      }
      return noteIds
    } catch (error) {
      Logger.warn('FileService', `listNoteIds failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async deleteNoteFile(noteId: string): Promise<void> {
    try {
      const filePath = this.getNotePath(noteId)
      if (fs.accessSync(filePath)) {
        fs.unlinkSync(filePath)
      }
      await this.deleteFlowchartFile(noteId)
    } catch (error) {
      Logger.warn('FileService', `deleteNoteFile failed: noteId=${noteId}, error=${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  /** 退出登录时删除本地全部笔记 Markdown 文件。 */
  async clearAllNoteFiles(): Promise<void> {
    try {
      await this.ensureBaseDir()
      if (!fs.accessSync(this.baseDir)) {
        return
      }
      const entries = fs.listFileSync(this.baseDir, {
        recursion: false,
        listNum: 0
      }) as string[]
      for (const entry of entries) {
        if (!NOTE_FILE_NAME_REGEX.test(entry)) {
          continue
        }
        const filePath = `${this.baseDir}/${entry}`
        if (fs.accessSync(filePath)) {
          fs.unlinkSync(filePath)
        }
      }
    } catch (error) {
      Logger.warn('FileService', `clearAllNoteFiles failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async exists(noteId: string): Promise<boolean> {
    try {
      return fs.accessSync(this.getNotePath(noteId))
    } catch (error) {
      Logger.warn('FileService', `exists failed: noteId=${noteId}, error=${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  private readModifiedAt(filePath: string): number {
    try {
      const stat = fs.statSync(filePath)
      const modifiedAt = stat.mtime
      return typeof modifiedAt === 'number' && modifiedAt > 0 ? modifiedAt : Date.now()
    } catch (error) {
      Logger.warn('FileService', `readModifiedAt failed: path=${filePath}, error=${JSON.stringify(error)}`)
      return Date.now()
    }
  }

  private describeError(error: Object): string {
    const raw = JSON.stringify(error)
    return raw.length > 0 && raw !== '{}' ? raw : `${error}`
  }

  private toRuntimeError(error: Object): Error {
    return new Error(this.describeError(error))
  }

  static fileExists(path: string): boolean {
    try {
      const stat = fs.statSync(path)
      Logger.info('FileService', `fileExists yes: path=${path}, size=${stat.size}`)
      return true
    } catch (e) {
      Logger.info('FileService', `fileExists no:  path=${path}, err=${JSON.stringify(e)}`)
      return false
    }
  }

  static readFileAsArrayBuffer(path: string): ArrayBuffer {
    let opened: fs.File | undefined = undefined
    try {
      opened = fs.openSync(path, fs.OpenMode.READ_ONLY)
      const stat = fs.statSync(path)
      const buffer = new ArrayBuffer(stat.size)
      fs.readSync(opened.fd, buffer)
      return buffer
    } catch (error) {
      throw error instanceof Error ? error : new Error(`${error}`)
    } finally {
      if (opened !== undefined) {
        try {
          fs.closeSync(opened)
        } catch (_) {
        }
      }
    }
  }

  static writeFile(path: string, data: ArrayBuffer): void {
    const dir = path.substring(0, path.lastIndexOf('/'))
    if (!FileService.fileExists(dir)) {
      Logger.info('FileService', `writeFile mkdir: ${dir}`)
      fs.mkdirSync(dir, true)
    }
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    try {
      fs.writeSync(file.fd, data)
      const stat = fs.statSync(file.fd)
      Logger.info('FileService', `writeFile ok: path=${path}, bytes=${data.byteLength}, onDisk=${stat.size}`)
    } finally {
      try {
        fs.closeSync(file)
      } catch (_) {
      }
    }
  }

  static deleteFile(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path)
      }
    } catch (_) {}
  }
}
