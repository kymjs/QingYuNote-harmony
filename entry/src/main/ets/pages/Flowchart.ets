import { FlowchartEditor } from '../components/FlowchartEditor'

@Entry
@Component
struct FlowchartPage {
  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>
    this.noteId = `${params?.noteId ?? ''}`
    this.focusQuery = `${params?.focusQuery ?? ''}`
    this.initialMindMap = `${params?.initialMindMap ?? ''}` === '1'
  }

  @State noteId: string = ''
  @State focusQuery: string = ''
  @State initialMindMap: boolean = false

  build() {
    Column() {
      FlowchartEditor({
        embeddedMode: false,
        embeddedNoteId: this.noteId,
        embeddedFocusQuery: this.focusQuery,
        embeddedInitialMindMap: this.initialMindMap
      })
    }
    .width('100%')
    .height('100%')
  }
}
