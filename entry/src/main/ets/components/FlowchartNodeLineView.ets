import { FlowchartShapeDrawer } from '../common/utils/FlowchartShapeDrawer'

/** 线条节点：端点坐标与 properties 一致，铺满节点框。 */
@Component
export struct FlowchartNodeLineView {
  @Prop nodeWidth: number = 160
  @Prop nodeHeight: number = 32
  @Prop fromX: number = 0
  @Prop fromY: number = 16
  @Prop toX: number = 160
  @Prop toY: number = 16
  @Prop lineType: string = 'solid'
  @Prop strokeColor: string = '#212121'
  @Prop strokeWidth: number = 1.8

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
    FlowchartShapeDrawer.drawLineSegment(
      ctx,
      this.fromX,
      this.fromY,
      this.toX,
      this.toY,
      this.lineType,
      this.strokeColor,
      this.strokeWidth,
      9)
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
