import router from '@ohos.router'
import { UIContext } from '@kit.ArkUI'

const TODO_EDITOR_URL = 'pages/dashboard/todo/TodoEditorPage'

export interface TodoEditorNavParams {
  noteId?: string
}

/**
 * 推入新建 / 编辑待办页；编辑现有 todo 时传 `noteId`。
 *
 * 落地规则见项目 CLAUDE.md「待办事项 / 日程 隐藏字段规则」与
 * `NoteRepository.createNote` / `saveDraft` 处理 is_todo=2 的分支。
 */
export async function navigateToTodoEditor(
  uiContext: UIContext,
  params: TodoEditorNavParams
): Promise<void> {
  try {
    await uiContext.getRouter().pushUrl({
      url: TODO_EDITOR_URL,
      params: {
        noteId: params.noteId ?? ''
      }
    })
  } catch (err) {
    console.error(`pushUrl TodoEditorPage failed: ${JSON.stringify(err)}`)
    throw err as Error
  }
}
