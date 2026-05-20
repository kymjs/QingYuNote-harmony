import { describe, it, expect } from '@ohos/hypium'
import { MarkdownUtils } from '../main/ets/common/utils/MarkdownUtils'

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
  })
}
