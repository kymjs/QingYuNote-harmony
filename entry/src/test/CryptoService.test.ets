import { describe, it, expect } from '@ohos/hypium'
import { CryptoService } from '../main/ets/services/CryptoService'
import { util } from '@kit.ArkTS'

const GCM_AUTH_TAG_LENGTH = 16
// Flutter cryptography::AesGcm.with128bits，key = MD5(zhangtaodeqingyuliulanqi-42)，
// nonce = 0x15..0x20，AAD = qingyu-note-rsa-aad。
const FLUTTER_NOTE_CIPHER = 'FRYXGBkaGxwdHh8g.gGCHoP0epXS3/8nz3qD29CcLJA2gDF/1YuecUwWaVweiHg3S'
// 旧 Harmony `AES128|GCM|PKCS7` 写入等价的 AES-GCM 密文：明文尾部保留
// PKCS7 0x02 0x02，nonce = 0x01..0x0c，AAD = qingyu-aad。
const LEGACY_PADDED_CIPHER = 'AQIDBAUGBwgJCgsM.xV04MepSuWDsn2QmbIQTW4xipArAWv6UObqC0E658Xs='

export default function cryptoServiceTest() {
  describe('CryptoService', () => {
    const service = CryptoService.getInstance()
    const base64 = new util.Base64Helper()

    it('should round-trip plaintext with the new payload format', 0, async () => {
      const plainText = 'webdav-password-123'
      const cipherText = await service.encryptText(plainText)
      expect(cipherText.split('.').length).assertEqual(2)

      const decrypted = await service.decryptText(cipherText)
      expect(decrypted).assertEqual(plainText)
    })

    it('should decrypt legacy three-segment payloads derived from the new payload', 0, async () => {
      const plainText = 'legacy-compatible-password'
      const newFormatCipherText = await service.encryptText(plainText)
      const segments = newFormatCipherText.split('.')
      const payloadBytes = base64.decodeSync(segments[1])
      const splitIndex = payloadBytes.length - GCM_AUTH_TAG_LENGTH
      const legacyCipherText = [
        segments[0],
        base64.encodeToStringSync(payloadBytes.subarray(splitIndex)),
        base64.encodeToStringSync(payloadBytes.subarray(0, splitIndex))
      ].join('.')

      const decrypted = await service.decryptText(legacyCipherText)
      expect(decrypted).assertEqual(plainText)
    })

    it('should decrypt Flutter AES-GCM note payloads', 0, async () => {
      const decrypted = await service.decryptNoteText(FLUTTER_NOTE_CIPHER, '42')
      expect(decrypted).assertEqual('Flutter 跨端正文')
    })

    it('should remove legacy GCM PKCS7 padding when reading historical payloads', 0, async () => {
      const decrypted = await service.decryptText(LEGACY_PADDED_CIPHER)
      expect(decrypted).assertEqual('legacy-harmony')
    })

    it('should return empty strings unchanged', 0, async () => {
      expect(await service.encryptText('')).assertEqual('')
      expect(await service.decryptText('')).assertEqual('')
    })

    it('should reject tampered two-segment payloads', 0, async () => {
      const cipherText = await service.encryptText('tamper-check')
      const segments = cipherText.split('.')
      const payloadBytes = base64.decodeSync(segments[1])
      payloadBytes[payloadBytes.length - 1] = payloadBytes[payloadBytes.length - 1] ^ 0x01
      const tamperedCipherText = `${segments[0]}.${base64.encodeToStringSync(payloadBytes)}`

      await expect(service.decryptText(tamperedCipherText)).assertPromiseIsRejected()
    })

    it('should reject too-short new payloads and ignore malformed segment counts', 0, async () => {
      const ivBytes = new Uint8Array(12)
      for (let index = 0; index < ivBytes.length; index++) {
        ivBytes[index] = index + 1
      }
      const tooShortPayload = new Uint8Array(GCM_AUTH_TAG_LENGTH)
      const tooShortCipherText = `${base64.encodeToStringSync(ivBytes)}.${base64.encodeToStringSync(tooShortPayload)}`

      await expect(service.decryptText(tooShortCipherText)).assertPromiseIsRejected()
      expect(await service.decryptText('onlyonesegment')).assertEqual('')
    })
  })
}
