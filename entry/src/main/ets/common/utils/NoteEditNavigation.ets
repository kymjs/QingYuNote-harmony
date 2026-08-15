import router from '@ohos.router'
import { UIContext } from '@kit.ArkUI'

import { type NoteEditorEntryAction } from '../model/NoteEditorEntryAction'
import { ensureAiMembershipAccess } from './AiMembershipGateNavigation'

const NOTE_EDIT_URL = 'pages/NoteEdit'

/** 进程内全局锁，避免首页多处并发触发重复 push。 */
let noteEditNavigationInFlight: boolean = false

export interface NoteEditNavParams {
  noteId?: string
  openWithPreview?: boolean
  initialAction?: NoteEditorEntryAction
}

function initialActionRequiresAiMembership(action?: NoteEditorEntryAction): boolean {
  return action === 'aiLinkExtract' ||
    action === 'generateNoteFromImage' ||
    action === 'bookScan' ||
    action === 'voiceMemo'
}

/** 笔记编辑页单例导航（RouterMode.Single）。 */
export async function navigateToNoteEdit(
  uiContext: UIContext,
  params: NoteEditNavParams
): Promise<void> {
  if (noteEditNavigationInFlight) {
    return
  }
  if (initialActionRequiresAiMembership(params.initialAction)) {
    if (!(await ensureAiMembershipAccess(uiContext))) {
      return
    }
  }
  noteEditNavigationInFlight = true
  try {
    await uiContext.getRouter().pushUrl({
      url: NOTE_EDIT_URL,
      params: {
        noteId: params.noteId ?? '',
        openWithPreview: params.openWithPreview === true,
        initialAction: params.initialAction
      }
    }, router.RouterMode.Single)
  } catch (err) {
    console.error(`pushUrl NoteEdit failed: ${JSON.stringify(err)}`)
    throw err as Error
  } finally {
    noteEditNavigationInFlight = false
  }
}
