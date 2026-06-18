import { AppContextHolder } from '../services/AppContextHolder'
import { LocaleService, APP_LOCALE_REVISION_KEY, type AppLanguage } from '../services/LocaleService'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'

@Entry
@Component
struct LanguageSettings {
  @StorageProp(APP_LOCALE_REVISION_KEY) @Watch('onLocaleChanged') localeRevision: number = 0
  @State selected: AppLanguage = 'zh'
  private closeGuard = new PageCloseGuard()

  aboutToAppear(): void {
    this.selected = LocaleService.getInstance().getLanguage()
  }

  private handleToolbarBack(): void {
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'LanguageSettings')
  }

  onBackPress(): boolean {
    this.handleToolbarBack()
    return true
  }

  onLocaleChanged(): void {
    this.selected = LocaleService.getInstance().getLanguage()
  }

  private async selectLanguage(language: AppLanguage): Promise<void> {
    if (this.selected === language) {
      return
    }
    const context = AppContextHolder.tryGetContext()
    await LocaleService.getInstance().setLanguage(language, context)
    this.selected = language
  }

  @Builder
  private buildOption(language: AppLanguage, label: string) {
    Row() {
      Text(label)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .layoutWeight(1)
      if (this.selected === language) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([$r('app.color.accent')])
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
      void this.selectLanguage(language)
    })
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
          Text($r('app.string.language_settings_title'))
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
        Column() {
          Column({ space: 0 }) {
            this.buildOption('zh', '简体中文')
            Divider()
              .color($r('app.color.divider'))
              .strokeWidth(1)
            this.buildOption('zh-Hant', '繁體中文')
            Divider()
              .color($r('app.color.divider'))
              .strokeWidth(1)
            this.buildOption('en', 'English')
            Divider()
              .color($r('app.color.divider'))
              .strokeWidth(1)
            this.buildOption('ja', '日本語')
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
        .alignItems(HorizontalAlign.Start)
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
