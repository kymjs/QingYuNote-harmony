import { fileUri } from '@kit.CoreFileKit'
import { ImageCacheService } from '../services/ImageCacheService'

/**
 * 网络图片统一入口：优先读 [ImageCacheService] 磁盘缓存，未命中再下载并落盘。
 */
@Component
export struct CachedNetworkImage {
  @Prop @Watch('onUrlChanged') url: string = ''
  @Prop imageWidth: Length = '100%'
  @Prop imageHeight: Length = '100%'
  @Prop imageBorderRadius: Length = 0
  @Prop objectFit: ImageFit = ImageFit.Cover
  @Prop alt: string = ''
  @Prop showLoading: boolean = true
  onError?: () => void = undefined
  @State private resolvedSrc: string = ''
  @State private failed: boolean = false
  @State private loading: boolean = true

  aboutToAppear(): void {
    void this.loadImage()
  }

  onUrlChanged(): void {
    this.resolvedSrc = ''
    this.failed = false
    this.loading = true
    void this.loadImage()
  }

  private async loadImage(): Promise<void> {
    const normalized = this.url.trim()
    if (!ImageCacheService.isNetworkImageUrl(normalized)) {
      this.failed = true
      this.loading = false
      this.onError?.()
      return
    }
    try {
      const filePath = await ImageCacheService.getInstance().resolve(normalized)
      if (filePath.length === 0) {
        throw new Error('empty cache path')
      }
      this.resolvedSrc = fileUri.getUriFromPath(filePath)
      this.failed = false
    } catch (_) {
      this.failed = true
      this.onError?.()
    } finally {
      this.loading = false
    }
  }

  build() {
    if (this.failed) {
      Blank()
        .width(this.imageWidth)
        .height(this.imageHeight)
    } else if (this.loading) {
      if (this.showLoading) {
        Row() {
          LoadingProgress()
            .width(24)
            .height(24)
        }
        .width(this.imageWidth)
        .height(this.imageHeight)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      } else {
        Blank()
          .width(this.imageWidth)
          .height(this.imageHeight)
      }
    } else {
      Image(this.resolvedSrc)
        .width(this.imageWidth)
        .height(this.imageHeight)
        .borderRadius(this.imageBorderRadius)
        .objectFit(this.objectFit)
        .alt(this.alt.length > 0 ? this.alt : this.url)
        .onError(() => {
          this.failed = true
          this.onError?.()
        })
    }
  }
}
