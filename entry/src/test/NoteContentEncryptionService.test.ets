import { describe, it, expect } from '@ohos/hypium'
import { NoteStateCodec } from '../main/ets/common/utils/NoteStateCodec'
import { NoteContentEncryptionService } from '../main/ets/services/NoteContentEncryptionService'

const FLUTTER_NOTE_CIPHER = 'FRYXGBkaGxwdHh8g.gGCHoP0epXS3/8nz3qD29CcLJA2gDF/1YuecUwWaVweiHg3S'

export default function noteContentEncryptionServiceTest() {
  describe('NoteContentEncryptionService', () => {
    it('should decrypt Flutter encrypted note payloads used by history versions', 0, async () => {
      const state = NoteStateCodec.createDefaultState('history-note', FLUTTER_NOTE_CIPHER, 0)
      state.rsa = 1
      const payload = {
        content: FLUTTER_NOTE_CIPHER,
        rawContent: FLUTTER_NOTE_CIPHER,
        state,
        hasStateBlock: true,
        filePath: '',
        modifiedAt: 0
      }

      const decrypted = await NoteContentEncryptionService.getInstance()
        .decryptPayloadForDisplay(payload, '42')

      expect(decrypted.state.title).assertEqual('Flutter 跨端正文')
      expect(decrypted.content).assertEqual('Flutter 跨端正文')
    })
  })
}
