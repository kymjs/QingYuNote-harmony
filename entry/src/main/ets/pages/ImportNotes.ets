import { promptAction } from '@kit.ArkUI'
import { PageLifecycle } from '../common/utils/PageLifecycle'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'
import { AppContextHolder } from '../services/AppContextHolder'
import { NoteImportResult, NoteImportService } from '../services/NoteImportService'

@Entry
@Component
struct ImportNotes {
  @State importingFiles: boolean = false
  private lifecycle = new PageLifecycle()
  private closeGuard = new PageCloseGuard()

  aboutToAppear(): void {
    this.lifecycle.appear()
    this.closeGuard.reset()
  }

  aboutToDisappear(): void {
    this.lifecycle.disappear()
  }

  onBackPress(): boolean {
    this.handleToolbarBack()
    return true
  }

  private handleToolbarBack(): void {
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'ImportNotes')
  }

  private openWereadImport(): void {
    this.getUIContext().getRouter()
      .pushUrl({ url: 'pages/WereadImport' })
      .catch((err: Error) => {
        console.error(`openWereadImport: ${JSON.stringify(err)}`)
      })
  }

  private openYoudaoImport(): void {
    this.getUIContext().getRouter()
      .pushUrl({ url: 'pages/YoudaoImport' })
      .catch((err: Error) => {
        console.error(`openYoudaoImport: ${JSON.stringify(err)}`)
      })
  }

  private openYinxiangImport(): void {
    this.getUIContext().getRouter()
      .pushUrl({ url: 'pages/YinxiangImport' })
      .catch((err: Error) => {
        console.error(`openYinxiangImport: ${JSON.stringify(err)}`)
      })
  }

  private showComingSoon(): void {
    try {
      this.getUIContext()
        .getPromptAction()
        .showToast({ message: '该功能即将上线', duration: 2000 })
    } catch (_) {
      console.error('ImportNotes showToast failed')
    }
  }

  private showToast(message: string, duration: number = 2000): void {
    if (message.trim().length === 0) {
      return
    }
    try {
      promptAction.showToast({ message, duration })
    } catch (error) {
      console.error(`ImportNotes showToast failed: ${JSON.stringify(error)}`)
    }
  }

  /** 触发「导入md/doc/txt等文件」流程：拉起 DocumentViewPicker → 串行处理 → 弹结果 Toast。 */
  private async importNotesFromFiles(): Promise<void> {
    if (this.importingFiles) {
      this.showToast('正在导入…')
      return
    }
    const context = AppContextHolder.tryGetContext()
    if (context === undefined) {
      this.showToast('导入失败，请稍后重试')
      return
    }
    this.importingFiles = true
    try {
      const result: NoteImportResult = await NoteImportService.getInstance().pickAndImport(context)
      const lines: string[] = []
      if (result.importedCount > 0) {
        lines.push(`已导入 ${result.importedCount} 篇笔记`)
      }
      if (result.failedFiles.length > 0) {
        lines.push(result.failedFiles.join('\n'))
      }
      if (result.skippedFiles.length > 0) {
        lines.push(`已跳过：${result.skippedFiles.join('、')}`)
      }
      if (lines.length > 0) {
        this.showToast(lines.join('\n'), 3000)
      }
    } catch (error) {
      console.error(`ImportNotes importNotesFromFiles failed: ${JSON.stringify(error)}`)
      this.showToast('导入失败，请稍后重试')
    } finally {
      this.importingFiles = false
    }
  }

  build() {
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
          this.handleToolbarBack()
        })

        Row() {
          Text($r('app.string.import_notes_title'))
            .fontSize($r('app.float.title_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 0 }) {
            Row() {
              Text($r('app.string.import_notes_weread'))
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text('›')
                .fontSize(22)
                .fontColor($r('app.color.tertiary_text'))
            }
            .width('100%')
            .padding({
              left: 20,
              right: 16,
              top: 14,
              bottom: 14
            })
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.openWereadImport()
            })

            Divider()
              .color($r('app.color.divider'))
              .strokeWidth(1)

            Row() {
              Text($r('app.string.import_notes_youdao'))
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text('›')
                .fontSize(22)
                .fontColor($r('app.color.tertiary_text'))
            }
            .width('100%')
            .padding({
              left: 20,
              right: 16,
              top: 14,
              bottom: 14
            })
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.openYoudaoImport()
            })

            Divider()
              .color($r('app.color.divider'))
              .strokeWidth(1)

            Row() {
              Text($r('app.string.import_notes_yinxiang'))
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text('›')
                .fontSize(22)
                .fontColor($r('app.color.tertiary_text'))
            }
            .width('100%')
            .padding({
              left: 20,
              right: 16,
              top: 14,
              bottom: 14
            })
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.openYinxiangImport()
            })

            Divider()
              .color($r('app.color.divider'))
              .strokeWidth(1)

            Row() {
              Text($r('app.string.import_notes_files'))
                .fontSize($r('app.float.body_font_size'))
                .fontColor(this.importingFiles ? $r('app.color.tertiary_text') : $r('app.color.primary_text'))
                .layoutWeight(1)
              if (this.importingFiles) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color($r('app.color.tertiary_text'))
              } else {
                Text('›')
                  .fontSize(22)
                  .fontColor($r('app.color.tertiary_text'))
              }
            }
            .width('100%')
            .padding({
              left: 20,
              right: 16,
              top: 14,
              bottom: 14
            })
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              void this.importNotesFromFiles()
            })
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({ width: 1, color: $r('app.color.card_border') })
          .shadow({
            radius: 20,
            color: $r('app.color.shadow_color'),
            offsetX: 0,
            offsetY: 4
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
      .padding({ bottom: 15, top: 5 })
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: 16,
      right: 16
    })
    .backgroundColor($r('app.color.app_background'))
  }
}
