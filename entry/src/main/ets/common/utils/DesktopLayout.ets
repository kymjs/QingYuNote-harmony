/** 与 Flutter `usePcStyleLayout` 对齐。 */
const TABLET_SHORTEST_SIDE_VP = 600

/** 基于当前窗口逻辑像素宽高判定 PC/iPad 横屏布局。 */
export function usePcStyleLayoutWithSize(widthVp: number, heightVp: number): boolean {
  if (widthVp <= 0 || heightVp <= 0) {
    return false
  }
  const shortest = Math.min(widthVp, heightVp)
  const landscape = widthVp > heightVp
  if (shortest >= TABLET_SHORTEST_SIDE_VP && landscape) {
    return true
  }
  if (widthVp >= 840 && landscape) {
    return true
  }
  return false
}
