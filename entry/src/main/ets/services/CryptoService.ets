import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { util } from '@kit.ArkTS'
import { Logger } from '../common/utils/Logger'

const KEY_SEED = 'qingyu-notes-key'
const AAD_SEED = 'qingyu-aad'
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

  async encryptText(plainText: string): Promise<string> {
    Logger.info('CryptoService', `encryptText start: inputLength=${plainText.length}`)
    if (plainText.length === 0) {
      Logger.info('CryptoService', 'encryptText short-circuit: empty plain text')
      return ''
    }
    try {
      const cipher = cryptoFramework.createCipher('AES128|GCM|PKCS7')
      const ivBytes = this.randomBytes(12)
      Logger.info('CryptoService', `encryptText iv ready: ivLength=${ivBytes.length}`)
      const aadBytes = this.toBytes(AAD_SEED)
      const params: cryptoFramework.GcmParamsSpec = {
        iv: { data: ivBytes },
        aad: { data: aadBytes },
        authTag: { data: new Uint8Array(16) },
        algName: 'GcmParamsSpec'
      }
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, await this.getSymKey(), params)
      Logger.info('CryptoService', 'encryptText cipher init success')
      const encrypted = await cipher.doFinal({
        data: this.toBytes(plainText)
      })
      Logger.info('CryptoService', `encryptText doFinal success: encryptedLength=${encrypted.data.length}`)
      const payload = this.buildGcmPayload(encrypted.data, params.authTag.data)
      const cipherText = [
        this.base64.encodeToStringSync(ivBytes),
        this.base64.encodeToStringSync(payload)
      ].join('.')
      Logger.info('CryptoService',
        `encryptText success: segmentCount=${cipherText.split('.').length}, cipherLength=${cipherText.length}`)
      return cipherText
    } catch (error) {
      Logger.warn('CryptoService', `encryptText failed: ${this.describeError(error)}`)
      throw this.toRuntimeError(error)
    }
  }

  async decryptText(cipherText: string): Promise<string> {
    Logger.info('CryptoService', `decryptText start: cipherLength=${cipherText.length}`)
    if (cipherText.length === 0) {
      Logger.info('CryptoService', 'decryptText short-circuit: empty cipher text')
      return ''
    }
    const segments = cipherText.split('.')
    Logger.info('CryptoService', `decryptText segments parsed: segmentCount=${segments.length}`)
    if (segments.length !== 2 && segments.length !== 3) {
      Logger.warn('CryptoService', 'decryptText invalid format: segmentCount is neither 2 nor 3')
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
      const cipherBytes = payloadParts.cipherBytes
      const authTagBytes = payloadParts.authTagBytes
      const params: cryptoFramework.GcmParamsSpec = {
        iv: { data: iv },
        aad: { data: this.toBytes(AAD_SEED) },
        authTag: { data: authTagBytes },
        algName: 'GcmParamsSpec'
      }
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, await this.getSymKey(), params)
      Logger.info('CryptoService', 'decryptText cipher init success')
      const decrypted = await cipher.doFinal({
        data: cipherBytes
      })
      const plainText = this.fromBytes(decrypted.data)
      Logger.info('CryptoService', `decryptText success: outputLength=${plainText.length}`)
      return plainText
    } catch (error) {
      Logger.warn('CryptoService', `decryptText failed: ${this.describeError(error)}`)
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
