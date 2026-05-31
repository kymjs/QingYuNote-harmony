import { webview } from '@kit.ArkWeb'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'

/** 设置页「用户反馈」飞书表单地址（与 Flutter `kFeedbackFormUrl` 对齐）。 */
const FEEDBACK_FORM_URL =
  'https://vcnedpub4ekz.feishu.cn/share/base/form/shrcnexjZUlhIkZ4eD9BjcDfdkb'

/** 隐藏飞书分享表单 AI 语音引导弹窗与底部录入按钮（与 Flutter `_kHideFeishuVoiceInputJs` 对齐）。 */
const HIDE_FEISHU_VOICE_INPUT_JS: string = `(function () {
  if (window.__qingyuHideFeishuVoiceInputInstalled) {
    return;
  }
  window.__qingyuHideFeishuVoiceInputInstalled = true;

  var STYLE_ID = 'qingyu-hide-feishu-voice-input-style';
  var SELECTORS = [
    '.mobile-voice-input-onboarding-guide',
    '.pc-voice-input-onboarding-guide',
    '.speech-input-button',
    '.speech-input-button-wrap',
    '.speech-input-container',
    '.speech-input-container-map',
    '.speech-input-content',
    '.speech-input-background',
    '.speech-input-recording-text',
    '.voice-toast',
    '.voice-toast-host',
    '.form-voice-quota-mobile-toast',
    '.share-form-text-ai-polish-actions--with-voice-input',
    '.share-form-pc-voice-drag-safe-areas',
    '[class*="speech-input"]',
    '[class*="voice-input-onboarding"]',
    '[class*="voice-toast"]'
  ].join(',');

  function injectStyle() {
    if (document.getElementById(STYLE_ID)) {
      return;
    }
    var style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent =
      SELECTORS +
      '{display:none!important;visibility:hidden!important;pointer-events:none!important;opacity:0!important;height:0!important;max-height:0!important;overflow:hidden!important;}';
    (document.head || document.documentElement).appendChild(style);
  }

  function hideElement(el) {
    if (!el || el.nodeType !== 1) {
      return;
    }
    el.style.setProperty('display', 'none', 'important');
    el.style.setProperty('visibility', 'hidden', 'important');
    el.style.setProperty('pointer-events', 'none', 'important');
  }

  function hideOnboardingWrappers() {
    document
      .querySelectorAll(
        '.mobile-voice-input-onboarding-guide, .pc-voice-input-onboarding-guide'
      )
      .forEach(function (el) {
        hideElement(el);
        var parent = el.parentElement;
        for (var depth = 0; depth < 8 && parent; depth++) {
          var className = parent.className;
          if (
            typeof className === 'string' &&
            (className.indexOf('ud__popover') >= 0 ||
              className.indexOf('ud__modal') >= 0 ||
              className.indexOf('mask') >= 0)
          ) {
            hideElement(parent);
          }
          parent = parent.parentElement;
        }
      });
  }

  function run() {
    injectStyle();
    try {
      document.querySelectorAll(SELECTORS).forEach(hideElement);
    } catch (_) {}
    hideOnboardingWrappers();
  }

  run();
  new MutationObserver(run).observe(document.documentElement, {
    childList: true,
    subtree: true
  });
  for (var i = 1; i <= 20; i++) {
    setTimeout(run, i * 500);
  }
})();`

function isFeedbackFormUrl(url: string): boolean {
  const trimmed = url.trim()
  if (trimmed.length === 0) {
    return false
  }
  return trimmed === FEEDBACK_FORM_URL || trimmed.includes('shrcnexjZUlhIkZ4eD9BjcDfdkb')
}

interface H5WebContainerParams {
  title?: string
  url?: string
}

@Entry
@Component
struct H5WebContainer {
  @State pageTitle: string = ''
  @State webUrl: string = 'about:blank'
  @State isLoading: boolean = false
  private webController: webview.WebviewController = new webview.WebviewController()
  private closeGuard = new PageCloseGuard()

  private shouldShowLoadingOverlay(): boolean {
    return this.isLoading &&
      (this.webUrl.startsWith('http://') || this.webUrl.startsWith('https://'))
  }

  aboutToAppear(): void {
    this.closeGuard.reset()
    try {
      const params = this.getUIContext().getRouter().getParams() as H5WebContainerParams
      const titleRaw = params?.title
      this.pageTitle =
        typeof titleRaw === 'string' && titleRaw.trim().length > 0 ? titleRaw.trim() : '网页'
      const urlRaw = params?.url
      const urlStr = typeof urlRaw === 'string' ? urlRaw.trim() : ''
      if (urlStr.length > 0 && (urlStr.startsWith('https://') || urlStr.startsWith('http://'))) {
        this.webUrl = urlStr
        this.isLoading = true
      } else {
        this.webUrl = 'about:blank'
        this.isLoading = false
        try {
          this.getUIContext().getPromptAction().showToast({
            message: '无效的链接',
            duration: 2000
          })
        } catch (_) {
          console.error('H5WebContainer invalid url toast failed')
        }
      }
    } catch (e) {
      console.error(`H5WebContainer aboutToAppear: ${JSON.stringify(e)}`)
      this.pageTitle = '网页'
      this.webUrl = 'about:blank'
      this.isLoading = false
    }
  }

  private handleToolbarBack(): void {
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'H5WebContainer')
  }

  onBackPress(): boolean {
    this.handleToolbarBack()
    return true
  }

  private hideFeishuVoiceInputIfNeeded(): void {
    if (!isFeedbackFormUrl(this.webUrl)) {
      return
    }
    try {
      this.webController.runJavaScript(HIDE_FEISHU_VOICE_INPUT_JS)
    } catch (e) {
      console.error(`H5WebContainer hideFeishuVoiceInput: ${JSON.stringify(e)}`)
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
          Text(this.pageTitle)
            .fontSize($r('app.float.title_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .alignItems(VerticalAlign.Center)

      Stack() {
        Web({ src: this.webUrl, controller: this.webController })
          .width('100%')
          .height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onPageBegin(() => {
            this.isLoading = true
          })
          .onPageEnd(() => {
            this.hideFeishuVoiceInputIfNeeded()
            this.isLoading = false
          })
          .onErrorReceive(() => {
            this.isLoading = false
          })
          .onHttpErrorReceive(() => {
            this.isLoading = false
          })

        if (this.shouldShowLoadingOverlay()) {
          Column({ space: 16 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color($r('app.color.accent'))
            Text('加载中…')
              .fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.secondary_text'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.app_background'))
        }
      }
      .width('100%')
      .layoutWeight(1)
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
