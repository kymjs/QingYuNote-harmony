import { MarkdownUtils } from './MarkdownUtils'

export interface TitleSaveResolution {
  title: string
  skipTitleAutoFill: boolean
}

/** 仅当标题和正文至少有一个非空时为 true（与 Flutter `_hasEditorTitleOrBody` 对齐）。 */
export function hasEditorTitleOrBody(title: string, content: string): boolean {
  return title.trim().length > 0 || content.trim().length > 0
}

/** 保存前解析标题：聚焦标题框时空标题不自动填充。 */
export function resolveTitleForSave(
  rawTitle: string,
  content: string,
  titleFieldFocused: boolean
): TitleSaveResolution {
  const trimmedTitle = rawTitle.trim()
  if (trimmedTitle.length > 0) {
    return { title: trimmedTitle, skipTitleAutoFill: false }
  }
  if (titleFieldFocused) {
    return { title: '', skipTitleAutoFill: true }
  }
  if (content.trim().length === 0) {
    return { title: '', skipTitleAutoFill: false }
  }
  return { title: MarkdownUtils.editorAutoTitle(content), skipTitleAutoFill: false }
}

/** 占位 Todo 笔记是否应跳过自动保存调度。 */
export function shouldSkipAutoSaveSchedule(
  title: string,
  content: string,
  isTodoTag: boolean,
  shouldPersistTodo: boolean
): boolean {
  if (title.trim().length === 0 && content.trim().length === 0) {
    return true
  }
  return isTodoTag && !shouldPersistTodo
}
