import fs from '@ohos.file.fs'
import util from '@ohos.util'
import { NoteStateCodec } from '../common/utils/NoteStateCodec'
import { FileService } from './FileService'

export interface AiNoteImagePayload {
  relativePath: string
  dataUrl: string
}

/**
 * 从笔记正文加载 qingyu-note-image 图片为 data URL（供 MiniMax image_url）。
 */
export class AiNoteImageLoader {
  private static readonly MAX_IMAGES: number = 6
  private static readonly MAX_BYTES_PER_IMAGE: number = 8 * 1024 * 1024
  private static readonly base64: util.Base64Helper = new util.Base64Helper()

  static loadFromNote(content: string, filesBasePath: string): AiNoteImagePayload[] {
    if (filesBasePath.trim().length === 0) {
      return []
    }
    const refs = NoteStateCodec.extractImageRefs(content)
    if (refs.length === 0) {
      return []
    }
    const payloads: AiNoteImagePayload[] = []
    for (let i = 0; i < refs.length; i++) {
      if (payloads.length >= AiNoteImageLoader.MAX_IMAGES) {
        break
      }
      const ref = refs[i]
      const filePath = `${filesBasePath}/${ref}`
      try {
        if (!fs.accessSync(filePath)) {
          continue
        }
        const stat = fs.statSync(filePath)
        if (stat.size <= 0 || stat.size > AiNoteImageLoader.MAX_BYTES_PER_IMAGE) {
          continue
        }
        const mime = AiNoteImageLoader.mimeFromPath(ref)
        if (mime.length === 0) {
          continue
        }
        const bytes = FileService.readFileAsArrayBuffer(filePath)
        const b64 = AiNoteImageLoader.base64.encodeToStringSync(new Uint8Array(bytes))
        payloads.push({
          relativePath: ref,
          dataUrl: `data:${mime};base64,${b64}`
        })
      } catch (_) {
        continue
      }
    }
    return payloads
  }

  private static mimeFromPath(ref: string): string {
    const lower = ref.toLowerCase()
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg'
    }
    if (lower.endsWith('.png')) {
      return 'image/png'
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif'
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp'
    }
    return ''
  }
}
