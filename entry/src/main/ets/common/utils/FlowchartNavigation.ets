import router from '@ohos.router'
import { UIContext } from '@kit.ArkUI'

const FLOWCHART_URL = 'pages/Flowchart'

/** 进程内全局锁，避免首页多处并发触发重复 push。 */
let flowchartNavigationInFlight: boolean = false

export interface FlowchartNavParams {
  noteId: string
  focusQuery?: string
}

/** 知识图谱页单例导航（RouterMode.Single）。 */
export async function navigateToFlowchart(
  uiContext: UIContext,
  params: FlowchartNavParams
): Promise<void> {
  if (flowchartNavigationInFlight) {
    return
  }
  flowchartNavigationInFlight = true
  try {
    await uiContext.getRouter().pushUrl({
      url: FLOWCHART_URL,
      params: {
        noteId: params.noteId,
        focusQuery: params.focusQuery ?? ''
      }
    }, router.RouterMode.Single)
  } catch (err) {
    console.error(`pushUrl Flowchart failed: ${JSON.stringify(err)}`)
    throw err as Error
  } finally {
    flowchartNavigationInFlight = false
  }
}
