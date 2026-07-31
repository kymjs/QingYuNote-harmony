import { EditorLinkCard } from './EditorLinkCard'
import {
  LinkOgMeta,
  LinkOgMetaService,
  linkOgLoading
} from '../services/LinkOgMetaService'

/** 预览/分享：单独成段链接的 OG 卡片。 */
@Component
export struct PreviewStandaloneLinkCard {
  @Prop @Watch('onHrefOrLabelChange') href: string = ''
  @Prop @Watch('onHrefOrLabelChange') label: string = ''
  onCardTap: () => void = () => {
  }

  @State private meta: LinkOgMeta = linkOgLoading('')
  private lastFetchKey: string = ''

  aboutToAppear(): void {
    this.loadMeta()
  }

  onHrefOrLabelChange(): void {
    this.loadMeta()
  }

  private loadMeta(): void {
    const url = this.href.trim()
    const key = `${url}|${this.label}`
    if (url.length === 0) {
      this.meta = linkOgLoading(this.label)
      return
    }
    if (key === this.lastFetchKey) {
      return
    }
    this.lastFetchKey = key
    this.meta = linkOgLoading(this.label)
    void LinkOgMetaService.getInstance().fetch(url, this.label).then((meta: LinkOgMeta) => {
      if (this.href.trim() !== url) {
        return
      }
      this.meta = meta
    })
  }

  build() {
    Column() {
      EditorLinkCard({
        meta: this.meta,
        onCardTap: () => {
          this.onCardTap()
        }
      })
    }
    .width('100%')
  }
}
