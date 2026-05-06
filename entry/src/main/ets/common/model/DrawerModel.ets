/**
 * 首页抽屉动画进度：仅由 HomeDrawerLayer（@ObjectLink）订阅展示，
 * 由 Index 侧滑动手势写入，避免使用 @State 存储 progress 导致整页每帧刷新。
 */
@Observed
export class DrawerModel {
  progress: number = 0
}
