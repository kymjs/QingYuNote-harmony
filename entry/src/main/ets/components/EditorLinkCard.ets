import { CachedNetworkImage } from './CachedNetworkImage'
import {
  LinkOgMeta,
  linkOgMetaLine
} from '../services/LinkOgMetaService'
import { ImageCacheService } from '../services/ImageCacheService'

@Component
export struct EditorLinkCard {
  @Prop meta: LinkOgMeta = {
    title: '网页链接',
    author: '未知来源',
    date: '—',
    description: '暂时无法获取该链接的详细信息',
    imageUrl: '',
    isFallback: true
  }
  onCardTap: () => void = () => {
  }

  build() {
    Row({ space: 10 }) {
      this.Thumb()
      Column({ space: 4 }) {
        Text(this.meta.title)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(linkOgMetaLine(this.meta))
          .fontSize(12)
          .fontColor($r('app.color.tertiary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.meta.description)
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(10)
    .backgroundColor($r('app.color.app_background'))
    .borderRadius(12)
    .onClick(() => {
      this.onCardTap()
    })
  }

  @Builder
  Thumb() {
    if (ImageCacheService.isNetworkImageUrl(this.meta.imageUrl)) {
      CachedNetworkImage({
        url: this.meta.imageUrl,
        imageWidth: 56,
        imageHeight: 56,
        imageBorderRadius: 8,
        objectFit: ImageFit.Cover
      })
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.link'))
          .fontSize(22)
          .fontColor([$r('app.color.tertiary_text')])
      }
      .width(56)
      .height(56)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.card_border'))
      .borderRadius(8)
    }
  }
}
