import { describe, it, expect } from '@ohos/hypium'
import { NoteStateCodec } from '../main/ets/common/utils/NoteStateCodec'
import { MarkdownUtils } from '../main/ets/common/utils/MarkdownUtils'

export default function noteStateCodecTest() {
  describe('NoteStateCodec', () => {
    it('should serialize and parse note state blocks', 0, () => {
      const state = NoteStateCodec.createDefaultState(
        '2f7bef91-443f-4a6c-b0a3-26de4b4bdcdb',
        '独立标题',
        Date.parse('2024-10-10T04:35:08.083Z')
      )
      state.tags = ['work', '项目A', 'with:colon']
      state.isTodo = 1
      const raw = NoteStateCodec.serializeStateBlock(state)
      const payload = NoteStateCodec.parseNoteFile(`正文内容\n\n${raw}`, 'fallback-id')
      expect(payload.hasStateBlock).assertTrue()
      expect(payload.state.id).assertEqual('2f7bef91-443f-4a6c-b0a3-26de4b4bdcdb')
      expect(payload.state.title).assertEqual('独立标题')
      expect(payload.state.isTodo).assertEqual(1)
      expect(payload.state.tags.length).assertEqual(3)
      expect(payload.state.tags[0]).assertEqual('work')
      expect(payload.state.tags[1]).assertEqual('项目A')
      expect(payload.state.tags[2]).assertEqual('with:colon')
      expect(payload.content).assertEqual('正文内容')
    })

    it('should keep markdown summary free from note state footer', 0, () => {
      const raw = `# 标题\n\n这里是正文。\n\n<!-- NOTE_STATE
id: 2f7bef91-443f-4a6c-b0a3-26de4b4bdcdb
title: 独立标题
parent_id:
created_time: 2024-10-10T04:35:08.083Z
updated_time: 2024-12-02T03:24:13.147Z
is_conflict: 0
latitude: 31.23041600
longitude: 121.47370100
altitude: 0.0000
author:
source_url:
is_todo: 0
todo_due: 0
todo_completed: 0
source: joplin-desktop
order: 0
user_data:
deleted_time: 0
type_: 1
-->`
      const visibleContent = NoteStateCodec.stripStateBlock(raw)
      const summary = MarkdownUtils.summary(visibleContent)
      expect(summary).assertContain('标题')
      expect(summary).assertContain('这里是正文')
      expect(summary.includes('source_application')).assertFalse()
      expect(summary.includes('type_')).assertFalse()
    })

    it('should ignore non-tail html comments', 0, () => {
      const raw = `正文前\n<!-- NOTE_STATE\nid: not-the-footer\n-->\n\n真正结尾`
      const payload = NoteStateCodec.parseNoteFile(raw, 'tail-id')
      expect(payload.hasStateBlock).assertFalse()
      expect(payload.content).assertEqual(raw)
      expect(payload.state.id).assertEqual('tail-id')
    })
  })
}
