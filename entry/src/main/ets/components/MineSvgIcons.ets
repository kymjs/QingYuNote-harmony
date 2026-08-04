/**
 * 「我的」tab 用 SVG 图标。
 *
 * - MineScalesIcon  天平图标（已开通会员 / 会员有效期）→ app.media.mine_scales
 * - MineDiamondIcon 钻石图标（轻羽云会员）             → app.media.mine_diamond
 *
 * SVG 使用 `fill="currentColor"`，由调用方通过 `iconColor` prop 传入颜色，
 * 再用 `Image.fillColor()` 着色，按 UI 上下文展示不同颜色（不再硬编码 SVG 原色）。
 */

@Component
export struct MineScalesIcon {
  @Prop iconColor: ResourceColor = '#0DAA4A';
  @Prop iconSize: number | string = 14;

  build() {
    Image($r('app.media.mine_scales'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .fillColor(this.iconColor)
  }
}

@Component
export struct MineDiamondIcon {
  @Prop iconColor: ResourceColor = '#0DAA4A';
  @Prop iconSize: number | string = 14;

  build() {
    Image($r('app.media.mine_diamond'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .fillColor(this.iconColor)
  }
}