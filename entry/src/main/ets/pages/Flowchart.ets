import componentSnapshot from '@ohos.arkui.componentSnapshot'
import { util } from '@kit.ArkTS'
import { vibrator } from '@kit.SensorServiceKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { image } from '@kit.ImageKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { common, Configuration } from '@kit.AbilityKit'
import { FlowchartService } from '../services/FlowchartService'
import { NoteRepository } from '../services/NoteRepository'
import { AppContextHolder } from '../services/AppContextHolder'
import { PageLifecycle } from '../common/utils/PageLifecycle'
import { FlowchartLayoutEngine } from '../common/utils/FlowchartLayoutEngine'
import { Logger } from '../common/utils/Logger'
import type {
  FlowchartAnchor,
  FlowchartAnchorHit,
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
  FLOWCHART_SHAPE_TYPES,
  createEmptyFlowchartGraph,
  createFlowchartPosition,
  cloneFlowchartGraph,
  flowchartFirstMatchingNodeId,
  FLOWCHART_DEFAULT_TITLE,
  isDefaultFlowchartTitle,
  isPlaceholderFlowchartGraph
} from '../common/model/FlowchartGraph'
import { FlowchartShapePath } from '../common/utils/FlowchartShapePath'
import { FlowchartNodePathView } from '../components/FlowchartNodePathView'

const FLOWCHART_LOG_TAG = 'FlowchartPage'

@Entry
@Component
struct FlowchartPage {
  @State graph: FlowchartGraphModel = createEmptyFlowchartGraph()
  @State noteTitle: string = FLOWCHART_DEFAULT_TITLE
  @State noteId: string = ''
  @State focusQuery: string = ''
  @State loading: boolean = true
  @State paletteExpanded: boolean = true
  @State @Watch('onSelectedNodeChanged') selectedNodeId: string = ''
  @State canvasScale: number = 1
  @State viewportX: number = 0
  @State viewportY: number = 0
  @State editTitle: string = ''
  @State editDescription: string = ''
  @State showEditDialog: boolean = false
  @State showNoteTitleDialog: boolean = false
  @State editNoteTitleInput: string = ''
  @State editingNodeId: string = ''
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
  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)

  aboutToAppear(): void {
    this.lifecycle.appear()
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>
    this.noteId = `${params?.noteId ?? ''}`
    this.focusQuery = `${params?.focusQuery ?? ''}`
    void this.loadGraph()
  }

  aboutToDisappear(): void {
    this.lifecycle.disappear()
    this.clearDragVisual()
  }

  onBackPress(): boolean {
    void this.finalizeOnExit().then(() => {
      this.getUIContext().getRouter().back()
    })
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
    const note = await NoteRepository.getInstance().getNote(this.noteId)
    const loaded = note === null
      ? createEmptyFlowchartGraph()
      : await FlowchartService.getInstance().load(this.noteId)
    if (this.lifecycle.isActive()) {
      this.graph = loaded
      this.noteTitle = note?.title ?? FLOWCHART_DEFAULT_TITLE
      this.initialHadNodes = !isPlaceholderFlowchartGraph(loaded)
      this.loading = false
      Logger.info(FLOWCHART_LOG_TAG,
        `loadGraph noteId=${this.noteId} nodes=${loaded.nodes.length} edges=${loaded.edges.length} ` +
        `edgeIds=[${loaded.edges.map((e: FlowchartEdgeModel) => e.id.slice(0, 8)).join(',')}]`)
      this.graphRevision++
      this.scheduleCanvasRedraw()
      const nodeId = flowchartFirstMatchingNodeId(loaded, this.focusQuery)
      if (nodeId.length > 0) {
        this.selectedNodeId = nodeId
        this.markNodeEdited(nodeId)
      } else if (loaded.nodes.length > 0) {
        this.lastEditedNodeId = loaded.nodes[loaded.nodes.length - 1].id
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
      this.showUserMessage('未关联笔记，无法保存')
      return
    }
    if (!this.shouldPersistFlowchart()) {
      this.dirty = false
      await this.abandonNewEmptyFlowchartIfNeeded()
      if (showToast) {
        this.showUserMessage('无需保存')
      }
      return
    }
    try {
      Logger.info(FLOWCHART_LOG_TAG,
        `persist start noteId=${this.noteId} nodes=${this.graph.nodes.length} edges=${this.graph.edges.length}`)
      await NoteRepository.getInstance().ensureFlowchartNote(this.noteId, this.noteTitle)
      await FlowchartService.getInstance().save(this.graph, this.noteId)
      await NoteRepository.getInstance().saveFlowchartNote(this.noteId, this.graph, this.noteTitle)
      this.dirty = false
      Logger.info(FLOWCHART_LOG_TAG, `persist ok noteId=${this.noteId} edges=${this.graph.edges.length}`)
      if (showToast) {
        this.showUserMessage('已保存')
      }
    } catch (error) {
      console.error(`persist failed: ${JSON.stringify(error)}`)
      this.showUserMessage('保存失败，请稍后重试')
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
    return this.pageWidth < FlowchartPage.WIDE_LAYOUT_MIN_WIDTH
  }

  private applyAlignedLayout(): void {
    this.pushUndo()
    this.graph = FlowchartLayoutEngine.applyAlignedLayout(this.graph, this.isPhoneLayout())
    this.graphRevision++
    this.markDirty()
    this.scheduleCanvasRedraw()
    this.showUserMessage('已对齐布局')
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
        this.showUserMessage('导出失败，请稍后重试')
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
        this.showUserMessage('图片已保存到相册')
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
    Logger.info(FLOWCHART_LOG_TAG,
      `${message} mode=${this.touchMode} activated=${this.dragActivated} moved=${this.touchMoved} ` +
      `pending=${this.pendingDragNodeId} dragging=${this.draggingNodeId} ` +
      `live=(${this.dragLiveX.toFixed(1)},${this.dragLiveY.toFixed(1)}) ` +
      `connectDraft=${this.connectDraftActive} edges=${this.graph.edges.length} ` +
      `viewport=(${this.viewportX.toFixed(1)},${this.viewportY.toFixed(1)}) ` +
      `nodes=${this.graph.nodes.length}`)
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
    const pad = FlowchartPage.ENDPOINT_BOUNDS_PAD
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
    const threshold = FlowchartPage.ENDPOINT_HIT_RADIUS / this.canvasScale
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
    const endpoints = this.edgeLineEndpoints(source, target)
    return `${edge.id}_${endpoints.from.x.toFixed(1)}_${endpoints.from.y.toFixed(1)}_` +
      `${endpoints.to.x.toFixed(1)}_${endpoints.to.y.toFixed(1)}_${this.graphRevision}_${this.interactionTick}`
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
    return x >= pos.x - padding && x <= pos.x + node.width + padding &&
      y >= pos.y - padding && y <= pos.y + node.height + padding
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

  private addNode(shape: FlowchartShapeType): void {
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
    const node: FlowchartNodeModel = {
      id: util.generateRandomUUID(),
      title: isArrow ? '' : '输入文本',
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
    const draft: FlowchartNodeModel = {
      id: util.generateRandomUUID(),
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

  private createEdge(fromId: string, toId: string): void {
    if (fromId.length === 0 || toId.length === 0 || fromId === toId) {
      return
    }
    const from = this.nodeById(fromId)
    const to = this.nodeById(toId)
    if (from === undefined || to === undefined) {
      return
    }
    this.pushUndo()
    const edge: FlowchartEdgeModel = {
      id: util.generateRandomUUID(),
      source: fromId,
      target: toId,
      label: '',
      directed: true,
      lineType: 'arrow',
      sourceAnchor: 'right',
      targetAnchor: 'left',
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
    const endpoints = this.edgeLineEndpoints(from, to)
    Logger.info(FLOWCHART_LOG_TAG,
      `createEdge ${fromId.slice(0, 8)} -> ${toId.slice(0, 8)} total=${this.graph.edges.length} ` +
      `from=(${endpoints.from.x.toFixed(1)},${endpoints.from.y.toFixed(1)}) ` +
      `to=(${endpoints.to.x.toFixed(1)},${endpoints.to.y.toFixed(1)}) rev=${this.graphRevision}`)
    void this.persist(false)
  }

  private deleteSelectedNode(): void {
    if (this.selectedNodeId.length === 0) {
      return
    }
    this.pushUndo()
    const id = this.selectedNodeId
    this.graph = {
      version: this.graph.version,
      metadata: this.graph.metadata,
      nodes: this.graph.nodes.filter((n: FlowchartNodeModel) => n.id !== id),
      edges: this.graph.edges.filter((e: FlowchartEdgeModel) => e.source !== id && e.target !== id)
    }
    this.selectedNodeId = ''
    this.markDirty()
    this.graphRevision++
  }

  private edgeLineEndpoints(source: FlowchartNodeModel,
    target: FlowchartNodeModel): FlowchartEdgeLineEndpoints {
    const tcx = target.position.x + target.width / 2
    const tcy = target.position.y + target.height / 2
    const scx = source.position.x + source.width / 2
    const scy = source.position.y + source.height / 2
    const endpoints: FlowchartEdgeLineEndpoints = {
      from: this.connectionPointToward(source, tcx, tcy),
      to: this.connectionPointToward(target, scx, scy)
    }
    if (source.shape === 'diamond' || target.shape === 'diamond') {
      Logger.info(FLOWCHART_LOG_TAG,
        `[EdgeLine] ${source.shape}(${source.id.slice(0, 8)}) -> ${target.shape}(${target.id.slice(0, 8)}) ` +
        `from=(${endpoints.from.x.toFixed(1)},${endpoints.from.y.toFixed(1)}) ` +
        `to=(${endpoints.to.x.toFixed(1)},${endpoints.to.y.toFixed(1)}) ` +
        `srcAnchor=${this.bestAnchorToward(source, tcx, tcy)} ` +
        `tgtAnchor=${this.bestAnchorToward(target, scx, scy)}`)
    }
    return endpoints
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

  private edgePathCommands(fromX: number, fromY: number, toX: number, toY: number,
    lineType: string): string {
    const fx = this.shapePathPx(fromX)
    const fy = this.shapePathPx(fromY)
    const tx = this.shapePathPx(toX)
    const ty = this.shapePathPx(toY)
    let commands = `M${fx.toFixed(1)} ${fy.toFixed(1)} L${tx.toFixed(1)} ${ty.toFixed(1)}`
    if (lineType === 'arrow' || lineType === 'doubleArrow') {
      commands += ` ${this.arrowHeadPathCommandsPx(tx, ty, fx, fy)}`
    }
    if (lineType === 'doubleArrow') {
      commands += ` ${this.arrowHeadPathCommandsPx(fx, fy, tx, ty)}`
    }
    return commands
  }

  private edgePathCommandsForEdge(edge: FlowchartEdgeModel): string {
    const source = this.nodeForRender(edge.source)
    const target = this.nodeForRender(edge.target)
    if (source === undefined || target === undefined) {
      return ''
    }
    const endpoints = this.edgeLineEndpoints(source, target)
    return this.edgePathCommands(endpoints.from.x, endpoints.from.y, endpoints.to.x, endpoints.to.y, edge.lineType)
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
        duration: FlowchartPage.LONG_PRESS_MS
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
    if (this.dragActivated) {
      return
    }
    this.pushUndo()
    if (this.longPressTimerId >= 0) {
      clearTimeout(this.longPressTimerId)
      this.longPressTimerId = -1
    }
    this.dragActivated = true
    this.touchMode = FlowchartPage.TOUCH_DRAG
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
    this.touchMode = FlowchartPage.TOUCH_ENDPOINT
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
      if (this.touchMode !== FlowchartPage.TOUCH_PENDING_DRAG) {
        return
      }
      const node = this.nodeById(this.pendingDragNodeId)
      if (node !== undefined) {
        this.activateNodeDrag(node)
      }
    }, FlowchartPage.LONG_PRESS_MS)
  }

  private hitTestAnchor(x: number, y: number): FlowchartAnchorHit | undefined {
    if (this.selectedNodeId.length === 0) {
      return undefined
    }
    const node = this.nodeById(this.selectedNodeId)
    if (node === undefined) {
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
    this.activeConnectFromId = ''
    this.connectDraftActive = false
    if (fromId.length === 0) {
      return
    }
    for (const other of this.graph.nodes) {
      if (other.id === fromId) {
        continue
      }
      const display = this.nodeForRender(other.id)
      if (display === undefined) {
        continue
      }
      if (endX >= display.position.x && endX <= display.position.x + display.width &&
        endY >= display.position.y && endY <= display.position.y + display.height) {
        this.createEdge(fromId, other.id)
        this.showUserMessage('已创建连线')
        Logger.info(FLOWCHART_LOG_TAG, `finishConnect ok ${fromId.slice(0, 8)} -> ${other.id.slice(0, 8)}`)
        return
      }
    }
    Logger.info(FLOWCHART_LOG_TAG,
      `finishConnect miss from=${fromId.slice(0, 8)} end=(${endX.toFixed(1)},${endY.toFixed(1)})`)
  }

  private handleCanvasTouch(event: TouchEvent): void {
    if (event.touches.length === 0) {
      return
    }
    if (event.touches.length >= 2) {
      if (event.type === TouchType.Down) {
        this.resetTouchGestureState()
        this.touchMode = FlowchartPage.TOUCH_PINCH
      }
      return
    }
    if (this.touchMode === FlowchartPage.TOUCH_PINCH) {
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
        this.touchMode = FlowchartPage.TOUCH_CONNECT
        this.activeConnectFromId = anchorHit.nodeId
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
        this.touchMode = FlowchartPage.TOUCH_PENDING_DRAG
        this.pendingDragNodeId = node.id
        this.touchDownAtMs = Date.now()
        this.schedulePendingDragActivation()
        this.logTouch(`down hit node id=${node.id}`)
        return
      }
      this.touchMode = FlowchartPage.TOUCH_PAN
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

      if (this.touchMode === FlowchartPage.TOUCH_PENDING_DRAG) {
        const pendingNode = this.nodeById(this.pendingDragNodeId)
        if (pendingNode !== undefined &&
          !this.dragActivated &&
          Date.now() - this.touchDownAtMs >= FlowchartPage.LONG_PRESS_MS) {
          this.activateNodeDrag(pendingNode)
        }
      }

      if (this.touchMode === FlowchartPage.TOUCH_ENDPOINT) {
        const endpointNode = this.nodeById(this.selectedNodeId)
        if (endpointNode !== undefined) {
          this.applyEndpointDragLive(endpointNode, canvasPt.x, canvasPt.y)
        }
      } else if (this.touchMode === FlowchartPage.TOUCH_DRAG) {
        this.dragLiveX += dxLocal / this.canvasScale
        this.dragLiveY += dyLocal / this.canvasScale
        this.bumpInteraction()
      } else if (this.touchMode === FlowchartPage.TOUCH_CONNECT) {
        this.connectDraftToX = canvasPt.x
        this.connectDraftToY = canvasPt.y
        this.bumpInteraction()
      } else if (this.touchMode === FlowchartPage.TOUCH_PAN) {
        this.viewportX += dxLocal
        this.viewportY += dyLocal
      }
      return
    }

    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.logTouch(`up/cancel type=${event.type}`)
      if (this.touchMode === FlowchartPage.TOUCH_ENDPOINT) {
        this.commitEndpointDrag()
      } else if (this.touchMode === FlowchartPage.TOUCH_DRAG ||
        (this.dragActivated && this.draggingNodeId.length > 0)) {
        this.commitDragIfNeeded()
      } else if (this.touchMode === FlowchartPage.TOUCH_PENDING_DRAG) {
        const node = this.nodeById(this.pendingDragNodeId)
        if (node !== undefined && !this.touchMoved) {
          const now = Date.now()
          if (this.lastTapNodeId === node.id && now - this.lastTapTime < 400) {
            this.openEditDialog(node)
            this.lastTapNodeId = ''
            this.lastTapTime = 0
          } else {
            this.selectedNodeId = node.id
            this.markNodeEdited(node.id)
            this.lastTapNodeId = node.id
            this.lastTapTime = now
          }
        }
      } else if (this.touchMode === FlowchartPage.TOUCH_CONNECT) {
        this.finishConnect(canvasPt.x, canvasPt.y)
      } else if (this.touchMode === FlowchartPage.TOUCH_PAN && !this.touchMoved) {
        this.selectedNodeId = ''
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
  }

  private openEditDialog(node: FlowchartNodeModel): void {
    this.editingNodeId = node.id
    this.editTitle = node.title
    this.editDescription = node.description
    this.markNodeEdited(node.id)
    this.showEditDialog = true
  }

  private saveEditDialog(): void {
    const node = this.nodeById(this.editingNodeId)
    if (node === undefined) {
      this.showEditDialog = false
      return
    }
    this.pushUndo()
    this.updateNode({
      id: node.id,
      title: this.editTitle.trim().length > 0 ? this.editTitle.trim() : '输入文本',
      description: this.editDescription.trim(),
      color: node.color,
      shape: node.shape,
      position: node.position,
      width: node.width,
      height: node.height,
      rotation: node.rotation,
      properties: node.properties
    })
    this.markNodeEdited(node.id)
    this.showEditDialog = false
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
        x: node.width + FlowchartPage.NODE_LAYER_PAD - 10,
        y: FlowchartPage.NODE_LAYER_PAD - 10
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
    .onClick(() => {
      this.paletteExpanded = true
    })
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
        .backgroundColor('#F5F5F5')
        .border({ width: 1.5, color: '#212121' })
    } else if (shape === 'pill') {
      Row()
        .width(size)
        .height(size * 0.55)
        .borderRadius(size * 0.3)
        .backgroundColor('#F5F5F5')
        .border({ width: 1.5, color: '#212121' })
    } else if (shape === 'roundedRect' || shape === 'speechBubble' || shape === 'rectSpeechBubble') {
      Row()
        .width(size)
        .height(size * 0.62)
        .borderRadius(8)
        .backgroundColor('#F5F5F5')
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
        .backgroundColor('#F5F5F5')
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
  private buildEdgeShape(edge: FlowchartEdgeModel) {
    Shape() {
      Path()
        .width(4000)
        .height(4000)
        .commands(this.edgePathCommandsForEdge(edge))
        .stroke('#212121')
        .strokeWidth(1.8)
        .fill('#212121')
    }
    .viewPort({ x: 0, y: 0, width: 4000, height: 4000 })
    .width(4000)
    .height(4000)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildConnectDraftShape() {
    if (this.connectDraftActive) {
      Shape() {
        Path()
          .width(4000)
          .height(4000)
          .commands(this.edgePathCommands(
            this.connectDraftFromX, this.connectDraftFromY,
            this.connectDraftToX, this.connectDraftToY, 'arrow'))
          .stroke('#212121')
          .strokeWidth(1.8)
          .fill('#212121')
      }
      .viewPort({ x: 0, y: 0, width: 4000, height: 4000 })
      .width(4000)
      .height(4000)
      .opacity(0.65)
      .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  private buildNode(node: FlowchartNodeModel) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isLineNode(node)) {
        Blank()
          .width(node.width)
          .height(node.height)
      } else if (FlowchartShapePath.isPathShape(node.shape)) {
        this.buildNodePathShape(node)
      } else {
        this.buildNodeShapeUi(node)
      }

      if (!this.isLineNode(node) && node.shape !== 'arrowRight' && node.shape !== 'arrowLeft' &&
        node.title.length > 0) {
        Column() {
          Text(node.title)
            .fontSize(13)
            .fontColor('#616161')
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
    .width(node.width)
    .height(node.height)
  }

  @Builder
  private buildEndpointHandle(node: FlowchartNodeModel, index: number) {
    Circle({ width: 16, height: 16 })
      .fill($r('app.color.accent'))
      .position({
        x: this.endpointLocalPoint(node, index).x - 8 + FlowchartPage.NODE_LAYER_PAD,
        y: this.endpointLocalPoint(node, index).y - 8 + FlowchartPage.NODE_LAYER_PAD
      })
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildNodeLayer(node: FlowchartNodeModel) {
    Stack() {
      Stack() {
        this.buildNode(node)
      }
      .position({ x: FlowchartPage.NODE_LAYER_PAD, y: FlowchartPage.NODE_LAYER_PAD })
      if (this.selectedNodeId === node.id && this.isEndpointShape(node)) {
        this.buildEndpointHandle(node, 0)
        this.buildEndpointHandle(node, 1)
      } else if (this.selectedNodeId === node.id) {
        this.buildAnchor(node, 'top')
        this.buildAnchor(node, 'right')
        this.buildAnchor(node, 'bottom')
        this.buildAnchor(node, 'left')
      }
      this.buildNodeDeleteButton(node)
    }
    .width(node.width + FlowchartPage.NODE_LAYER_PAD * 2)
    .height(node.height + FlowchartPage.NODE_LAYER_PAD * 2)
    .clip(false)
    .position({
      x: this.nodeDisplayPosition(node).x - FlowchartPage.NODE_LAYER_PAD,
      y: this.nodeDisplayPosition(node).y - FlowchartPage.NODE_LAYER_PAD
    })
    .zIndex(this.endpointLayerZIndex(node))
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildAnchor(node: FlowchartNodeModel, anchor: FlowchartAnchor) {
    if (this.selectedNodeId !== node.id) {
      Blank()
    } else {
      Circle({ width: 16, height: 16 })
        .fill($r('app.color.accent'))
        .position({
          x: this.anchorCircleOffset(node, anchor).x + FlowchartPage.NODE_LAYER_PAD,
          y: this.anchorCircleOffset(node, anchor).y + FlowchartPage.NODE_LAYER_PAD
        })
        .hitTestBehavior(HitTestMode.None)
    }
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Row() {
            SymbolGlyph($r('sys.symbol.arrow_left'))
              .fontSize(18)
              .fontColor([$r('app.color.primary_text')])
          }
          .height('100%')
          .padding({
            left: $r('app.float.toolbar_icon_button_padding_h'),
            right: $r('app.float.toolbar_icon_button_padding_h')
          })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.pill_radius'))
          .onClick(() => {
            void this.finalizeOnExit().then(() => {
              this.getUIContext().getRouter().back()
            })
          })

          Text(this.noteTitle.length > 0 ? this.noteTitle : $r('app.string.flowchart_title'))
            .fontSize($r('app.float.title_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .layoutWeight(1)
            .margin({ left: 8 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Start)
            .onClick(() => this.openNoteTitleDialog())

          Button('布局', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .fontSize(14)
            .fontColor($r('app.color.accent'))
            .height(36)
            .onClick(() => this.applyAlignedLayout())

          Button('导出', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .fontSize(14)
            .fontColor($r('app.color.accent'))
            .height(36)
            .onClick(() => {
              void this.exportImage()
            })
        }
        .width('100%')
        .height($r('app.float.toolbar_height'))
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16 })

        if (this.loading) {
          LoadingProgress()
            .width(36)
            .height(36)
            .layoutWeight(1)
        } else {
          Row() {
            if (this.paletteExpanded) {
              Column() {
                Scroll() {
                  Column({ space: 2 }) {
                    ForEach(FLOWCHART_SHAPE_TYPES, (shape: FlowchartShapeType) => {
                      this.buildPaletteItem(shape)
                    }, (shape: FlowchartShapeType) => shape)
                    ForEach(FLOWCHART_LINE_TYPES, (line: string) => {
                      Column() {
                        this.buildLinePreview(line)
                      }
                      .width('100%')
                      .height(28)
                      .justifyContent(FlexAlign.Center)
                      .alignItems(HorizontalAlign.Center)
                      .onClick(() => this.addLineNode(line as FlowchartLineType))
                    }, (line: string) => line)
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Center)
                  .justifyContent(FlexAlign.Start)
                  .padding({ left: 4, right: 4, top: 8, bottom: 8 })
                }
                .align(Alignment.TopStart)
                .layoutWeight(1)
                .width('100%')
                .scrollBar(BarState.Auto)
                .edgeEffect(EdgeEffect.Spring)

                this.buildHistoryButtons()

                Row() {
                  Text('‹')
                    .fontSize(18)
                    .width('100%')
                    .textAlign(TextAlign.Center)
                }
                .width('100%')
                .height(40)
                .justifyContent(FlexAlign.Center)
                .border({ width: { top: 1 }, color: $r('app.color.divider') })
                .onClick(() => {
                  this.paletteExpanded = false
                })
              }
              .width(72)
              .height('100%')
              .justifyContent(FlexAlign.Start)
              .backgroundColor($r('app.color.surface_muted'))
              .border({ width: { right: 1 }, color: $r('app.color.divider') })
            }

            Stack({ alignContent: Alignment.BottomStart }) {
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

              if (!this.paletteExpanded) {
                this.buildPaletteExpandFab()
              }
            }
            .width('100%')
            .layoutWeight(1)
            .height('100%')
            .clip(true)
            .parallelGesture(
              PinchGesture({ fingers: 2 })
                .onActionStart((_event: GestureEvent) => {
                  this.pinchStartScale = this.canvasScale
                })
                .onActionUpdate((event: GestureEvent) => {
                  const s = event.scale
                  if (s !== undefined && s > 0) {
                    let next = this.pinchStartScale * s
                    if (next < FlowchartPage.MIN_CANVAS_SCALE) {
                      next = FlowchartPage.MIN_CANVAS_SCALE
                    }
                    if (next > FlowchartPage.MAX_CANVAS_SCALE) {
                      next = FlowchartPage.MAX_CANVAS_SCALE
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
          .alignItems(VerticalAlign.Top)
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
            Text('编辑标题')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
            TextInput({ text: this.editNoteTitleInput, placeholder: '标题' })
              .onChange((v: string) => {
                this.editNoteTitleInput = v
              })
            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .backgroundColor($r('app.color.surface_muted'))
                .fontColor($r('app.color.primary_text'))
                .onClick(() => {
                  this.showNoteTitleDialog = false
                })
              Button('保存')
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
            Text('编辑节点')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
            TextInput({ text: this.editTitle, placeholder: '标题' })
              .onChange((v: string) => {
                this.editTitle = v
              })
            TextInput({ text: this.editDescription, placeholder: '描述' })
              .onChange((v: string) => {
                this.editDescription = v
              })
            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .backgroundColor($r('app.color.surface_muted'))
                .fontColor($r('app.color.primary_text'))
                .onClick(() => {
                  this.showEditDialog = false
                })
              Button('保存')
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }
}
