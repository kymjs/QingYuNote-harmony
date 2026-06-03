import type { MarkdownBlock } from './MarkdownUtils'

export class NoteImageGalleryUtils {
  /** 按文档顺序收集 Markdown 图片块 `language`（src）。 */
  static collectImageSources(blocks: MarkdownBlock[]): string[] {
    const sources: string[] = []
    for (const block of blocks) {
      if (block.type === 'image') {
        const src = block.language.trim()
        if (src.length > 0) {
          sources.push(src)
        }
      }
    }
    return sources
  }
}
