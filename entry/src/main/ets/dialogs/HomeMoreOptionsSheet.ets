import { APP_LOCALE_REVISION_KEY, LocaleService } from '../services/LocaleService'

export interface HomeMoreOptionsSheetParams {
  onClose: () => void
  onTodoList: () => void
  onPasteLink: () => void
  onPhotoImage: () => void
  onKnowledgeGraph: () => void
}

@Component
export struct HomeMoreOptionsSheet {
  @StorageProp(APP_LOCALE_REVISION_KEY) localeRevision: number = 0
  @Prop params: HomeMoreOptionsSheetParams = {
    onClose: (): void => {},
    onTodoList: (): void => {},
    onPasteLink: (): void => {},
    onPhotoImage: (): void => {},
    onKnowledgeGraph: (): void => {}
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
        Text(LocaleService.loc('更多方式', 'More options'))
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
          $r('sys.symbol.list_bullet'),
          LocaleService.loc('待办事项', 'To-do list', 'ToDoリスト'),
          LocaleService.loc('把每天安排的更清楚', 'Plan your day more clearly', '毎日の予定をもっと明確に'),
          (): void => {
            this.params.onClose()
            this.params.onTodoList()
          }
        )
        Divider()
          .color($r('app.color.divider'))
          .strokeWidth(1)
          .margin({ left: 68 })
        this.buildOptionRow(
          $r('sys.symbol.link'),
          LocaleService.loc('链接生成笔记', 'Create note from link'),
          LocaleService.loc('抖音/B站/公众号/小红书链接，秒变笔记', 'Douyin, Bilibili, WeChat & RedNote links — notes in seconds'),
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
          LocaleService.loc('图片生成笔记', 'Create note from image'),
          LocaleService.loc('白板记录/课堂笔记/日常打卡，秒变笔记', 'Whiteboard, class notes, check-ins — notes in seconds'),
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
          $r('sys.symbol.shareplay'),
          LocaleService.loc('知识图谱', 'Mind map'),
          LocaleService.loc('知识图谱/思维导图/流程图，都能完成', 'Mind maps and flowcharts supported'),
          (): void => {
            this.params.onClose()
            this.params.onKnowledgeGraph()
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
    .backgroundColor($r('app.color.sheet_background'))
    .borderRadius({ topLeft: 24, topRight: 24 })
  }
}

@Builder
export function buildHomeMoreOptionsSheetContent(params: HomeMoreOptionsSheetParams): void {
  HomeMoreOptionsSheet({ params: params })
}
