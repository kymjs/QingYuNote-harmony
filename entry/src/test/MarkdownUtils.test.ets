import { describe, it, expect } from '@ohos/hypium'
import {
  MarkdownUtils,
  isPlaceholderTodoContent,
  shouldPersistTodoNote,
  shouldShowTodoNoteInHomeList
} from '../main/ets/common/utils/MarkdownUtils'

export default function markdownUtilsTest() {
  describe('MarkdownUtils', () => {
    it('should parse headings and paragraph blocks', 0, () => {
      const blocks = MarkdownUtils.parseBlocks('# 标题\n\n普通段落')
      expect(blocks.length).assertEqual(2)
      expect(blocks[0].type).assertEqual('heading1')
      expect(blocks[0].content).assertEqual('标题')
      expect(blocks[1].type).assertEqual('paragraph')
      expect(blocks[1].content).assertEqual('普通段落')
    })

    it('should parse heading levels 1 through 6', 0, () => {
      const src = '# H1\n## H2\n### H3\n#### H4\n##### H5\n###### H6'
      const blocks = MarkdownUtils.parseBlocks(src)
      expect(blocks.length).assertEqual(6)
      expect(blocks[0].type).assertEqual('heading1')
      expect(blocks[0].content).assertEqual('H1')
      expect(blocks[1].type).assertEqual('heading2')
      expect(blocks[1].content).assertEqual('H2')
      expect(blocks[2].type).assertEqual('heading3')
      expect(blocks[2].content).assertEqual('H3')
      expect(blocks[3].type).assertEqual('heading4')
      expect(blocks[3].content).assertEqual('H4')
      expect(blocks[4].type).assertEqual('heading5')
      expect(blocks[4].content).assertEqual('H5')
      expect(blocks[5].type).assertEqual('heading6')
      expect(blocks[5].content).assertEqual('H6')
    })

    it('should not treat seven hashes as heading', 0, () => {
      const blocks = MarkdownUtils.parseBlocks('####### not a heading')
      expect(blocks.length).assertEqual(1)
      expect(blocks[0].type).assertEqual('paragraph')
    })

    it('should group unordered and ordered lists', 0, () => {
      const blocks = MarkdownUtils.parseBlocks('- 第一项\n- 第二项\n\n1. 一\n2. 二')
      expect(blocks.length).assertEqual(2)
      expect(blocks[0].type).assertEqual('unordered_list')
      expect(blocks[0].items.length).assertEqual(2)
      expect(blocks[0].items[0][0].content).assertEqual('第一项')
      expect(blocks[1].type).assertEqual('ordered_list')
      expect(blocks[1].items.length).assertEqual(2)
      expect(blocks[1].items[1][0].content).assertEqual('二')
    })

    it('should parse code fences and divider', 0, () => {
      const blocks = MarkdownUtils.parseBlocks('```ts\nconst value = 1\n```\n\n---')
      expect(blocks.length).assertEqual(2)
      expect(blocks[0].type).assertEqual('code')
      expect(blocks[0].language).assertEqual('ts')
      expect(blocks[0].content).assertEqual('const value = 1')
      expect(blocks[1].type).assertEqual('divider')
    })

    it('should parse inline triple-backtick code in paragraph', 0, () => {
      const blocks = MarkdownUtils.parseBlocks('文本 ```inline code``` 结束')
      expect(blocks.length).assertEqual(1)
      expect(blocks[0].type).assertEqual('paragraph')
      expect(blocks[0].inlines.some((i) => i.type === 'inline_code' && i.content === 'inline code')).assertTrue()
    })

    it('should not treat same-line inline fence as multiline opener', 0, () => {
      const blocks = MarkdownUtils.parseBlocks('```inline only```')
      expect(blocks.length).assertEqual(1)
      expect(blocks[0].type).assertEqual('paragraph')
      expect(blocks[0].inlines[0].type).assertEqual('inline_code')
      expect(blocks[0].inlines[0].content).assertEqual('inline only')
    })

    it('should parse strikethrough inline', 0, () => {
      const blocks = MarkdownUtils.parseBlocks('~~删除线~~')
      expect(blocks.length).assertEqual(1)
      expect(blocks[0].inlines.length).assertEqual(1)
      expect(blocks[0].inlines[0].type).assertEqual('strikethrough')
      expect(blocks[0].inlines[0].content).assertEqual('删除线')
    })

    it('should parse inline emphasis code and links', 0, () => {
      const blocks = MarkdownUtils.parseBlocks('这是 **加粗**、*斜体*、`代码` 和 [链接](https://example.com)')
      expect(blocks.length).assertEqual(1)
      expect(blocks[0].inlines.length).assertEqual(8)
      expect(blocks[0].inlines[1].type).assertEqual('bold')
      expect(blocks[0].inlines[1].content).assertEqual('加粗')
      expect(blocks[0].inlines[3].type).assertEqual('italic')
      expect(blocks[0].inlines[3].content).assertEqual('斜体')
      expect(blocks[0].inlines[5].type).assertEqual('inline_code')
      expect(blocks[0].inlines[5].content).assertEqual('代码')
      expect(blocks[0].inlines[7].type).assertEqual('link')
      expect(blocks[0].inlines[7].href).assertEqual('https://example.com')
    })

    it('should parse math display and inline', 0, () => {
      const blocks = MarkdownUtils.parseBlocks('$$\n\\frac{a}{b}\n$$')
      expect(blocks.some((b) => b.type === 'math_display')).assertTrue()
      const inlines = MarkdownUtils.parseInlines('公式 \\(x^2\\) 结束')
      expect(inlines.some((i) => i.type === 'math_inline' && i.content === 'x^2')).assertTrue()
    })

    it('should keep summary readable after stripping markdown', 0, () => {
      const summary = MarkdownUtils.summary('# 标题\n\n- **项目**\n- [链接](https://example.com)')
      expect(summary).assertContain('标题')
      expect(summary).assertContain('项目')
      expect(summary).assertContain('链接')
    })

    it('should parse markdown table', 0, () => {
      const blocks = MarkdownUtils.parseBlocks('| Name | Age |\n| --- | --- |\n| Alice | 20 |')
      expect(blocks.length).assertEqual(1)
      expect(blocks[0].type).assertEqual('table')
      expect((blocks[0].tableHeaders ?? []).length).assertEqual(2)
      expect(blocks[0].tableHeaders?.[0]?.[0]?.content).assertEqual('Name')
      expect(blocks[0].tableHeaders?.[1]?.[0]?.content).assertEqual('Age')
      expect((blocks[0].tableRows ?? []).length).assertEqual(1)
      expect(blocks[0].tableRows?.[0]?.[0]?.[0]?.content).assertEqual('Alice')
      expect(blocks[0].tableRows?.[0]?.[1]?.[0]?.content).assertEqual('20')
    })

    it('should parse unicode unchecked checkbox like [ ]', 0, () => {
      const blocks = MarkdownUtils.parseBlocks('☐ 待办一\n☐ 待办二')
      expect(blocks.length).assertEqual(1)
      expect(blocks[0].type).assertEqual('checkbox_list')
      expect((blocks[0].checkboxItems ?? []).length).assertEqual(2)
      expect(blocks[0].checkboxItems?.[0]?.checked).assertFalse()
      expect(blocks[0].checkboxItems?.[0]?.inlines?.[0]?.content).assertEqual('待办一')
      expect(blocks[0].checkboxItems?.[1]?.inlines?.[0]?.content).assertEqual('待办二')
    })

    it('should parse [ ] and ☐ checkbox lines together', 0, () => {
      const blocks = MarkdownUtils.parseBlocks('[ ] 任务A\n☐ 任务B')
      expect(blocks.length).assertEqual(1)
      expect(blocks[0].type).assertEqual('checkbox_list')
      expect((blocks[0].checkboxItems ?? []).length).assertEqual(2)
      expect(blocks[0].checkboxItems?.[0]?.inlines?.[0]?.content).assertEqual('任务A')
      expect(blocks[0].checkboxItems?.[1]?.inlines?.[0]?.content).assertEqual('任务B')
    })

    it('should treat empty checkbox todo content as placeholder', 0, () => {
      expect(isPlaceholderTodoContent('[ ] ')).assertTrue()
      expect(isPlaceholderTodoContent('[ ]\n[-]')).assertTrue()
      expect(shouldPersistTodoNote('待办事项', '[ ] ')).assertFalse()
    })

    it('should persist todo when checkbox has text', 0, () => {
      expect(isPlaceholderTodoContent('[ ] 买牛奶')).assertFalse()
      expect(shouldPersistTodoNote('待办事项', '[ ] 买牛奶')).assertTrue()
    })

    it('should hide placeholder todo from home list', 0, () => {
      expect(shouldShowTodoNoteInHomeList('待办事项', '[ ] ', ['Todo'])).assertFalse()
      expect(shouldShowTodoNoteInHomeList('待办事项', '[ ] ', ['Work'])).assertTrue()
    })

    it('should continue markdown marker on newline', 0, () => {
      const bullet = MarkdownUtils.applyMarkdownMarkerOnNewline('* item', '* item\n')
      expect(bullet?.text).assertEqual('* item\n* ')
      const ordered = MarkdownUtils.applyMarkdownMarkerOnNewline('1. first', '1. first\n')
      expect(ordered?.text).assertEqual('1. first\n2. ')
      const unchecked = MarkdownUtils.applyMarkdownMarkerOnNewline('[ ] todo', '[ ] todo\n')
      expect(unchecked?.text).assertEqual('[ ] todo\n[ ] ')
      const checked = MarkdownUtils.applyMarkdownMarkerOnNewline('[-] done', '[-] done\n')
      expect(checked?.text).assertEqual('[-] done\n[-] ')
    })

    it('should not continue marker-only line on newline', 0, () => {
      expect(MarkdownUtils.applyMarkdownMarkerOnNewline('* ', '* \n')).assertNull()
      expect(MarkdownUtils.applyMarkdownMarkerOnNewline('hello', 'hello\n')).assertNull()
    })

    it('should use todo fallback when enabled', 0, () => {
      const result = MarkdownUtils.applyMarkdownMarkerOnNewline('hello', 'hello\n', true)
      expect(result?.text).assertEqual('hello\n[ ] ')
    })
  })
}
