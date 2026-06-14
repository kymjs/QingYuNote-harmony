import pako from 'pako'
import { Logger } from './Logger'

/** 单个 zip 条目解压后的内容。 */
export class ZipEntry {
  fileName: string
  data: Uint8Array

  constructor(fileName: string, data: Uint8Array) {
    this.fileName = fileName
    this.data = data
  }
}

/**
 * 最简 zip 解析：仅支持标准 zip（不支持 zip64 / 加密 / 分卷），用于解析 docx。
 * 解析流程：先在 buffer 末尾扫 EOCD 拿到中央目录偏移与条目数，再遍历中央目录条目，
 * 最后按 local header 偏移读出文件数据并用 pako.inflateRaw 解压。
 */
export class ZipReader {
  private static readonly SIGNATURE_EOCD: number = 0x06054b50
  private static readonly SIGNATURE_CENTRAL: number = 0x02014b50
  private static readonly SIGNATURE_LOCAL: number = 0x04034b50
  private static readonly METHOD_STORED: number = 0
  private static readonly METHOD_DEFLATE: number = 8
  private static readonly MAX_EOCD_SEARCH: number = 65557
  private static readonly MAX_FILE_BYTES: number = 64 * 1024 * 1024

  /** 解析整个 zip；遇到非预期格式抛错由调用方兜底。 */
  static readEntries(buffer: Uint8Array): ZipEntry[] {
    if (buffer.length < 22) {
      throw new Error('ZipReader: buffer too small')
    }
    const eocdOffset = ZipReader.findEocd(buffer)
    if (eocdOffset < 0) {
      throw new Error('ZipReader: EOCD signature not found')
    }
    const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength)
    const totalEntries = view.getUint16(eocdOffset + 10, true)
    const cdSize = view.getUint32(eocdOffset + 12, true)
    const cdOffset = view.getUint32(eocdOffset + 16, true)
    if (cdOffset + cdSize > buffer.length) {
      throw new Error('ZipReader: central directory out of range')
    }
    const entries: ZipEntry[] = []
    let cursor = cdOffset
    for (let i = 0; i < totalEntries; i += 1) {
      if (cursor + 46 > buffer.length) {
        throw new Error('ZipReader: central directory truncated')
      }
      const signature = view.getUint32(cursor, true)
      if (signature !== ZipReader.SIGNATURE_CENTRAL) {
        throw new Error('ZipReader: invalid central directory signature')
      }
      const method = view.getUint16(cursor + 10, true)
      const compressedSize = view.getUint32(cursor + 20, true)
      const uncompressedSize = view.getUint32(cursor + 24, true)
      const fileNameLength = view.getUint16(cursor + 28, true)
      const extraLength = view.getUint16(cursor + 30, true)
      const commentLength = view.getUint16(cursor + 32, true)
      const localHeaderOffset = view.getUint32(cursor + 42, true)
      const fileNameBytes = buffer.subarray(cursor + 46, cursor + 46 + fileNameLength)
      const fileName = ZipReader.decodeUtf8(fileNameBytes)
      const nextCursor = cursor + 46 + fileNameLength + extraLength + commentLength
      try {
        const data = ZipReader.readEntryData(buffer, localHeaderOffset, method, compressedSize, uncompressedSize)
        entries.push(new ZipEntry(fileName, data))
      } catch (error) {
        Logger.warn('ZipReader', `skip entry ${fileName}: ${JSON.stringify(error)}`)
      }
      cursor = nextCursor
    }
    return entries
  }

  /** 找到第一个名称匹配的条目（区分大小写，docx 内部固定小写）。 */
  static findEntry(entries: ZipEntry[], name: string): ZipEntry | null {
    for (const entry of entries) {
      if (entry.fileName === name) {
        return entry
      }
    }
    return null
  }

  private static findEocd(buffer: Uint8Array): number {
    const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength)
    const start = Math.max(0, buffer.length - ZipReader.MAX_EOCD_SEARCH)
    for (let i = buffer.length - 22; i >= start; i -= 1) {
      if (view.getUint32(i, true) === ZipReader.SIGNATURE_EOCD) {
        return i
      }
    }
    return -1
  }

  private static readEntryData(
    buffer: Uint8Array,
    localHeaderOffset: number,
    method: number,
    compressedSize: number,
    uncompressedSize: number
  ): Uint8Array {
    if (localHeaderOffset + 30 > buffer.length) {
      throw new Error('local header out of range')
    }
    const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength)
    if (view.getUint32(localHeaderOffset, true) !== ZipReader.SIGNATURE_LOCAL) {
      throw new Error('invalid local header signature')
    }
    const fileNameLength = view.getUint16(localHeaderOffset + 26, true)
    const extraLength = view.getUint16(localHeaderOffset + 28, true)
    const dataStart = localHeaderOffset + 30 + fileNameLength + extraLength
    if (dataStart + compressedSize > buffer.length) {
      throw new Error('entry data out of range')
    }
    if (compressedSize > ZipReader.MAX_FILE_BYTES || uncompressedSize > ZipReader.MAX_FILE_BYTES) {
      throw new Error('entry too large')
    }
    const compressed = buffer.subarray(dataStart, dataStart + compressedSize)
    if (method === ZipReader.METHOD_STORED) {
      return new Uint8Array(compressed)
    }
    if (method === ZipReader.METHOD_DEFLATE) {
      // pako.inflateRaw 是同步 API，docx 单文档一般几 MB，主线程可接受
      return pako.inflateRaw(compressed)
    }
    throw new Error(`unsupported compression method: ${method}`)
  }

  private static decodeUtf8(bytes: Uint8Array): string {
    let result = ''
    let i = 0
    while (i < bytes.length) {
      const b1 = bytes[i]
      if (b1 < 0x80) {
        result += String.fromCharCode(b1)
        i += 1
      } else if (b1 >= 0xc0 && b1 < 0xe0) {
        const b2 = bytes[i + 1]
        result += String.fromCharCode(((b1 & 0x1f) << 6) | (b2 & 0x3f))
        i += 2
      } else if (b1 >= 0xe0 && b1 < 0xf0) {
        const b2 = bytes[i + 1]
        const b3 = bytes[i + 2]
        result += String.fromCharCode(((b1 & 0x0f) << 12) | ((b2 & 0x3f) << 6) | (b3 & 0x3f))
        i += 3
      } else {
        // 4 字节或无效字节，按 ? 处理
        result += '?'
        i += 1
      }
    }
    return result
  }
}
