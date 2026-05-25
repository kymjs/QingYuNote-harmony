import { FlowchartShapeDrawer } from '../common/utils/FlowchartShapeDrawer'
import type { FlowchartShapeType } from '../common/model/FlowchartGraph'

/** 菱形/箭头等路径节点：Canvas 按节点宽高绘制，顶点与锚点局部坐标一致。 */
@Component
export struct FlowchartNodePathView {
  @Prop shape: FlowchartShapeType = 'diamond'
  @Prop nodeWidth: number = 120
  @Prop nodeHeight: number = 72
  @Prop fillColor: string = '#FFF8E1'
  @Prop strokeColor: string = '#212121'
  @Prop strokeWidth: number = 1.5
  @Prop useEndpoints: boolean = false
  @Prop endpointFromX: number = 0
  @Prop endpointFromY: number = 0
  @Prop endpointToX: number = 0
  @Prop endpointToY: number = 0

  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)

  private redraw(): void {
    const w = this.nodeWidth
    const h = this.nodeHeight
    if (w <= 0 || h <= 0) {
      return
    }
    const ctx = this.context
    ctx.clearRect(0, 0, w, h)
    if (this.useEndpoints &&
      (this.shape === 'arrowRight' || this.shape === 'arrowLeft')) {
      FlowchartShapeDrawer.drawBlockArrowBetween(
        ctx,
        this.endpointFromX,
        this.endpointFromY,
        this.endpointToX,
        this.endpointToY,
        this.fillColor,
        this.strokeColor,
        this.strokeWidth)
      return
    }
    FlowchartShapeDrawer.drawShape(
      ctx,
      this.shape,
      0,
      0,
      w,
      h,
      this.fillColor,
      this.strokeColor,
      this.strokeWidth)
  }

  aboutToUpdate(): void {
    this.redraw()
  }

  build() {
    Canvas(this.context)
      .width(this.nodeWidth)
      .height(this.nodeHeight)
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => {
        this.redraw()
      })
  }
}
