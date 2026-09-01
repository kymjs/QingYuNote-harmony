/** PC / iPad 横屏内嵌知识图谱编辑（保留 MainShell TabBar）。 */
export const FLOWCHART_INLINE_NOTE_ID_KEY = 'flowchartInlineNoteId'
export const FLOWCHART_INLINE_FOCUS_QUERY_KEY = 'flowchartInlineFocusQuery'
export const FLOWCHART_INLINE_INITIAL_MIND_MAP_KEY = 'flowchartInlineInitialMindMap'
export const FLOWCHART_PC_LAYOUT_KEY = 'flowchartPcLayoutActive'

export interface FlowchartInlineLaunch {
  noteId: string
  focusQuery?: string
  initialMindMap?: boolean
}

export function openFlowchartInline(launch: FlowchartInlineLaunch): void {
  AppStorage.setOrCreate(FLOWCHART_INLINE_NOTE_ID_KEY, launch.noteId)
  AppStorage.setOrCreate(FLOWCHART_INLINE_FOCUS_QUERY_KEY, launch.focusQuery ?? '')
  AppStorage.setOrCreate(
    FLOWCHART_INLINE_INITIAL_MIND_MAP_KEY,
    launch.initialMindMap === true ? '1' : '0'
  )
}

export function closeFlowchartInline(): void {
  AppStorage.setOrCreate(FLOWCHART_INLINE_NOTE_ID_KEY, '')
  AppStorage.setOrCreate(FLOWCHART_INLINE_FOCUS_QUERY_KEY, '')
  AppStorage.setOrCreate(FLOWCHART_INLINE_INITIAL_MIND_MAP_KEY, '0')
}

export function isFlowchartInlineActive(): boolean {
  const id = `${AppStorage.get<string>(FLOWCHART_INLINE_NOTE_ID_KEY) ?? ''}`
  return id.length > 0
}
