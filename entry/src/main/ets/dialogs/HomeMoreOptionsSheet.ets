export interface HomeMoreOptionsSheetParams {
  onClose: () => void
  onPasteLink: () => void
  onPhotoImage: () => void
  onTodoList: () => void
}

@Component
export struct HomeMoreOptionsSheet {
  @Prop params: HomeMoreOptionsSheetParams = {
    onClose: (): void => {},
    onPasteLink: (): void => {},
    onPhotoImage: (): void => {},
    onTodoList: (): void => {}
  }

  @Builder
  private buildOptionRow(
    icon: Resource,
    title: string,
    subtitle: string,
    onTap: () => void
  ): void {
    Row({ space: 12 }) {
      Row() {
        SymbolGlyph(icon)
          .fontSize(22)
          .fontColor([$r('app.color.secondary_text')])
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.surface_muted'))
      .borderRadius(12)

      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .width('100%')
        Text(subtitle)
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([$r('app.color.tertiary_text')])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .onClick(onTap)
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Text('更多方式')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Blank()
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.secondary_text')])
        }
        .width(32)
        .height(32)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(16)
        .onClick(() => {
          this.params.onClose()
        })
      }
      .width('100%')

      Column() {
        this.buildOptionRow(
          $r('sys.symbol.link'),
          '粘贴内容提取',
          '暂不支持公众号文章，后续版本将优化…',
          (): void => {
            this.params.onClose()
            this.params.onPasteLink()
          }
        )
        Divider()
          .color($r('app.color.divider'))
          .strokeWidth(1)
          .margin({ left: 68 })
        this.buildOptionRow(
          $r('sys.symbol.picture'),
          '拍照/图片',
          '白板记录/课堂笔记/日常打卡，秒变笔记',
          (): void => {
            this.params.onClose()
            this.params.onPhotoImage()
          }
        )
        Divider()
          .color($r('app.color.divider'))
          .strokeWidth(1)
          .margin({ left: 68 })
        this.buildOptionRow(
          $r('sys.symbol.list_bullet'),
          'Todo List',
          '备忘录/日程清单/待办事项，都能完成',
          (): void => {
            this.params.onClose()
            this.params.onTodoList()
          }
        )
      }
      .width('100%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(16)
      .shadow({
        radius: 12,
        color: $r('app.color.shadow_color'),
        offsetX: 0,
        offsetY: 4
      })
      .margin({ bottom: 12 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 12 })
    .backgroundBlurStyle(BlurStyle.Thin)
    .backgroundColor('#EBF3F4F8')
    .borderRadius({ topLeft: 24, topRight: 24 })
  }
}

@Builder
export function buildHomeMoreOptionsSheetContent(params: HomeMoreOptionsSheetParams): void {
  HomeMoreOptionsSheet({ params: params })
}
