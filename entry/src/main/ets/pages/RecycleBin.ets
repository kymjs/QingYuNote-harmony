import type { Note } from '../common/model/Note'
import { NoteRepository } from '../services/NoteRepository'
import { AppContextHolder } from '../services/AppContextHolder'
import { PreferencesService } from '../services/PreferencesService'

@Entry
@Component
struct RecycleBinPage {
  @State notes: Note[] = []
  @State loading: boolean = true
  @State pageWidth: number = 360
  /** 还原/删除后递增，强制 ForEach 与列表数据源同步刷新 */
  @State listRevision: number = 0
  private loadingCount: number = 0

  private beginLoading(): void {
    this.loadingCount += 1
    this.loading = this.loadingCount > 0
  }

  private endLoading(): void {
    if (this.loadingCount > 0) {
      this.loadingCount -= 1
    }
    this.loading = this.loadingCount > 0
  }

  aboutToAppear(): void {
    void this.loadList(true)
  }

  onPageShow(): void {
    void this.loadList(true)
  }

  /** @param trackLoading 为 true 时计入全屏 Loading；读取/还原/删除任一进行中均保持 Loading。 */
  private async loadList(trackLoading: boolean = true): Promise<void> {
    if (trackLoading) {
      this.beginLoading()
    }
    try {
      const context = AppContextHolder.tryGetContext()
      if (context) {
        try {
          await PreferencesService.getInstance().init(context)
        } catch (_) {
          // 偏好未初始化时仅展示本地回收站
        }
      }
      await NoteRepository.getInstance().init()
      const result = await NoteRepository.getInstance().listRecycleBinNotesMergedWithRemote()
      this.notes = [...result.notes]
      this.listRevision += 1
    } finally {
      if (trackLoading) {
        this.endLoading()
      }
    }
  }

  private async reloadRecycleListAfterMutation(): Promise<void> {
    await this.loadList(false)
  }

  private showUserMessage(message: string): void {
    if (message.trim().length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message,
        duration: 2000
      })
    } catch (error) {
      console.error(`showToast failed: ${JSON.stringify(error)}`)
    }
  }

  private async handleRestore(note: Note): Promise<void> {
    this.beginLoading()
    try {
      await NoteRepository.getInstance().restoreRecycleBinNote(note.id)
      await this.reloadRecycleListAfterMutation()
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage('还原失败，请稍后重试')
    } finally {
      this.endLoading()
    }
  }

  private async handlePermanentDelete(note: Note): Promise<void> {
    this.beginLoading()
    try {
      await NoteRepository.getInstance().setRecycleBinNoteDeletedTimePermanent(note.id)
      await this.reloadRecycleListAfterMutation()
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage('删除失败，请稍后重试')
    } finally {
      this.endLoading()
    }
  }

  private async handleRestoreAll(): Promise<void> {
    const ids = this.notes.map((note: Note) => note.id)
    if (ids.length === 0) {
      return
    }
    this.beginLoading()
    try {
      for (const id of ids) {
        await NoteRepository.getInstance().restoreRecycleBinNote(id)
      }
      await this.reloadRecycleListAfterMutation()
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage('还原失败，请稍后重试')
      await this.reloadRecycleListAfterMutation()
    } finally {
      this.endLoading()
    }
  }

  private async handlePermanentDeleteAll(): Promise<void> {
    const ids = this.notes.map((note: Note) => note.id)
    if (ids.length === 0) {
      return
    }
    this.beginLoading()
    try {
      for (const id of ids) {
        await NoteRepository.getInstance().setRecycleBinNoteDeletedTimePermanent(id)
      }
      await this.reloadRecycleListAfterMutation()
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage('删除失败，请稍后重试')
      await this.reloadRecycleListAfterMutation()
    } finally {
      this.endLoading()
    }
  }

  private async showClearAllConfirmDialog(): Promise<void> {
    if (this.notes.length === 0) {
      return
    }
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.recycle_bin_clear_all_title'),
        message: $r('app.string.recycle_bin_clear_all_message'),
        buttons: [
          { text: $r('app.string.recycle_bin_clear_all_cancel'), color: '#8E8E93' },
          { text: $r('app.string.recycle_bin_clear_all_restore'), color: '#007AFF' },
          { text: $r('app.string.recycle_bin_clear_all_delete'), color: '#FF3B30' }
        ]
      })
      if (result.index === 1) {
        await this.handleRestoreAll()
      } else if (result.index === 2) {
        await this.handlePermanentDeleteAll()
      }
    } catch (error) {
      console.error(JSON.stringify(error))
    }
  }

  private noteKey(note: Note): string {
    return `${this.listRevision}:${note.id}:${note.title}:${note.summary}:${note.updatedAt}:${note.deleted}:${note.deletedTime}`
  }

  @Builder
  private buildToolbar() {
    Row() {
      Row() {
        Image($r('app.media.ic_back'))
          .width($r('app.float.toolbar_back_icon_size'))
          .height($r('app.float.toolbar_back_icon_size'))
          .objectFit(ImageFit.Contain)
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
        this.getUIContext().getRouter().back()
      })

      Row() {
        Text($r('app.string.recycle_bin_title'))
          .fontSize($r('app.float.title_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .textAlign(TextAlign.Center)
      }
      .layoutWeight(1)
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)

      Row() {
        Image($r('app.media.ic_recycle_clear_all'))
          .width($r('app.float.toolbar_back_icon_size'))
          .height($r('app.float.toolbar_back_icon_size'))
          .objectFit(ImageFit.Contain)
          .opacity(this.notes.length === 0 ? 0.35 : 1)
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
      .enabled(!this.loading && this.notes.length > 0)
      .onClick(() => {
        void this.showClearAllConfirmDialog()
      })
    }
    .width('100%')
    .height($r('app.float.toolbar_height'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildNoteRow(note: Note) {
    Column({ space: 0 }) {
      Row() {
        Column({ space: 8 }) {
          Row({ space: 6 }) {
            Text(note.title.length > 0 ? note.title : '无标题')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))
              .lineHeight(20)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(note.summary.length > 0 ? note.summary : '暂无摘要')
            .fontSize(13)
            .fontColor(note.summary.length > 0 ? $r('app.color.secondary_text') : $r('app.color.tertiary_text'))
            .lineHeight(18)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 2, right: 2, top: 14, bottom: 14 })
      .alignItems(VerticalAlign.Center)

      Text('')
        .width('100%')
        .height(1)
        .backgroundColor($r('app.color.divider'))
    }
    .padding({ left: 14, right: 12 })
    .width('100%')
  }

  @Builder
  private buildRecycleSwipeRestoreAction(note: Note) {
    Row() {
      Text('还原')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
    }
    .width(88)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.accent'))
    .onClick(() => {
      void this.handleRestore(note)
    })
  }

  @Builder
  private buildRecycleSwipeDeleteAction(note: Note) {
    Row() {
      Text('删除')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
    }
    .width(88)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.danger'))
    .onClick(() => {
      void this.handlePermanentDelete(note)
    })
  }

  @Builder
  private buildRecycleSwipeActions(note: Note) {
    Row() {
      this.buildRecycleSwipeRestoreAction(note)
      this.buildRecycleSwipeDeleteAction(note)
    }
    .width(176)
    .height('100%')
  }

  @Builder
  private buildEmptyState() {
    Column({ space: 16 }) {
      Text($r('app.string.recycle_bin_empty'))
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 72, bottom: 24 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private buildLoadingState() {
    Column({ space: 18 }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color($r('app.color.accent'))
      Text($r('app.string.recycle_bin_loading'))
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      this.buildToolbar()

      if (this.loading) {
        Column() {
          this.buildLoadingState()
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.notes.length === 0) {
        Column() {
          this.buildEmptyState()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        List() {
          ForEach(this.notes, (note: Note) => {
            ListItem() {
              this.buildNoteRow(note)
            }
            .width('100%')
            .swipeAction({
              end: {
                builder: () => {
                  this.buildRecycleSwipeActions(note)
                },
                actionAreaDistance: 176
              },
              edgeEffect: SwipeEdgeEffect.Spring
            })
          }, (note: Note) => this.noteKey(note))
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ bottom: 20 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: this.pageWidth >= 600 ? 28 : 16,
      right: this.pageWidth >= 600 ? 28 : 16,
    })
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_, value) => {
      const nextWidth = Number.parseFloat(`${value.width}`) || 360
      if (Math.abs(this.pageWidth - nextWidth) >= 1) {
        this.pageWidth = nextWidth
      }
    })
  }
}
