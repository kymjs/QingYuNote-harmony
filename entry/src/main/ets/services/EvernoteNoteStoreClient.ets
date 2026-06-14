import { http } from '@kit.NetworkKit'
import { Logger } from '../common/utils/Logger'
import { util } from '@kit.ArkTS'

const TAG = 'EvernoteNoteStore'

const TYPE_STOP = 0
const TYPE_BOOL = 2
const TYPE_I32 = 8
const TYPE_STRING = 11
const TYPE_BINARY = 11
const TYPE_STRUCT = 12
const TYPE_LIST = 15

const MSG_CALL = 1
const VERSION1 = 0x80010000

export class EvernoteNoteMeta {
  guid: string = ''
  title: string = ''
}

export class EvernoteNotesMetadataPage {
  totalNotes: number = 0
  notes: EvernoteNoteMeta[] = []
}

export class EvernoteResource {
  guid: string = ''
  bodyHashHex: string = ''
  body: Uint8Array = new Uint8Array(0)
  mime: string = ''
}

export class EvernoteNote {
  content: string = ''
  resources: EvernoteResource[] = []
}

export class EvernoteNoteStoreException extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'EvernoteNoteStoreException'
  }
}

interface ThriftField {
  type: number
  id: number
}

class EvernoteData {
  bodyHash: Uint8Array = new Uint8Array(0)
  body: Uint8Array = new Uint8Array(0)
}

class ThriftWriter {
  private chunks: number[] = []

  toUint8Array(): Uint8Array {
    return new Uint8Array(this.chunks)
  }

  writeMessageBegin(name: string, type: number, seqId: number): void {
    this.writeI32(VERSION1 | type)
    this.writeString(name)
    this.writeI32(seqId)
  }

  writeMessageEnd(): void {
  }

  writeStructBegin(): void {
  }

  writeStructEnd(): void {
    this.writeByte(0)
  }

  writeFieldStructBegin(id: number): void {
    this.writeByte(TYPE_STRUCT)
    this.writeI16(id)
  }

  writeFieldStructEnd(): void {
    this.writeByte(0)
  }

  writeFieldString(id: number, value: string): void {
    this.writeByte(TYPE_STRING)
    this.writeI16(id)
    this.writeString(value)
  }

  writeFieldI32(id: number, value: number): void {
    this.writeByte(TYPE_I32)
    this.writeI16(id)
    this.writeI32(value)
  }

  writeFieldBool(id: number, value: boolean): void {
    this.writeByte(TYPE_BOOL)
    this.writeI16(id)
    this.writeByte(value ? 1 : 0)
  }

  writeByte(value: number): void {
    this.chunks.push(value & 0xff)
  }

  writeI16(value: number): void {
    this.writeByte((value >> 8) & 0xff)
    this.writeByte(value & 0xff)
  }

  writeI32(value: number): void {
    this.writeByte((value >> 24) & 0xff)
    this.writeByte((value >> 16) & 0xff)
    this.writeByte((value >> 8) & 0xff)
    this.writeByte(value & 0xff)
  }

  writeString(value: string): void {
    const encoder = new util.TextEncoder()
    const bytes = encoder.encodeInto(value)
    this.writeI32(bytes.length)
    for (let i = 0; i < bytes.length; i++) {
      this.chunks.push(bytes[i])
    }
  }
}

class ThriftReader {
  private bytes: Uint8Array
  private offset: number = 0

  constructor(bytes: Uint8Array) {
    this.bytes = bytes
  }

  readMessageBegin(): void {
    this.readI32()
    this.readString()
    this.readI32()
  }

  readStructFieldHeader(): ThriftField | null {
    const type = this.readByte()
    if (type === 0) {
      return null
    }
    const id = this.readI16()
    return { type: type, id: id }
  }

  readListBegin(): number {
    this.readByte()
    return this.readI32()
  }

  readListEnd(): void {
  }

  readI32(): number {
    const b0 = this.readByte()
    const b1 = this.readByte()
    const b2 = this.readByte()
    const b3 = this.readByte()
    return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
  }

  readString(): string {
    const slice = this.readBinary()
    if (slice.length === 0) {
      return ''
    }
    const decoder = new util.TextDecoder('utf-8', { ignoreBOM: true })
    return decoder.decodeWithStream(slice, { stream: false })
  }

  readBinary(): Uint8Array {
    const length = this.readI32()
    if (length <= 0) {
      return new Uint8Array(0)
    }
    const slice = this.bytes.subarray(this.offset, this.offset + length)
    this.offset += length
    return slice
  }

  readByte(): number {
    if (this.offset >= this.bytes.length) {
      return 0
    }
    return this.bytes[this.offset++]
  }

  readI16(): number {
    const hi = this.readByte()
    const lo = this.readByte()
    let value = (hi << 8) | lo
    if (value >= 0x8000) {
      value -= 0x10000
    }
    return value
  }

  skip(type: number): void {
    switch (type) {
      case 0:
        return
      case 2:
      case 3:
        this.offset += 1
        return
      case 6:
        this.offset += 2
        return
      case 8:
        this.offset += 4
        return
      case 4:
      case 10:
        this.offset += 8
        return
      case 11: {
        const len = this.readI32()
        this.offset += len
        return
      }
      case 12:
        while (true) {
          const field = this.readStructFieldHeader()
          if (field === null) {
            break
          }
          this.skip(field.type)
        }
        return
      case 13: {
        const keyType = this.readByte()
        const valueType = this.readByte()
        const size = this.readI32()
        for (let i = 0; i < size; i++) {
          this.skip(keyType)
          this.skip(valueType)
        }
        return
      }
      case 14:
      case 15: {
        const elementType = this.readByte()
        const size = this.readI32()
        for (let i = 0; i < size; i++) {
          this.skip(elementType)
        }
        return
      }
      default:
        return
    }
  }
}

export class EvernoteNoteStoreClient {
  async findNotesMetadata(
    noteStoreUrl: string,
    token: string,
    offset: number,
    maxNotes: number
  ): Promise<EvernoteNotesMetadataPage> {
    const writer = new ThriftWriter()
    writer.writeMessageBegin('findNotesMetadata', MSG_CALL, 1)
    writer.writeStructBegin()
    writer.writeFieldString(1, token)
    writer.writeFieldStructBegin(2)
    writer.writeFieldStructEnd()
    writer.writeFieldI32(3, offset)
    writer.writeFieldI32(4, maxNotes)
    writer.writeFieldStructBegin(5)
    writer.writeFieldBool(2, true)
    writer.writeFieldStructEnd()
    writer.writeStructEnd()
    writer.writeMessageEnd()

    const bytes = await this.post(noteStoreUrl, writer.toUint8Array())
    const reader = new ThriftReader(bytes)
    reader.readMessageBegin()
    const resultField = reader.readStructFieldHeader()
    if (resultField === null) {
      throw new EvernoteNoteStoreException('findNotesMetadata: empty response')
    }
    if (resultField.id === 0 && resultField.type === TYPE_STRUCT) {
      return this.parseNotesMetadataList(reader)
    }
    this.throwIfException(reader, resultField, 'findNotesMetadata')
    throw new EvernoteNoteStoreException('findNotesMetadata: unexpected response')
  }

  async getNoteContent(noteStoreUrl: string, token: string, guid: string): Promise<string> {
    const note = await this.getNote(noteStoreUrl, token, guid)
    return note.content
  }

  async getNote(noteStoreUrl: string, token: string, guid: string): Promise<EvernoteNote> {
    const writer = new ThriftWriter()
    writer.writeMessageBegin('getNote', MSG_CALL, 1)
    writer.writeStructBegin()
    writer.writeFieldString(1, token)
    writer.writeFieldString(2, guid)
    writer.writeFieldBool(3, true)
    writer.writeFieldBool(4, true)
    writer.writeFieldBool(5, false)
    writer.writeFieldBool(6, true)
    writer.writeStructEnd()
    writer.writeMessageEnd()

    const bytes = await this.post(noteStoreUrl, writer.toUint8Array())
    const reader = new ThriftReader(bytes)
    reader.readMessageBegin()
    const resultField = reader.readStructFieldHeader()
    if (resultField === null) {
      throw new EvernoteNoteStoreException('getNote: empty response')
    }
    if (resultField.id === 0 && resultField.type === TYPE_STRUCT) {
      return this.parseNote(reader)
    }
    this.throwIfException(reader, resultField, 'getNote')
    throw new EvernoteNoteStoreException('getNote: unexpected response')
  }

  async getResource(noteStoreUrl: string, token: string, guid: string): Promise<EvernoteResource> {
    const writer = new ThriftWriter()
    writer.writeMessageBegin('getResource', MSG_CALL, 1)
    writer.writeStructBegin()
    writer.writeFieldString(1, token)
    writer.writeFieldString(2, guid)
    writer.writeFieldBool(3, true)
    writer.writeFieldBool(4, false)
    writer.writeFieldBool(5, true)
    writer.writeStructEnd()
    writer.writeMessageEnd()

    const bytes = await this.post(noteStoreUrl, writer.toUint8Array())
    const reader = new ThriftReader(bytes)
    reader.readMessageBegin()
    const resultField = reader.readStructFieldHeader()
    if (resultField === null) {
      throw new EvernoteNoteStoreException('getResource: empty response')
    }
    if (resultField.id === 0 && resultField.type === TYPE_STRUCT) {
      return this.parseResource(reader)
    }
    this.throwIfException(reader, resultField, 'getResource')
    throw new EvernoteNoteStoreException('getResource: unexpected response')
  }

  async getResourceData(noteStoreUrl: string, token: string, guid: string): Promise<Uint8Array> {
    const writer = new ThriftWriter()
    writer.writeMessageBegin('getResourceData', MSG_CALL, 1)
    writer.writeStructBegin()
    writer.writeFieldString(1, token)
    writer.writeFieldString(2, guid)
    writer.writeStructEnd()
    writer.writeMessageEnd()

    const bytes = await this.post(noteStoreUrl, writer.toUint8Array())
    const reader = new ThriftReader(bytes)
    reader.readMessageBegin()
    const resultField = reader.readStructFieldHeader()
    if (resultField === null) {
      throw new EvernoteNoteStoreException('getResourceData: empty response')
    }
    if (resultField.id === 0 && resultField.type === TYPE_BINARY) {
      return reader.readBinary()
    }
    this.throwIfException(reader, resultField, 'getResourceData')
    throw new EvernoteNoteStoreException('getResourceData: unexpected response')
  }

  private parseNote(reader: ThriftReader): EvernoteNote {
    const note = new EvernoteNote()
    while (true) {
      const field = reader.readStructFieldHeader()
      if (field === null) {
        break
      }
      if (field.id === 3 && field.type === TYPE_STRING) {
        note.content = reader.readString()
      } else if ((field.id === 11 || field.id === 13) && field.type === TYPE_LIST) {
        const count = reader.readListBegin()
        for (let i = 0; i < count; i++) {
          note.resources.push(this.parseResource(reader))
        }
        reader.readListEnd()
      } else {
        reader.skip(field.type)
      }
    }
    return note
  }

  private parseResource(reader: ThriftReader): EvernoteResource {
    const resource = new EvernoteResource()
    let alternateBody = new Uint8Array(0)
    let alternateHash = new Uint8Array(0)
    while (true) {
      const field = reader.readStructFieldHeader()
      if (field === null) {
        break
      }
      if (field.id === 1 && field.type === TYPE_STRING) {
        resource.guid = reader.readString()
      } else if (field.id === 3 && field.type === TYPE_STRUCT) {
        const data = this.parseData(reader)
        resource.bodyHashHex = this.bytesToHex(data.bodyHash)
        resource.body = data.body
      } else if (field.id === 4 && field.type === TYPE_STRING) {
        resource.mime = reader.readString()
      } else if (field.id === 11 && field.type === TYPE_STRUCT) {
        const data = this.parseData(reader)
        alternateHash = data.bodyHash
        alternateBody = data.body
      } else {
        reader.skip(field.type)
      }
    }
    if (resource.body.length === 0 && alternateBody.length > 0) {
      resource.body = alternateBody
      if (resource.bodyHashHex.length === 0) {
        resource.bodyHashHex = this.bytesToHex(alternateHash)
      }
    }
    return resource
  }

  private parseData(reader: ThriftReader): EvernoteData {
    const data = new EvernoteData()
    while (true) {
      const field = reader.readStructFieldHeader()
      if (field === null) {
        break
      }
      if (field.id === 1 && field.type === TYPE_BINARY) {
        data.bodyHash = reader.readBinary()
      } else if (field.id === 3 && field.type === TYPE_BINARY) {
        data.body = reader.readBinary()
      } else {
        reader.skip(field.type)
      }
    }
    return data
  }

  private bytesToHex(bytes: Uint8Array): string {
    if (bytes.length === 0) {
      return ''
    }
    let hex = ''
    for (let i = 0; i < bytes.length; i++) {
      hex += bytes[i].toString(16).padStart(2, '0')
    }
    return hex
  }

  private async post(url: string, body: Uint8Array): Promise<Uint8Array> {
    const req = http.createHttp()
    try {
      Logger.info(TAG, `post: url=${url} bodyLen=${body.length}`)
      const resp = await req.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/x-thrift',
          'Accept': 'application/x-thrift'
        },
        extraData: body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 20000,
        readTimeout: 60000
      })
      const code = resp.responseCode
      if (code < 200 || code >= 300) {
        let preview = ''
        if (resp.result instanceof ArrayBuffer) {
          const arr = new Uint8Array(resp.result)
          const decoder = new util.TextDecoder('utf-8', { ignoreBOM: true })
          preview = decoder.decodeWithStream(arr.subarray(0, Math.min(arr.length, 200)), { stream: false })
        }
        Logger.error(TAG, `post failed: status=${code} preview=${preview}`)
        throw new EvernoteNoteStoreException(`NoteStore HTTP ${code}${preview.length > 0 ? `: ${preview}` : ''}`)
      }
      if (!(resp.result instanceof ArrayBuffer) || resp.result.byteLength === 0) {
        throw new EvernoteNoteStoreException('NoteStore empty response body')
      }
      return new Uint8Array(resp.result)
    } finally {
      req.destroy()
    }
  }

  private parseNotesMetadataList(reader: ThriftReader): EvernoteNotesMetadataPage {
    const page = new EvernoteNotesMetadataPage()
    while (true) {
      const field = reader.readStructFieldHeader()
      if (field === null) {
        break
      }
      if (field.id === 2 && field.type === TYPE_I32) {
        page.totalNotes = reader.readI32()
      } else if (field.id === 3 && field.type === TYPE_LIST) {
        const count = reader.readListBegin()
        for (let i = 0; i < count; i++) {
          page.notes.push(this.parseNoteMetadata(reader))
        }
        reader.readListEnd()
      } else {
        reader.skip(field.type)
      }
    }
    return page
  }

  private parseNoteMetadata(reader: ThriftReader): EvernoteNoteMeta {
    const note = new EvernoteNoteMeta()
    while (true) {
      const field = reader.readStructFieldHeader()
      if (field === null) {
        break
      }
      if (field.id === 1 && field.type === TYPE_STRING) {
        note.guid = reader.readString()
      } else if (field.id === 2 && field.type === TYPE_STRING) {
        note.title = reader.readString()
      } else {
        reader.skip(field.type)
      }
    }
    return note
  }

  private throwIfException(reader: ThriftReader, field: ThriftField, method: string): void {
    if (field.type !== TYPE_STRUCT) {
      reader.skip(field.type)
      return
    }
    let message = ''
    while (true) {
      const inner = reader.readStructFieldHeader()
      if (inner === null) {
        break
      }
      if (inner.type === TYPE_STRING) {
        message = reader.readString()
      } else {
        reader.skip(inner.type)
      }
    }
    throw new EvernoteNoteStoreException(message.length > 0 ? message : `${method} failed`)
  }
}
