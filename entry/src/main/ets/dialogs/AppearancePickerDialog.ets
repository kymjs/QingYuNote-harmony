import { ComponentContent, UIContext } from '@kit.ArkUI'
import { LocaleService } from '../services/LocaleService'
import type { AppThemeMode } from '../common/utils/AppTheme'

export interface AppearancePickerDialogParams {
  selected: AppThemeMode
  onSelect: (mode: AppThemeMode) => void
  onDismiss: () => void
}

@Component
struct AppearancePickerDialog {
  @Prop params: AppearancePickerDialogParams = {
    selected: 'system',
    onSelect: (_: AppThemeMode): void => {},
    onDismiss: (): void => {}
  }

  @Builder
  optionRow(mode: AppThemeMode, label: string) {
    Row() {
      Text(label)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .layoutWeight(1)
      if (this.params.selected === mode) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([$r('app.color.accent')])
      }
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 14, bottom: 14 })
    .onClick(() => {
      this.params.onSelect(mode)
    })
  }

  build() {
    Column({ space: 4 }) {
      Text(LocaleService.loc('外观', 'Appearance', '外観'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
        .margin({ bottom: 8 })
      this.optionRow('system', LocaleService.loc('跟随系统', 'System', 'システムに合わせる'))
      Divider().color($r('app.color.card_border'))
      this.optionRow('light', LocaleService.loc('浅色', 'Light', 'ライト'))
      Divider().color($r('app.color.card_border'))
      this.optionRow('dark', LocaleService.loc('深色', 'Dark', 'ダーク'))
    }
    .width('85%')
    .constraintSize({ maxWidth: 400 })
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.card_radius'))
    .border({ width: 1, color: $r('app.color.card_border') })
    .shadow({
      radius: 20,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 4
    })
    .alignItems(HorizontalAlign.Start)
  }
}

@Builder
function buildAppearancePickerDialogContent(params: AppearancePickerDialogParams): void {
  AppearancePickerDialog({ params: params })
}

/**
 * 外观三选一弹窗（对齐 Flutter SimpleDialog）。
 * @returns 选中的模式；点蒙层取消则返回 null。
 */
export function showAppearancePickerDialog(
  uiContext: UIContext,
  selected: AppThemeMode
): Promise<AppThemeMode | null> {
  return new Promise((resolve) => {
    let settled: boolean = false
    let holder: ComponentContent<AppearancePickerDialogParams> | undefined = undefined
    const finish = (mode: AppThemeMode | null): void => {
      if (settled) {
        return
      }
      settled = true
      if (holder !== undefined) {
        try {
          uiContext.getPromptAction().closeCustomDialog(holder)
        } catch (_) {
          // ignore
        }
      }
      resolve(mode)
    }
    const params: AppearancePickerDialogParams = {
      selected: selected,
      onSelect: (mode: AppThemeMode): void => {
        finish(mode)
      },
      onDismiss: (): void => {
        finish(null)
      }
    }
    holder = new ComponentContent(uiContext, wrapBuilder(buildAppearancePickerDialogContent), params)
    try {
      uiContext.getPromptAction().openCustomDialog(holder, {
        alignment: DialogAlignment.Center,
        autoCancel: true,
        isModal: true,
        onWillDismiss: (action: DismissDialogAction) => {
          action.dismiss()
          finish(null)
        }
      })
    } catch (error) {
      console.error(`showAppearancePickerDialog failed: ${JSON.stringify(error)}`)
      resolve(null)
    }
  })
}
