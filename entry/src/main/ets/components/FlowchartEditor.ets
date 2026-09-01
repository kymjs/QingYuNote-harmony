import componentSnapshot from '@ohos.arkui.componentSnapshot'
import { util } from '@kit.ArkTS'
import { vibrator } from '@kit.SensorServiceKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { image } from '@kit.ImageKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { common, Configuration } from '@kit.AbilityKit'
import { FlowchartService } from '../services/FlowchartService'
import { FlowchartLegacyMigrate } from '../common/utils/FlowchartLegacyMigrate'
import { NoteRepository } from '../services/NoteRepository'
import { AppContextHolder } from '../services/AppContextHolder'
import { PageLifecycle } from '../common/utils/PageLifecycle'
import { FlowchartLayoutEngine } from '../common/utils/FlowchartLayoutEngine'
import { FlowchartEdgeRouting } from '../common/utils/FlowchartEdgeRouting'
import { FlowchartMindMap,
  type FlowchartBranchLabelLayout,
  type FlowchartLabelSize,
  FLOWCHART_MIND_MAP_BRANCH_FONT_SIZE,
  FLOWCHART_MIND_MAP_BRANCH_LINE_HEIGHT,
  FLOWCHART_MIND_MAP_BRANCH_SELECTION_PAD_H,
  FLOWCHART_MIND_MAP_BRANCH_SELECTION_PAD_V
} from '../common/utils/FlowchartMindMap'
import { FlowchartNodeIds } from '../common/utils/FlowchartNodeIds'
import { Logger } from '../common/utils/Logger'
import { EditorUiStrings } from '../common/utils/EditorUiStrings'
import { APP_LOCALE_REVISION_KEY } from '../services/LocaleService'
import type {
  FlowchartAnchor,
  FlowchartAnchorHit,
  FlowchartMindMapAddHit,
  FlowchartMindMapButtonRect,
  FlowchartEdgeLineEndpoints,
  FlowchartEdgeModel,
  FlowchartGraphModel,
  FlowchartLineType,
  FlowchartNodeModel,
  FlowchartNodePosition,
  FlowchartShapeType
} from '../common/model/FlowchartGraph'
import {
  FLOWCHART_LINE_NODE_SHAPE,
  FLOWCHART_LINE_PROP_FROM_X,
  FLOWCHART_LINE_PROP_FROM_Y,
  FLOWCHART_LINE_PROP_TO_X,
  FLOWCHART_LINE_PROP_TO_Y,
  FLOWCHART_LINE_PROP_TYPE,
  FLOWCHART_LINE_TYPES,
  FLOWCHART_ORTHOGONAL_ROUTING_KEY,
  FLOWCHART_MERMAID_NAME_KEY,
  FLOWCHART_GIT_TAG_KEY,
  FLOWCHART_GIT_BRANCH_NAME_KEY,
  FLOWCHART_JOURNEY_SECTION_KEY,
  FLOWCHART_MIND_MAP_ROLE_KEY,
  FLOWCHART_MIND_MAP_ROLE_ROOT,
  FLOWCHART_MIND_MAP_ROLE_BRANCH,
  FLOWCHART_MIND_MAP_ROOT_COLOR,
  FLOWCHART_MIND_MAP_LINE_COLOR,
  FLOWCHART_MIND_MAP_BRANCH_TEXT_COLOR,
  FLOWCHART_MIND_MAP_ROOT_TEXT_COLOR,
  FLOWCHART_MIND_MAP_SIDE_LEFT,
  FLOWCHART_MIND_MAP_SIDE_RIGHT,
  FLOWCHART_MIND_MAP_ROOT_ID_KEY,
  FLOWCHART_SHAPE_TYPES,
  FLOWCHART_DIAGRAM_KIND_KEY,
  createEmptyFlowchartGraph,
  createFlowchartPosition,
  cloneFlowchartGraph,
  cloneFlowchartRecord,
  flowchartFirstMatchingNodeId,
  FLOWCHART_DEFAULT_TITLE,
  isDefaultFlowchartTitle,
  isPlaceholderFlowchartGraph
} from '../common/model/FlowchartGraph'
import { FlowchartShapePath } from '../common/utils/FlowchartShapePath'
import { FlowchartNodePathView } from '../components/FlowchartNodePathView'
import { FlowchartMermaidCodec } from '../common/utils/FlowchartMermaidCodec'
import { MermaidTemplates } from '../common/utils/MermaidTemplates'
import {
  FLOWCHART_EDGE_COLOR_KEY,
  FLOWCHART_EDITOR_CHART_KINDS,
  FLOWCHART_EDITOR_COLORS,
  FLOWCHART_MERMAID_TEMPLATE_KIND_KEY,
  FlowchartAddNodeOption,
  FlowchartEditorChartKind,
  flowchartAddNodeLabel,
  flowchartAddNodeOptionsFor,
  flowchartEditorChartLabel,
  isCanvasEditableChartKind,
  isMermaidPreviewOnlyChartKind,
  chartKindFromMermaidBody
} from '../common/utils/FlowchartEditorConstants'
import { closeFlowchartInline } from '../common/utils/FlowchartInlineBridge'
import { MermaidPreview } from './MermaidPreview'
import type { MermaidInteractionEvent } from './MermaidPreview'
import { FlowchartStylePreviewIcon } from './FlowchartStylePreviewIcon'

const FLOWCHART_LOG_TAG = 'FlowchartEditor'

@Component
export struct FlowchartEditor {
  @StorageProp(APP_LOCALE_REVISION_KEY) localeRevision: number = 0
  @Prop embeddedMode: boolean = false
  @Prop @Watch('onEmbeddedLaunchChanged') embeddedNoteId: string = ''
  @Prop embeddedFocusQuery: string = ''
  @Prop embeddedInitialMindMap: boolean = false
  @State graph: FlowchartGraphModel = createEmptyFlowchartGraph()
  @State noteTitle: string = FLOWCHART_DEFAULT_TITLE
  @State noteId: string = ''
  @State focusQuery: string = ''
  @State loading: boolean = true
  @State showSourceView: boolean = false
  @State sourceText: string = ''
  @State chartKind: FlowchartEditorChartKind = 'flowchart'
  @State selectedEdgeId: string = ''
  @State showAddNodeSheet: boolean = false
  @State showColorSheet: boolean = false
  @State showStyleSheet: boolean = false
  @State @Watch('onSelectedNodeChanged') selectedNodeId: string = ''
  @State canvasScale: number = 1
  @State viewportX: number = 0
  @State viewportY: number = 0
  @State editTitle: string = ''
  @State editDescription: string = ''
  /** default | nodeName | user | single */
  @State editDialogMode: string = 'default'
  @State editSecondaryLabel: string = '描述'
  @State showEditDialog: boolean = false
  @State showEdgeEditDialog: boolean = false
  @State showNoteTitleDialog: boolean = false
  @State editNoteTitleInput: string = ''
  @State editingNodeId: string = ''
  @State editingEdgeId: string = ''
  @State editEdgeLabel: string = ''
  /** single 模式：journeySection | gitBranch | gitTag */
  @State editSingleKind: string = ''
  @State touchMoved: boolean = false
  @State graphRevision: number = 0
  @State interactionTick: number = 0
  @State draggingNodeId: string = ''
  @State dragLiveX: number = 0
  @State dragLiveY: number = 0
  @State connectDraftActive: boolean = false
  @State connectDraftFromX: number = 0
  @State connectDraftFromY: number = 0
  @State connectDraftToX: number = 0
  @State connectDraftToY: number = 0
  @State pageWidth: number = 360
  @State historyRevision: number = 0
  private undoStack: FlowchartGraphModel[] = []
  private redoStack: FlowchartGraphModel[] = []
  private touchMode: number = 0
  private lastEditedNodeId: string = ''
  private pinchStartScale: number = 1
  private pendingDragNodeId: string = ''
  private touchDownAtMs: number = 0
  private dragActivated: boolean = false
  private longPressTimerId: number = -1
  private activeConnectFromId: string = ''
  private activeConnectFromAnchor: FlowchartAnchor = 'right'
  private lastTouchLocalX: number = 0
  private lastTouchLocalY: number = 0
  private dragStartX: number = 0
  private dragStartY: number = 0
  private draggingEndpointIndex: number = -1
  private endpointDragStartFromX: number = 0
  private endpointDragStartFromY: number = 0
  private endpointDragStartToX: number = 0
  private endpointDragStartToY: number = 0
  private endpointDragStartPosX: number = 0
  private endpointDragStartPosY: number = 0
  private endpointDragStartWidth: number = 0
  private lastTapTime: number = 0
  private lastTapNodeId: string = ''
  private lastTapEdgeId: string = ''
  private lastTapEdgeTime: number = 0
  private canvasReady: boolean = false
  private static readonly TOUCH_DRAG = 1
  private static readonly TOUCH_CONNECT = 2
  private static readonly TOUCH_PAN = 3
  private static readonly TOUCH_PENDING_DRAG = 4
  private static readonly TOUCH_PINCH = 5
  private static readonly TOUCH_ENDPOINT = 6
  private static readonly LONG_PRESS_MS = 100
  private static readonly ENDPOINT_HIT_RADIUS = 18
  private static readonly MIN_CANVAS_SCALE = 0.25
  private static readonly MAX_CANVAS_SCALE = 4
  private static readonly WIDE_LAYOUT_MIN_WIDTH = 600
  /** 节点层相对逻辑包围盒的外扩边距，避免连接点圆被裁切。 */
  private static readonly NODE_LAYER_PAD = 4
  /** 直线/箭头端点规范化时的内边距。 */
  private static readonly ENDPOINT_BOUNDS_PAD = 16
  private lifecycle = new PageLifecycle()
  private dirty: boolean = false
  private initialHadNodes: boolean = false
  private initialMindMap: boolean = false
  private initialMindMapApplied: boolean = false
  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)

  aboutToAppear(): void {
    this.lifecycle.appear()
    if (this.embeddedMode) {
      this.applyEmbeddedLaunch()
      return
    }
    if (this.embeddedNoteId.trim().length > 0) {
      this.noteId = this.embeddedNoteId.trim()
      this.focusQuery = this.embeddedFocusQuery
      this.initialMindMap = this.embeddedInitialMindMap
      this.initialMindMapApplied = false
      void this.loadGraph()
      return
    }
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>
    this.noteId = `${params?.noteId ?? ''}`
    this.focusQuery = `${params?.focusQuery ?? ''}`
    this.initialMindMap = `${params?.initialMindMap ?? ''}` === '1'
    this.initialMindMapApplied = false
    void this.loadGraph()
  }

  private onEmbeddedLaunchChanged(): void {
    if (!this.embeddedMode) {
      return
    }
    this.applyEmbeddedLaunch()
  }

  private applyEmbeddedLaunch(): void {
    const nextNoteId = this.embeddedNoteId.trim()
    if (nextNoteId.length === 0) {
      return
    }
    if (nextNoteId === this.noteId &&
      this.focusQuery === this.embeddedFocusQuery &&
      this.initialMindMap === this.embeddedInitialMindMap) {
      return
    }
    void this.saveIfDirty().then(() => {
      if (!this.lifecycle.isActive()) {
        return
      }
      this.noteId = nextNoteId
      this.focusQuery = this.embeddedFocusQuery
      this.initialMindMap = this.embeddedInitialMindMap
      this.initialMindMapApplied = false
      this.loading = true
      void this.loadGraph()
    })
  }

  private exitEditor(): void {
    void this.finalizeOnExit().then(() => {
      if (this.embeddedMode) {
        closeFlowchartInline()
        return
      }
      this.getUIContext().getRouter().back()
    })
  }

  onPageShow(): void {
    void this.applyRouterParamsIfNeeded()
  }

  private async applyRouterParamsIfNeeded(): Promise<void> {
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>
    const nextNoteId = `${params?.noteId ?? ''}`
    const nextFocus = `${params?.focusQuery ?? ''}`
    const nextMindMap = `${params?.initialMindMap ?? ''}` === '1'
    if (nextNoteId === this.noteId && nextFocus === this.focusQuery &&
      nextMindMap === this.initialMindMap) {
      return
    }
    await this.saveIfDirty()
    if (!this.lifecycle.isActive()) {
      return
    }
    this.noteId = nextNoteId
    this.focusQuery = nextFocus
    this.initialMindMap = nextMindMap
    this.initialMindMapApplied = false
    this.loading = true
    void this.loadGraph()
  }

  aboutToDisappear(): void {
    this.lifecycle.disappear()
    this.clearDragVisual()
  }

  onBackPress(): boolean {
    this.exitEditor()
    return true
  }

  private async finalizeOnExit(): Promise<void> {
    await this.saveIfDirty()
  }

  onConfigurationUpdate(_config: Configuration): void {
    if (this.canvasReady) {
      this.redrawCanvas()
    }
  }

  private colorResourceToHex(name: string): string {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    const argb = context.resourceManager.getColorByNameSync(name)
    const toHex = (value: number): string => value.toString(16).padStart(2, '0')
    const r = (argb >>> 16) & 0xFF
    const g = (argb >>> 8) & 0xFF
    const b = argb & 0xFF
    return `#${toHex(r)}${toHex(g)}${toHex(b)}`
  }

  private async loadGraph(): Promise<void> {
    if (this.noteId.length === 0) {
      this.loading = false
      return
    }
    await NoteRepository.getInstance().init()
    await FlowchartLegacyMigrate.migrateIfNeeded(this.noteId)
    const note = await NoteRepository.getInstance().getNote(this.noteId)
    const loaded = note === null
      ? createEmptyFlowchartGraph()
      : await FlowchartService.getInstance().load(this.noteId)
    let graph = loaded
    if (FlowchartMindMap.isMindMapMode(graph)) {
      const rootId = FlowchartMindMap.rootId(graph)
      if (rootId.length > 0) {
        graph = FlowchartLayoutEngine.applyMindMapLinearLayout(
          graph,
          this.isPhoneLayout(),
          rootId
        )
      }
    }
    if (this.lifecycle.isActive()) {
      this.graph = graph
      this.noteTitle = note?.title ?? FLOWCHART_DEFAULT_TITLE
      this.initialHadNodes = !isPlaceholderFlowchartGraph(loaded)
      this.loading = false
      Logger.info(FLOWCHART_LOG_TAG,
        `loadGraph noteId=${this.noteId} nodes=${loaded.nodes.length} edges=${loaded.edges.length} ` +
        `edgeIds=[${loaded.edges.map((e: FlowchartEdgeModel) => e.id.slice(0, 8)).join(',')}]`)
      this.graphRevision++
      this.scheduleCanvasRedraw()
      // 先恢复 chartKind，再 sync 源码；否则预览类样式会按 flowchart 编码，或首帧空源码不展示。
      const templateRaw = `${graph.metadata[FLOWCHART_MERMAID_TEMPLATE_KIND_KEY] ?? ''}`
      if (FLOWCHART_EDITOR_CHART_KINDS.includes(templateRaw as FlowchartEditorChartKind)) {
        this.chartKind = templateRaw as FlowchartEditorChartKind
      } else {
        this.chartKind = 'flowchart'
      }
      if (this.chartKind === 'mindmap' && !FlowchartMindMap.isMindMapMode(this.graph)) {
        this.graph = this.promoteGraphToMindMap(this.graph)
        this.graphRevision++
        this.scheduleCanvasRedraw()
      }
      this.syncSourceFromGraph()
      const nodeId = flowchartFirstMatchingNodeId(loaded, this.focusQuery)
      if (nodeId.length > 0) {
        this.selectedNodeId = nodeId
        this.markNodeEdited(nodeId)
      } else if (loaded.nodes.length > 0) {
        this.lastEditedNodeId = loaded.nodes[loaded.nodes.length - 1].id
      }
      if (this.initialMindMap && !this.initialMindMapApplied && isPlaceholderFlowchartGraph(graph)) {
        this.initialMindMapApplied = true
        this.enterMindMapMode()
      }
    }
  }

  /** 无节点且标题为默认/空时不写入知识图谱。 */
  private shouldPersistFlowchart(): boolean {
    return !isPlaceholderFlowchartGraph(this.graph) || !isDefaultFlowchartTitle(this.noteTitle)
  }

  private async abandonNewEmptyFlowchartIfNeeded(): Promise<void> {
    if (this.noteId.length === 0 || this.shouldPersistFlowchart() || this.initialHadNodes) {
      return
    }
    await NoteRepository.getInstance().purgeLocalNoteCompletely(this.noteId)
  }

  private async persist(showToast: boolean = false): Promise<void> {
    if (this.noteId.length === 0) {
      this.showUserMessage(EditorUiStrings.loc('未关联笔记，无法保存', 'No linked note; cannot save', 'ノートが関連付けられていないため保存できません'))
      return
    }
    if (!this.shouldPersistFlowchart()) {
      this.dirty = false
      await this.abandonNewEmptyFlowchartIfNeeded()
      if (showToast) {
        this.showUserMessage(EditorUiStrings.loc('无需保存', 'Nothing to save', '保存不要'))
      }
      return
    }
    try {
      Logger.info(FLOWCHART_LOG_TAG,
        `persist start noteId=${this.noteId} nodes=${this.graph.nodes.length} edges=${this.graph.edges.length}`)
      await NoteRepository.getInstance().ensureFlowchartNote(this.noteId, this.noteTitle)
      await FlowchartService.getInstance().save(this.graph, this.noteId)
      const bodyOverride = (this.showSourceView || isMermaidPreviewOnlyChartKind(this.chartKind)) ?
        this.sourceText.trim() : undefined
      await NoteRepository.getInstance().saveFlowchartNote(
        this.noteId,
        this.graph,
        this.noteTitle,
        bodyOverride !== undefined && bodyOverride.length > 0 ? bodyOverride : undefined
      )
      this.dirty = false
      Logger.info(FLOWCHART_LOG_TAG, `persist ok noteId=${this.noteId} edges=${this.graph.edges.length}`)
      if (showToast) {
        this.showUserMessage(EditorUiStrings.loc('已保存', 'Saved', '保存済み'))
      }
    } catch (error) {
      console.error(`persist failed: ${JSON.stringify(error)}`)
      this.showUserMessage(EditorUiStrings.loc('保存失败，请稍后重试', 'Save failed; try again', '保存に失敗しました。後でもう一度お試しください'))
    }
  }

  private async saveIfDirty(): Promise<void> {
    if (!this.dirty) {
      await this.abandonNewEmptyFlowchartIfNeeded()
      return
    }
    if (!this.shouldPersistFlowchart()) {
      this.dirty = false
      await this.abandonNewEmptyFlowchartIfNeeded()
      return
    }
    await this.persist()
  }

  private isPhoneLayout(): boolean {
    return this.pageWidth < FlowchartEditor.WIDE_LAYOUT_MIN_WIDTH
  }

  private applyAlignedLayout(): void {
    this.pushUndo()
    this.graph = FlowchartLayoutEngine.applyAlignedLayout(this.graph, this.isPhoneLayout())
    this.graphRevision++
    this.markDirty()
    this.scheduleCanvasRedraw()
    this.showUserMessage(EditorUiStrings.loc('已对齐布局', 'Layout aligned', 'レイアウトを整列しました'))
  }

  private isMindMapMode(): boolean {
    return FlowchartMindMap.isMindMapMode(this.graph)
  }

  private mindMapBranchLabel(node: FlowchartNodeModel): FlowchartBranchLabelLayout {
    return FlowchartMindMap.layoutBranchLabel(node.title)
  }

  private mindMapRootId(): string {
    return FlowchartMindMap.rootId(this.graph)
  }

  private onMindMapPaletteTap(): void {
    this.enterMindMapMode()
  }

  /** 侧边栏点击思维导图：始终新增一套默认模板，不复用/升格已有图形节点。 */
  private enterMindMapMode(): void {
    this.pushUndo()
    const wasMindMapMode = this.isMindMapMode()
    const preferVertical = this.isPhoneLayout()
    const inputText = EditorUiStrings.loc('输入文本', 'Enter text', 'テキストを入力')

    const allocated: string[] = []
    let template = FlowchartMindMap.createDefaultTemplate((): string => {
      const used: string[] = []
      for (const n of this.graph.nodes) {
        used.push(n.id)
      }
      for (const id of allocated) {
        used.push(id)
      }
      const next = FlowchartNodeIds.next(used)
      allocated.push(next)
      return next
    })
    const templateNodes = template.nodes.map((node: FlowchartNodeModel): FlowchartNodeModel => ({
      id: node.id,
      title: inputText,
      description: node.description,
      color: node.color,
      shape: node.shape,
      position: node.position,
      width: node.width,
      height: node.height,
      rotation: node.rotation,
      properties: node.properties
    }))
    template = {
      version: template.version,
      metadata: template.metadata,
      nodes: templateNodes,
      edges: [...template.edges]
    }
    const newRootId = FlowchartMindMap.rootId(template)
    template = FlowchartLayoutEngine.applyMindMapLinearLayout(template, preferVertical, newRootId)

    if (this.graph.nodes.length > 0) {
      template = this.offsetGraphToFreeSpace(template, this.graph.nodes)
    }

    const metadata = cloneFlowchartRecord(this.graph.metadata)
    const templateMetaKeys = Object.keys(template.metadata)
    for (let i = 0; i < templateMetaKeys.length; i++) {
      const key = templateMetaKeys[i]
      metadata[key] = template.metadata[key]
    }
    metadata[FLOWCHART_MERMAID_TEMPLATE_KIND_KEY] = 'mindmap'
    metadata[FLOWCHART_DIAGRAM_KIND_KEY] = 'mindmap'
    // 先切样式再写图，保证编码与右下角「图表样式」选中态一致。
    this.chartKind = 'mindmap'
    this.graph = {
      version: this.graph.version,
      metadata,
      nodes: [...this.graph.nodes, ...template.nodes],
      edges: [...this.graph.edges, ...template.edges]
    }
    this.selectedNodeId = newRootId
    this.markNodeEdited(newRootId)
    this.graphRevision++
    this.markDirty()
    this.scheduleCanvasRedraw()
    this.syncSourceFromGraph()
    if (!wasMindMapMode) {
      this.showUserMessage(EditorUiStrings.loc('已进入思维导图模式', 'Mind map mode enabled', 'マインドマップモードを開始しました'))
    }
  }

  private offsetGraphToFreeSpace(
    graph: FlowchartGraphModel,
    against: FlowchartNodeModel[]
  ): FlowchartGraphModel {
    if (graph.nodes.length === 0) {
      return graph
    }
    let minX = Number.MAX_VALUE
    let minY = Number.MAX_VALUE
    let maxX = Number.MIN_VALUE
    let maxY = Number.MIN_VALUE
    for (const node of graph.nodes) {
      minX = Math.min(minX, node.position.x)
      minY = Math.min(minY, node.position.y)
      maxX = Math.max(maxX, node.position.x + node.width)
      maxY = Math.max(maxY, node.position.y + node.height)
    }
    const blockW = Math.max(1, maxX - minX)
    const blockH = Math.max(1, maxY - minY)
    const start = this.newNodePosition(blockW, blockH, against.length)
    const freeOrigin = this.findFreePositionAmong(start.x, start.y, blockW, blockH, against)
    const dx = freeOrigin.x - minX
    const dy = freeOrigin.y - minY
    if (dx === 0 && dy === 0) {
      return graph
    }
    const nodes = graph.nodes.map((node: FlowchartNodeModel): FlowchartNodeModel => ({
      id: node.id,
      title: node.title,
      description: node.description,
      color: node.color,
      shape: node.shape,
      position: { x: node.position.x + dx, y: node.position.y + dy },
      width: node.width,
      height: node.height,
      rotation: node.rotation,
      properties: node.properties
    }))
    return {
      version: graph.version,
      metadata: graph.metadata,
      nodes,
      edges: [...graph.edges]
    }
  }

  private overlapsNodes(
    x: number,
    y: number,
    w: number,
    h: number,
    nodes: FlowchartNodeModel[]
  ): boolean {
    const pad = 8
    const right = x + w
    const bottom = y + h
    for (const node of nodes) {
      const nLeft = node.position.x - pad
      const nTop = node.position.y - pad
      const nRight = node.position.x + node.width + pad
      const nBottom = node.position.y + node.height + pad
      if (x < nRight && right > nLeft && y < nBottom && bottom > nTop) {
        return true
      }
    }
    return false
  }

  private findFreePositionAmong(
    startX: number,
    startY: number,
    w: number,
    h: number,
    nodes: FlowchartNodeModel[]
  ): FlowchartNodePosition {
    const gapY = 24
    const stepX = 48
    let x = startX
    let y = startY
    for (let attempt = 0; attempt < 64; attempt++) {
      if (!this.overlapsNodes(x, y, w, h, nodes)) {
        return createFlowchartPosition(x, y)
      }
      y += gapY
      if (attempt % 8 === 7) {
        x += stepX
        y = startY
      }
    }
    return createFlowchartPosition(startX, startY + gapY * 64)
  }

  private addMindMapChildOnSide(parentId: string, side: string): void {
    const parent = this.nodeById(parentId)
    if (parent === undefined) {
      return
    }

    this.pushUndo()
    const existingIds: string[] = []
    for (const n of this.graph.nodes) {
      existingIds.push(n.id)
    }
    const childId = FlowchartNodeIds.next(existingIds)
    const childProperties: Record<string, Object> = {}
    childProperties[FLOWCHART_MIND_MAP_ROLE_KEY] = FLOWCHART_MIND_MAP_ROLE_BRANCH
    const child: FlowchartNodeModel = {
      id: childId,
      title: EditorUiStrings.loc('输入文本', 'Enter text', 'テキストを入力'),
      description: '',
      color: '',
      shape: 'roundedRect',
      position: parent.position,
      width: 40,
      height: 24,
      rotation: 0,
      properties: childProperties
    }
    let graph = FlowchartMindMap.addChildOnSide(
      this.graph,
      parentId,
      side,
      child,
      util.generateRandomUUID()
    )
    const treeRoot = FlowchartMindMap.treeRootId(graph, parentId)
    const rootId = treeRoot.length > 0
      ? treeRoot
      : (this.mindMapRootId().length > 0 ? this.mindMapRootId() : FlowchartMindMap.rootId(graph))
    graph = FlowchartLayoutEngine.applyMindMapLinearLayout(graph, this.isPhoneLayout(), rootId, true)
    this.graph = graph
    this.selectedNodeId = childId
    this.markNodeEdited(childId)
    this.graphRevision++
    this.markDirty()
    this.scheduleCanvasRedraw()
  }

  private mindMapAddButtonRect(node: FlowchartNodeModel, side: string): FlowchartMindMapButtonRect {
    const size = 24
    const gap = 8
    const display = this.nodeDisplaySize(node)
    const top = node.position.y + display.h / 2 - size / 2
    if (side === FLOWCHART_MIND_MAP_SIDE_LEFT) {
      const rect: FlowchartMindMapButtonRect = { x: node.position.x - gap - size, y: top, w: size, h: size }
      return rect
    }
    const rect: FlowchartMindMapButtonRect = { x: node.position.x + display.w + gap, y: top, w: size, h: size }
    return rect
  }

  private hitTestMindMapAddButton(x: number, y: number): FlowchartMindMapAddHit | undefined {
    if (!this.isMindMapMode() || this.selectedNodeId.length === 0) {
      return undefined
    }
    const node = this.nodeById(this.selectedNodeId)
    if (node === undefined) {
      return undefined
    }
    if (!FlowchartMindMap.isRoot(this.graph, node) &&
      !FlowchartMindMap.isBranch(this.graph, node)) {
      return undefined
    }
    const sides = FlowchartMindMap.isRoot(this.graph, node)
      ? [FLOWCHART_MIND_MAP_SIDE_LEFT, FLOWCHART_MIND_MAP_SIDE_RIGHT]
      : [FlowchartMindMap.expansionSide(this.graph, node.id)]
    for (const side of sides) {
      if (side.length === 0) {
        continue
      }
      const rect = this.mindMapAddButtonRect(node, side)
      if (x >= rect.x && x <= rect.x + rect.w && y >= rect.y && y <= rect.y + rect.h) {
        const hit: FlowchartMindMapAddHit = { parentId: node.id, side }
        return hit
      }
    }
    return undefined
  }

  private markNodeEdited(nodeId: string): void {
    if (nodeId.length > 0) {
      this.lastEditedNodeId = nodeId
    }
  }

  private pushUndo(): void {
    this.undoStack.push(cloneFlowchartGraph(this.graph))
    if (this.undoStack.length > 20) {
      this.undoStack.shift()
    }
    this.redoStack = []
    this.historyRevision++
  }

  private undo(): void {
    if (this.undoStack.length === 0) {
      return
    }
    this.redoStack.push(cloneFlowchartGraph(this.graph))
    this.graph = this.undoStack.pop() as FlowchartGraphModel
    this.selectedNodeId = ''
    this.selectedEdgeId = ''
    this.markDirty()
    this.graphRevision++
    this.scheduleCanvasRedraw()
    this.historyRevision++
  }

  private redo(): void {
    if (this.redoStack.length === 0) {
      return
    }
    this.undoStack.push(cloneFlowchartGraph(this.graph))
    this.graph = this.redoStack.pop() as FlowchartGraphModel
    this.selectedNodeId = ''
    this.selectedEdgeId = ''
    this.markDirty()
    this.graphRevision++
    this.scheduleCanvasRedraw()
    this.historyRevision++
  }

  private canUndo(): boolean {
    return this.undoStack.length > 0
  }

  private canRedo(): boolean {
    return this.redoStack.length > 0
  }

  private syncSourceFromGraph(): void {
    if (isCanvasEditableChartKind(this.chartKind)) {
      const encoded = FlowchartMermaidCodec.encodeGraph(this.graph)
      this.sourceText = encoded.mermaidBody
      return
    }
    const converted = MermaidTemplates.fromGraph(this.chartKind, this.graph, this.noteTitle)
    this.sourceText = converted.length > 0
      ? converted
      : FlowchartMermaidCodec.encodeGraph(this.graph).mermaidBody
  }

  private maybeSyncSourceFromGraph(): void {
    if (!this.showSourceView) {
      this.syncSourceFromGraph()
    }
  }

  private toggleSourceView(): void {
    if (this.showSourceView) {
      const applied = this.applySourceToGraph()
      this.showSourceView = false
      this.graphRevision++
      if (!applied) {
        this.showUserMessage(EditorUiStrings.loc(
          '源码有语法错误无法渲染，请切换源码修改',
          'Source has syntax errors and cannot be rendered. Switch to Code to fix.',
          'ソースに構文エラーがあり描画できません。コードに切り替えて修正してください'
        ))
      }
      return
    }
    // 进入编码：流程图从画布同步；预览类样式以当前编码为准，勿覆盖用户已改内容。
    if (isCanvasEditableChartKind(this.chartKind)) {
      this.syncSourceFromGraph()
    }
    this.showSourceView = true
  }

  /** 将编码应用到画布。成功 true；无法渲染 false（保留原图）。 */
  private applySourceToGraph(): boolean {
    const body = this.sourceText.trim()
    if (body.length === 0) {
      this.markDirty()
      return true
    }
    const detected = chartKindFromMermaidBody(body, this.chartKind)
    if (detected === undefined) {
      this.markDirty()
      return false
    }

    // 饼图 / 时序图等：画布走 Mermaid 预览，以当前编码为准。
    if (isMermaidPreviewOnlyChartKind(detected)) {
      const metadata: Record<string, Object> = cloneFlowchartRecord(this.graph.metadata)
      metadata[FLOWCHART_MERMAID_TEMPLATE_KIND_KEY] = detected
      this.chartKind = detected
      this.graph = {
        version: this.graph.version,
        metadata: metadata,
        nodes: this.graph.nodes,
        edges: this.graph.edges
      }
      this.markDirty()
      return true
    }

    // 状态图源码（statediagram）：切到可交互画布 + 直线。
    const bodyLower = body.trim().toLowerCase()
    if (detected === 'state' && bodyLower.startsWith('statediagram')) {
      const metadata: Record<string, Object> = cloneFlowchartRecord(this.graph.metadata)
      metadata[FLOWCHART_MERMAID_TEMPLATE_KIND_KEY] = detected
      metadata[FLOWCHART_DIAGRAM_KIND_KEY] = 'flowchart'
      metadata[FLOWCHART_ORTHOGONAL_ROUTING_KEY] = false
      this.chartKind = detected
      this.graph = {
        version: this.graph.version,
        metadata: metadata,
        nodes: this.graph.nodes,
        edges: this.graph.edges
      }
      this.markDirty()
      this.scheduleCanvasRedraw()
      return true
    }

    // flowchart / 状态图（graph 编码）：解析进可交互画布。
    try {
      const parsed = FlowchartMermaidCodec.parseFromNote(
        FlowchartMermaidCodec.wrapMermaidFence(body),
        FlowchartMermaidCodec.encodeGraph(this.graph).flowchartExtJson
      )
      const metadata: Record<string, Object> = cloneFlowchartRecord(parsed.metadata)
      metadata[FLOWCHART_MERMAID_TEMPLATE_KIND_KEY] = detected
      metadata[FLOWCHART_DIAGRAM_KIND_KEY] = FlowchartMermaidCodec.detectKind(body)
      metadata[FLOWCHART_ORTHOGONAL_ROUTING_KEY] = detected === 'flowchart'
      this.chartKind = detected
      this.graph = {
        version: parsed.version,
        metadata: metadata,
        nodes: parsed.nodes,
        edges: parsed.edges
      }
      this.markDirty()
      this.scheduleCanvasRedraw()
      return true
    } catch (_) {
      return false
    }
  }

  private onAddNodeOption(option: FlowchartAddNodeOption): void {
    this.showAddNodeSheet = false
    if (option === 'mindmap') {
      this.enterMindMapMode()
      return
    }
    if (option === 'pieSlice') {
      this.addNode('roundedRect', this.nextIndexedTitle('类型'))
      return
    }
    if (option === 'gitBranch') {
      this.addGitBranch()
      return
    }
    if (option === 'gitCommit') {
      this.addNode('roundedRect', this.nextIndexedTitle('事件'))
      return
    }
    if (option === 'gitTag') {
      this.addGitTagNode()
      return
    }
    if (option === 'classBox') {
      this.addNode('rectangle')
      return
    }
    let shape: FlowchartShapeType = 'roundedRect'
    if (option === 'rectangle') {
      shape = 'roundedRect'
    } else if (option === 'circle') {
      shape = 'circle'
    } else if (option === 'diamond') {
      shape = 'diamond'
    } else if (option === 'sharpRect') {
      shape = 'rectangle'
    }
    this.addNode(shape)
  }

  private nextIndexedTitle(prefix: string): string {
    let max = 0
    for (const node of this.graph.nodes) {
      if (`${node.shape}` === 'line') {
        continue
      }
      const title = node.title.trim()
      if (!title.startsWith(prefix)) {
        continue
      }
      const numStr = title.substring(prefix.length)
      let ok = numStr.length > 0
      for (let i = 0; i < numStr.length; i++) {
        const ch = numStr.charAt(i)
        if (ch < '0' || ch > '9') {
          ok = false
          break
        }
      }
      if (!ok) {
        continue
      }
      const n = Number.parseInt(numStr, 10)
      if (!Number.isNaN(n) && n > max) {
        max = n
      }
    }
    return `${prefix}${max + 1}`
  }

  private addGitBranch(): void {
    this.pushUndo()
    const current = `${this.graph.metadata[FLOWCHART_GIT_BRANCH_NAME_KEY] ?? ''}`.trim()
    let max = 0
    if (current.startsWith('分支')) {
      const numStr = current.substring(2)
      const n = Number.parseInt(numStr, 10)
      if (!Number.isNaN(n)) {
        max = n
      } else if (current.length > 0) {
        max = 1
      }
    } else if (current.length > 0) {
      max = 1
    }
    const branchName = `分支${max + 1}`
    const metadata = cloneFlowchartRecord(this.graph.metadata)
    metadata[FLOWCHART_GIT_BRANCH_NAME_KEY] = branchName
    const index = this.graph.nodes.length
    const width = 120
    const height = 72
    const existingIds: string[] = []
    for (const n of this.graph.nodes) {
      existingIds.push(n.id)
    }
    const props: Record<string, Object> = {}
    props[FLOWCHART_MERMAID_NAME_KEY] = `branch${max + 1}`
    const node: FlowchartNodeModel = {
      id: FlowchartNodeIds.next(existingIds),
      title: branchName,
      description: '',
      color: '#E3F2FD',
      shape: 'roundedRect',
      position: this.newNodePosition(width, height, index),
      width,
      height,
      rotation: 0,
      properties: props
    }
    const edges: FlowchartEdgeModel[] = [...this.graph.edges]
    let prevId = ''
    for (let i = this.graph.nodes.length - 1; i >= 0; i--) {
      if (`${this.graph.nodes[i].shape}` !== 'line') {
        prevId = this.graph.nodes[i].id
        break
      }
    }
    if (prevId.length > 0) {
      edges.push({
        id: util.generateRandomUUID(),
        source: prevId,
        target: node.id,
        label: '',
        directed: true,
        lineType: 'solid',
        sourceAnchor: 'right',
        targetAnchor: 'left',
        properties: {}
      })
    }
    this.graph = {
      version: this.graph.version,
      metadata: metadata,
      nodes: [...this.graph.nodes, node],
      edges: edges
    }
    this.selectedNodeId = node.id
    this.markNodeEdited(node.id)
    this.markDirty()
    this.graphRevision++
    this.scheduleCanvasRedraw()
    this.syncSourceFromGraph()
  }

  private addGitTagNode(): void {
    const title = this.nextIndexedTitle('标签')
    this.pushUndo()
    const index = this.graph.nodes.length
    const width = 120
    const height = 72
    const existingIds: string[] = []
    for (const n of this.graph.nodes) {
      existingIds.push(n.id)
    }
    const props: Record<string, Object> = {}
    props[FLOWCHART_GIT_TAG_KEY] = title
    const node: FlowchartNodeModel = {
      id: FlowchartNodeIds.next(existingIds),
      title: title,
      description: '',
      color: '#E3F2FD',
      shape: 'roundedRect',
      position: this.newNodePosition(width, height, index),
      width,
      height,
      rotation: 0,
      properties: props
    }
    this.graph = {
      version: this.graph.version,
      metadata: this.graph.metadata,
      nodes: [...this.graph.nodes, node],
      edges: [...this.graph.edges]
    }
    this.selectedNodeId = node.id
    this.markNodeEdited(node.id)
    this.markDirty()
    this.graphRevision++
    this.scheduleCanvasRedraw()
    this.syncSourceFromGraph()
  }

  private applySelectedColor(color: string): void {
    this.showColorSheet = false
    this.pushUndo()
    if (this.selectedNodeId.length > 0) {
      const node = this.nodeById(this.selectedNodeId)
      if (node !== undefined) {
        this.updateNode({
          id: node.id,
          title: node.title,
          description: node.description,
          color: color,
          shape: node.shape,
          position: createFlowchartPosition(node.position.x, node.position.y),
          width: node.width,
          height: node.height,
          rotation: node.rotation,
          properties: node.properties
        })
      }
      return
    }
    if (this.selectedEdgeId.length === 0) {
      return
    }
    const edges: FlowchartEdgeModel[] = []
    for (const edge of this.graph.edges) {
      if (edge.id !== this.selectedEdgeId) {
        edges.push(edge)
        continue
      }
      const props: Record<string, Object> = {}
      for (const key of Object.keys(edge.properties)) {
        props[key] = edge.properties[key]
      }
      props[FLOWCHART_EDGE_COLOR_KEY] = color
      edges.push({
        id: edge.id,
        source: edge.source,
        target: edge.target,
        label: edge.label,
        directed: edge.directed,
        lineType: edge.lineType,
        sourceAnchor: edge.sourceAnchor,
        targetAnchor: edge.targetAnchor,
        properties: props
      })
    }
    this.graph = {
      version: this.graph.version,
      metadata: this.graph.metadata,
      nodes: this.graph.nodes,
      edges: edges
    }
    this.markDirty()
    this.graphRevision++
    this.scheduleCanvasRedraw()
  }

  private applyChartKind(kind: FlowchartEditorChartKind): void {
    this.showStyleSheet = false
    this.pushUndo()
    this.chartKind = kind
    if (isCanvasEditableChartKind(kind)) {
      const metadata: Record<string, Object> = cloneFlowchartRecord(this.graph.metadata)
      metadata[FLOWCHART_MERMAID_TEMPLATE_KIND_KEY] = kind
      metadata[FLOWCHART_ORTHOGONAL_ROUTING_KEY] = kind === 'flowchart'
      if (kind === 'mindmap') {
        metadata[FLOWCHART_DIAGRAM_KIND_KEY] = 'mindmap'
      } else {
        metadata[FLOWCHART_DIAGRAM_KIND_KEY] = 'flowchart'
      }
      let next: FlowchartGraphModel = {
        version: this.graph.version,
        metadata: metadata,
        nodes: this.graph.nodes,
        edges: this.graph.edges
      }
      if (kind === 'mindmap') {
        if (!FlowchartMindMap.isMindMapMode(next)) {
          next = this.promoteGraphToMindMap(next)
        }
      } else {
        // 离开思维导图：清 layoutMode，否则 encode 仍输出 mindmap
        next = FlowchartMindMap.exitMode(next)
      }
      this.graph = next
      this.markDirty()
      this.graphRevision++
      this.scheduleCanvasRedraw()
      this.syncSourceFromGraph()
      return
    }
    // 非流程图：用真实节点/连线转成对应 Mermaid，不写假数据骨架。
    const metadata: Record<string, Object> = cloneFlowchartRecord(this.graph.metadata)
    metadata[FLOWCHART_MERMAID_TEMPLATE_KIND_KEY] = kind
    let nextGraph: FlowchartGraphModel = {
      version: this.graph.version,
      metadata: metadata,
      nodes: this.graph.nodes,
      edges: this.graph.edges
    }
    if (FlowchartMindMap.isMindMapMode(nextGraph)) {
      nextGraph = FlowchartMindMap.exitMode(nextGraph)
    }
    this.graph = nextGraph
    const converted = MermaidTemplates.fromGraph(kind, this.graph, this.noteTitle)
    this.sourceText = converted.length > 0 ? converted : MermaidTemplates.skeleton(kind)
    this.markDirty()
    this.graphRevision++
    this.scheduleCanvasRedraw()
  }

  /** 非流程图样式：画布展示 Mermaid 预览（随编码/样式实时更新）。 */
  private usesMermaidPreview(): boolean {
    return !this.showSourceView && isMermaidPreviewOnlyChartKind(this.chartKind)
  }

  private mermaidSelectedKind(): string {
    if (this.selectedNodeId.length > 0) {
      return 'node'
    }
    if (this.selectedEdgeId.length > 0) {
      return 'edge'
    }
    return ''
  }

  private mermaidSelectedId(): string {
    if (this.selectedNodeId.length > 0) {
      const visible: FlowchartNodeModel[] = []
      for (const n of this.graph.nodes) {
        if (`${n.shape}` === 'line') {
          continue
        }
        visible.push(n)
      }
      let idx = -1
      for (let i = 0; i < visible.length; i++) {
        if (visible[i].id === this.selectedNodeId) {
          idx = i
          break
        }
      }
      if (idx < 0) {
        return this.selectedNodeId
      }
      if (this.chartKind === 'sequence') {
        return `actor${idx}`
      }
      if (this.chartKind === 'pie' || this.chartKind === 'journey' ||
        this.chartKind === 'timeline' || this.chartKind === 'gitgraph') {
        return `node${idx}`
      }
      return MermaidTemplates.nodeMermaidName(visible[idx], idx)
    }
    if (this.selectedEdgeId.length > 0) {
      for (let i = 0; i < this.graph.edges.length; i++) {
        if (this.graph.edges[i].id === this.selectedEdgeId) {
          return `e${i}`
        }
      }
      return this.selectedEdgeId
    }
    return ''
  }

  private normalizeMermaidLabel(raw: string): string {
    let out = ''
    let space = false
    for (let i = 0; i < raw.length; i++) {
      const ch = raw.charAt(i)
      if (ch === ' ' || ch === '\n' || ch === '\t' || ch === '\r') {
        space = true
        continue
      }
      if (space && out.length > 0) {
        out += ' '
      }
      space = false
      out += ch
    }
    return out
  }

  private resolveMermaidNode(mermaidId: string, label: string): FlowchartNodeModel | undefined {
    const nodes: FlowchartNodeModel[] = []
    for (const n of this.graph.nodes) {
      if (`${n.shape}` === 'line') {
        continue
      }
      nodes.push(n)
    }
    const actorPrefix = 'actor'
    if (mermaidId.toLowerCase().startsWith(actorPrefix)) {
      const numStr = mermaidId.substring(actorPrefix.length)
      const idx = Number.parseInt(numStr, 10)
      if (!Number.isNaN(idx) && idx >= 0 && idx < nodes.length) {
        return nodes[idx]
      }
    }
    const nodePrefix = 'node'
    if (mermaidId.toLowerCase().startsWith(nodePrefix)) {
      const numStr = mermaidId.substring(nodePrefix.length)
      const idx = Number.parseInt(numStr, 10)
      if (!Number.isNaN(idx) && idx >= 0 && idx < nodes.length) {
        return nodes[idx]
      }
    }
    for (let i = 0; i < nodes.length; i++) {
      const safe = MermaidTemplates.nodeMermaidName(nodes[i], i)
      if (mermaidId.length > 0 &&
        (safe === mermaidId || mermaidId.indexOf(safe) >= 0 || safe.indexOf(mermaidId) >= 0)) {
        return nodes[i]
      }
    }
    const normalized = this.normalizeMermaidLabel(label.trim())
    if (normalized.length === 0) {
      return undefined
    }
    for (const node of nodes) {
      const title = this.normalizeMermaidLabel(node.title.trim())
      if (title.length === 0) {
        continue
      }
      if (title === normalized ||
        normalized.indexOf(`${title}:`) === 0 ||
        normalized.indexOf(`${title} `) === 0 ||
        normalized.indexOf(title) >= 0 ||
        title.indexOf(normalized) >= 0) {
        return node
      }
    }
    return undefined
  }

  private resolveMermaidEdge(mermaidId: string, label: string): FlowchartEdgeModel | undefined {
    if (mermaidId.length > 1 && mermaidId.charAt(0).toLowerCase() === 'e') {
      const idx = Number.parseInt(mermaidId.substring(1), 10)
      if (!Number.isNaN(idx) && idx >= 0 && idx < this.graph.edges.length) {
        return this.graph.edges[idx]
      }
    }
    const normalized = this.normalizeMermaidLabel(label.trim())
    if (normalized.length > 0) {
      for (const edge of this.graph.edges) {
        if (this.normalizeMermaidLabel(edge.label.trim()) === normalized) {
          return edge
        }
      }
    }
    const idMap: Record<string, string> = {}
    for (let i = 0; i < this.graph.nodes.length; i++) {
      idMap[this.graph.nodes[i].id] = MermaidTemplates.mermaidSafeId(this.graph.nodes[i].id, i)
    }
    if (mermaidId.length > 0) {
      for (const edge of this.graph.edges) {
        const a = idMap[edge.source] ?? ''
        const b = idMap[edge.target] ?? ''
        if (a.length > 0 && b.length > 0 && mermaidId.indexOf(a) >= 0 && mermaidId.indexOf(b) >= 0) {
          return edge
        }
      }
    }
    if (this.graph.edges.length === 1) {
      return this.graph.edges[0]
    }
    return undefined
  }

  private onMermaidPreviewInteraction(event: MermaidInteractionEvent): void {
    const id = event.id.trim()
    if (id === 'pieTitle' || id === 'chartTitle') {
      if (event.action === 'edit') {
        this.openNoteTitleDialog()
      }
      return
    }
    if (id === 'journeySection') {
      if (event.action === 'edit') {
        this.openJourneySectionDialog()
      }
      return
    }
    if (id === 'gitBranch') {
      if (event.action === 'edit') {
        this.openGitBranchDialog()
      }
      return
    }
    if (id.toLowerCase().startsWith('gittag')) {
      const numStr = id.substring(6)
      const idx = Number.parseInt(numStr, 10)
      const nodes: FlowchartNodeModel[] = []
      for (const n of this.graph.nodes) {
        if (`${n.shape}` !== 'line') {
          nodes.push(n)
        }
      }
      if (!Number.isNaN(idx) && idx >= 0 && idx < nodes.length && event.action === 'edit') {
        this.openGitTagDialog(nodes[idx])
      }
      return
    }
    if (event.action === 'delete') {
      if (event.kind === 'edge') {
        const edge = this.resolveMermaidEdge(event.id, event.label)
        if (edge === undefined) {
          return
        }
        this.pushUndo()
        const edges: FlowchartEdgeModel[] = []
        for (const e of this.graph.edges) {
          if (e.id !== edge.id) {
            edges.push(e)
          }
        }
        this.selectedEdgeId = ''
        this.selectedNodeId = ''
        this.graph = {
          version: this.graph.version,
          metadata: this.graph.metadata,
          nodes: this.graph.nodes,
          edges: edges
        }
        this.markDirty()
        this.graphRevision++
        this.scheduleCanvasRedraw()
        this.syncSourceFromGraph()
        return
      }
      const node = this.resolveMermaidNode(event.id, event.label)
      if (node === undefined) {
        return
      }
      this.selectedNodeId = node.id
      this.selectedEdgeId = ''
      this.deleteSelectedNode()
      return
    }
    if (event.action === 'connect') {
      const from = this.resolveMermaidNode(event.id, event.label)
      const to = this.resolveMermaidNode(event.targetId ?? '', event.targetLabel ?? '')
      if (from === undefined || to === undefined || from.id === to.id) {
        return
      }
      this.createEdge(from.id, to.id)
      this.selectedNodeId = from.id
      this.selectedEdgeId = ''
      this.showUserMessage(EditorUiStrings.loc('已创建连线', 'Connection created', '接続を作成しました'))
      return
    }
    if (event.kind === 'node') {
      const node = this.resolveMermaidNode(event.id, event.label)
      if (node === undefined) {
        return
      }
      this.selectedNodeId = node.id
      this.selectedEdgeId = ''
      if (event.action === 'edit') {
        this.openEditDialog(node)
      }
      return
    }
    if (event.kind === 'edge') {
      const edge = this.resolveMermaidEdge(event.id, event.label)
      if (edge === undefined) {
        return
      }
      this.selectedEdgeId = edge.id
      this.selectedNodeId = ''
      if (event.action === 'edit') {
        this.openEdgeEditDialog(edge)
      }
    }
  }

  private mermaidColorsJson(): string {
    const nodes: Record<string, string> = {}
    const labels: Record<string, string> = {}
    const titleCounts: Record<string, number> = {}
    const visible: FlowchartNodeModel[] = []
    for (const node of this.graph.nodes) {
      if (`${node.shape}` === 'line') {
        continue
      }
      visible.push(node)
      const title = this.normalizeMermaidLabel(node.title.trim())
      if (title.length > 0) {
        const prev = titleCounts[title]
        titleCounts[title] = (prev === undefined ? 0 : prev) + 1
      }
    }
    let index = 0
    for (const node of visible) {
      const id = MermaidTemplates.mermaidSafeId(node.id, index)
      const color = node.color.trim()
      if (color.length > 0) {
        nodes[id] = color
        nodes[`actor${index}`] = color
        nodes[`node${index}`] = color
        const title = this.normalizeMermaidLabel(node.title.trim())
        const isPlaceholder = title.length === 0 || title === '双击编辑' ||
          title === '未命名' || title === '输入文本'
        if (!isPlaceholder && titleCounts[title] === 1) {
          labels[title] = color
        }
      }
      index++
    }
    const edges: Record<string, string> = {}
    for (let i = 0; i < this.graph.edges.length; i++) {
      const edge = this.graph.edges[i]
      const raw = edge.properties[FLOWCHART_EDGE_COLOR_KEY]
      const color = `${raw ?? ''}`.trim()
      if (color.length === 0) {
        continue
      }
      edges[edge.id] = color
      edges[`e${i}`] = color
      const label = this.normalizeMermaidLabel(edge.label.trim())
      if (label.length > 0 && label !== '消息') {
        edges[`label:${label}`] = color
      }
    }
    const payload: Record<string, Object> = {
      'nodes': nodes as Object,
      'labels': labels as Object,
      'edges': edges as Object
    }
    return JSON.stringify(payload)
  }

  @Builder
  private buildMermaidPreviewCanvas() {
    MermaidPreview({
      source: this.sourceText,
      interactive: true,
      editable: true,
      selectedKind: this.mermaidSelectedKind(),
      selectedId: this.mermaidSelectedId(),
      colorsJson: this.mermaidColorsJson(),
      syntaxErrorTitle: EditorUiStrings.loc(
        '源码有语法错误无法渲染，请切换源码修改',
        'Source has syntax errors and cannot be rendered. Switch to Code to fix.',
        'ソースに構文エラーがあり描画できません。コードに切り替えて修正してください'
      ),
      onMermaidInteraction: (event: MermaidInteractionEvent) => {
        this.onMermaidPreviewInteraction(event)
      }
    })
  }

  private isWideToolbarLayout(): boolean {
    return this.pageWidth >= FlowchartEditor.WIDE_LAYOUT_MIN_WIDTH
  }

  private onModifyColorTap(): void {
    if (this.selectedNodeId.length === 0 && this.selectedEdgeId.length === 0) {
      this.showUserMessage(EditorUiStrings.loc(
        '请先选中节点或连接线',
        'Select a node or connection first',
        '先にノードまたは接続線を選択してください'
      ))
      return
    }
    this.showColorSheet = true
  }

  private obtainUiAbilityContext(): common.UIAbilityContext | undefined {
    const host = this.getUIContext().getHostContext()
    if (host !== undefined) {
      return host as common.UIAbilityContext
    }
    return AppContextHolder.tryGetContext()
  }

  private async exportImage(): Promise<void> {
    const previousSelection = this.selectedNodeId
    if (previousSelection.length > 0) {
      this.selectedNodeId = ''
      this.graphRevision++
      await new Promise<void>((resolve) => setTimeout(() => resolve(), 80))
    }
    try {
      const snap = this.getUIContext().getComponentSnapshot()
      const opts: componentSnapshot.SnapshotOptions = { waitUntilRenderFinished: true }
      const pixelMap = await snap.get('flowchartExportHost', opts)
      const packer = image.createImagePacker()
      let pngBuf: ArrayBuffer
      try {
        pngBuf = await packer.packToData(pixelMap, {
          format: 'image/png',
          quality: 100,
          desiredDynamicRange: image.PackingDynamicRange.SDR
        })
      } finally {
        try {
          await pixelMap.release()
        } catch (_) {
          // ignore
        }
      }
      const context = this.obtainUiAbilityContext()
      if (context === undefined) {
        this.showUserMessage(EditorUiStrings.loc('导出失败，请稍后重试', 'Export failed; try again', 'エクスポートに失敗しました。後でもう一度お試しください'))
        return
      }
      const cachePath = `${context.cacheDir}/flowchart_export_${Date.now()}.png`
      const f = fileIo.openSync(cachePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(f.fd, pngBuf)
      fileIo.closeSync(f)
      const helper = photoAccessHelper.getPhotoAccessHelper(context)
      const srcFileUris: Array<string> = [fileUri.getUriFromPath(cachePath)]
      const photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [
        {
          title: `knowledge_graph_${Date.now()}`,
          fileNameExtension: 'png',
          photoType: photoAccessHelper.PhotoType.IMAGE,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT
        }
      ]
      const destUris: Array<string> = await helper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs)
      if (destUris.length > 0) {
        const src = fileIo.openSync(cachePath, fileIo.OpenMode.READ_ONLY)
        const dest = await fileIo.open(destUris[0], fileIo.OpenMode.WRITE_ONLY)
        await fileIo.copyFile(src.fd, dest.fd)
        fileIo.closeSync(src)
        fileIo.closeSync(dest)
        this.showUserMessage(EditorUiStrings.loc('图片已保存到相册', 'Saved to album', 'アルバムに保存しました'))
      }
    } catch (error) {
      console.error(`exportImage failed: ${JSON.stringify(error)}`)
      this.showUserMessage('导出失败，请稍后重试')
    } finally {
      if (previousSelection.length > 0) {
        this.selectedNodeId = previousSelection
        this.graphRevision++
      }
    }
  }

  private showUserMessage(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message,
        duration: 2000
      })
    } catch (error) {
      console.error(`showToast failed: ${JSON.stringify(error)}`)
    }
  }

  private logTouch(message: string): void {
    // 拖动画布时高频触发；关闭以免刷屏。
  }

  private nodeRenderKey(node: FlowchartNodeModel): string {
    const pos = this.nodeDisplayPosition(node)
    let extra = ''
    if (this.isLineNode(node) || this.isArrowNode(node)) {
      const ep = this.endpointEndpointsLocal(node)
      extra = `_${ep.from.x.toFixed(1)}_${ep.from.y.toFixed(1)}_${ep.to.x.toFixed(1)}_${ep.to.y.toFixed(1)}`
    }
    const selected = this.selectedNodeId === node.id ? 1 : 0
    return `${node.id}_${pos.x.toFixed(1)}_${pos.y.toFixed(1)}_${node.width.toFixed(1)}_` +
      `${node.height.toFixed(1)}${extra}_${this.graphRevision}_` +
      `${selected}_${this.draggingNodeId === node.id ? this.interactionTick : 0}`
  }

  private isLineNode(node: FlowchartNodeModel): boolean {
    return node.shape === FLOWCHART_LINE_NODE_SHAPE
  }

  private isArrowNode(node: FlowchartNodeModel): boolean {
    return node.shape === 'arrowRight' || node.shape === 'arrowLeft'
  }

  private isEndpointShape(node: FlowchartNodeModel): boolean {
    return this.isLineNode(node) || this.isArrowNode(node)
  }

  private hasStoredEndpoints(node: FlowchartNodeModel): boolean {
    return typeof node.properties[FLOWCHART_LINE_PROP_FROM_X] === 'number'
  }

  private nodesForRender(): FlowchartNodeModel[] {
    const shapes: FlowchartNodeModel[] = []
    const overlays: FlowchartNodeModel[] = []
    for (const node of this.graph.nodes) {
      if (this.isLineNode(node) || this.isArrowNode(node)) {
        overlays.push(node)
      } else {
        shapes.push(node)
      }
    }
    return shapes.concat(overlays)
  }

  private propNumber(props: Record<string, Object>, key: string, fallback: number): number {
    const raw = props[key]
    if (typeof raw === 'number') {
      return raw
    }
    return fallback
  }

  private lineEndpointsLocal(node: FlowchartNodeModel): FlowchartEdgeLineEndpoints {
    const midY = node.height / 2
    return {
      from: {
        x: this.propNumber(node.properties, FLOWCHART_LINE_PROP_FROM_X, 0),
        y: this.propNumber(node.properties, FLOWCHART_LINE_PROP_FROM_Y, midY)
      },
      to: {
        x: this.propNumber(node.properties, FLOWCHART_LINE_PROP_TO_X, node.width),
        y: this.propNumber(node.properties, FLOWCHART_LINE_PROP_TO_Y, midY)
      }
    }
  }

  private endpointEndpointsLocal(node: FlowchartNodeModel): FlowchartEdgeLineEndpoints {
    if (this.isLineNode(node) || (this.isArrowNode(node) && this.hasStoredEndpoints(node))) {
      return this.lineEndpointsLocal(node)
    }
    if (this.isArrowNode(node)) {
      return {
        from: FlowchartShapePath.endpointLocal(node.shape, 0, node.width, node.height),
        to: FlowchartShapePath.endpointLocal(node.shape, 1, node.width, node.height)
      }
    }
    const midY = node.height / 2
    return {
      from: { x: 0, y: midY },
      to: { x: node.width, y: midY }
    }
  }

  private ensureEndpointProperties(node: FlowchartNodeModel): FlowchartNodeModel {
    if (!this.isLineNode(node) && !this.isArrowNode(node)) {
      return node
    }
    if (this.hasStoredEndpoints(node)) {
      return node
    }
    const ep = this.endpointEndpointsLocal(node)
    const props: Record<string, Object> = {}
    for (const key of Object.keys(node.properties)) {
      props[key] = node.properties[key]
    }
    if (this.isLineNode(node)) {
      props[FLOWCHART_LINE_PROP_TYPE] = this.lineTypeOf(node)
    }
    props[FLOWCHART_LINE_PROP_FROM_X] = ep.from.x
    props[FLOWCHART_LINE_PROP_FROM_Y] = ep.from.y
    props[FLOWCHART_LINE_PROP_TO_X] = ep.to.x
    props[FLOWCHART_LINE_PROP_TO_Y] = ep.to.y
    return {
      id: node.id,
      title: node.title,
      description: node.description,
      color: node.color,
      shape: node.shape,
      position: node.position,
      width: node.width,
      height: node.height,
      rotation: node.rotation,
      properties: props
    }
  }

  private normalizeEndpointNodeBounds(node: FlowchartNodeModel): FlowchartNodeModel {
    if (!this.isLineNode(node) && !this.isArrowNode(node)) {
      return node
    }
    const withProps = this.ensureEndpointProperties(node)
    const ep = this.lineEndpointsLocal(withProps)
    const pos = withProps.position
    return this.endpointNodeFromCanvas(
      withProps,
      createFlowchartPosition(pos.x + ep.from.x, pos.y + ep.from.y),
      createFlowchartPosition(pos.x + ep.to.x, pos.y + ep.to.y)
    )
  }

  /** 根据画布坐标系下的两端点，计算含内边距的节点包围盒与局部端点。 */
  private endpointNodeFromCanvas(
    base: FlowchartNodeModel,
    fromCanvas: FlowchartNodePosition,
    toCanvas: FlowchartNodePosition
  ): FlowchartNodeModel {
    const pad = FlowchartEditor.ENDPOINT_BOUNDS_PAD
    let minX = Math.min(fromCanvas.x, toCanvas.x) - pad
    let minY = Math.min(fromCanvas.y, toCanvas.y) - pad
    let maxX = Math.max(fromCanvas.x, toCanvas.x) + pad
    let maxY = Math.max(fromCanvas.y, toCanvas.y) + pad
    if (this.isArrowNode(base)) {
      const dx = toCanvas.x - fromCanvas.x
      const dy = toCanvas.y - fromCanvas.y
      const len = Math.sqrt(dx * dx + dy * dy)
      if (len > 0.001) {
        const shaftH = Math.max(20, Math.min(56, len * 0.35))
        const halfThickness = shaftH * 0.75
        const nx = -dy / len
        const ny = dx / len
        const corners: FlowchartNodePosition[] = [
          createFlowchartPosition(fromCanvas.x + nx * halfThickness, fromCanvas.y + ny * halfThickness),
          createFlowchartPosition(fromCanvas.x - nx * halfThickness, fromCanvas.y - ny * halfThickness),
          createFlowchartPosition(toCanvas.x + nx * halfThickness, toCanvas.y + ny * halfThickness),
          createFlowchartPosition(toCanvas.x - nx * halfThickness, toCanvas.y - ny * halfThickness)
        ]
        for (const pt of corners) {
          minX = Math.min(minX, pt.x)
          minY = Math.min(minY, pt.y)
          maxX = Math.max(maxX, pt.x)
          maxY = Math.max(maxY, pt.y)
        }
      }
    }
    if (this.isLineNode(base)) {
      const strokePad = 4
      minX -= strokePad
      minY -= strokePad
      maxX += strokePad
      maxY += strokePad
    }
    const minW = 48
    const minH = this.isLineNode(base) ? 32 : 48
    const newW = Math.max(minW, maxX - minX)
    const newH = Math.max(minH, maxY - minY)
    const props: Record<string, Object> = {}
    for (const key of Object.keys(base.properties)) {
      props[key] = base.properties[key]
    }
    if (this.isLineNode(base)) {
      props[FLOWCHART_LINE_PROP_TYPE] = this.lineTypeOf(base)
    }
    props[FLOWCHART_LINE_PROP_FROM_X] = fromCanvas.x - minX
    props[FLOWCHART_LINE_PROP_FROM_Y] = fromCanvas.y - minY
    props[FLOWCHART_LINE_PROP_TO_X] = toCanvas.x - minX
    props[FLOWCHART_LINE_PROP_TO_Y] = toCanvas.y - minY
    return {
      id: base.id,
      title: base.title,
      description: base.description,
      color: base.color,
      shape: base.shape,
      position: createFlowchartPosition(minX, minY),
      width: newW,
      height: newH,
      rotation: base.rotation,
      properties: props
    }
  }

  private endpointOverflow(node: FlowchartNodeModel): string {
    const ep = this.lineEndpointsLocal(node)
    const left = Math.min(ep.from.x, ep.to.x)
    const top = Math.min(ep.from.y, ep.to.y)
    const right = Math.max(ep.from.x, ep.to.x)
    const bottom = Math.max(ep.from.y, ep.to.y)
    const clipLeft = left < 0 ? left : 0
    const clipTop = top < 0 ? top : 0
    const clipRight = right > node.width ? right - node.width : 0
    const clipBottom = bottom > node.height ? bottom - node.height : 0
    return `overflow L=${clipLeft.toFixed(1)} T=${clipTop.toFixed(1)} ` +
      `R=${clipRight.toFixed(1)} B=${clipBottom.toFixed(1)} ` +
      `clipped=${clipLeft < 0 || clipTop < 0 || clipRight > 0 || clipBottom > 0}`
  }

  private overlappingNodeIds(x: number, y: number, w: number, h: number, excludeId: string = ''): string[] {
    const ids: string[] = []
    for (const node of this.graph.nodes) {
      if (node.id === excludeId) {
        continue
      }
      const pad = 0
      const left = x
      const top = y
      const right = x + w
      const bottom = y + h
      const nLeft = node.position.x - pad
      const nTop = node.position.y - pad
      const nRight = node.position.x + node.width + pad
      const nBottom = node.position.y + node.height + pad
      if (left < nRight && right > nLeft && top < nBottom && bottom > nTop) {
        ids.push(`${node.id.slice(0, 8)}:${node.shape}`)
      }
    }
    return ids
  }

  private logEndpointVisualState(node: FlowchartNodeModel, reason: string): void {
    if (!this.isLineNode(node) && !this.isArrowNode(node)) {
      return
    }
    const ep = this.lineEndpointsLocal(node)
    const canvasEp = this.lineEndpointsCanvas(node)
    const overlaps = this.overlappingNodeIds(
      node.position.x, node.position.y, node.width, node.height, node.id)
    const pathCmd = this.isLineNode(node) ? this.lineNodePathCommands(node) : ''
    const z = this.endpointLayerZIndex(node)
    Logger.info(FLOWCHART_LOG_TAG,
      `[EndpointVisual] ${reason} id=${node.id.slice(0, 8)} shape=${node.shape} ` +
      `box=(${node.position.x.toFixed(1)},${node.position.y.toFixed(1)}) ` +
      `${node.width.toFixed(1)}x${node.height.toFixed(1)} ` +
      `localFrom=(${ep.from.x.toFixed(1)},${ep.from.y.toFixed(1)}) ` +
      `localTo=(${ep.to.x.toFixed(1)},${ep.to.y.toFixed(1)}) ` +
      `canvasFrom=(${canvasEp.from.x.toFixed(1)},${canvasEp.from.y.toFixed(1)}) ` +
      `canvasTo=(${canvasEp.to.x.toFixed(1)},${canvasEp.to.y.toFixed(1)}) ` +
      `${this.endpointOverflow(node)} zIndex=${z} ` +
      `selected=${this.selectedNodeId === node.id} dragging=${this.draggingNodeId === node.id} ` +
      `overlaps=[${overlaps.join(',')}] ` +
      `path=${pathCmd.length > 0 ? pathCmd.slice(0, 80) : 'n/a'} ` +
      `canvasPath=${this.isLineNode(node) ? this.lineNodeCanvasPathCommands(node).slice(0, 80) : 'n/a'} ` +
      `render=${this.isLineNode(node) ? 'canvas' : 'node'} ` +
      `viewport=(${this.viewportX.toFixed(1)},${this.viewportY.toFixed(1)}) ` +
      `scale=${this.canvasScale.toFixed(2)} rev=${this.graphRevision}`)
  }

  private endpointLayerZIndex(node: FlowchartNodeModel): number {
    if (this.isLineNode(node) || this.isArrowNode(node)) {
      if (this.selectedNodeId === node.id || this.draggingNodeId === node.id) {
        return 20
      }
      return 5
    }
    return 1
  }

  private lineTypeOf(node: FlowchartNodeModel): string {
    const raw = node.properties[FLOWCHART_LINE_PROP_TYPE]
    return typeof raw === 'string' ? raw : 'solid'
  }

  private lineEndpointsCanvas(node: FlowchartNodeModel): FlowchartEdgeLineEndpoints {
    const pos = this.nodeDisplayPosition(node)
    const ep = this.lineEndpointsLocal(node)
    return {
      from: { x: pos.x + ep.from.x, y: pos.y + ep.from.y },
      to: { x: pos.x + ep.to.x, y: pos.y + ep.to.y }
    }
  }

  private endpointLocalPoint(node: FlowchartNodeModel, index: number): FlowchartNodePosition {
    const ep = this.endpointEndpointsLocal(node)
    return index === 0 ? ep.from : ep.to
  }

  private anchorPointLocal(node: FlowchartNodeModel, anchor: FlowchartAnchor): FlowchartNodePosition {
    return FlowchartShapePath.anchorLocal(node.shape, anchor, node.width, node.height)
  }

  private hitTestEndpoint(x: number, y: number): FlowchartAnchorHit | undefined {
    if (this.selectedNodeId.length === 0) {
      return undefined
    }
    const node = this.nodeById(this.selectedNodeId)
    if (node === undefined || !this.isEndpointShape(node)) {
      return undefined
    }
    const displayNode = this.nodeForRender(node.id)
    if (displayNode === undefined) {
      return undefined
    }
    const threshold = FlowchartEditor.ENDPOINT_HIT_RADIUS / this.canvasScale
    for (let i = 0; i < 2; i++) {
      const local = this.endpointLocalPoint(displayNode, i)
      const cx = displayNode.position.x + local.x
      const cy = displayNode.position.y + local.y
      const dx = x - cx
      const dy = y - cy
      if (dx * dx + dy * dy <= threshold * threshold) {
        const hit: FlowchartAnchorHit = {
          nodeId: node.id,
          anchor: i === 0 ? 'left' : 'right'
        }
        return hit
      }
    }
    return undefined
  }

  private distancePointToSegment(px: number, py: number, x1: number, y1: number,
    x2: number, y2: number): number {
    const dx = x2 - x1
    const dy = y2 - y1
    const lenSq = dx * dx + dy * dy
    if (lenSq < 0.001) {
      const ddx = px - x1
      const ddy = py - y1
      return Math.sqrt(ddx * ddx + ddy * ddy)
    }
    let t = ((px - x1) * dx + (py - y1) * dy) / lenSq
    t = Math.max(0, Math.min(1, t))
    const projX = x1 + t * dx
    const projY = y1 + t * dy
    const ddx = px - projX
    const ddy = py - projY
    return Math.sqrt(ddx * ddx + ddy * ddy)
  }

  private bumpInteraction(): void {
    this.interactionTick++
  }

  private logNodeShapeLayout(node: FlowchartNodeModel, reason: string): void {
    if (node.shape !== 'diamond' && node.shape !== 'arrowRight' && node.shape !== 'arrowLeft' &&
      !this.isLineNode(node)) {
      return
    }
    const pos = node.position
    const top = this.anchorPointLocal(node, 'top')
    const right = this.anchorPointLocal(node, 'right')
    const bottom = this.anchorPointLocal(node, 'bottom')
    const left = this.anchorPointLocal(node, 'left')
    let endpoints = ''
    if (this.isLineNode(node)) {
      const ep = this.lineEndpointsLocal(node)
      endpoints = ` lineFrom=(${ep.from.x.toFixed(1)},${ep.from.y.toFixed(1)}) ` +
        `lineTo=(${ep.to.x.toFixed(1)},${ep.to.y.toFixed(1)})`
    } else if (node.shape === 'arrowRight' || node.shape === 'arrowLeft') {
      const p0 = this.endpointLocalPoint(node, 0)
      const p1 = this.endpointLocalPoint(node, 1)
      endpoints = ` end0=(${p0.x.toFixed(1)},${p0.y.toFixed(1)}) end1=(${p1.x.toFixed(1)},${p1.y.toFixed(1)})`
    }
    Logger.info(FLOWCHART_LOG_TAG,
      `[ShapeLayout] ${reason} id=${node.id.slice(0, 8)} shape=${node.shape} ` +
      `pos=(${pos.x.toFixed(1)},${pos.y.toFixed(1)}) size=${node.width.toFixed(1)}x${node.height.toFixed(1)} ` +
      `vp2px=${this.shapePathPx(node.width).toFixed(1)}x${this.shapePathPx(node.height).toFixed(1)} ` +
      `anchors top=(${top.x.toFixed(1)},${top.y.toFixed(1)}) right=(${right.x.toFixed(1)},${right.y.toFixed(1)}) ` +
      `bottom=(${bottom.x.toFixed(1)},${bottom.y.toFixed(1)}) left=(${left.x.toFixed(1)},${left.y.toFixed(1)})` +
      `${endpoints} render=shapeUi`)
  }

  private scheduleCanvasRedraw(): void {
    if (!this.canvasReady) {
      return
    }
    this.redrawCanvas()
  }

  private onSelectedNodeChanged(): void {
    this.graphRevision++
  }

  private edgeRenderKey(edge: FlowchartEdgeModel): string {
    const source = this.nodeForRender(edge.source)
    const target = this.nodeForRender(edge.target)
    if (source === undefined || target === undefined) {
      return `${edge.id}_${this.graphRevision}_${this.interactionTick}`
    }
    const route = this.edgeRoutePoints(edge)
    const routeKey = route.map((p: FlowchartNodePosition) =>
      `${p.x.toFixed(1)}_${p.y.toFixed(1)}`).join('_')
    return `${edge.id}_${routeKey}_${this.graphRevision}_${this.interactionTick}`
  }

  private overlapsAnyNode(x: number, y: number, w: number, h: number, excludeId: string = ''): boolean {
    const left = x
    const top = y
    const right = x + w
    const bottom = y + h
    const pad = 8
    for (const node of this.graph.nodes) {
      if (node.id === excludeId) {
        continue
      }
      const nLeft = node.position.x - pad
      const nTop = node.position.y - pad
      const nRight = node.position.x + node.width + pad
      const nBottom = node.position.y + node.height + pad
      if (left < nRight && right > nLeft && top < nBottom && bottom > nTop) {
        return true
      }
    }
    return false
  }

  private findFreePosition(startX: number, startY: number, w: number, h: number,
    excludeId: string = ''): FlowchartNodePosition {
    const gapY = 24
    const stepX = 48
    let x = startX
    let y = startY
    for (let attempt = 0; attempt < 64; attempt++) {
      if (!this.overlapsAnyNode(x, y, w, h, excludeId)) {
        return createFlowchartPosition(x, y)
      }
      y += gapY
      if (attempt % 8 === 7) {
        x += stepX
        y = startY
      }
    }
    return createFlowchartPosition(startX, startY + gapY * 64)
  }

  private newNodePosition(width: number, height: number, index: number): FlowchartNodePosition {
    const gapY = 40
    const anchorId = this.lastEditedNodeId.length > 0 ? this.lastEditedNodeId : this.selectedNodeId
    const anchor = anchorId.length > 0 ? this.nodeById(anchorId) : undefined
    if (anchor !== undefined) {
      const startX = anchor.position.x
      const startY = anchor.position.y + anchor.height + gapY
      return this.findFreePosition(startX, startY, width, height, anchor.id)
    }
    const nodeW = 120
    const nodeH = 72
    const gapX = 40
    if (this.isPhoneLayout()) {
      return this.findFreePosition(48, 48 + index * (nodeH + gapY), width, height)
    }
    const col = index % 4
    const row = Math.floor(index / 4)
    return this.findFreePosition(
      48 + col * (nodeW + gapX),
      48 + row * (nodeH + gapY),
      width,
      height
    )
  }

  private logNodeBounds(canvasPt: FlowchartNodePosition): void {
    const parts: string[] = []
    for (const node of this.graph.nodes) {
      parts.push(`${node.id.slice(0, 8)}@(${node.position.x.toFixed(1)},${node.position.y.toFixed(1)})`)
    }
    Logger.info(FLOWCHART_LOG_TAG,
      `hitTest canvas=(${canvasPt.x.toFixed(1)},${canvasPt.y.toFixed(1)}) nodes=[${parts.join(', ')}]`)
  }

  private markDirty(): void {
    this.dirty = true
    this.maybeSyncSourceFromGraph()
  }

  private nodeById(id: string): FlowchartNodeModel | undefined {
    return this.graph.nodes.find((n: FlowchartNodeModel) => n.id === id)
  }

  private nodeDisplayPosition(node: FlowchartNodeModel): FlowchartNodePosition {
    if (this.draggingNodeId === node.id) {
      return { x: this.dragLiveX, y: this.dragLiveY }
    }
    return node.position
  }

  private nodeVisualPosition(node: FlowchartNodeModel): FlowchartNodePosition {
    return node.position
  }

  private hitTestNodeBounds(node: FlowchartNodeModel, x: number, y: number, padding: number = 0): boolean {
    const pos = this.nodeVisualPosition(node)
    if (this.isLineNode(node)) {
      const ep = this.lineEndpointsCanvas(node)
      const threshold = Math.max(padding, 12 / this.canvasScale)
      return this.distancePointToSegment(x, y, ep.from.x, ep.from.y, ep.to.x, ep.to.y) <= threshold
    }
    const size = this.nodeDisplaySize(node)
    return x >= pos.x - padding && x <= pos.x + size.w + padding &&
      y >= pos.y - padding && y <= pos.y + size.h + padding
  }

  private bestAnchorToward(node: FlowchartNodeModel, targetX: number, targetY: number): FlowchartAnchor {
    const cx = node.position.x + node.width / 2
    const cy = node.position.y + node.height / 2
    const dx = targetX - cx
    const dy = targetY - cy
    if (Math.abs(dx) < 0.001 && Math.abs(dy) < 0.001) {
      return 'right'
    }
    if (node.shape === 'diamond') {
      const normX = Math.abs(dx) / (node.width / 2)
      const normY = Math.abs(dy) / (node.height / 2)
      if (normX > normY) {
        return dx > 0 ? 'right' : 'left'
      }
      return dy > 0 ? 'bottom' : 'top'
    }
    if (Math.abs(dx) > Math.abs(dy)) {
      return dx > 0 ? 'right' : 'left'
    }
    return dy > 0 ? 'bottom' : 'top'
  }

  /** 节点轮廓上朝向 target 的连接点（与选中时显示的连接点一致）。 */
  private connectionPointToward(node: FlowchartNodeModel, targetX: number, targetY: number): FlowchartNodePosition {
    if (this.isLineNode(node)) {
      const ep = this.lineEndpointsLocal(node)
      const from = createFlowchartPosition(
        node.position.x + ep.from.x,
        node.position.y + ep.from.y
      )
      const to = createFlowchartPosition(
        node.position.x + ep.to.x,
        node.position.y + ep.to.y
      )
      const dFrom = (from.x - targetX) * (from.x - targetX) + (from.y - targetY) * (from.y - targetY)
      const dTo = (to.x - targetX) * (to.x - targetX) + (to.y - targetY) * (to.y - targetY)
      return dFrom <= dTo ? from : to
    }
    if (node.shape === 'arrowRight' || node.shape === 'arrowLeft' || node.shape === 'doubleArrow') {
      const p0 = this.endpointLocalPoint(node, 0)
      const p1 = this.endpointLocalPoint(node, 1)
      const e0 = createFlowchartPosition(
        node.position.x + p0.x,
        node.position.y + p0.y
      )
      const e1 = createFlowchartPosition(
        node.position.x + p1.x,
        node.position.y + p1.y
      )
      const d0 = (e0.x - targetX) * (e0.x - targetX) + (e0.y - targetY) * (e0.y - targetY)
      const d1 = (e1.x - targetX) * (e1.x - targetX) + (e1.y - targetY) * (e1.y - targetY)
      return d0 <= d1 ? e0 : e1
    }
    const anchor = this.bestAnchorToward(node, targetX, targetY)
    const local = this.anchorPointLocal(node, anchor)
    return {
      x: node.position.x + local.x,
      y: node.position.y + local.y
    }
  }

  private addNode(shape: FlowchartShapeType, titleOverride?: string): void {
    this.pushUndo()
    const index = this.graph.nodes.length
    const isArrow = shape === 'arrowRight' || shape === 'arrowLeft'
    const width = isArrow ? 160 : 120
    const height = isArrow ? 56 : 72
    const props: Record<string, Object> = {}
    if (isArrow) {
      props[FLOWCHART_LINE_PROP_FROM_X] = 0
      props[FLOWCHART_LINE_PROP_FROM_Y] = height / 2
      props[FLOWCHART_LINE_PROP_TO_X] = width
      props[FLOWCHART_LINE_PROP_TO_Y] = height / 2
    }
    const existingIds: string[] = []
    for (const n of this.graph.nodes) {
      existingIds.push(n.id)
    }
    const node: FlowchartNodeModel = {
      id: FlowchartNodeIds.next(existingIds),
      title: isArrow ? '' : (titleOverride !== undefined && titleOverride.length > 0 ? titleOverride : '双击编辑'),
      description: '',
      color: shape === 'diamond' ? '#FFF8E1' : '#E3F2FD',
      shape,
      position: this.newNodePosition(width, height, index),
      width,
      height,
      rotation: 0,
      properties: props
    }
    const placed = isArrow ? this.normalizeEndpointNodeBounds(node) : node
    this.logEndpointVisualState(placed, 'addNode:after')
    this.graph = {
      version: this.graph.version,
      metadata: this.graph.metadata,
      nodes: [...this.graph.nodes, placed],
      edges: [...this.graph.edges]
    }
    this.selectedNodeId = placed.id
    this.markNodeEdited(placed.id)
    this.markDirty()
    this.graphRevision++
    this.logNodeShapeLayout(placed, 'addNode')
    this.scheduleCanvasRedraw()
    if (isMermaidPreviewOnlyChartKind(this.chartKind)) {
      this.syncSourceFromGraph()
    }
    Logger.info(FLOWCHART_LOG_TAG, `addNode id=${placed.id} shape=${shape} index=${index} rev=${this.graphRevision}`)
  }

  private addLineNode(lineType: FlowchartLineType): void {
    this.pushUndo()
    const index = this.graph.nodes.length
    const width = 160
    const height = 32
    const props: Record<string, Object> = {}
    props[FLOWCHART_LINE_PROP_TYPE] = lineType
    props[FLOWCHART_LINE_PROP_FROM_X] = 0
    props[FLOWCHART_LINE_PROP_FROM_Y] = height / 2
    props[FLOWCHART_LINE_PROP_TO_X] = width
    props[FLOWCHART_LINE_PROP_TO_Y] = height / 2
    const existingIds: string[] = []
    for (const n of this.graph.nodes) {
      existingIds.push(n.id)
    }
    const draft: FlowchartNodeModel = {
      id: FlowchartNodeIds.next(existingIds),
      title: '',
      description: '',
      color: '#E3F2FD',
      shape: FLOWCHART_LINE_NODE_SHAPE,
      position: this.newNodePosition(width, height, index),
      width,
      height,
      rotation: 0,
      properties: props
    }
    this.logEndpointVisualState(draft, 'addLineNode:draft')
    const node = this.normalizeEndpointNodeBounds(draft)
    this.logEndpointVisualState(node, 'addLineNode:afterNormalize')
    this.graph = {
      version: this.graph.version,
      metadata: this.graph.metadata,
      nodes: [...this.graph.nodes, node],
      edges: [...this.graph.edges]
    }
    this.selectedNodeId = node.id
    this.markNodeEdited(node.id)
    this.markDirty()
    this.graphRevision++
    this.logNodeShapeLayout(node, 'addLineNode')
    this.scheduleCanvasRedraw()
    Logger.info(FLOWCHART_LOG_TAG, `addLineNode id=${node.id} lineType=${lineType} rev=${this.graphRevision}`)
  }

  private updateNode(node: FlowchartNodeModel, redrawEdges: boolean = true): void {
    const nextNodes: FlowchartNodeModel[] = []
    for (const n of this.graph.nodes) {
      if (n.id !== node.id) {
        nextNodes.push(n)
        continue
      }
      nextNodes.push({
        id: node.id,
        title: node.title,
        description: node.description,
        color: node.color,
        shape: node.shape,
        position: createFlowchartPosition(node.position.x, node.position.y),
        width: node.width,
        height: node.height,
        rotation: node.rotation,
        properties: node.properties
      })
    }
    this.graph = {
      version: this.graph.version,
      metadata: this.graph.metadata,
      nodes: nextNodes,
      edges: [...this.graph.edges]
    }
    this.graphRevision++
    this.logNodeShapeLayout(node, 'updateNode')
    this.scheduleCanvasRedraw()
    this.logTouch(`updateNode id=${node.id} pos=(${node.position.x.toFixed(1)},${node.position.y.toFixed(1)}) rev=${this.graphRevision}`)
    this.markDirty()
  }

  private updateEdge(edge: FlowchartEdgeModel): void {
    const nextEdges: FlowchartEdgeModel[] = []
    for (const e of this.graph.edges) {
      if (e.id !== edge.id) {
        nextEdges.push(e)
        continue
      }
      nextEdges.push({
        id: edge.id,
        source: edge.source,
        target: edge.target,
        label: edge.label,
        directed: edge.directed,
        lineType: edge.lineType,
        sourceAnchor: edge.sourceAnchor,
        targetAnchor: edge.targetAnchor,
        properties: edge.properties
      })
    }
    this.graph = {
      version: this.graph.version,
      metadata: this.graph.metadata,
      nodes: [...this.graph.nodes],
      edges: nextEdges
    }
    this.graphRevision++
    this.markDirty()
  }

  /** 节点上指定连接锚点的画布坐标（与选中时显示的连接点一致）。 */
  private connectionPointForAnchor(node: FlowchartNodeModel, anchor: FlowchartAnchor): FlowchartNodePosition {
    if (this.isLineNode(node)) {
      const ep = this.lineEndpointsLocal(node)
      if (anchor === 'left') {
        return createFlowchartPosition(
          node.position.x + ep.from.x,
          node.position.y + ep.from.y
        )
      }
      if (anchor === 'right') {
        return createFlowchartPosition(
          node.position.x + ep.to.x,
          node.position.y + ep.to.y
        )
      }
    }
    if (node.shape === 'arrowRight' || node.shape === 'arrowLeft' || node.shape === 'doubleArrow') {
      if (anchor === 'left') {
        const p = this.endpointLocalPoint(node, 0)
        return createFlowchartPosition(node.position.x + p.x, node.position.y + p.y)
      }
      if (anchor === 'right') {
        const p = this.endpointLocalPoint(node, 1)
        return createFlowchartPosition(node.position.x + p.x, node.position.y + p.y)
      }
    }
    const local = this.anchorPointLocal(node, anchor)
    return createFlowchartPosition(node.position.x + local.x, node.position.y + local.y)
  }

  private createEdge(fromId: string, toId: string,
    sourceAnchor?: FlowchartAnchor, targetAnchor?: FlowchartAnchor): void {
    if (fromId.length === 0 || toId.length === 0 || fromId === toId) {
      return
    }
    const from = this.nodeById(fromId)
    const to = this.nodeById(toId)
    if (from === undefined || to === undefined) {
      return
    }
    if (this.isMindMapMode() &&
      FlowchartMindMap.isTreeNode(this.graph, from) &&
      FlowchartMindMap.isTreeNode(this.graph, to)) {
      if (!FlowchartMindMap.canInitiateConnection(this.graph, from)) {
        return
      }
      if (FlowchartMindMap.isRoot(this.graph, to)) {
        return
      }
      this.pushUndo()
      const preferVertical = this.isPhoneLayout()
      // 思维导图连线只走左右锚点（上下居中）
      const side = FlowchartMindMap.inferChildSide(from, to, sourceAnchor, targetAnchor)
      const resolvedSourceAnchor: FlowchartAnchor = side === 'left' ? 'left' : 'right'
      const resolvedTargetAnchor: FlowchartAnchor = side === 'left' ? 'right' : 'left'
      let graph = FlowchartMindMap.addChildEdge(this.graph, fromId, toId, util.generateRandomUUID(),
        resolvedSourceAnchor, resolvedTargetAnchor)
      const nodes = graph.nodes.map((node: FlowchartNodeModel): FlowchartNodeModel => {
        if (node.id === toId) {
          return FlowchartMindMap.markBranch(node)
        }
        return node
      })
      graph = {
        version: graph.version,
        metadata: graph.metadata,
        nodes,
        edges: graph.edges
      }
      const treeRoot = FlowchartMindMap.treeRootId(graph, fromId)
      const rootId = treeRoot.length > 0
        ? treeRoot
        : (this.mindMapRootId().length > 0 ? this.mindMapRootId() : fromId)
      graph = FlowchartMindMap.assignRoles(graph, rootId)
      graph = FlowchartLayoutEngine.applyMindMapLinearLayout(graph, preferVertical, rootId, true)
      this.graph = graph
      this.graphRevision++
      this.markDirty()
      this.scheduleCanvasRedraw()
      void this.persist(false)
      return
    }
    this.pushUndo()
    const tcx = to.position.x + to.width / 2
    const tcy = to.position.y + to.height / 2
    const scx = from.position.x + from.width / 2
    const scy = from.position.y + from.height / 2
    const edge: FlowchartEdgeModel = {
      id: util.generateRandomUUID(),
      source: fromId,
      target: toId,
      label: '',
      directed: true,
      lineType: 'arrow',
      sourceAnchor: sourceAnchor ?? this.bestAnchorToward(from, tcx, tcy),
      targetAnchor: targetAnchor ?? this.bestAnchorToward(to, scx, scy),
      properties: {}
    }
    this.graph = {
      version: this.graph.version,
      metadata: this.graph.metadata,
      nodes: [...this.graph.nodes],
      edges: [...this.graph.edges, edge]
    }
    this.markDirty()
    this.graphRevision++
    const endpoints = this.edgeLineEndpoints(edge)
    Logger.info(FLOWCHART_LOG_TAG,
      `createEdge ${fromId.slice(0, 8)} -> ${toId.slice(0, 8)} total=${this.graph.edges.length} ` +
      `from=(${endpoints.from.x.toFixed(1)},${endpoints.from.y.toFixed(1)}) ` +
      `to=(${endpoints.to.x.toFixed(1)},${endpoints.to.y.toFixed(1)}) ` +
      `srcAnchor=${edge.sourceAnchor} tgtAnchor=${edge.targetAnchor} rev=${this.graphRevision}`)
    void this.persist(false)
  }

  private deleteSelectedNode(): void {
    if (this.selectedNodeId.length === 0) {
      return
    }
    this.pushUndo()
    const id = this.selectedNodeId
    const node = this.graph.nodes.find((n: FlowchartNodeModel) => n.id === id)
    if (node !== undefined &&
      this.isMindMapMode() &&
      FlowchartMindMap.isTreeNode(this.graph, node)) {
      const treeRootBefore = FlowchartMindMap.treeRootId(this.graph, id)
      const deletedEntireTree = treeRootBefore === id
      let graph = FlowchartMindMap.removeSubtree(this.graph, id)
      if (!deletedEntireTree &&
        treeRootBefore.length > 0 &&
        FlowchartMindMap.isMindMapMode(graph) &&
        graph.nodes.some((n: FlowchartNodeModel) => n.id === treeRootBefore)) {
        graph = FlowchartLayoutEngine.applyMindMapLinearLayout(
          graph,
          this.isPhoneLayout(),
          treeRootBefore,
          true
        )
      }
      this.graph = graph
      this.selectedNodeId = ''
      this.markDirty()
      this.graphRevision++
      this.scheduleCanvasRedraw()
      return
    }
    this.graph = {
      version: this.graph.version,
      metadata: this.graph.metadata,
      nodes: this.graph.nodes.filter((n: FlowchartNodeModel) => n.id !== id),
      edges: this.graph.edges.filter((e: FlowchartEdgeModel) => e.source !== id && e.target !== id)
    }
    this.selectedNodeId = ''
    this.selectedEdgeId = ''
    this.markDirty()
    this.graphRevision++
  }

  private edgeLineEndpoints(edge: FlowchartEdgeModel): FlowchartEdgeLineEndpoints {
    const source = this.nodeForRender(edge.source)
    const target = this.nodeForRender(edge.target)
    if (source === undefined || target === undefined) {
      return {
        from: createFlowchartPosition(0, 0),
        to: createFlowchartPosition(0, 0)
      }
    }
    const endpoints: FlowchartEdgeLineEndpoints = {
      from: this.connectionPointForAnchor(source, edge.sourceAnchor),
      to: this.connectionPointForAnchor(target, edge.targetAnchor)
    }
    if (source.shape === 'diamond' || target.shape === 'diamond') {
      Logger.info(FLOWCHART_LOG_TAG,
        `[EdgeLine] ${source.shape}(${source.id.slice(0, 8)}) -> ${target.shape}(${target.id.slice(0, 8)}) ` +
        `from=(${endpoints.from.x.toFixed(1)},${endpoints.from.y.toFixed(1)}) ` +
        `to=(${endpoints.to.x.toFixed(1)},${endpoints.to.y.toFixed(1)}) ` +
        `srcAnchor=${edge.sourceAnchor} tgtAnchor=${edge.targetAnchor}`)
    }
    return endpoints
  }

  private orthogonalRoutingEnabled(): boolean {
    if (this.chartKind === 'flowchart') {
      return true
    }
    if (this.chartKind === 'state' || this.chartKind === 'mindmap' || this.isMindMapMode()) {
      return false
    }
    return this.graph.metadata[FLOWCHART_ORTHOGONAL_ROUTING_KEY] === true
  }

  private nodeDegreeMap(): Record<string, number> {
    return FlowchartLayoutEngine.nodeDegrees(this.graph.edges)
  }

  private edgeRoutePoints(edge: FlowchartEdgeModel): FlowchartNodePosition[] {
    const source = this.nodeForRender(edge.source)
    const target = this.nodeForRender(edge.target)
    if (source === undefined || target === undefined) {
      return []
    }
    // 思维导图：一律正交折线，端点固定在节点左右侧垂直中心。
    if (FlowchartMindMap.isMindMapEdge(this.graph, edge)) {
      const anchors = FlowchartEdgeRouting.mindMapSideAnchors(
        source.position.x, source.position.x + source.width,
        target.position.x, target.position.x + target.width,
        edge.sourceAnchor, edge.targetAnchor
      )
      const from = this.connectionPointForAnchor(source, anchors.source)
      const to = this.connectionPointForAnchor(target, anchors.target)
      return FlowchartEdgeRouting.orthogonalPath(
        from.x, from.y, to.x, to.y, anchors.source, anchors.target
      )
    }
    const endpoints = this.edgeLineEndpoints(edge)
    if (!this.orthogonalRoutingEnabled()) {
      return [endpoints.from, endpoints.to]
    }
    return FlowchartEdgeRouting.orthogonalPath(
      endpoints.from.x, endpoints.from.y,
      endpoints.to.x, endpoints.to.y,
      edge.sourceAnchor, edge.targetAnchor
    )
  }

  private distanceToSegment(px: number, py: number,
    ax: number, ay: number, bx: number, by: number): number {
    const abx = bx - ax
    const aby = by - ay
    const apx = px - ax
    const apy = py - ay
    const abLenSq = abx * abx + aby * aby
    if (abLenSq < 0.001) {
      const dx = px - ax
      const dy = py - ay
      return Math.sqrt(dx * dx + dy * dy)
    }
    let t = (apx * abx + apy * aby) / abLenSq
    if (t < 0) {
      t = 0
    } else if (t > 1) {
      t = 1
    }
    const cx = ax + abx * t
    const cy = ay + aby * t
    const dx = px - cx
    const dy = py - cy
    return Math.sqrt(dx * dx + dy * dy)
  }

  private edgeLabelPosition(fromX: number, fromY: number,
    toX: number, toY: number): FlowchartNodePosition {
    const midX = (fromX + toX) / 2
    const midY = (fromY + toY) / 2
    const dx = toX - fromX
    const dy = toY - fromY
    const len = Math.sqrt(dx * dx + dy * dy)
    if (len < 0.001) {
      return createFlowchartPosition(midX, midY)
    }
    const offset = 12
    return createFlowchartPosition(
      midX - (dy / len) * offset,
      midY + (dx / len) * offset
    )
  }

  private hitTestEdge(x: number, y: number): FlowchartEdgeModel | undefined {
    const threshold = 14 / this.canvasScale
    let best: FlowchartEdgeModel | undefined = undefined
    let bestDist = threshold
    for (let i = 0; i < this.graph.edges.length; i++) {
      const edge = this.graph.edges[i]
      const source = this.nodeForRender(edge.source)
      const target = this.nodeForRender(edge.target)
      if (source === undefined || target === undefined) {
        continue
      }
      const route = this.edgeRoutePoints(edge)
      const dist = FlowchartEdgeRouting.distanceToPolyline(x, y, route)
      if (dist <= bestDist) {
        bestDist = dist
        best = edge
      }
    }
    return best
  }

  private edgeById(id: string): FlowchartEdgeModel | undefined {
    for (let i = 0; i < this.graph.edges.length; i++) {
      if (this.graph.edges[i].id === id) {
        return this.graph.edges[i]
      }
    }
    return undefined
  }

  private shapePathPx(vp: number): number {
    return this.getUIContext().vp2px(vp)
  }

  private arrowHeadPathCommandsPx(tipX: number, tipY: number, fromX: number, fromY: number): string {
    const size = this.shapePathPx(9)
    const angle = Math.atan2(tipY - fromY, tipX - fromX)
    const ax1 = tipX - size * Math.cos(angle - Math.PI / 6)
    const ay1 = tipY - size * Math.sin(angle - Math.PI / 6)
    const ax2 = tipX - size * Math.cos(angle + Math.PI / 6)
    const ay2 = tipY - size * Math.sin(angle + Math.PI / 6)
    return `M${tipX.toFixed(1)} ${tipY.toFixed(1)} L${ax1.toFixed(1)} ${ay1.toFixed(1)} L${ax2.toFixed(1)} ${ay2.toFixed(1)} Z`
  }

  private routeToPxPoints(points: FlowchartNodePosition[]): FlowchartNodePosition[] {
    const pxPoints: FlowchartNodePosition[] = []
    for (let i = 0; i < points.length; i++) {
      pxPoints.push({
        x: this.shapePathPx(points[i].x),
        y: this.shapePathPx(points[i].y)
      })
    }
    return pxPoints
  }

  private edgePolylineCommandsFromRoute(points: FlowchartNodePosition[]): string {
    if (points.length < 2) {
      return ''
    }
    return FlowchartEdgeRouting.pathCommandsFromPoints(this.routeToPxPoints(points))
  }

  private edgeArrowHeadCommandAt(route: FlowchartNodePosition[], end: 'start' | 'end'): string {
    const pxPoints = this.routeToPxPoints(route)
    if (pxPoints.length < 2) {
      return ''
    }
    if (end === 'end') {
      const last = pxPoints[pxPoints.length - 1]
      const prev = pxPoints[pxPoints.length - 2]
      return this.arrowHeadPathCommandsPx(last.x, last.y, prev.x, prev.y)
    }
    const first = pxPoints[0]
    const second = pxPoints[1]
    return this.arrowHeadPathCommandsPx(first.x, first.y, second.x, second.y)
  }

  private edgeStrokeColor(edge: FlowchartEdgeModel): string {
    if (this.selectedEdgeId === edge.id) {
      return '#2196F3'
    }
    const custom = edge.properties[FLOWCHART_EDGE_COLOR_KEY]
    if (typeof custom === 'string' && custom.length > 0) {
      return custom
    }
    return FlowchartMindMap.isMindMapEdge(this.graph, edge) ?
      FLOWCHART_MIND_MAP_LINE_COLOR : '#212121'
  }

  private edgeStrokeWidth(edge: FlowchartEdgeModel): number {
    if (this.selectedEdgeId === edge.id) {
      return 3
    }
    return FlowchartMindMap.isMindMapEdge(this.graph, edge) ? 2.4 : 1.8
  }

  private edgePolylineCommandsForEdge(edge: FlowchartEdgeModel): string {
    const route = this.edgeRoutePoints(edge)
    return this.edgePolylineCommandsFromRoute(route)
  }

  private edgeArrowHeadCommandsForEdge(edge: FlowchartEdgeModel, end: 'start' | 'end'): string {
    const route = this.edgeRoutePoints(edge)
    return this.edgeArrowHeadCommandAt(route, end)
  }

  private edgePathCommandsFromRoute(points: FlowchartNodePosition[], lineType: string): string {
    if (points.length < 2) {
      return ''
    }
    const pxPoints: FlowchartNodePosition[] = []
    for (let i = 0; i < points.length; i++) {
      pxPoints.push({
        x: this.shapePathPx(points[i].x),
        y: this.shapePathPx(points[i].y)
      })
    }
    let commands = FlowchartEdgeRouting.pathCommandsFromPoints(pxPoints)
    const last = pxPoints[pxPoints.length - 1]
    const prev = pxPoints[pxPoints.length - 2]
    if (lineType === 'arrow' || lineType === 'doubleArrow') {
      commands += ` ${this.arrowHeadPathCommandsPx(last.x, last.y, prev.x, prev.y)}`
    }
    if (lineType === 'doubleArrow') {
      const first = pxPoints[0]
      const second = pxPoints[1]
      commands += ` ${this.arrowHeadPathCommandsPx(first.x, first.y, second.x, second.y)}`
    }
    return commands
  }

  private edgePathCommands(fromX: number, fromY: number, toX: number, toY: number,
    lineType: string): string {
    let commands = this.edgeStraightCommands(fromX, fromY, toX, toY)
    const fx = this.shapePathPx(fromX)
    const fy = this.shapePathPx(fromY)
    const tx = this.shapePathPx(toX)
    const ty = this.shapePathPx(toY)
    if (lineType === 'arrow' || lineType === 'doubleArrow') {
      commands += ` ${this.arrowHeadPathCommandsPx(tx, ty, fx, fy)}`
    }
    if (lineType === 'doubleArrow') {
      commands += ` ${this.arrowHeadPathCommandsPx(fx, fy, tx, ty)}`
    }
    return commands
  }

  private edgeStraightCommands(fromX: number, fromY: number, toX: number, toY: number): string {
    const fx = this.shapePathPx(fromX)
    const fy = this.shapePathPx(fromY)
    const tx = this.shapePathPx(toX)
    const ty = this.shapePathPx(toY)
    return `M${fx.toFixed(1)} ${fy.toFixed(1)} L${tx.toFixed(1)} ${ty.toFixed(1)}`
  }

  private edgePathCommandsForEdge(edge: FlowchartEdgeModel): string {
    const route = this.edgeRoutePoints(edge)
    if (route.length < 2) {
      return ''
    }
    return this.edgePathCommandsFromRoute(route, edge.lineType)
  }

  private localToCanvas(localX: number, localY: number): FlowchartNodePosition {
    return {
      x: (localX - this.viewportX) / this.canvasScale,
      y: (localY - this.viewportY) / this.canvasScale
    }
  }

  private nodeForRender(id: string): FlowchartNodeModel | undefined {
    const node = this.nodeById(id)
    if (node === undefined) {
      return undefined
    }
    return {
      id: node.id,
      title: node.title,
      description: node.description,
      color: node.color,
      shape: node.shape,
      position: this.nodeDisplayPosition(node),
      width: node.width,
      height: node.height,
      rotation: node.rotation,
      properties: node.properties
    }
  }

  private hitTestNode(x: number, y: number): FlowchartNodeModel | undefined {
    if (this.draggingNodeId.length > 0) {
      const dragging = this.nodeById(this.draggingNodeId)
      if (dragging !== undefined &&
        x >= this.dragLiveX && x <= this.dragLiveX + dragging.width &&
        y >= this.dragLiveY && y <= this.dragLiveY + dragging.height) {
        return dragging
      }
    }
    if (this.selectedNodeId.length > 0) {
      const selected = this.nodeById(this.selectedNodeId)
      if (selected !== undefined && this.hitTestNodeBounds(selected, x, y, 16)) {
        return selected
      }
    }
    for (let i = this.graph.nodes.length - 1; i >= 0; i--) {
      const node = this.graph.nodes[i]
      if (this.hitTestNodeBounds(node, x, y, 0)) {
        return node
      }
    }
    return undefined
  }

  private playDragVibration(): void {
    try {
      vibrator.startVibration({
        type: 'time',
        duration: FlowchartEditor.LONG_PRESS_MS
      }, {
        id: 0,
        usage: 'touch'
      }, (error: BusinessError) => {
        if (error) {
          console.error(`playDragVibration failed: ${error.message}`)
        }
      })
    } catch (error) {
      console.error(`playDragVibration error: ${JSON.stringify(error)}`)
    }
  }

  private activateNodeDrag(node: FlowchartNodeModel): void {
    if (this.isMindMapMode() && FlowchartMindMap.isTreeNode(this.graph, node)) {
      return
    }
    if (this.dragActivated) {
      return
    }
    this.pushUndo()
    if (this.longPressTimerId >= 0) {
      clearTimeout(this.longPressTimerId)
      this.longPressTimerId = -1
    }
    this.dragActivated = true
    this.touchMode = FlowchartEditor.TOUCH_DRAG
    this.draggingNodeId = node.id
    this.dragLiveX = node.position.x
    this.dragLiveY = node.position.y
    this.dragStartX = node.position.x
    this.dragStartY = node.position.y
    this.logTouch(`activateNodeDrag id=${node.id}`)
    this.playDragVibration()
    this.bumpInteraction()
  }

  private resetTouchGestureState(): void {
    if (this.longPressTimerId >= 0) {
      clearTimeout(this.longPressTimerId)
      this.longPressTimerId = -1
    }
    this.pendingDragNodeId = ''
    this.activeConnectFromId = ''
    this.activeConnectFromAnchor = 'right'
    this.dragActivated = false
    this.draggingEndpointIndex = -1
  }

  private clearDragVisual(): void {
    this.resetTouchGestureState()
    this.draggingNodeId = ''
    this.connectDraftActive = false
  }

  private beginEndpointDrag(node: FlowchartNodeModel, index: number): void {
    this.pushUndo()
    let active = node
    if (!this.hasStoredEndpoints(node) && (this.isLineNode(node) || this.isArrowNode(node))) {
      const ready = this.ensureEndpointProperties(node)
      this.updateNode(ready, false)
      const updated = this.nodeById(node.id)
      if (updated !== undefined) {
        active = updated
      } else {
        active = ready
      }
    }
    this.touchMode = FlowchartEditor.TOUCH_ENDPOINT
    this.draggingEndpointIndex = index
    this.selectedNodeId = active.id
    const pos = active.position
    this.endpointDragStartPosX = pos.x
    this.endpointDragStartPosY = pos.y
    this.endpointDragStartWidth = active.width
    if (this.isLineNode(active) || this.isArrowNode(active)) {
      const ep = this.lineEndpointsLocal(active)
      this.endpointDragStartFromX = ep.from.x
      this.endpointDragStartFromY = ep.from.y
      this.endpointDragStartToX = ep.to.x
      this.endpointDragStartToY = ep.to.y
    }
    this.logEndpointVisualState(active, 'beginEndpointDrag')
    this.bumpInteraction()
  }

  private applyEndpointDragLive(node: FlowchartNodeModel, canvasX: number, canvasY: number): void {
    if (this.isLineNode(node) || this.isArrowNode(node)) {
      const ep = this.lineEndpointsLocal(node)
      const pos = node.position
      let fromCanvas = createFlowchartPosition(pos.x + ep.from.x, pos.y + ep.from.y)
      let toCanvas = createFlowchartPosition(pos.x + ep.to.x, pos.y + ep.to.y)
      if (this.draggingEndpointIndex === 0) {
        fromCanvas = createFlowchartPosition(canvasX, canvasY)
      } else {
        toCanvas = createFlowchartPosition(canvasX, canvasY)
      }
      const normalized = this.endpointNodeFromCanvas(node, fromCanvas, toCanvas)
      this.draggingNodeId = node.id
      this.dragLiveX = normalized.position.x
      this.dragLiveY = normalized.position.y
      this.graph = {
        version: this.graph.version,
        metadata: this.graph.metadata,
        nodes: this.graph.nodes.map((n: FlowchartNodeModel) => n.id === node.id ? normalized : n),
        edges: [...this.graph.edges]
      }
      if (this.interactionTick % 6 === 0) {
        this.logEndpointVisualState(normalized, 'endpointDragLive')
      }
      this.bumpInteraction()
    }
  }

  private commitEndpointDrag(): void {
    if (this.draggingEndpointIndex < 0) {
      return
    }
    const node = this.nodeById(this.selectedNodeId)
    if (node === undefined) {
      return
    }
    if (this.draggingNodeId.length > 0) {
      const live = this.nodeById(this.draggingNodeId)
      if (live !== undefined) {
        this.logEndpointVisualState(live, 'commitEndpointDrag:before')
        const normalized = this.normalizeEndpointNodeBounds(live)
        this.logEndpointVisualState(normalized, 'commitEndpointDrag:after')
        this.updateNode(normalized)
      }
    }
    this.markNodeEdited(node.id)
    this.draggingEndpointIndex = -1
  }

  private dragMovedEnough(node: FlowchartNodeModel | undefined): boolean {
    if (node === undefined) {
      return false
    }
    const dx = this.dragLiveX - this.dragStartX
    const dy = this.dragLiveY - this.dragStartY
    return this.touchMoved || (dx * dx + dy * dy > 9)
  }

  private commitDragIfNeeded(): void {
    if (this.draggingNodeId.length === 0) {
      return
    }
    const node = this.nodeById(this.draggingNodeId)
    if (node === undefined) {
      this.logTouch(`commitDrag skip: node missing id=${this.draggingNodeId}`)
      return
    }
    if (!this.dragMovedEnough(node)) {
      this.selectedNodeId = node.id
      this.logTouch(`commitDrag skip: not moved id=${node.id}`)
      return
    }
    this.updateNode({
      id: node.id,
      title: node.title,
      description: node.description,
      color: node.color,
      shape: node.shape,
      position: createFlowchartPosition(this.dragLiveX, this.dragLiveY),
      width: node.width,
      height: node.height,
      rotation: node.rotation,
      properties: node.properties
    })
    this.selectedNodeId = node.id
    this.markNodeEdited(node.id)
    this.logTouch(`commitDrag ok id=${node.id}`)
  }

  private schedulePendingDragActivation(): void {
    if (this.longPressTimerId >= 0) {
      clearTimeout(this.longPressTimerId)
    }
    this.longPressTimerId = setTimeout((): void => {
      this.longPressTimerId = -1
      if (this.touchMode !== FlowchartEditor.TOUCH_PENDING_DRAG) {
        return
      }
      const node = this.nodeById(this.pendingDragNodeId)
      if (node !== undefined) {
        this.activateNodeDrag(node)
      }
    }, FlowchartEditor.LONG_PRESS_MS)
  }

  private hitTestAnchor(x: number, y: number): FlowchartAnchorHit | undefined {
    if (this.selectedNodeId.length === 0) {
      return undefined
    }
    const node = this.nodeById(this.selectedNodeId)
    if (node === undefined) {
      return undefined
    }
    if (!FlowchartMindMap.shouldShowConnectionAnchors(this.graph, node)) {
      return undefined
    }
    const displayNode: FlowchartNodeModel = {
      id: node.id,
      title: node.title,
      description: node.description,
      color: node.color,
      shape: node.shape,
      position: this.nodeDisplayPosition(node),
      width: node.width,
      height: node.height,
      rotation: node.rotation,
      properties: node.properties
    }
    const anchors: FlowchartAnchor[] = ['top', 'right', 'bottom', 'left']
    const threshold = 24 / this.canvasScale
    for (const anchor of anchors) {
      const pt = this.anchorPoint(displayNode, anchor)
      const dx = x - pt.x
      const dy = y - pt.y
      if (dx * dx + dy * dy <= threshold * threshold) {
        const hit: FlowchartAnchorHit = { nodeId: node.id, anchor }
        return hit
      }
    }
    return undefined
  }

  private finishConnect(endX: number, endY: number): void {
    const fromId = this.activeConnectFromId
    const sourceAnchor = this.activeConnectFromAnchor
    this.activeConnectFromId = ''
    this.activeConnectFromAnchor = 'right'
    this.connectDraftActive = false
    if (fromId.length === 0) {
      return
    }
    const pad = 28
    let target: FlowchartNodeModel | undefined = undefined
    for (let i = this.graph.nodes.length - 1; i >= 0; i--) {
      const other = this.graph.nodes[i]
      if (other.id === fromId) {
        continue
      }
      const display = this.nodeForRender(other.id)
      if (display === undefined) {
        continue
      }
      if (endX >= display.position.x - pad &&
        endX <= display.position.x + display.width + pad &&
        endY >= display.position.y - pad &&
        endY <= display.position.y + display.height + pad) {
        target = other
        break
      }
    }
    if (target === undefined) {
      let bestDist = 48
      for (const other of this.graph.nodes) {
        if (other.id === fromId) {
          continue
        }
        const display = this.nodeForRender(other.id)
        if (display === undefined) {
          continue
        }
        const cx = display.position.x + display.width / 2
        const cy = display.position.y + display.height / 2
        const dx = cx - endX
        const dy = cy - endY
        const d = Math.sqrt(dx * dx + dy * dy)
        if (d < bestDist) {
          bestDist = d
          target = other
        }
      }
    }
    if (target === undefined) {
      Logger.info(FLOWCHART_LOG_TAG,
        `finishConnect miss from=${fromId.slice(0, 8)} end=(${endX.toFixed(1)},${endY.toFixed(1)})`)
      return
    }
    const targetAnchor = this.bestAnchorToward(target, this.connectDraftFromX, this.connectDraftFromY)
    this.createEdge(fromId, target.id, sourceAnchor, targetAnchor)
    this.showUserMessage(EditorUiStrings.loc('已创建连线', 'Connection created', '接続を作成しました'))
    Logger.info(FLOWCHART_LOG_TAG, `finishConnect ok ${fromId.slice(0, 8)} -> ${target.id.slice(0, 8)}`)
  }

  private handleCanvasTouch(event: TouchEvent): void {
    if (event.touches.length === 0) {
      return
    }
    if (event.touches.length >= 2) {
      if (event.type === TouchType.Down) {
        this.resetTouchGestureState()
        this.touchMode = FlowchartEditor.TOUCH_PINCH
      }
      return
    }
    if (this.touchMode === FlowchartEditor.TOUCH_PINCH) {
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.touchMode = 0
      }
      return
    }
    const localX = event.touches[0].x
    const localY = event.touches[0].y
    const canvasPt = this.localToCanvas(localX, localY)

    if (event.type === TouchType.Down) {
      this.resetTouchGestureState()
      this.lastTouchLocalX = localX
      this.lastTouchLocalY = localY
      this.touchMoved = false
      this.logTouch(`down canvas=(${canvasPt.x.toFixed(1)},${canvasPt.y.toFixed(1)})`)
      if (this.isMindMapMode()) {
        const addHit = this.hitTestMindMapAddButton(canvasPt.x, canvasPt.y)
        if (addHit !== undefined) {
          this.addMindMapChildOnSide(addHit.parentId, addHit.side)
          this.logTouch(`hit mind map add side=${addHit.side}`)
          return
        }
      }
      const endpointHit = this.hitTestEndpoint(canvasPt.x, canvasPt.y)
      if (endpointHit !== undefined) {
        const endpointNode = this.nodeById(endpointHit.nodeId)
        if (endpointNode !== undefined) {
          const index = endpointHit.anchor === 'left' ? 0 : 1
          this.beginEndpointDrag(endpointNode, index)
          this.logTouch(`endpoint drag start id=${endpointNode.id} index=${index}`)
          return
        }
      }
      const anchorHit = this.hitTestAnchor(canvasPt.x, canvasPt.y)
      if (anchorHit !== undefined) {
        this.touchMode = FlowchartEditor.TOUCH_CONNECT
        this.activeConnectFromId = anchorHit.nodeId
        this.activeConnectFromAnchor = anchorHit.anchor
        const displayNode = this.nodeForRender(anchorHit.nodeId)
        if (displayNode !== undefined) {
          const pt = this.anchorPoint(displayNode, anchorHit.anchor)
          this.connectDraftFromX = pt.x
          this.connectDraftFromY = pt.y
          this.connectDraftToX = pt.x
          this.connectDraftToY = pt.y
          this.connectDraftActive = true
          this.logTouch(`connect start from=${anchorHit.nodeId.slice(0, 8)} anchor=${anchorHit.anchor}`)
        }
        return
      }
      const node = this.hitTestNode(canvasPt.x, canvasPt.y)
      if (node === undefined) {
        this.logNodeBounds(canvasPt)
      }
      if (node !== undefined) {
        this.touchMode = FlowchartEditor.TOUCH_PENDING_DRAG
        this.pendingDragNodeId = node.id
        this.touchDownAtMs = Date.now()
        this.schedulePendingDragActivation()
        this.logTouch(`down hit node id=${node.id}`)
        return
      }
      this.touchMode = FlowchartEditor.TOUCH_PAN
      this.logTouch('down hit blank -> pan')
      return
    }

    if (event.type === TouchType.Move) {
      const dxLocal = localX - this.lastTouchLocalX
      const dyLocal = localY - this.lastTouchLocalY
      if (Math.abs(dxLocal) > 2 || Math.abs(dyLocal) > 2) {
        this.touchMoved = true
      }
      this.lastTouchLocalX = localX
      this.lastTouchLocalY = localY

      if (this.touchMode === FlowchartEditor.TOUCH_PENDING_DRAG) {
        const pendingNode = this.nodeById(this.pendingDragNodeId)
        if (pendingNode !== undefined &&
          !this.dragActivated &&
          Date.now() - this.touchDownAtMs >= FlowchartEditor.LONG_PRESS_MS) {
          this.activateNodeDrag(pendingNode)
        }
      }

      if (this.touchMode === FlowchartEditor.TOUCH_ENDPOINT) {
        const endpointNode = this.nodeById(this.selectedNodeId)
        if (endpointNode !== undefined) {
          this.applyEndpointDragLive(endpointNode, canvasPt.x, canvasPt.y)
        }
      } else if (this.touchMode === FlowchartEditor.TOUCH_DRAG) {
        this.dragLiveX += dxLocal / this.canvasScale
        this.dragLiveY += dyLocal / this.canvasScale
        this.bumpInteraction()
      } else if (this.touchMode === FlowchartEditor.TOUCH_CONNECT) {
        this.connectDraftToX = canvasPt.x
        this.connectDraftToY = canvasPt.y
        this.bumpInteraction()
      } else if (this.touchMode === FlowchartEditor.TOUCH_PAN) {
        this.viewportX += dxLocal
        this.viewportY += dyLocal
      }
      return
    }

    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.logTouch(`up/cancel type=${event.type}`)
      if (this.touchMode === FlowchartEditor.TOUCH_ENDPOINT) {
        this.commitEndpointDrag()
      } else if (this.touchMode === FlowchartEditor.TOUCH_DRAG ||
        (this.dragActivated && this.draggingNodeId.length > 0)) {
        this.commitDragIfNeeded()
      } else if (this.touchMode === FlowchartEditor.TOUCH_PENDING_DRAG) {
        const node = this.nodeById(this.pendingDragNodeId)
        if (node !== undefined && !this.touchMoved) {
          const now = Date.now()
          if (this.lastTapNodeId === node.id && now - this.lastTapTime < 400) {
            this.openEditDialog(node)
            this.lastTapNodeId = ''
            this.lastTapTime = 0
            this.lastTapEdgeId = ''
            this.lastTapEdgeTime = 0
          } else {
            this.selectedNodeId = node.id
            this.selectedEdgeId = ''
            this.markNodeEdited(node.id)
            this.lastTapNodeId = node.id
            this.lastTapTime = now
            this.lastTapEdgeId = ''
            this.lastTapEdgeTime = 0
          }
        }
      } else if (this.touchMode === FlowchartEditor.TOUCH_CONNECT) {
        this.finishConnect(canvasPt.x, canvasPt.y)
      } else if (this.touchMode === FlowchartEditor.TOUCH_PAN && !this.touchMoved) {
        const edge = this.hitTestEdge(canvasPt.x, canvasPt.y)
        if (edge !== undefined) {
          const now = Date.now()
          if (this.lastTapEdgeId === edge.id && now - this.lastTapEdgeTime < 400) {
            this.openEdgeEditDialog(edge)
            this.lastTapEdgeId = ''
            this.lastTapEdgeTime = 0
          } else {
            this.lastTapEdgeId = edge.id
            this.lastTapEdgeTime = now
            this.lastTapNodeId = ''
            this.lastTapTime = 0
            this.selectedEdgeId = edge.id
            this.selectedNodeId = ''
          }
        } else {
          this.selectedNodeId = ''
          this.selectedEdgeId = ''
          this.lastTapEdgeId = ''
          this.lastTapEdgeTime = 0
        }
      }
      this.clearDragVisual()
      this.touchMode = 0
    }
  }

  private redrawCanvas(): void {
    const ctx = this.canvasContext
    const w = 4000
    const h = 4000
    ctx.fillStyle = this.colorResourceToHex('editor_background')
    ctx.fillRect(0, 0, w, h)
    ctx.strokeStyle = this.colorResourceToHex('divider')
    ctx.lineWidth = 0.5
    for (let x = 0; x <= w; x += 24) {
      ctx.beginPath()
      ctx.moveTo(x, 0)
      ctx.lineTo(x, h)
      ctx.stroke()
    }
    for (let y = 0; y <= h; y += 24) {
      ctx.beginPath()
      ctx.moveTo(0, y)
      ctx.lineTo(w, y)
      ctx.stroke()
    }
  }

  private anchorCircleOffset(node: FlowchartNodeModel, anchor: FlowchartAnchor): FlowchartNodePosition {
    const local = this.anchorPointLocal(node, anchor)
    return { x: local.x - 8, y: local.y - 8 }
  }

  private anchorPoint(node: FlowchartNodeModel, anchor: FlowchartAnchor): FlowchartNodePosition {
    const local = this.anchorPointLocal(node, anchor)
    return {
      x: node.position.x + local.x,
      y: node.position.y + local.y
    }
  }

  private openNoteTitleDialog(): void {
    this.editNoteTitleInput = this.noteTitle
    this.showNoteTitleDialog = true
  }

  private saveNoteTitleDialog(): void {
    const trimmed = this.editNoteTitleInput.trim()
    this.noteTitle = trimmed.length > 0 ? trimmed : FLOWCHART_DEFAULT_TITLE
    this.showNoteTitleDialog = false
    this.markDirty()
    if (isMermaidPreviewOnlyChartKind(this.chartKind) && !this.showSourceView) {
      this.syncSourceFromGraph()
      this.graphRevision++
      this.scheduleCanvasRedraw()
    }
  }

  private mindMapDefaultTitle(): string {
    return EditorUiStrings.loc('输入文本', 'Enter text', 'テキストを入力')
  }

  private openEditDialog(node: FlowchartNodeModel): void {
    this.editingNodeId = node.id
    this.editTitle = FlowchartMindMap.mindMapTitleForEdit(
      node.title,
      this.mindMapDefaultTitle()
    )
    this.editSingleKind = ''
    if (this.chartKind === 'class' || this.chartKind === 'gitgraph') {
      this.editDialogMode = 'nodeName'
      this.editSecondaryLabel = EditorUiStrings.loc('节点名', 'Node name', 'ノード名')
      const visible: FlowchartNodeModel[] = []
      for (const n of this.graph.nodes) {
        if (`${n.shape}` !== 'line') {
          visible.push(n)
        }
      }
      let idx = 0
      for (let i = 0; i < visible.length; i++) {
        if (visible[i].id === node.id) {
          idx = i
          break
        }
      }
      this.editDescription = MermaidTemplates.rawMermaidName(node).length > 0 ?
        MermaidTemplates.rawMermaidName(node) :
        MermaidTemplates.nodeMermaidName(node, idx)
    } else if (this.chartKind === 'journey') {
      this.editDialogMode = 'user'
      this.editSecondaryLabel = EditorUiStrings.loc('用户', 'User', 'ユーザー')
      const desc = node.description.trim()
      this.editDescription = desc.length === 0 ? '用户' : desc
    } else {
      this.editDialogMode = 'default'
      this.editSecondaryLabel = EditorUiStrings.loc('描述', 'Description', '説明')
      this.editDescription = node.description
    }
    this.markNodeEdited(node.id)
    this.showEditDialog = true
  }

  private openJourneySectionDialog(): void {
    const raw = `${this.graph.metadata[FLOWCHART_JOURNEY_SECTION_KEY] ?? ''}`.trim()
    this.editingNodeId = ''
    this.editSingleKind = 'journeySection'
    this.editDialogMode = 'single'
    this.editSecondaryLabel = EditorUiStrings.loc('流程', 'Section', 'フロー')
    this.editTitle = raw.length > 0 ? raw : '流程'
    this.editDescription = ''
    this.showEditDialog = true
  }

  private openGitBranchDialog(): void {
    const raw = `${this.graph.metadata[FLOWCHART_GIT_BRANCH_NAME_KEY] ?? ''}`.trim()
    this.editingNodeId = ''
    this.editSingleKind = 'gitBranch'
    this.editDialogMode = 'single'
    this.editSecondaryLabel = EditorUiStrings.loc('分支名', 'Branch', 'ブランチ名')
    this.editTitle = raw.length > 0 ? raw : 'develop'
    this.editDescription = ''
    this.showEditDialog = true
  }

  private openGitTagDialog(node: FlowchartNodeModel): void {
    this.editingNodeId = node.id
    this.editSingleKind = 'gitTag'
    this.editDialogMode = 'single'
    this.editSecondaryLabel = 'Tag'
    const tagRaw = `${node.properties[FLOWCHART_GIT_TAG_KEY] ?? ''}`.trim()
    this.editTitle = tagRaw.length > 0 ? tagRaw : node.title.trim()
    this.editDescription = ''
    this.showEditDialog = true
  }

  private saveEditDialog(): void {
    if (this.editDialogMode === 'single') {
      this.saveSingleFieldDialog()
      return
    }
    const node = this.nodeById(this.editingNodeId)
    if (node === undefined) {
      this.showEditDialog = false
      return
    }
    this.pushUndo()
    const localizedDefault = this.mindMapDefaultTitle()
    const trimmedTitle = this.editTitle.trim()
    const savedTitle = FlowchartMindMap.normalizeSavedMindMapTitle(
      trimmedTitle,
      localizedDefault
    )
    let graph = this.graph
    const nextNodes: FlowchartNodeModel[] = []
    const visible: FlowchartNodeModel[] = []
    for (const n of graph.nodes) {
      if (`${n.shape}` !== 'line') {
        visible.push(n)
      }
    }
    let nodeIndex = 0
    for (let i = 0; i < visible.length; i++) {
      if (visible[i].id === node.id) {
        nodeIndex = i
        break
      }
    }
    for (const n of graph.nodes) {
      if (n.id !== node.id) {
        nextNodes.push(n)
        continue
      }
      const props: Record<string, Object> = cloneFlowchartRecord(n.properties)
      let description = n.description
      if (this.editDialogMode === 'nodeName') {
        const name = this.editDescription.trim()
        if (name.length === 0) {
          const cleaned: Record<string, Object> = {}
          for (const key of Object.keys(props)) {
            if (key !== FLOWCHART_MERMAID_NAME_KEY) {
              cleaned[key] = props[key]
            }
          }
          nextNodes.push({
            id: n.id,
            title: savedTitle,
            description: n.description,
            color: n.color,
            shape: n.shape,
            position: n.position,
            width: n.width,
            height: n.height,
            rotation: n.rotation,
            properties: cleaned
          })
          continue
        }
        // 存用户原文；导出 Mermaid 时再 sanitize
        props[FLOWCHART_MERMAID_NAME_KEY] = name
      } else if (this.editDialogMode === 'user') {
        const actor = this.editDescription.trim()
        description = actor.length === 0 ? '用户' : actor
      } else {
        description = this.editDescription.trim()
      }
      nextNodes.push({
        id: n.id,
        title: savedTitle,
        description: description,
        color: n.color,
        shape: n.shape,
        position: n.position,
        width: n.width,
        height: n.height,
        rotation: n.rotation,
        properties: props
      })
    }
    graph = {
      version: graph.version,
      metadata: graph.metadata,
      nodes: nextNodes,
      edges: [...graph.edges]
    }
    if (this.isMindMapMode()) {
      const rootId = this.mindMapRootId().length > 0 ?
        this.mindMapRootId() : FlowchartMindMap.rootId(graph)
      if (rootId.length > 0) {
        if (FlowchartMindMap.isBranch(graph, node)) {
          const size = FlowchartMindMap.measureBranchLabel(savedTitle)
          const sizedNodes = graph.nodes.map((n: FlowchartNodeModel): FlowchartNodeModel => {
            if (n.id !== node.id) {
              return n
            }
            return {
              id: n.id,
              title: n.title,
              description: n.description,
              color: n.color,
              shape: n.shape,
              position: n.position,
              width: size.w,
              height: size.h,
              rotation: n.rotation,
              properties: n.properties
            }
          })
          graph = {
            version: graph.version,
            metadata: graph.metadata,
            nodes: sizedNodes,
            edges: [...graph.edges]
          }
        }
        graph = FlowchartLayoutEngine.applyMindMapLinearLayout(
          graph,
          this.isPhoneLayout(),
          rootId
        )
      }
    }
    this.graph = graph
    this.graphRevision++
    this.scheduleCanvasRedraw()
    this.markNodeEdited(node.id)
    this.showEditDialog = false
    this.markDirty()
    this.syncSourceFromGraph()
  }

  private saveSingleFieldDialog(): void {
    const value = this.editTitle.trim()
    this.pushUndo()
    if (this.editSingleKind === 'journeySection') {
      const metadata = cloneFlowchartRecord(this.graph.metadata)
      metadata[FLOWCHART_JOURNEY_SECTION_KEY] = value.length > 0 ? value : '流程'
      this.graph = {
        version: this.graph.version,
        metadata: metadata,
        nodes: this.graph.nodes,
        edges: this.graph.edges
      }
    } else if (this.editSingleKind === 'gitBranch') {
      const metadata = cloneFlowchartRecord(this.graph.metadata)
      metadata[FLOWCHART_GIT_BRANCH_NAME_KEY] = value.length > 0 ? value : 'develop'
      this.graph = {
        version: this.graph.version,
        metadata: metadata,
        nodes: this.graph.nodes,
        edges: this.graph.edges
      }
    } else if (this.editSingleKind === 'gitTag' && this.editingNodeId.length > 0) {
      const nextNodes: FlowchartNodeModel[] = []
      for (const n of this.graph.nodes) {
        if (n.id !== this.editingNodeId) {
          nextNodes.push(n)
          continue
        }
        const props = cloneFlowchartRecord(n.properties)
        if (value.length === 0) {
          const cleaned: Record<string, Object> = {}
          for (const key of Object.keys(props)) {
            if (key !== FLOWCHART_GIT_TAG_KEY) {
              cleaned[key] = props[key]
            }
          }
          nextNodes.push({
            id: n.id,
            title: n.title,
            description: n.description,
            color: n.color,
            shape: n.shape,
            position: n.position,
            width: n.width,
            height: n.height,
            rotation: n.rotation,
            properties: cleaned
          })
        } else {
          props[FLOWCHART_GIT_TAG_KEY] = value
          nextNodes.push({
            id: n.id,
            title: n.title,
            description: n.description,
            color: n.color,
            shape: n.shape,
            position: n.position,
            width: n.width,
            height: n.height,
            rotation: n.rotation,
            properties: props
          })
        }
      }
      this.graph = {
        version: this.graph.version,
        metadata: this.graph.metadata,
        nodes: nextNodes,
        edges: this.graph.edges
      }
    }
    this.showEditDialog = false
    this.markDirty()
    this.graphRevision++
    this.scheduleCanvasRedraw()
    this.syncSourceFromGraph()
  }

  private promoteGraphToMindMap(graph: FlowchartGraphModel): FlowchartGraphModel {
    const preferVertical = this.isPhoneLayout()
    const placeholderText = EditorUiStrings.loc('双击编辑', 'Double-tap to edit', 'ダブルタップで編集')
    const visible: FlowchartNodeModel[] = []
    for (const n of graph.nodes) {
      if (`${n.shape}` !== 'line') {
        visible.push(n)
      }
    }
    if (visible.length === 0) {
      const allocated: string[] = []
      let template = FlowchartMindMap.createDefaultTemplate((): string => {
        const ids: string[] = []
        for (const n of graph.nodes) {
          ids.push(n.id)
        }
        for (const a of allocated) {
          ids.push(a)
        }
        let i = 1
        while (ids.indexOf(`node${i}`) >= 0) {
          i++
        }
        const id = `node${i}`
        allocated.push(id)
        return id
      })
      const tplNodes: FlowchartNodeModel[] = []
      for (const node of template.nodes) {
        tplNodes.push({
          id: node.id,
          title: placeholderText,
          description: node.description,
          color: node.color,
          shape: node.shape,
          position: node.position,
          width: node.width,
          height: node.height,
          rotation: node.rotation,
          properties: node.properties
        })
      }
      template = {
        version: template.version,
        metadata: template.metadata,
        nodes: tplNodes,
        edges: template.edges
      }
      const rootId = FlowchartMindMap.rootId(template)
      template = FlowchartLayoutEngine.applyMindMapLinearLayout(template, preferVertical, rootId)
      const metadata = cloneFlowchartRecord(graph.metadata)
      for (const key of Object.keys(template.metadata)) {
        metadata[key] = template.metadata[key]
      }
      return {
        version: graph.version,
        metadata: metadata,
        nodes: template.nodes,
        edges: template.edges
      }
    }
    const root = visible[0]
    const nextNodes: FlowchartNodeModel[] = []
    for (const n of graph.nodes) {
      if (`${n.shape}` === 'line') {
        nextNodes.push(n)
        continue
      }
      const props = cloneFlowchartRecord(n.properties)
      if (n.id === root.id) {
        props[FLOWCHART_MIND_MAP_ROLE_KEY] = FLOWCHART_MIND_MAP_ROLE_ROOT
        nextNodes.push({
          id: n.id,
          title: n.title,
          description: n.description,
          color: n.color.trim().length === 0 ? FLOWCHART_MIND_MAP_ROOT_COLOR : n.color,
          shape: n.shape,
          position: n.position,
          width: n.width,
          height: n.height,
          rotation: n.rotation,
          properties: props
        })
      } else {
        props[FLOWCHART_MIND_MAP_ROLE_KEY] = FLOWCHART_MIND_MAP_ROLE_BRANCH
        nextNodes.push({
          id: n.id,
          title: n.title,
          description: n.description,
          color: n.color,
          shape: n.shape,
          position: n.position,
          width: n.width,
          height: n.height,
          rotation: n.rotation,
          properties: props
        })
      }
    }
    let edges = graph.edges
    if (edges.length === 0 && visible.length > 1) {
      const built: FlowchartEdgeModel[] = []
      for (let i = 1; i < visible.length; i++) {
        built.push({
          id: `e_mm_${root.id}_${visible[i].id}`,
          source: root.id,
          target: visible[i].id,
          label: '',
          directed: true,
          lineType: 'arrow',
          sourceAnchor: 'right',
          targetAnchor: 'left',
          properties: {}
        })
      }
      edges = built
    }
    const metadata = cloneFlowchartRecord(graph.metadata)
    metadata[FLOWCHART_MIND_MAP_ROOT_ID_KEY] = root.id
    const next: FlowchartGraphModel = {
      version: graph.version,
      metadata: metadata,
      nodes: nextNodes,
      edges: edges
    }
    return FlowchartLayoutEngine.applyMindMapLinearLayout(next, preferVertical, root.id)
  }

  private openEdgeEditDialog(edge: FlowchartEdgeModel): void {
    this.editingEdgeId = edge.id
    this.editEdgeLabel = edge.label
    this.showEdgeEditDialog = true
  }

  private saveEdgeEditDialog(): void {
    const edge = this.edgeById(this.editingEdgeId)
    if (edge === undefined) {
      this.showEdgeEditDialog = false
      return
    }
    this.pushUndo()
    this.updateEdge({
      id: edge.id,
      source: edge.source,
      target: edge.target,
      label: this.editEdgeLabel.trim(),
      directed: edge.directed,
      lineType: edge.lineType,
      sourceAnchor: edge.sourceAnchor,
      targetAnchor: edge.targetAnchor,
      properties: edge.properties
    })
    this.showEdgeEditDialog = false
  }

  @Builder
  private buildHistoryButtons() {
    Column() {
      SymbolGlyph($r('sys.symbol.undo'))
        .fontSize(24)
        .fontColor([$r('app.color.primary_text')])
        .opacity(this.canUndo() ? 1 : 0.35)
        .onClick(() => {
          if (this.canUndo()) {
            this.undo()
          }
        })
    }
    .width('100%')
    .padding({ bottom: 5 })
    .alignItems(HorizontalAlign.Center)
    .key(`history_${this.historyRevision}`)
  }

  @Builder
  private buildMindMapAddButton(node: FlowchartNodeModel, side: string) {
    Stack() {
      Circle({ width: 24, height: 24 })
        .fill(FLOWCHART_MIND_MAP_LINE_COLOR)
      Text('+')
        .fontSize(16)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Medium)
    }
    .width(24)
    .height(24)
    .position({
      x: (side === FLOWCHART_MIND_MAP_SIDE_LEFT
        ? -8 - 24
        : node.width + 8) + FlowchartEditor.NODE_LAYER_PAD,
      y: node.height / 2 - 12 + FlowchartEditor.NODE_LAYER_PAD
    })
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildMindMapAddButtons(node: FlowchartNodeModel) {
    if (!this.isMindMapMode() || this.selectedNodeId !== node.id) {
      Blank()
    } else if (FlowchartMindMap.isRoot(this.graph, node)) {
      this.buildMindMapAddButton(node, FLOWCHART_MIND_MAP_SIDE_LEFT)
      this.buildMindMapAddButton(node, FLOWCHART_MIND_MAP_SIDE_RIGHT)
    } else if (FlowchartMindMap.isBranch(this.graph, node)) {
      this.buildMindMapAddButton(node, FlowchartMindMap.expansionSide(this.graph, node.id))
    } else {
      Blank()
    }
  }

  @Builder
  private buildNodeDeleteButton(node: FlowchartNodeModel) {
    if (this.selectedNodeId !== node.id) {
      Blank()
    } else {
      Stack() {
        Circle({ width: 24, height: 24 })
          .fill('#E53935')
        Text('×')
          .fontSize(16)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
      }
      .width(24)
      .height(24)
      .position({
        x: node.width + FlowchartEditor.NODE_LAYER_PAD - 10,
        y: FlowchartEditor.NODE_LAYER_PAD - 10
      })
      .onClick(() => this.deleteSelectedNode())
    }
  }

  @Builder
  private buildPaletteExpandFab() {
    Row() {
      Text('›')
        .fontSize(20)
        .fontColor($r('app.color.primary_text'))
    }
    .width(44)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.surface_muted'))
    .borderRadius(8)
    .border({ width: 1, color: $r('app.color.divider') })
    .margin({ left: 12, bottom: 12 })
    .onClick(() => {})
  }

  @Builder
  private buildPaletteItem(shape: FlowchartShapeType) {
    Column() {
      if (shape === 'roundedRect') {
        SymbolGlyph($r('sys.symbol.rectangle'))
          .fontSize(24)
          .fontColor([$r('app.color.primary_text')])
      } else if (shape === 'pill') {
        SymbolGlyph($r('sys.symbol.oval'))
          .fontSize(24)
          .fontColor([$r('app.color.primary_text')])
      } else if (shape === 'arrowRight') {
        SymbolGlyph($r('sys.symbol.arrowshape_up'))
          .fontSize(24)
          .fontColor([$r('app.color.primary_text')])
          .rotate({ angle: 90, centerX: '50%', centerY: '50%' })
      } else if (shape === 'rectangle') {
        SymbolGlyph($r('sys.symbol.square'))
          .fontSize(24)
          .fontColor([$r('app.color.primary_text')])
      } else if (shape === 'diamond') {
        SymbolGlyph($r('sys.symbol.square'))
          .fontSize(24)
          .fontColor([$r('app.color.primary_text')])
          .rotate({ angle: 45, centerX: '50%', centerY: '50%' })
      }
    }
    .width('100%')
    .height(44)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => this.addNode(shape))
  }

  @Builder
  private buildPathShapeFill(shape: FlowchartShapeType, width: number, height: number, fill: string,
    stroke: string, strokeWidth: number) {
    Shape() {
      Path()
        .width(width)
        .height(height)
        .commands(FlowchartShapePath.shapeCommands(shape, width, height))
        .fill(fill)
        .stroke(stroke)
        .strokeWidth(strokeWidth)
    }
    .width(width)
    .height(height)
    .viewPort({ x: 0, y: 0, width: width, height: height })
    .align(Alignment.Center)
    .antiAlias(true)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildNodePathShape(node: FlowchartNodeModel) {
    FlowchartNodePathView({
      shape: node.shape,
      nodeWidth: node.width,
      nodeHeight: node.height,
      fillColor: node.color,
      strokeColor: this.selectedNodeId === node.id ? '#1976D2' : '#212121',
      strokeWidth: this.selectedNodeId === node.id ? 2.2 : 1.5,
      useEndpoints: this.isArrowNode(node) && this.hasStoredEndpoints(node),
      endpointFromX: this.endpointEndpointsLocal(node).from.x,
      endpointFromY: this.endpointEndpointsLocal(node).from.y,
      endpointToX: this.endpointEndpointsLocal(node).to.x,
      endpointToY: this.endpointEndpointsLocal(node).to.y
    })
  }

  @Builder
  private buildLineNodeCanvasShape(node: FlowchartNodeModel) {
    Shape() {
      Path()
        .width(4000)
        .height(4000)
        .commands(this.lineNodeCanvasPathCommands(node))
    }
    .viewPort({ x: 0, y: 0, width: 4000, height: 4000 })
    .width(4000)
    .height(4000)
    .stroke(this.lineNodeStrokeColor(node.id))
    .strokeWidth(this.lineNodeStrokeWidth(node.id))
    .fill(Color.Transparent)
    .antiAlias(true)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildShapePreview(shape: FlowchartShapeType, size: number) {
    if (FlowchartShapePath.isPathShape(shape)) {
      this.buildPathShapeFill(shape, size, size * 0.62, '#F5F5F5', '#212121', 1.5)
    } else if (shape === 'circle') {
      Row()
        .width(size)
        .height(size)
        .borderRadius(size / 2)
        .backgroundColor($r('app.color.card_background'))
        .border({ width: 1.5, color: '#212121' })
    } else if (shape === 'pill') {
      Row()
        .width(size)
        .height(size * 0.55)
        .borderRadius(size * 0.3)
        .backgroundColor($r('app.color.card_background'))
        .border({ width: 1.5, color: '#212121' })
    } else if (shape === 'roundedRect' || shape === 'speechBubble' || shape === 'rectSpeechBubble') {
      Row()
        .width(size)
        .height(size * 0.62)
        .borderRadius(8)
        .backgroundColor($r('app.color.card_background'))
        .border({ width: 1.5, color: '#212121' })
    } else if (shape === 'triangle' || shape === 'equilateralTriangle') {
      Text('△')
        .fontSize(22)
        .fontColor('#212121')
    } else if (shape === 'star') {
      Text('★')
        .fontSize(22)
        .fontColor('#212121')
    } else if (shape === 'plus') {
      Text('+')
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor('#212121')
    } else if (shape === 'cloud') {
      Text('☁')
        .fontSize(20)
        .fontColor('#212121')
    } else if (shape === 'chevron') {
      Text('→')
        .fontSize(22)
        .fontColor('#212121')
    } else {
      Row()
        .width(size)
        .height(size * 0.62)
        .borderRadius(shape === 'rectangle' ? 0 : 2)
        .backgroundColor($r('app.color.card_background'))
        .border({ width: 1.5, color: '#212121' })
    }
  }

  private lineNodeStrokeColor(nodeId: string): string {
    return this.selectedNodeId === nodeId ? '#1976D2' : '#212121'
  }

  private lineNodeStrokeWidth(nodeId: string): number {
    return this.selectedNodeId === nodeId ? 2.2 : 1.8
  }

  private lineNodePathCommands(node: FlowchartNodeModel): string {
    const ep = this.lineEndpointsLocal(node)
    return FlowchartShapePath.lineSegment(
      ep.from.x, ep.from.y, ep.to.x, ep.to.y, this.lineTypeOf(node), 9)
  }

  /** 线条节点：与 edge 相同，在 4000×4000 画布坐标系下用 px 绘制，避免局部 Shape 裁切/偏移。 */
  private lineNodeCanvasPathCommands(node: FlowchartNodeModel): string {
    const ep = this.lineEndpointsCanvas(node)
    return this.edgePathCommands(
      ep.from.x, ep.from.y, ep.to.x, ep.to.y, this.lineTypeOf(node))
  }

  private lineNodeCanvasRenderKey(node: FlowchartNodeModel): string {
    const ep = this.lineEndpointsCanvas(node)
    const selected = this.selectedNodeId === node.id ? 1 : 0
    return `lineCanvas_${node.id}_${ep.from.x.toFixed(1)}_${ep.from.y.toFixed(1)}_` +
      `${ep.to.x.toFixed(1)}_${ep.to.y.toFixed(1)}_${this.lineNodeStrokeWidth(node.id).toFixed(1)}_` +
      `${selected}_${this.graphRevision}_${this.interactionTick}`
  }

  private lineNodesForRender(): FlowchartNodeModel[] {
    const result: FlowchartNodeModel[] = []
    for (const node of this.graph.nodes) {
      if (this.isLineNode(node)) {
        result.push(node)
      }
    }
    return result
  }

  @Builder
  private buildLinePreview(lineType: string) {
    SymbolGlyph($r('sys.symbol.minus'))
      .fontSize(24)
      .fontColor([$r('app.color.primary_text')])
  }

  @Builder
  private buildNodeShapeUi(node: FlowchartNodeModel) {
    if (node.shape === 'circle') {
      Row()
        .width(node.width)
        .height(node.width)
        .borderRadius(node.width / 2)
        .backgroundColor(node.color)
        .border({
          width: this.selectedNodeId === node.id ? 2.2 : 1.5,
          color: this.selectedNodeId === node.id ? '#1976D2' : '#212121'
        })
    } else if (node.shape === 'pill') {
      Row()
        .width(node.width)
        .height(node.height)
        .borderRadius(node.height / 2)
        .backgroundColor(node.color)
        .border({
          width: this.selectedNodeId === node.id ? 2.2 : 1.5,
          color: this.selectedNodeId === node.id ? '#1976D2' : '#212121'
        })
    } else if (node.shape === 'roundedRect' || node.shape === 'speechBubble' ||
      node.shape === 'rectSpeechBubble') {
      Row()
        .width(node.width)
        .height(node.height)
        .borderRadius(12)
        .backgroundColor(node.color)
        .border({
          width: this.selectedNodeId === node.id ? 2.2 : 1.5,
          color: this.selectedNodeId === node.id ? '#1976D2' : '#212121'
        })
    } else if (node.shape === 'triangle' || node.shape === 'equilateralTriangle') {
      Text('△')
        .fontSize(28)
        .fontColor('#212121')
    } else if (node.shape === 'star') {
      Text('★')
        .fontSize(28)
        .fontColor('#212121')
    } else if (node.shape === 'plus') {
      Text('+')
        .fontSize(32)
        .fontWeight(FontWeight.Medium)
        .fontColor('#212121')
    } else if (node.shape === 'cloud') {
      Text('☁')
        .fontSize(28)
        .fontColor('#212121')
    } else {
      Row()
        .width(node.width)
        .height(node.height)
        .borderRadius(node.shape === 'rectangle' ? 0 : 2)
        .backgroundColor(node.color)
        .border({
          width: this.selectedNodeId === node.id ? 2.2 : 1.5,
          color: this.selectedNodeId === node.id ? '#1976D2' : '#212121'
        })
    }
  }

  @Builder
  private buildEdgePolylineShape(edge: FlowchartEdgeModel) {
    Shape() {
      Path()
        .width(4000)
        .height(4000)
        .commands(this.edgePolylineCommandsForEdge(edge))
        .stroke(this.edgeStrokeColor(edge))
        .strokeWidth(this.edgeStrokeWidth(edge))
        .fill(Color.Transparent)
    }
    .viewPort({ x: 0, y: 0, width: 4000, height: 4000 })
    .width(4000)
    .height(4000)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildEdgeArrowHeadShape(edge: FlowchartEdgeModel, end: 'start' | 'end') {
    Shape() {
      Path()
        .width(4000)
        .height(4000)
        .commands(this.edgeArrowHeadCommandsForEdge(edge, end))
        .stroke(this.edgeStrokeColor(edge))
        .strokeWidth(this.edgeStrokeWidth(edge))
        .fill(this.edgeStrokeColor(edge))
    }
    .viewPort({ x: 0, y: 0, width: 4000, height: 4000 })
    .width(4000)
    .height(4000)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildEdgeShape(edge: FlowchartEdgeModel) {
    Stack() {
      this.buildEdgePolylineShape(edge)
      if (edge.lineType === 'arrow' || edge.lineType === 'doubleArrow') {
        this.buildEdgeArrowHeadShape(edge, 'end')
      }
      if (edge.lineType === 'doubleArrow') {
        this.buildEdgeArrowHeadShape(edge, 'start')
      }
    }
    .width(4000)
    .height(4000)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildEdgeLabel(edge: FlowchartEdgeModel) {
    if (edge.label.length === 0) {
      Blank()
    } else {
      this.buildEdgeLabelContent(edge)
    }
  }

  @Builder
  private buildEdgeLabelContent(edge: FlowchartEdgeModel) {
    Stack({ alignContent: Alignment.Center }) {
      Text(edge.label)
        .fontSize(12)
        .fontColor('#616161')
        .backgroundColor('#E6FFFFFF')
        .padding({ left: 4, right: 4, top: 2, bottom: 2 })
        .borderRadius(4)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 160 })
    }
    .width(1)
    .height(1)
    .position({
      x: this.edgeLabelPositionForEdge(edge).x,
      y: this.edgeLabelPositionForEdge(edge).y
    })
    .hitTestBehavior(HitTestMode.None)
  }

  private edgeLabelPositionForEdge(edge: FlowchartEdgeModel): FlowchartNodePosition {
    const route = this.edgeRoutePoints(edge)
    if (route.length < 2) {
      return createFlowchartPosition(0, 0)
    }
    const from = route[0]
    const to = route[route.length - 1]
    return this.edgeLabelPosition(from.x, from.y, to.x, to.y)
  }

  @Builder
  private buildConnectDraftShape() {
    if (this.connectDraftActive) {
      Stack() {
        Shape() {
          Path()
            .width(4000)
            .height(4000)
            .commands(this.edgeStraightCommands(
              this.connectDraftFromX, this.connectDraftFromY,
              this.connectDraftToX, this.connectDraftToY))
            .stroke('#212121')
            .strokeWidth(1.8)
            .fill(Color.Transparent)
        }
        .viewPort({ x: 0, y: 0, width: 4000, height: 4000 })
        .width(4000)
        .height(4000)
        Shape() {
          Path()
            .width(4000)
            .height(4000)
            .commands(this.arrowHeadPathCommandsPx(
              this.shapePathPx(this.connectDraftToX),
              this.shapePathPx(this.connectDraftToY),
              this.shapePathPx(this.connectDraftFromX),
              this.shapePathPx(this.connectDraftFromY)))
            .stroke('#212121')
            .strokeWidth(1.8)
            .fill('#212121')
        }
        .viewPort({ x: 0, y: 0, width: 4000, height: 4000 })
        .width(4000)
        .height(4000)
      }
      .width(4000)
      .height(4000)
      .opacity(0.65)
      .hitTestBehavior(HitTestMode.None)
    }
  }

  private mindMapBranchSize(node: FlowchartNodeModel): FlowchartLabelSize {
    return FlowchartMindMap.effectiveBranchDisplaySize(this.graph, node)
  }

  private nodeDisplaySize(node: FlowchartNodeModel): FlowchartLabelSize {
    return FlowchartMindMap.effectiveBranchDisplaySize(this.graph, node)
  }

  @Builder
  private buildMindMapBranchLines(node: FlowchartNodeModel) {
    Column({ space: 0 }) {
      ForEach(this.mindMapBranchLabel(node).lines, (line: string, index: number) => {
        Text(line)
          .fontSize(FLOWCHART_MIND_MAP_BRANCH_FONT_SIZE)
          .lineHeight(FLOWCHART_MIND_MAP_BRANCH_LINE_HEIGHT)
          .fontColor(FLOWCHART_MIND_MAP_BRANCH_TEXT_COLOR)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)
      }, (_line: string, index: number) => `${index}`)
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildNode(node: FlowchartNodeModel) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isLineNode(node)) {
        Blank()
          .width(node.width)
          .height(node.height)
      } else if (FlowchartMindMap.isTextOnlyBranch(this.graph, node)) {
        if (this.selectedNodeId === node.id) {
          Row() {
            this.buildMindMapBranchLines(node)
          }
          .width(this.mindMapBranchSize(node).w)
          .height(this.mindMapBranchSize(node).h)
          .padding({
            left: FLOWCHART_MIND_MAP_BRANCH_SELECTION_PAD_H,
            right: FLOWCHART_MIND_MAP_BRANCH_SELECTION_PAD_H,
            top: FLOWCHART_MIND_MAP_BRANCH_SELECTION_PAD_V,
            bottom: FLOWCHART_MIND_MAP_BRANCH_SELECTION_PAD_V
          })
          .borderRadius(4)
          .backgroundColor(Color.White)
          .border({ width: 1.5, color: FLOWCHART_MIND_MAP_LINE_COLOR })
          .justifyContent(FlexAlign.Start)
          .alignItems(VerticalAlign.Center)
        } else {
          Row() {
            this.buildMindMapBranchLines(node)
          }
          .width(this.mindMapBranchSize(node).w)
          .height(this.mindMapBranchSize(node).h)
          .padding({
            left: FLOWCHART_MIND_MAP_BRANCH_SELECTION_PAD_H,
            right: FLOWCHART_MIND_MAP_BRANCH_SELECTION_PAD_H,
            top: FLOWCHART_MIND_MAP_BRANCH_SELECTION_PAD_V,
            bottom: FLOWCHART_MIND_MAP_BRANCH_SELECTION_PAD_V
          })
          .justifyContent(FlexAlign.Start)
          .alignItems(VerticalAlign.Center)
        }
      } else if (FlowchartMindMap.isRoot(this.graph, node) && this.isMindMapMode()) {
        Row()
          .width(node.width)
          .height(node.height)
          .borderRadius(12)
          .backgroundColor(FLOWCHART_MIND_MAP_ROOT_COLOR)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        Text(node.title.length > 0 ? node.title : '输入文本')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(FLOWCHART_MIND_MAP_ROOT_TEXT_COLOR)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width(node.width - 24)
      } else if (FlowchartShapePath.isPathShape(node.shape)) {
        this.buildNodePathShape(node)
      } else {
        this.buildNodeShapeUi(node)
        // 普通图形（非 line / 非箭头）的标题栏。
        // 挪进 first-chain 的 else 里执行，避免被 mind-map 分支 / 根节点重复渲染
        // （分支 / 根节点各自的分支里已经渲染过文本；path 形状走的是 buildNodePathShape，
        //  自己处理文本）。
        Column() {
          Text(FlowchartMindMap.isDefaultMindMapNodeTitle(node.title) ? '双击编辑' : node.title)
            .fontSize(13)
            .fontColor(FlowchartMindMap.isDefaultMindMapNodeTitle(node.title) ? '#B0B6BE' : '#616161')
            .fontStyle(FlowchartMindMap.isDefaultMindMapNodeTitle(node.title) ? FontStyle.Italic : FontStyle.Normal)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .width(node.width - 16)
        }
        .width(node.width)
        .height(node.height)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(this.nodeDisplaySize(node).w)
    .height(this.nodeDisplaySize(node).h)
  }

  @Builder
  private buildEndpointHandle(node: FlowchartNodeModel, index: number) {
    Circle({ width: 16, height: 16 })
      .fill($r('app.color.accent'))
      .position({
        x: this.endpointLocalPoint(node, index).x - 8 + FlowchartEditor.NODE_LAYER_PAD,
        y: this.endpointLocalPoint(node, index).y - 8 + FlowchartEditor.NODE_LAYER_PAD
      })
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildNodeLayer(node: FlowchartNodeModel) {
    Stack() {
      Stack() {
        this.buildNode(node)
      }
      .position({ x: FlowchartEditor.NODE_LAYER_PAD, y: FlowchartEditor.NODE_LAYER_PAD })
      if (this.selectedNodeId === node.id && this.isEndpointShape(node)) {
        this.buildEndpointHandle(node, 0)
        this.buildEndpointHandle(node, 1)
      } else if (this.selectedNodeId === node.id) {
        this.buildAnchor(node, 'top')
        this.buildAnchor(node, 'right')
        this.buildAnchor(node, 'bottom')
        this.buildAnchor(node, 'left')
      }
      this.buildMindMapAddButtons(node)
      this.buildNodeDeleteButton(node)
    }
    .width(node.width + FlowchartEditor.NODE_LAYER_PAD * 2)
    .height(node.height + FlowchartEditor.NODE_LAYER_PAD * 2)
    .clip(false)
    .position({
      x: this.nodeDisplayPosition(node).x - FlowchartEditor.NODE_LAYER_PAD,
      y: this.nodeDisplayPosition(node).y - FlowchartEditor.NODE_LAYER_PAD
    })
    .zIndex(this.endpointLayerZIndex(node))
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildAnchor(node: FlowchartNodeModel, anchor: FlowchartAnchor) {
    if (this.selectedNodeId !== node.id ||
      !FlowchartMindMap.shouldShowConnectionAnchors(this.graph, node)) {
      Blank()
    } else {
      Circle({ width: 16, height: 16 })
        .fill($r('app.color.accent'))
        .position({
          x: this.anchorCircleOffset(node, anchor).x + FlowchartEditor.NODE_LAYER_PAD,
          y: this.anchorCircleOffset(node, anchor).y + FlowchartEditor.NODE_LAYER_PAD
        })
        .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  private buildBottomBar() {
    if (this.isWideToolbarLayout()) {
      this.buildBottomBarVertical()
    } else {
      this.buildBottomBarHorizontal()
    }
  }

  @Builder
  private buildBottomBarHorizontal() {
    Row() {
      this.buildBottomBarItem(
        $r('sys.symbol.plus_circle'),
        EditorUiStrings.loc('添加节点', 'Add node', 'ノード追加'),
        () => { this.showAddNodeSheet = true },
        true
      )
      Divider()
        .vertical(true)
        .height(36)
        .color($r('app.color.divider'))
      this.buildBottomBarItem(
        $r('sys.symbol.paintpalette'),
        EditorUiStrings.loc('修改颜色', 'Change color', '色を変更'),
        () => this.onModifyColorTap(),
        true
      )
      Divider()
        .vertical(true)
        .height(36)
        .color($r('app.color.divider'))
      this.buildBottomBarItem(
        $r('sys.symbol.square_grid_2x2'),
        EditorUiStrings.loc('图表样式', 'Chart style', 'チャートスタイル'),
        () => { this.showStyleSheet = true },
        true
      )
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
    .border({ width: 1, color: $r('app.color.divider') })
    .shadow({ radius: 12, color: '#14000000', offsetY: 3 })
  }

  @Builder
  private buildBottomBarVertical() {
    Column() {
      this.buildBottomBarItem(
        $r('sys.symbol.plus_circle'),
        EditorUiStrings.loc('添加节点', 'Add node', 'ノード追加'),
        () => { this.showAddNodeSheet = true },
        false
      )
      Divider()
        .width('100%')
        .color($r('app.color.divider'))
      this.buildBottomBarItem(
        $r('sys.symbol.paintpalette'),
        EditorUiStrings.loc('修改颜色', 'Change color', '色を変更'),
        () => this.onModifyColorTap(),
        false
      )
      Divider()
        .width('100%')
        .color($r('app.color.divider'))
      this.buildBottomBarItem(
        $r('sys.symbol.square_grid_2x2'),
        EditorUiStrings.loc('图表样式', 'Chart style', 'チャートスタイル'),
        () => { this.showStyleSheet = true },
        false
      )
    }
    .width(88)
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
    .border({ width: 1, color: $r('app.color.divider') })
    .shadow({ radius: 12, color: '#14000000', offsetY: 3 })
  }

  @Builder
  private buildBottomBarItem(icon: Resource, label: string, onTap: () => void, expanded: boolean) {
    Column({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([$r('app.color.primary_text')])
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
    }
    .width(expanded ? '100%' : 72)
    .layoutWeight(expanded ? 1 : 0)
    .alignItems(HorizontalAlign.Center)
    .onClick(onTap)
  }

  @Builder
  private buildAddNodeSheetOverlay() {
    Column() {
      Column({ space: 16 }) {
        Text(EditorUiStrings.loc('添加节点', 'Add node', 'ノード追加'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(flowchartAddNodeOptionsFor(this.chartKind), (option: FlowchartAddNodeOption) => {
            Column({ space: 6 }) {
              Stack({ alignContent: Alignment.Center }) {
                if (option === 'rectangle') {
                  Row()
                    .width(20)
                    .height(14)
                    .border({ width: 1, color: $r('app.color.primary_text') })
                    .borderRadius(3.5)
                } else if (option === 'sharpRect') {
                  Row()
                    .width(20)
                    .height(14)
                    .border({ width: 1, color: $r('app.color.primary_text') })
                } else if (option === 'circle') {
                  Text('○')
                    .fontSize(22)
                    .fontColor($r('app.color.primary_text'))
                } else if (option === 'diamond') {
                  Text('◇')
                    .fontSize(22)
                    .fontColor($r('app.color.primary_text'))
                } else if (option === 'classBox') {
                  // 目字形类框
                  Column() {
                    Row().width(20).height(7)
                      .border({ width: 1, color: $r('app.color.primary_text') })
                    Row().width(20).height(7)
                      .border({
                        width: { left: 1, right: 1, bottom: 1, top: 0 },
                        color: $r('app.color.primary_text')
                      })
                    Row().width(20).height(7)
                      .border({
                        width: { left: 1, right: 1, bottom: 1, top: 0 },
                        color: $r('app.color.primary_text')
                      })
                  }
                } else if (option === 'mindmap') {
                  FlowchartStylePreviewIcon({
                    kind: 'mindmap',
                    color: '#333333',
                    iconSize: 28
                  })
                } else if (option === 'pieSlice') {
                  Text('◔')
                    .fontSize(22)
                    .fontColor($r('app.color.primary_text'))
                } else if (option === 'gitBranch') {
                  Text('⎇')
                    .fontSize(18)
                    .fontColor($r('app.color.primary_text'))
                } else if (option === 'gitCommit') {
                  Text('●')
                    .fontSize(16)
                    .fontColor($r('app.color.primary_text'))
                } else if (option === 'gitTag') {
                  Text('🏷')
                    .fontSize(16)
                } else {
                  Text('◇')
                    .fontSize(22)
                    .fontColor($r('app.color.primary_text'))
                }
              }
              .width(28)
              .height(28)
              Text(flowchartAddNodeLabel(option))
                .fontSize(12)
                .fontColor($r('app.color.secondary_text'))
            }
            .width(72)
            .padding(8)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => this.onAddNodeOption(option))
          }, (option: FlowchartAddNodeOption) => option)
        }
        .width('100%')
      }
      .width('100%')
      .padding(20)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .backgroundColor('#66000000')
    .onClick(() => {
      this.showAddNodeSheet = false
    })
  }

  @Builder
  private buildColorSheetOverlay() {
    Column() {
      Column({ space: 16 }) {
        Text(EditorUiStrings.loc('修改颜色', 'Change color', '色を変更'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(FLOWCHART_EDITOR_COLORS, (color: string) => {
            Circle({ width: 40, height: 40 })
              .fill(color)
              .margin({ right: 12, bottom: 12 })
              .onClick(() => this.applySelectedColor(color))
          }, (color: string) => color)
        }
        .width('100%')
      }
      .width('100%')
      .padding(20)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .backgroundColor('#66000000')
    .onClick(() => {
      this.showColorSheet = false
    })
  }

  @Builder
  private buildStyleSheetOverlay() {
    Column() {
      Column({ space: 16 }) {
        Text(EditorUiStrings.loc('图表样式', 'Chart style', 'チャートスタイル'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(FLOWCHART_EDITOR_CHART_KINDS, (kind: FlowchartEditorChartKind) => {
            Column({ space: 6 }) {
              FlowchartStylePreviewIcon({
                kind: kind,
                color: this.chartKind === kind ? '#1976D2' : '#333333',
                iconSize: 36
              })
              Text(this.styleSheetLabel(kind))
                .fontSize(12)
                .fontColor(this.chartKind === kind ?
                  $r('app.color.accent') : $r('app.color.primary_text'))
                .fontWeight(this.chartKind === kind ? FontWeight.Medium : FontWeight.Regular)
                .textAlign(TextAlign.Center)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('31%')
            .constraintSize({ minHeight: 88 })
            .padding({ left: 6, right: 6, top: 10, bottom: 10 })
            .margin({ right: '2%', bottom: 10 })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(this.chartKind === kind ?
              '#1A1976D2' : $r('app.color.card_background'))
            .borderRadius(12)
            .border({
              width: this.chartKind === kind ? 1.5 : 1,
              color: this.chartKind === kind ?
                $r('app.color.accent') : $r('app.color.divider')
            })
            .onClick(() => this.applyChartKind(kind))
          }, (kind: FlowchartEditorChartKind) => kind)
        }
        .width('100%')
      }
      .width('100%')
      .padding(20)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .backgroundColor('#66000000')
    .onClick(() => {
      this.showStyleSheet = false
    })
  }

  private styleSheetLabel(kind: FlowchartEditorChartKind): string {
    const zh = flowchartEditorChartLabel(kind)
    switch (kind) {
      case 'flowchart':
        return EditorUiStrings.loc(zh, 'Flowchart', 'フローチャート')
      case 'state':
        return EditorUiStrings.loc(zh, 'Knowledge graph', '知識グラフ')
      case 'sequence':
        return EditorUiStrings.loc(zh, 'Sequence', 'シーケンス図')
      case 'class':
        return EditorUiStrings.loc(zh, 'Class', 'クラス図')
      case 'mindmap':
        return EditorUiStrings.loc(zh, 'Mind map', 'マインドマップ')
      case 'pie':
        return EditorUiStrings.loc(zh, 'Pie chart', '円グラフ')
      case 'gitgraph':
        return EditorUiStrings.loc(zh, 'Git graph', 'ブランチ図')
      case 'journey':
        return EditorUiStrings.loc(zh, 'User journey', 'ユーザージャーニー')
      case 'timeline':
        return EditorUiStrings.loc(zh, 'Timeline', 'タイムライン')
      case 'gantt':
        return EditorUiStrings.loc(zh, 'Gantt', 'ガントチャート')
      default:
        return zh
    }
  }

  @Builder
  private buildInteractiveCanvasHost() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack() {
        Stack() {
          Canvas(this.canvasContext)
            .id('flowchartCanvas')
            .width(4000)
            .height(4000)
            .hitTestBehavior(HitTestMode.None)
            .onReady(() => {
              this.canvasReady = true
              this.redrawCanvas()
            })

          ForEach(this.graph.edges, (edge: FlowchartEdgeModel) => {
            this.buildEdgeShape(edge)
          }, (edge: FlowchartEdgeModel) => this.edgeRenderKey(edge))

          ForEach(this.graph.edges, (edge: FlowchartEdgeModel) => {
            this.buildEdgeLabel(edge)
          }, (edge: FlowchartEdgeModel) => `${this.edgeRenderKey(edge)}_label_${edge.label}`)

          ForEach(this.lineNodesForRender(), (node: FlowchartNodeModel) => {
            this.buildLineNodeCanvasShape(node)
          }, (node: FlowchartNodeModel) => this.lineNodeCanvasRenderKey(node))

          ForEach(this.nodesForRender(), (node: FlowchartNodeModel) => {
            this.buildNodeLayer(node)
          }, (node: FlowchartNodeModel) => this.nodeRenderKey(node))

          this.buildConnectDraftShape()
        }
        .width(4000)
        .height(4000)
        .alignContent(Alignment.TopStart)
        .position({ x: this.viewportX, y: this.viewportY })
        .scale({ x: this.canvasScale, y: this.canvasScale, centerX: 0, centerY: 0 })
      }
      .width('100%')
      .height('100%')
      .clip(true)
      .alignContent(Alignment.TopStart)
      .backgroundColor($r('app.color.editor_background'))
      .id('flowchartExportHost')
      .parallelGesture(
        PinchGesture({ fingers: 2 })
          .onActionStart((_event: GestureEvent) => {
            this.pinchStartScale = this.canvasScale
          })
          .onActionUpdate((event: GestureEvent) => {
            const s = event.scale
            if (s !== undefined && s > 0) {
              let next = this.pinchStartScale * s
              if (next < FlowchartEditor.MIN_CANVAS_SCALE) {
                next = FlowchartEditor.MIN_CANVAS_SCALE
              }
              if (next > FlowchartEditor.MAX_CANVAS_SCALE) {
                next = FlowchartEditor.MAX_CANVAS_SCALE
              }
              this.canvasScale = next
            }
          }),
        GestureMask.Normal
      )
      .onTouch((event: TouchEvent) => this.handleCanvasTouch(event))
    }
    .layoutWeight(1)
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(18)
            .fontColor([$r('app.color.primary_text')])
            .padding({ left: 4, right: 4 })
            .onClick(() => this.exitEditor())

          Row({ space: 2 }) {
            Text(this.noteTitle.length > 0 && !isDefaultFlowchartTitle(this.noteTitle) ?
              this.noteTitle : FLOWCHART_DEFAULT_TITLE)
              .fontSize($r('app.float.title_font_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(14)
              .fontColor([$r('app.color.secondary_text')])
          }
          .layoutWeight(1)
          .margin({ left: 4 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => this.openNoteTitleDialog())

          SymbolGlyph($r('sys.symbol.undo'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
            .opacity(this.canUndo() ? 1 : 0.35)
            .padding({ left: 6, right: 6 })
            .onClick(() => {
              if (this.canUndo()) {
                this.undo()
              }
            })

          SymbolGlyph($r('sys.symbol.redo'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
            .opacity(this.canRedo() ? 1 : 0.35)
            .padding({ left: 6, right: 6 })
            .onClick(() => {
              if (this.canRedo()) {
                this.redo()
              }
            })

          Button(this.showSourceView ?
            EditorUiStrings.loc('画布', 'Canvas', 'キャンバス') :
            EditorUiStrings.loc('编码', 'Code', 'コード'), { buttonStyle: ButtonStyleMode.NORMAL })
            .fontSize(13)
            .fontColor($r('app.color.accent'))
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: $r('app.color.accent') })
            .height(32)
            .margin({ left: 4 })
            .onClick(() => this.toggleSourceView())
        }
        .width('100%')
        .height($r('app.float.toolbar_height'))
        .alignItems(VerticalAlign.Center)
        .padding({ left: 12, right: 12 })

        if (this.loading) {
          LoadingProgress()
            .width(36)
            .height(36)
            .layoutWeight(1)
        } else if (this.showSourceView) {
          TextArea({ text: this.sourceText })
            .layoutWeight(1)
            .width('100%')
            .fontSize(13)
            .fontFamily('monospace')
            .backgroundColor($r('app.color.editor_background'))
            .padding(16)
            .onChange((v: string) => {
              this.sourceText = v
              this.markDirty()
            })
        } else if (this.usesMermaidPreview()) {
          if (this.isWideToolbarLayout()) {
            Row() {
              Column() {
                this.buildBottomBar()
              }
              .padding({ left: 12, top: 8, bottom: 8 })

              Column() {
                this.buildMermaidPreviewCanvas()
              }
              .layoutWeight(1)
              .width('100%')
              .height('100%')
              .backgroundColor($r('app.color.editor_background'))
            }
            .layoutWeight(1)
            .width('100%')
            .height('100%')
            .alignItems(VerticalAlign.Top)
          } else {
            Column() {
              Column() {
                this.buildMermaidPreviewCanvas()
              }
              .layoutWeight(1)
              .width('100%')
              .backgroundColor($r('app.color.editor_background'))

              this.buildBottomBar()
            }
            .layoutWeight(1)
            .width('100%')
            .height('100%')
          }
        } else if (this.isWideToolbarLayout()) {
          Row() {
            Column() {
              this.buildBottomBar()
            }
            .padding({ left: 12, top: 8, bottom: 8 })

            this.buildInteractiveCanvasHost()
          }
          .layoutWeight(1)
          .width('100%')
          .height('100%')
          .alignItems(VerticalAlign.Top)
        } else {
          Stack({ alignContent: Alignment.Bottom }) {
            this.buildInteractiveCanvasHost()

            Column() {
              this.buildBottomBar()
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 12 })
          }
          .layoutWeight(1)
          .width('100%')
          .height('100%')
        }
      }
      .width('100%')
      .height('100%')
      .onAreaChange((_: Area, area: Area) => {
        const w = area.width as number
        if (w > 0) {
          this.pageWidth = w
        }
      })

      if (this.showNoteTitleDialog) {
        Column() {
          Column({ space: 12 }) {
            Text(EditorUiStrings.loc('编辑标题', 'Edit title', 'タイトルを編集'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
            TextInput({ text: this.editNoteTitleInput, placeholder: EditorUiStrings.loc('标题', 'Title', 'タイトル') })
              .onChange((v: string) => {
                this.editNoteTitleInput = v
              })
            Row({ space: 12 }) {
              Button(EditorUiStrings.loc('取消', 'Cancel', 'キャンセル'))
                .layoutWeight(1)
                .backgroundColor($r('app.color.surface_muted'))
                .fontColor($r('app.color.primary_text'))
                .onClick(() => {
                  this.showNoteTitleDialog = false
                })
              Button(EditorUiStrings.loc('保存', 'Save', '保存'))
                .layoutWeight(1)
                .onClick(() => this.saveNoteTitleDialog())
            }
            .width('100%')
          }
          .width('88%')
          .padding(20)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#66000000')
      }

      if (this.showEditDialog) {
        Column() {
          Column({ space: 12 }) {
            Text(this.editDialogMode === 'single' ?
              (this.editSingleKind === 'gitTag' ?
                EditorUiStrings.loc('编辑 Tag', 'Edit tag', 'Tagを編集') :
                (this.editSingleKind === 'gitBranch' ?
                  EditorUiStrings.loc('编辑分支名', 'Edit branch', 'ブランチ名を編集') :
                  EditorUiStrings.loc('编辑流程', 'Edit section', 'フローを編集'))) :
              EditorUiStrings.loc('编辑节点', 'Edit node', 'ノードを編集'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
            if (this.editDialogMode === 'single') {
              TextInput({
                text: this.editTitle,
                placeholder: this.editSecondaryLabel
              })
                .onChange((v: string) => {
                  this.editTitle = v
                })
            } else {
              TextArea({
                text: this.editTitle,
                placeholder: EditorUiStrings.loc('标题', 'Title', 'タイトル')
              })
                .fontSize(14)
                .borderRadius(8)
                .maxLines(this.editDialogMode === 'default' ? 4 : 2)
                .height(this.editDialogMode === 'default' ? 96 : 56)
                .onChange((v: string) => {
                  this.editTitle = v
                })
              TextInput({
                text: this.editDescription,
                placeholder: this.editSecondaryLabel
              })
                .onChange((v: string) => {
                  this.editDescription = v
                })
            }
            Row({ space: 12 }) {
              Button(EditorUiStrings.loc('取消', 'Cancel', 'キャンセル'))
                .layoutWeight(1)
                .backgroundColor($r('app.color.surface_muted'))
                .fontColor($r('app.color.primary_text'))
                .onClick(() => {
                  this.showEditDialog = false
                })
              Button(EditorUiStrings.loc('保存', 'Save', '保存'))
                .layoutWeight(1)
                .onClick(() => this.saveEditDialog())
            }
            .width('100%')
          }
          .width('88%')
          .padding(20)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#66000000')
      }

      if (this.showEdgeEditDialog) {
        Column() {
          Column({ space: 12 }) {
            Text(EditorUiStrings.loc('编辑连线', 'Edit edge', '接続を編集'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
            TextInput({ text: this.editEdgeLabel, placeholder: EditorUiStrings.loc('标签文字', 'Edge label', 'ラベル') })
              .onChange((v: string) => {
                this.editEdgeLabel = v
              })
            Row({ space: 12 }) {
              Button(EditorUiStrings.loc('取消', 'Cancel', 'キャンセル'))
                .layoutWeight(1)
                .backgroundColor($r('app.color.surface_muted'))
                .fontColor($r('app.color.primary_text'))
                .onClick(() => {
                  this.showEdgeEditDialog = false
                })
              Button(EditorUiStrings.loc('保存', 'Save', '保存'))
                .layoutWeight(1)
                .onClick(() => this.saveEdgeEditDialog())
            }
            .width('100%')
          }
          .width('88%')
          .padding(20)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#66000000')
      }

      if (this.showAddNodeSheet) {
        this.buildAddNodeSheetOverlay()
      }

      if (this.showColorSheet) {
        this.buildColorSheetOverlay()
      }

      if (this.showStyleSheet) {
        this.buildStyleSheetOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }
}
