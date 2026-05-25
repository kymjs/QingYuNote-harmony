import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { util } from '@kit.ArkTS'
import { Logger } from '../common/utils/Logger'

const KEY_SEED = 'qingyu-notes-key'
const AAD_SEED = 'qingyu-aad'
const NOTE_KEY_PREFIX = 'zhangtaodeqingyuliulanqi-'
const NOTE_AAD_SEED = 'qingyu-note-rsa-aad'
const FLOWCHART_AAD_SEED = 'qingyu-flowchart-aad'
const GCM_AUTH_TAG_LENGTH = 16

interface ErrorLike {
  code?: number | string
  message?: string
  name?: string
}

interface PayloadParts {
  cipherBytes: Uint8Array
  authTagBytes: Uint8Array
}

export class CryptoService {
  private static instance: CryptoService = new CryptoService()
  private readonly base64: util.Base64Helper = new util.Base64Helper()

  static getInstance(): CryptoService {
    return CryptoService.instance
  }

  async init(): Promise<void> {
    await this.getSymKey()
  }

  async encryptNoteText(plainText: string, userId: string): Promise<string> {
    const trimmedUserId = userId.trim()
    if (plainText.length === 0 || trimmedUserId.length === 0) {
      return plainText
    }
    return this.encryptTextWithKey(plainText, await this.deriveNoteEncryptionKey(trimmedUserId), NOTE_AAD_SEED)
  }

  async decryptNoteText(cipherText: string, userId: string): Promise<string> {
    const trimmedUserId = userId.trim()
    if (cipherText.length === 0 || trimmedUserId.length === 0) {
      return cipherText
    }
    try {
      const key = await this.deriveNoteEncryptionKey(trimmedUserId)
      return await this.decryptTextWithKey(cipherText, key, NOTE_AAD_SEED)
    } catch (error) {
      Logger.warn('CryptoService', `decryptNoteText failed: ${this.describeError(error)}`)
      return ''
    }
  }

  async encryptFlowchartText(plainText: string, userId: string): Promise<string> {
    const trimmedUserId = userId.trim()
    if (plainText.length === 0 || trimmedUserId.length === 0) {
      return plainText
    }
    return this.encryptTextWithKey(plainText, await this.deriveNoteEncryptionKey(trimmedUserId), FLOWCHART_AAD_SEED)
  }

  async decryptFlowchartText(cipherText: string, userId: string): Promise<string> {
    const trimmedUserId = userId.trim()
    if (cipherText.length === 0 || trimmedUserId.length === 0) {
      return cipherText
    }
    try {
      const key = await this.deriveNoteEncryptionKey(trimmedUserId)
      return await this.decryptTextWithKey(cipherText, key, FLOWCHART_AAD_SEED)
    } catch (error) {
      Logger.warn('CryptoService', `decryptFlowchartText failed: ${this.describeError(error)}`)
      return cipherText
    }
  }

  private async deriveNoteEncryptionKey(userId: string): Promise<cryptoFramework.SymKey> {
    const md5Hex = await this.md5Hex(`${NOTE_KEY_PREFIX}${userId}`)
    const keyBytes = new Uint8Array(16)
    for (let i = 0; i < 16; i++) {
      keyBytes[i] = parseInt(md5Hex.substring(i * 2, i * 2 + 2), 16)
    }
    const generator = cryptoFramework.createSymKeyGenerator('AES128')
    return generator.convertKey({ data: keyBytes })
  }

  async encryptText(plainText: string): Promise<string> {
    return this.encryptTextWithKey(plainText, await this.getSymKey(), AAD_SEED)
  }

  private async encryptTextWithKey(plainText: string, symKey: cryptoFramework.SymKey, aad: string): Promise<string> {
    Logger.info('CryptoService', `encryptTextWithKey start: inputLength=${plainText.length}`)
    if (plainText.length === 0) {
      return ''
    }
    try {
      const cipher = cryptoFramework.createCipher('AES128|GCM|PKCS7')
      const ivBytes = this.randomBytes(12)
      const aadBytes = this.toBytes(aad)
      const params: cryptoFramework.GcmParamsSpec = {
        iv: { data: ivBytes },
        aad: { data: aadBytes },
        authTag: { data: new Uint8Array(16) },
        algName: 'GcmParamsSpec'
      }
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params)
      const encrypted = await cipher.doFinal({
        data: this.toBytes(plainText)
      })
      const payload = this.buildGcmPayload(encrypted.data, params.authTag.data)
      return [
        this.base64.encodeToStringSync(ivBytes),
        this.base64.encodeToStringSync(payload)
      ].join('.')
    } catch (error) {
      Logger.warn('CryptoService', `encryptTextWithKey failed: ${this.describeError(error)}`)
      throw this.toRuntimeError(error)
    }
  }

  /** 返回小写十六进制 MD5，用于轻羽云目录名派生。 */
  async md5Hex(plain: string): Promise<string> {
    try {
      const md = cryptoFramework.createMd('MD5')
      await md.update({
        data: this.toBytes(plain)
      })
      const digest = await md.digest()
      const bytes = digest.data
      let hex = ''
      for (let i = 0; i < bytes.length; i++) {
        const h = bytes[i].toString(16)
        hex += h.length === 1 ? `0${h}` : h
      }
      return hex
    } catch (error) {
      Logger.warn('CryptoService', `md5Hex failed: ${this.describeError(error)}`)
      throw this.toRuntimeError(error)
    }
  }

  async decryptText(cipherText: string): Promise<string> {
    return this.decryptTextWithKey(cipherText, await this.getSymKey(), AAD_SEED)
  }

  private async decryptTextWithKey(cipherText: string, symKey: cryptoFramework.SymKey, aad: string): Promise<string> {
    if (cipherText.length === 0) {
      return ''
    }
    const segments = cipherText.split('.')
    if (segments.length !== 2 && segments.length !== 3) {
      return ''
    }
    try {
      const cipher = cryptoFramework.createCipher('AES128|GCM|PKCS7')
      const iv = this.base64.decodeSync(segments[0])
      const payloadParts: PayloadParts = segments.length === 2
        ? this.unpackNewFormatPayload(this.base64.decodeSync(segments[1]))
        : {
            cipherBytes: this.base64.decodeSync(segments[2]),
            authTagBytes: this.base64.decodeSync(segments[1])
          }
      const params: cryptoFramework.GcmParamsSpec = {
        iv: { data: iv },
        aad: { data: this.toBytes(aad) },
        authTag: { data: payloadParts.authTagBytes },
        algName: 'GcmParamsSpec'
      }
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params)
      const decrypted = await cipher.doFinal({
        data: payloadParts.cipherBytes
      })
      return this.fromBytes(decrypted.data)
    } catch (error) {
      Logger.warn('CryptoService', `decryptTextWithKey failed: ${this.describeError(error)}`)
      throw this.toRuntimeError(error)
    }
  }

  private async getSymKey(): Promise<cryptoFramework.SymKey> {
    Logger.info('CryptoService', 'getSymKey start')
    try {
      const generator = cryptoFramework.createSymKeyGenerator('AES128')
      Logger.info('CryptoService', 'getSymKey generator created')
      const key = await generator.convertKey({
        data: this.toBytes(KEY_SEED)
      })
      Logger.info('CryptoService', 'getSymKey convertKey success')
      return key
    } catch (error) {
      Logger.warn('CryptoService', `getSymKey failed: ${this.describeError(error)}`)
      throw this.toRuntimeError(error)
    }
  }

  private toBytes(input: string): Uint8Array {
    return new util.TextEncoder().encodeInto(input)
  }

  private fromBytes(input: Uint8Array): string {
    return util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(input)
  }

  private randomBytes(length: number): Uint8Array {
    const result = new Uint8Array(length)
    for (let index = 0; index < length; index++) {
      result[index] = Math.floor(Math.random() * 256)
    }
    return result
  }

  private buildGcmPayload(encryptedBytes: Uint8Array, authTagBytes: Uint8Array): Uint8Array {
    if (!this.hasNonZeroBytes(authTagBytes) || this.endsWithBytes(encryptedBytes, authTagBytes)) {
      return encryptedBytes
    }
    return this.concatBytes(encryptedBytes, authTagBytes)
  }

  private unpackNewFormatPayload(payloadBytes: Uint8Array): PayloadParts {
    if (payloadBytes.length <= GCM_AUTH_TAG_LENGTH) {
      throw new Error(`invalid encrypted payload length: ${payloadBytes.length}`)
    }
    const splitIndex = payloadBytes.length - GCM_AUTH_TAG_LENGTH
    const payloadParts: PayloadParts = {
      cipherBytes: payloadBytes.subarray(0, splitIndex),
      authTagBytes: payloadBytes.subarray(splitIndex)
    }
    return payloadParts
  }

  private hasNonZeroBytes(bytes: Uint8Array): boolean {
    for (let index = 0; index < bytes.length; index++) {
      if (bytes[index] !== 0) {
        return true
      }
    }
    return false
  }

  private endsWithBytes(data: Uint8Array, suffix: Uint8Array): boolean {
    if (suffix.length === 0 || data.length < suffix.length) {
      return false
    }
    const startIndex = data.length - suffix.length
    for (let index = 0; index < suffix.length; index++) {
      if (data[startIndex + index] !== suffix[index]) {
        return false
      }
    }
    return true
  }

  private concatBytes(first: Uint8Array, second: Uint8Array): Uint8Array {
    const result = new Uint8Array(first.length + second.length)
    result.set(first, 0)
    result.set(second, first.length)
    return result
  }

  private describeError(error: Object): string {
    const detail = error as ErrorLike
    const raw = JSON.stringify(error)
    const fallbackRaw = raw.length > 0 ? raw : `${error}`
    return `code=${detail.code ?? 'n/a'}, name=${detail.name ?? 'n/a'}, message=${detail.message ?? 'n/a'}, raw=${fallbackRaw}`
  }

  private toRuntimeError(error: Object): Error {
    return new Error(this.describeError(error))
  }
}
