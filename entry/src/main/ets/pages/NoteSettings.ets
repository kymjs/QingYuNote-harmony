import { PreferencesService } from '../services/PreferencesService'
import { AppContextHolder } from '../services/AppContextHolder'

@Entry
@Component
struct NoteSettings {
  @State quickActionBarEnabled: boolean = true
  @State loading: boolean = true

  aboutToAppear(): void {
    void this.loadSettings()
  }

  onPageShow(): void {
    void this.loadSettings()
  }

  private async loadSettings(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    this.quickActionBarEnabled =
      await PreferencesService.getInstance().getNoteQuickActionBarEnabled()
    this.loading = false
  }

  private async setQuickActionBarEnabled(enabled: boolean): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    await PreferencesService.getInstance().setNoteQuickActionBarEnabled(enabled)
    this.quickActionBarEnabled = enabled
  }

  private toggleQuickActionBar(): void {
    void this.setQuickActionBarEnabled(!this.quickActionBarEnabled)
  }

  build() {
    Column() {
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
          Text($r('app.string.note_settings_title'))
            .fontSize($r('app.float.title_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .textAlign(TextAlign.Start)
        }
        .layoutWeight(1)
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .alignItems(VerticalAlign.Center)

      if (this.loading) {
        LoadingProgress()
          .width(36)
          .height(36)
          .margin({ top: 48 })
      } else {
        Scroll() {
          Column({ space: 12 }) {
            Column({ space: 0 }) {
              Row() {
                Text($r('app.string.note_quick_action_bar'))
                  .fontSize($r('app.float.body_font_size'))
                  .fontColor($r('app.color.primary_text'))
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.quickActionBarEnabled })
                  .selectedColor($r('app.color.accent'))
                  .hitTestBehavior(HitTestMode.None)
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
                this.toggleQuickActionBar()
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
