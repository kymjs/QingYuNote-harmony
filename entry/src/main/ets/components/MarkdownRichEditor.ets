import { fileUri } from '@kit.CoreFileKit'
import { MarkdownEditSession } from '../common/utils/MarkdownEditSession'
import { MarkdownEmbedKind, MarkdownEmbedMatcher } from '../common/utils/MarkdownEmbedMatcher'
import {
  MarkdownSyntaxHighlighter,
  MarkdownSyntaxTokenType
} from '../common/utils/MarkdownSyntaxHighlighter'
import { EditorLinkCard } from './EditorLinkCard'
import { CachedNetworkImage } from './CachedNetworkImage'
import {
  LinkOgMeta,
  LinkOgMetaService,
  linkOgFallback,
  linkOgLoading
} from '../services/LinkOgMetaService'
import { ImageCacheService } from '../services/ImageCacheService'
import { AppContextHolder } from '../services/AppContextHolder'
import { Logger } from '../common/utils/Logger'

const PLACEHOLDER = '\uFFFC'
const LOG_TAG = 'MarkdownRichEditor'

interface EmbedBinding {
  key: string
  kind: MarkdownEmbedKind
  label: string
  url: string
  raw: string
  breakBefore: boolean
  breakAfter: boolean
}

interface SpanPiece {
  offset: number
  value: string
}

interface ProjectedMarkdown {
  display: string
  bindings: EmbedBinding[]
}

/** 窄屏 flat：按正文估高铺满，供外层 Scroll 整体滚动（编辑区自身不竖滑）。 */
export function estimateMarkdownEditorHeight(content: string, minContentHeight: number): number {
  const minH = minContentHeight > 0 ? minContentHeight : 280
  const text = content.length > 0 ? content : ''
  const lines = Math.max(1, text.split('\n').length)
  const imageCount = (text.match(/!\[[^\]]*]\([^)]+\)/g) ?? []).length
  // 行高约 28，图片块约 220，段落余量 + 底部缓冲；宁高勿低，避免裁切后无法内滚补偿。
  const estimated = lines * 28 + 200 + Math.floor(text.length / 60) * 10 + imageCount * 220
  return Math.max(minH, Math.min(estimated, 20000))
}

/**
 * 编辑态单一富文本：RichEditor + 语法高亮 + 图片/链接 BuilderSpan。
 * - enterEditToken：进入编辑 / 预览切回 → onEnterEdit + 重建
 * - refreshToken：工具栏插入后重建（保留会话）
 * - toolbarSignal：`image|label|url` 或 `link|label|url`，触发 onToolbarInsert
 * - colorModeToken：深浅色切换后重建 span 色
 */
@Component
export struct MarkdownRichEditor {
  @Link @Watch('onContentLinkChange') content: string
  @Prop @Watch('onEnterEditToken') enterEditToken: number = 0
  @Prop @Watch('onRefreshToken') refreshToken: number = 0
  @Prop @Watch('onToolbarSignal') toolbarSignal: string = ''
  @Prop @Watch('onColorModeToken') colorModeToken: number = 0
  @Prop filesDir: string = ''
  /** 窄屏扁平：透明底、无圆角。 */
  @Prop flatChrome: boolean = false
  /** flatChrome 时最小高度（外层视口铺满高）。 */
  @Prop minContentHeight: number = 280
  onContentChange: () => void = () => {
  }
  onContentSelectionChange: (selectionStart: number, selectionEnd: number) => void =
    (_selectionStart: number, _selectionEnd: number) => {
    }

  private controller: RichEditorController = new RichEditorController()
  private options: RichEditorOptions = { controller: this.controller }
  private session: MarkdownEditSession = new MarkdownEditSession()
  private bindings: EmbedBinding[] = []
  private rebuilding: boolean = false
  private applyingSync: boolean = false
  private pendingRebuildAfterBusy: boolean = false
  private editorReady: boolean = false
  private syncTimerId: number = -1
  private lastToolbarSignal: string = ''
  private lastBuiltContent: string = '\u0000'
  @State private ogTick: number = 0
  private ogCache: Map<string, LinkOgMeta> = new Map()
  @State private layoutWidth: number = 360
  @State private layoutHeight: number = 0

  aboutToAppear(): void {
    Logger.info(LOG_TAG,
      `aboutToAppear contentLen=${this.content.length} enterEditToken=${this.enterEditToken} (wait onReady)`)
    this.session.onEnterEdit(this.content)
    // 不在此处 addTextSpan：RichEditor 未 ready 时写入会丢，表现为空白。
  }

  onContentLinkChange(): void {
    Logger.info(LOG_TAG,
      `onContentLinkChange len=${this.content.length} ready=${this.editorReady} rebuilding=${this.rebuilding}`)
    if (this.applyingSync) {
      return
    }
    if (this.content === this.lastBuiltContent) {
      return
    }
    this.session.onEnterEdit(this.content)
    this.requestRebuild('contentLink')
  }

  onEnterEditToken(): void {
    Logger.info(LOG_TAG,
      `onEnterEditToken=${this.enterEditToken} contentLen=${this.content.length} ready=${this.editorReady}`)
    this.session.onEnterEdit(this.content)
    this.requestRebuild('enterEditToken')
  }

  onRefreshToken(): void {
    Logger.info(LOG_TAG, `onRefreshToken=${this.refreshToken} contentLen=${this.content.length}`)
    this.requestRebuild('refreshToken')
  }

  onToolbarSignal(): void {
    if (this.toolbarSignal.length === 0 || this.toolbarSignal === this.lastToolbarSignal) {
      return
    }
    this.lastToolbarSignal = this.toolbarSignal
    const at = this.toolbarSignal.lastIndexOf('@')
    const body = at > 0 ? this.toolbarSignal.substring(0, at) : this.toolbarSignal
    const parts = body.split('|')
    if (parts.length < 3) {
      return
    }
    const kind = parts[0] === 'image' ? 'image' : 'link'
    const label = parts[1]
    const url = parts.slice(2).join('|')
    this.session.onToolbarInsert(kind as MarkdownEmbedKind, label, url, this.content)
    this.requestRebuild('toolbar')
  }

  onColorModeToken(): void {
    Logger.info(LOG_TAG, `onColorModeToken=${this.colorModeToken}`)
    this.requestRebuild('colorMode')
  }

  private requestRebuild(reason: string): void {
    if (!this.editorReady) {
      this.pendingRebuildAfterBusy = true
      Logger.warn(LOG_TAG, `requestRebuild(${reason}) deferred: editor not ready`)
      return
    }
    if (this.rebuilding) {
      this.pendingRebuildAfterBusy = true
      Logger.warn(LOG_TAG, `requestRebuild(${reason}) deferred: busy`)
      return
    }
    this.rebuildFromContent()
  }

  /** flatChrome：估高铺满全文，外层 Scroll 整体滚动。 */
  private flatEditorHeight(): number {
    return estimateMarkdownEditorHeight(this.content, this.minContentHeight)
  }

  /**
   * 拒绝内置竖滑：编辑区不可滚，手势交给外层页面 Scroll（单一滚动整体）。
   * 点击聚焦、输入仍保留。
   */
  private rejectBuiltInPan(
    _event: BaseGestureEvent,
    current: GestureRecognizer,
    _others: Array<GestureRecognizer>
  ): GestureJudgeResult {
    if (current.isBuiltIn() && current.getType() === GestureControl.GestureType.PAN_GESTURE) {
      return GestureJudgeResult.REJECT
    }
    return GestureJudgeResult.CONTINUE
  }

  private notifySelectionRange(start: number, end: number): void {
    if (this.rebuilding || start < 0) {
      return
    }
    const s = start
    const e = end >= 0 ? end : s
    this.onContentSelectionChange(s, e)
  }

  build() {
    if (this.flatChrome) {
      // 估高铺开 + 拒绝内置 Pan：全部竖滑由外层 Scroll 承担。
      RichEditor(this.options)
        .width('100%')
        .height(this.flatEditorHeight())
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .barState(BarState.Off)
        .onGestureRecognizerJudgeBegin((
          event: BaseGestureEvent,
          current: GestureRecognizer,
          others: Array<GestureRecognizer>
        ): GestureJudgeResult => {
          return this.rejectBuiltInPan(event, current, others)
        })
        .onReady(() => {
          this.editorReady = true
          Logger.info(LOG_TAG, `onReady(flat) contentLen=${this.content.length}`)
          this.session.onEnterEdit(this.content)
          this.rebuildFromContent()
        })
        .onAreaChange((_old: Area, neu: Area) => {
          const w = Number(neu.width)
          if (w > 0) {
            this.layoutWidth = w
          }
        })
        .onDidChange((_before: TextRange, _after: TextRange) => {
          if (this.rebuilding || !this.editorReady) {
            return
          }
          this.scheduleSyncFromEditor()
        })
        .onSelectionChange((value: RichEditorRange) => {
          const start = value.start !== undefined ? value.start : -1
          const end = value.end !== undefined ? value.end : start
          this.notifySelectionRange(start, end)
        })
    } else {
      RichEditor(this.options)
        .width('100%')
        .height('100%')
        .constraintSize({ minHeight: 120 })
        .backgroundColor($r('app.color.editor_background'))
        .borderRadius(12)
        .onReady(() => {
          this.editorReady = true
          Logger.info(LOG_TAG, `onReady contentLen=${this.content.length}`)
          this.session.onEnterEdit(this.content)
          this.rebuildFromContent()
        })
        .onAreaChange((_old: Area, neu: Area) => {
          const w = Number(neu.width)
          const h = Number(neu.height)
          if (w > 0) {
            this.layoutWidth = w
          }
          if (h > 0 && Math.abs(h - this.layoutHeight) > 1) {
            this.layoutHeight = h
            Logger.info(LOG_TAG, `onAreaChange w=${w} h=${h}`)
          }
        })
        .onDidChange((_before: TextRange, _after: TextRange) => {
          if (this.rebuilding || !this.editorReady) {
            return
          }
          this.scheduleSyncFromEditor()
        })
        .onSelectionChange((value: RichEditorRange) => {
          const start = value.start !== undefined ? value.start : -1
          const end = value.end !== undefined ? value.end : start
          this.notifySelectionRange(start, end)
        })
    }
  }

  private scheduleSyncFromEditor(): void {
    if (this.syncTimerId >= 0) {
      clearTimeout(this.syncTimerId)
    }
    this.syncTimerId = setTimeout(() => {
      this.syncTimerId = -1
      this.syncContentFromEditor()
    }, 80) as number
  }

  private syncContentFromEditor(): void {
    try {
      const spans = this.controller.getSpans({ start: 0, end: 1_000_000 })
      const display = this.displayFromSpans(spans)
      Logger.info(LOG_TAG,
        `syncFromEditor spans=${spans.length} displayLen=${display.length} contentLen=${this.content.length}`)
      if (display.length === 0 && this.content.length > 0) {
        Logger.warn(LOG_TAG, 'sync skipped: empty display while content non-empty')
        return
      }
      const phCount = display.split(PLACEHOLDER).length - 1
      let bindings = this.bindings
      if (phCount < bindings.length) {
        bindings = bindings.slice(0, phCount)
        this.bindings = bindings
      }
      const oldContent = this.content
      const next = this.reconstructMarkdown(display, bindings)
      if (next === oldContent) {
        return
      }
      if (next.length === 0 && oldContent.length > 0) {
        Logger.warn(LOG_TAG, 'sync skipped: would clear non-empty content')
        return
      }
      this.session.reindexAfterTextChange(oldContent, next)
      const richCount =
        MarkdownEmbedMatcher.findAll(next).filter((m) => this.session.shouldRenderRich(m)).length
      this.applyingSync = true
      this.content = next
      this.lastBuiltContent = next
      this.applyingSync = false
      this.onContentChange()
      if (richCount !== this.bindings.length) {
        this.rebuildFromContent()
      }
    } catch (e) {
      this.applyingSync = false
      Logger.error(LOG_TAG, `syncContentFromEditor error: ${JSON.stringify(e)}`)
    }
  }

  private displayFromSpans(spans: Array<RichEditorTextSpanResult | RichEditorImageSpanResult>): string {
    interface Event {
      offset: number
      kind: string
      value: string
    }
    const events: Event[] = []
    for (let i = 0; i < spans.length; i++) {
      const s = spans[i] as RichEditorTextSpanResult
      const start = s.spanPosition !== undefined ? s.spanPosition.spanRange[0] : 0
      if (s.value !== undefined && typeof s.value === 'string' && s.value.length > 0) {
        events.push({ offset: start, kind: 'text', value: s.value })
      } else {
        events.push({ offset: start, kind: 'ph', value: PLACEHOLDER })
      }
    }
    events.sort((a, b) => a.offset - b.offset)

    let display = ''
    let expected = 0
    let bi = 0
    for (let i = 0; i < events.length; i++) {
      const ev = events[i]
      while (expected < ev.offset && bi < this.bindings.length) {
        display += PLACEHOLDER
        expected += 1
        bi += 1
      }
      while (expected < ev.offset) {
        expected += 1
      }
      if (ev.kind === 'ph') {
        display += PLACEHOLDER
        if (bi < this.bindings.length) {
          bi += 1
        }
        expected += 1
      } else {
        display += ev.value
        expected = ev.offset + ev.value.length
      }
    }
    while (bi < this.bindings.length) {
      display += PLACEHOLDER
      bi += 1
    }
    return display
  }

  private reconstructMarkdown(display: string, bindings: EmbedBinding[]): string {
    let out = ''
    let bi = 0
    for (let i = 0; i < display.length; i++) {
      const ch = display.charAt(i)
      if (ch === '\n' &&
        bi < bindings.length &&
        bindings[bi].breakBefore &&
        i + 1 < display.length &&
        display.charAt(i + 1) === PLACEHOLDER) {
        continue
      }
      if (ch === PLACEHOLDER) {
        if (bi < bindings.length) {
          const b = bindings[bi]
          out += b.raw
          bi++
          if (b.breakAfter && i + 1 < display.length && display.charAt(i + 1) === '\n') {
            i++
          }
        }
      } else {
        out += ch
      }
    }
    return out
  }

  private rebuildFromContent(): void {
    if (!this.editorReady) {
      this.pendingRebuildAfterBusy = true
      Logger.warn(LOG_TAG, `rebuild skipped: not ready, contentLen=${this.content.length}`)
      return
    }
    Logger.info(LOG_TAG, `rebuild start contentLen=${this.content.length}`)
    this.rebuilding = true
    try {
      try {
        this.controller.deleteSpans({ start: 0, end: 1_000_000 })
        Logger.info(LOG_TAG, 'deleteSpans ok')
      } catch (e) {
        Logger.warn(LOG_TAG, `deleteSpans failed: ${JSON.stringify(e)}`)
      }

      const projected = this.project(this.content)
      this.bindings = projected.bindings
      Logger.info(LOG_TAG,
        `project displayLen=${projected.display.length} embedCount=${projected.bindings.length}`)
      try {
        this.addDisplayToEditor(projected.display, projected.bindings)
        // 校验 controller 内是否真有 span
        let spanCount = -1
        try {
          spanCount = this.controller.getSpans({ start: 0, end: 1_000_000 }).length
        } catch (_) {
        }
        Logger.info(LOG_TAG, `addDisplayToEditor ok, getSpansCount=${spanCount}`)
        if (spanCount === 0 && this.content.length > 0) {
          throw new Error('getSpans empty after add')
        }
      } catch (e) {
        Logger.error(LOG_TAG, `addDisplay failed, fallback plain: ${JSON.stringify(e)}`)
        try {
          this.controller.deleteSpans({ start: 0, end: 1_000_000 })
        } catch (_) {
        }
        if (this.content.length > 0) {
          this.controller.addTextSpan(this.content, {
            style: { fontColor: $r('app.color.primary_text'), fontSize: 16 }
          })
          this.bindings = []
          Logger.info(LOG_TAG, `fallback plain text added len=${this.content.length}`)
        }
      }
      this.lastBuiltContent = this.content
    } catch (e) {
      Logger.error(LOG_TAG, `rebuild fatal: ${JSON.stringify(e)}`)
    } finally {
      setTimeout((): void => {
        this.rebuilding = false
        Logger.info(LOG_TAG, `rebuild done contentLen=${this.content.length}`)
        if (this.pendingRebuildAfterBusy) {
          this.pendingRebuildAfterBusy = false
          Logger.info(LOG_TAG, `flush pendingRebuild contentLen=${this.content.length}`)
          this.session.onEnterEdit(this.content)
          this.rebuildFromContent()
        }
      }, 120)
    }
  }

  private project(source: string): ProjectedMarkdown {
    const matches = MarkdownEmbedMatcher.findAll(source)
    let display = ''
    const bindings: EmbedBinding[] = []
    let i = 0
    for (let mi = 0; mi < matches.length; mi++) {
      const m = matches[mi]
      if (!this.session.shouldRenderRich(m)) {
        continue
      }
      if (m.start > i) {
        display += source.substring(i, m.start)
      }
      // 独占一行，避免 ImageSpan/BuilderSpan 与上下文字叠画
      const useBreakBefore = display.length > 0 && !display.endsWith('\n')
      if (useBreakBefore) {
        display += '\n'
      }
      display += PLACEHOLDER
      const useBreakAfter = m.end < source.length && source.charAt(m.end) !== '\n'
      if (useBreakAfter) {
        display += '\n'
      }
      bindings.push({
        key: m.key,
        kind: m.kind,
        label: m.label,
        url: m.url,
        raw: m.raw,
        breakBefore: useBreakBefore,
        breakAfter: useBreakAfter
      })
      i = m.end
    }
    if (i < source.length) {
      display += source.substring(i)
    }
    Logger.info(LOG_TAG,
      `project displayLen=${display.length} embedCount=${bindings.length} sourceLen=${source.length}`)
    const result: ProjectedMarkdown = { display: display, bindings: bindings }
    return result
  }

  private addDisplayToEditor(display: string, bindings: EmbedBinding[]): void {
    let bi = 0
    let cursor = 0
    let textChunks = 0
    let embedChunks = 0
    for (let i = 0; i < display.length; i++) {
      if (display.charAt(i) !== PLACEHOLDER) {
        continue
      }
      if (i > cursor) {
        this.addHighlightedText(display.substring(cursor, i))
        textChunks++
      }
      if (bi < bindings.length) {
        this.addEmbedBuilder(bindings[bi])
        embedChunks++
        bi++
      }
      cursor = i + 1
    }
    if (cursor < display.length) {
      this.addHighlightedText(display.substring(cursor))
      textChunks++
    }
    if (display.length > 0 && textChunks === 0 && embedChunks === 0 &&
      display.indexOf(PLACEHOLDER) < 0) {
      this.addHighlightedText(display)
      textChunks = 1
    }
    Logger.info(LOG_TAG, `addDisplay textChunks=${textChunks} embedChunks=${embedChunks}`)
  }

  private addHighlightedText(segment: string): void {
    if (segment.length === 0) {
      return
    }
    const tokens = MarkdownSyntaxHighlighter.tokenize(segment)
    for (let i = 0; i < tokens.length; i++) {
      const t = tokens[i]
      const slice = segment.substring(t.start, t.end)
      if (slice.length === 0) {
        continue
      }
      this.controller.addTextSpan(slice, {
        style: this.styleFor(t.type)
      })
    }
  }

  private styleFor(type: MarkdownSyntaxTokenType): RichEditorTextStyle {
    if (type === 'h1') {
      return {
        fontColor: $r('app.color.primary_text'),
        fontWeight: FontWeight.Bold,
        fontSize: 16
      }
    }
    if (type === 'quote') {
      return { fontColor: $r('app.color.secondary_text'), fontSize: 16 }
    }
    if (type === 'italic') {
      return {
        fontColor: $r('app.color.accent'),
        fontStyle: FontStyle.Italic,
        fontSize: 16
      }
    }
    if (type === 'plain') {
      return { fontColor: $r('app.color.primary_text'), fontSize: 16 }
    }
    return { fontColor: $r('app.color.accent'), fontSize: 16 }
  }

  private addEmbedBuilder(binding: EmbedBinding): void {
    const key = binding.key
    const kind = binding.kind
    const label = binding.label
    const url = binding.url
    const cardW = Math.max(200, this.layoutWidth > 0 ? this.layoutWidth - 16 : 320)
    try {
      if (kind === 'image') {
        const src = ImageCacheService.isNetworkImageUrl(url) ? url : this.localImageUri(url)
        this.controller.addImageSpan(src, {
          imageStyle: {
            size: [cardW, 180],
            layoutStyle: {
              margin: { top: 10, bottom: 10 }
            }
          },
          gesture: {
            onClick: () => {
              Logger.info(LOG_TAG, `image tapped key=${key}`)
              this.session.onEmbedTapped(key)
              this.requestRebuild('imageTap')
              this.onContentChange()
            }
          }
        })
        Logger.info(LOG_TAG, `addImageSpan ok url=${url}`)
        return
      }

      // 链接：BuilderSpan 卡片（须在 onReady 之后调用）
      this.ensureOg(url, label)
      this.controller.addBuilderSpan((): void => {
        this.LinkEmbedBuilder(url, label, key)
      })
      Logger.info(LOG_TAG, `addBuilderSpan link ok url=${url}`)
    } catch (e) {
      Logger.error(LOG_TAG, `addEmbedBuilder failed, raw text: ${JSON.stringify(e)}`)
      this.addHighlightedText(binding.raw)
    }
  }

  private ensureOg(url: string, label: string): void {
    if (this.ogCache.has(url)) {
      return
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      this.ogCache.set(url, linkOgFallback())
      return
    }
    // 先放 loading，避免卡片空白
    this.ogCache.set(url, linkOgLoading(label))
    void LinkOgMetaService.getInstance().fetch(url, label).then((meta: LinkOgMeta) => {
      this.ogCache.set(url, meta)
      this.ogTick = this.ogTick + 1
      Logger.info(LOG_TAG, `og fetched url=${url} title=${meta.title}`)
      // 仅刷新卡片，不清除会话
      this.requestRebuild('ogReady')
    })
  }

  private ogMetaFor(url: string, label: string): LinkOgMeta {
    return this.ogCache.get(url) ?? linkOgLoading(label)
  }

  @Builder
  ImageEmbedBuilder(url: string, label: string, key: string) {
    Column() {
      if (ImageCacheService.isNetworkImageUrl(url)) {
        CachedNetworkImage({
          url: url,
          imageWidth: '100%',
          imageHeight: 160,
          imageBorderRadius: 8,
          objectFit: ImageFit.Contain,
          alt: label
        })
      } else {
        Image(this.localImageUri(url))
          .width('100%')
          .constraintSize({ maxHeight: 240 })
          .objectFit(ImageFit.Contain)
          .borderRadius(8)
      }
    }
    .width(Math.max(200, this.layoutWidth - 16))
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      this.session.onEmbedTapped(key)
      this.rebuildFromContent()
      this.onContentChange()
    })
  }

  @Builder
  LinkEmbedBuilder(url: string, label: string, key: string) {
    Column() {
      EditorLinkCard({
        meta: this.ogMetaFor(url, label),
        onCardTap: () => {
          this.session.onEmbedTapped(key)
          this.rebuildFromContent()
          this.onContentChange()
        }
      })
    }
    .width(Math.max(200, this.layoutWidth - 16))
    .padding({ top: 10, bottom: 10 })
  }

  private localImageUri(relativeOrAbs: string): string {
    let filePath = relativeOrAbs
    if (filePath.startsWith('file://')) {
      return filePath
    }
    if (!filePath.startsWith('/')) {
      let base = this.filesDir
      if (base.length === 0) {
        try {
          base = AppContextHolder.getContext().filesDir
        } catch (_) {
          base = ''
        }
      }
      filePath = base.length > 0 ? `${base}/${filePath}` : filePath
    }
    try {
      return fileUri.getUriFromPath(filePath)
    } catch (_) {
      return filePath
    }
  }
}
