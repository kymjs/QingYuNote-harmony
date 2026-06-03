import { fileUri } from '@kit.CoreFileKit'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'

interface NoteImageGalleryParams {
  imagesJson?: string
  initialIndex?: number
  filesDir?: string
}

const GALLERY_DOUBLE_TAP_ZOOM: number = 2.5

@Component
struct GalleryImageItem {
  @Prop src: string = ''
  @Prop zoomScale: number = 1
  @Prop resolvedSrc: string = ''
  onClose: () => void = () => {
  }
  onToggleZoom: () => void = () => {
  }

  build() {
    Image(this.resolvedSrc.length > 0 ? this.resolvedSrc : this.src)
      .width('100%')
      .height('100%')
      .objectFit(ImageFit.Contain)
      .scale({
        x: this.zoomScale,
        y: this.zoomScale,
        centerX: '50%',
        centerY: '50%'
      })
      .alt(this.src)
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          TapGesture({ count: 2 })
            .onAction(() => {
              this.onToggleZoom()
            }),
          TapGesture({ count: 1 })
            .onAction(() => {
              this.onClose()
            })
        )
      )
  }
}

@Entry
@Component
struct NoteImageGallery {
  @State imageSources: string[] = []
  @State currentIndex: number = 0
  @State filesDir: string = ''
  @State zoomScales: number[] = []
  private closeGuard = new PageCloseGuard()
  private swiperController: SwiperController = new SwiperController()

  aboutToAppear(): void {
    this.closeGuard.reset()
    try {
      const params = this.getUIContext().getRouter().getParams() as NoteImageGalleryParams
      const jsonRaw = params?.imagesJson
      if (typeof jsonRaw === 'string' && jsonRaw.length > 0) {
        const parsed = JSON.parse(jsonRaw) as Object
        if (Array.isArray(parsed)) {
          this.imageSources = (parsed as string[]).filter((s: string) => typeof s === 'string' && s.length > 0)
        }
      }
      const idxRaw = params?.initialIndex
      const idx = typeof idxRaw === 'number' ? idxRaw : 0
      const maxIdx = this.imageSources.length > 0 ? this.imageSources.length - 1 : 0
      this.currentIndex = Math.max(0, Math.min(idx, maxIdx))
      const dirRaw = params?.filesDir
      this.filesDir = typeof dirRaw === 'string' ? dirRaw : ''
      this.zoomScales = new Array<number>(this.imageSources.length).fill(1)
    } catch (e) {
      console.error(`NoteImageGallery aboutToAppear: ${JSON.stringify(e)}`)
      this.imageSources = []
      this.currentIndex = 0
      this.zoomScales = []
    }
  }

  private resolveLocalImageAbsPath(src: string): string {
    if (src.startsWith('file://')) {
      return src.replace('file://', '')
    }
    if (src.startsWith('/')) {
      return src
    }
    return `${this.filesDir}/${src}`
  }

  private resolveImageSrc(src: string): string {
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return src
    }
    return fileUri.getUriFromPath(this.resolveLocalImageAbsPath(src))
  }

  private handleToolbarBack(): void {
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'NoteImageGallery')
  }

  onBackPress(): boolean {
    this.handleToolbarBack()
    return true
  }

  private imagePageKey(src: string, index: number): string {
    return `${index}:${src}:${this.zoomScales[index] ?? 1}`
  }

  private zoomScaleAt(index: number): number {
    if (index < 0 || index >= this.zoomScales.length) {
      return 1
    }
    return this.zoomScales[index]
  }

  private toggleZoomAt(index: number): void {
    if (index < 0 || index >= this.zoomScales.length) {
      return
    }
    const next = [...this.zoomScales]
    const current = next[index] ?? 1
    next[index] = current > 1 ? 1 : GALLERY_DOUBLE_TAP_ZOOM
    this.zoomScales = next
  }

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.handleToolbarBack()
        })

        if (this.imageSources.length > 1) {
          Text(`${this.currentIndex + 1} / ${this.imageSources.length}`)
            .fontSize(16)
            .fontColor('rgba(255,255,255,0.72)')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
        } else {
          Blank().layoutWeight(1)
        }

        Blank().width(40)
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .backgroundColor(Color.Black)

      if (this.imageSources.length === 0) {
        Column() {
          Text('暂无图片')
            .fontSize(16)
            .fontColor('rgba(255,255,255,0.54)')
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Color.Black)
      } else {
        Swiper(this.swiperController) {
          ForEach(this.imageSources, (src: string, index: number) => {
            Column() {
              GalleryImageItem({
                src: src,
                resolvedSrc: this.resolveImageSrc(src),
                zoomScale: this.zoomScaleAt(index),
                onClose: (): void => {
                  this.handleToolbarBack()
                },
                onToggleZoom: (): void => {
                  this.toggleZoomAt(index)
                }
              })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          }, (src: string, index: number) => this.imagePageKey(src, index))
        }
        .layoutWeight(1)
        .width('100%')
        .index(this.currentIndex)
        .indicator(this.imageSources.length > 1)
        .loop(false)
        .backgroundColor(Color.Black)
        .onChange((index: number) => {
          this.currentIndex = index
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
