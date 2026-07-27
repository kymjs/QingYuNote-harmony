import { EditorUiStrings } from '../common/utils/EditorUiStrings'
import { LinkUrlUtils } from '../common/utils/LinkUrlUtils'
import { PreferencesService } from '../services/PreferencesService'

export interface EditorAiLinkExtractDialogParams {
  onCancel: () => void
  onConfirm: (url: string, summarize: number) => void
}

@Component
export struct EditorAiLinkExtractDialog {
  @Prop params: EditorAiLinkExtractDialogParams = {
    onCancel: (): void => {},
    onConfirm: (_: string, __: number): void => {}
  }
  @State urlDraft: string = ''
  @State summaryEnabled: boolean = true
  @State prefLoaded: boolean = false

  aboutToAppear(): void {
    void this.loadPref()
  }

  private async loadPref(): Promise<void> {
    const enabled = await PreferencesService.getInstance().isAiLinkExtractSummaryEnabled()
    this.summaryEnabled = enabled
    this.prefLoaded = true
  }

  private canConfirm(): boolean {
    return LinkUrlUtils.extractFirstUrl(this.urlDraft) !== null
  }

  private async onSummaryChanged(value: boolean): Promise<void> {
    this.summaryEnabled = value
    await PreferencesService.getInstance().setAiLinkExtractSummaryEnabled(value)
  }

  @Builder
  private labeledTrackSwitch() {
    Row() {
      if (this.summaryEnabled) {
        Text(EditorUiStrings.loc('摘要提取', 'Summary', '要約抽出'))
          .fontSize(9)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .margin({ left: 4 })
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Clip })
        Circle({ width: 22, height: 22 })
          .fill(Color.White)
          .margin({ right: 2 })
      } else {
        Circle({ width: 22, height: 22 })
          .fill(Color.White)
          .margin({ left: 2 })
        Text(EditorUiStrings.loc('全文提取', 'Full text', '全文抽出'))
          .fontSize(9)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .margin({ right: 4 })
          .layoutWeight(1)
          .textAlign(TextAlign.End)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Clip })
      }
    }
    .width(71.5)
    .height(28)
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .borderRadius(14)
    .backgroundColor($r('app.color.accent'))
    .onClick(() => {
      void this.onSummaryChanged(!this.summaryEnabled)
    })
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Text(EditorUiStrings.loc('AI提取链接', 'AI extract link', 'AIでリンク抽出'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.prefLoaded) {
          this.labeledTrackSwitch()
        } else {
          Row()
            .width(71.5)
            .height(28)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      TextInput({ text: this.urlDraft, placeholder: EditorUiStrings.loc('链接', 'Link', 'リンク') })
        .fontSize($r('app.float.body_font_size'))
        .width('100%')
        .onChange((v: string) => {
          this.urlDraft = v
        })
      Row({ space: 12 }) {
        Button(EditorUiStrings.loc('取消', 'Cancel', 'キャンセル'))
          .layoutWeight(1)
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.pill_radius'))
          .padding({ top: 12, bottom: 12 })
          .onClick(() => {
            this.params.onCancel()
          })
        Button(EditorUiStrings.loc('确定', 'OK', 'OK'))
          .layoutWeight(1)
          .fontSize($r('app.float.body_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.canConfirm() ? $r('app.color.on_accent') : $r('app.color.secondary_text'))
          .backgroundColor(this.canConfirm() ? $r('app.color.accent') : $r('app.color.surface_muted'))
          .borderRadius($r('app.float.pill_radius'))
          .padding({ top: 12, bottom: 12 })
          .enabled(this.canConfirm())
          .onClick(() => {
            const url = LinkUrlUtils.extractFirstUrl(this.urlDraft)
            if (url !== null) {
              this.params.onConfirm(url, this.summaryEnabled ? 1 : 0)
            }
          })
      }
      .width('100%')
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
export function buildEditorAiLinkExtractDialogContent(params: EditorAiLinkExtractDialogParams): void {
  EditorAiLinkExtractDialog({ params: params })
}
