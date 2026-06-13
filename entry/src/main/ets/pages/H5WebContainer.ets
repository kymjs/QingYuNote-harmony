import { webview } from '@kit.ArkWeb'
import { http } from '@kit.NetworkKit'
import { common } from '@kit.AbilityKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { util } from '@kit.ArkTS'
import { deviceInfo } from '@kit.BasicServicesKit'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'
import { WereadQrSaveBridge } from '../common/utils/WereadQrSaveBridge'

/** 微信读书 Skill / API Key 页（导入笔记「获取 API Key」入口，与 Flutter `kWereadSkillsUrl` 对齐）。 */
const WEREAD_SKILLS_URL = 'https://weread.qq.com/r/weread-skills'

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

/** 内置浏览器打开微信读书 Skill 页时，隐藏与 API Key 无关的营销与 Skill 安装步骤（与 Flutter 对齐）。 */
const HIDE_WEREAD_SKILLS_EXTRA_JS: string = `(function () {
  if (window.__qingyuHideWereadSkillsExtraInstalled) {
    return;
  }
  window.__qingyuHideWereadSkillsExtraInstalled = true;

  var STYLE_ID = 'qingyu-hide-weread-skills-extra-style';

  function injectStyle() {
    if (document.getElementById(STYLE_ID)) {
      return;
    }
    var style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent =
      '.wr_skillsFeaturesSection,.wr_skillsSetup_header,.wr_skillsStepCard.qingyu-wr-hidden,.wr_skillsStepNum.qingyu-wr-hidden{display:none!important;visibility:hidden!important;pointer-events:none!important;height:0!important;max-height:0!important;overflow:hidden!important;margin:0!important;padding:0!important;}html,body,.wr_skillsPage{background:#f4f5f7!important;}.wr_skillsSetupSection{background:#f4f5f7!important;margin-top:0!important;padding-top:70px!important;}@media (min-width:641px){.wr_skillsSetupSection{padding-top:170px!important;}}';
    (document.head || document.documentElement).appendChild(style);
  }

  function hideElement(el) {
    if (!el || el.nodeType !== 1) {
      return;
    }
    el.style.setProperty('display', 'none', 'important');
    el.style.setProperty('visibility', 'hidden', 'important');
    el.style.setProperty('pointer-events', 'none', 'important');
    el.classList.add('qingyu-wr-hidden');
  }

  function containsText(el, text) {
    if (!el) {
      return false;
    }
    return (el.textContent || '').indexOf(text) >= 0;
  }

  var LOGIN_HINT_NEW = '请截图保存到本地，导入微信后识别登录';
  var LONG_PRESS_MS = 500;

  function isMobileViewport() {
    return (
      window.matchMedia('(max-width: 640px)').matches ||
      /Android|iPhone|iPod|Mobile|HarmonyOS/i.test(navigator.userAgent)
    );
  }

  function notifySaveQr(payload) {
    if (!payload) {
      return;
    }
    try {
      if (window.QingyuWereadBridge) {
        if (typeof window.QingyuWereadBridge.postMessage === 'function') {
          window.QingyuWereadBridge.postMessage(payload);
          return;
        }
        if (typeof window.QingyuWereadBridge.saveQrImage === 'function') {
          window.QingyuWereadBridge.saveQrImage(payload);
        }
      }
    } catch (_) {}
  }

  function getQrPayload(node) {
    if (!node) {
      return '';
    }
    var tag = (node.tagName || '').toUpperCase();
    if (tag === 'IMG') {
      return node.src || '';
    }
    if (tag === 'CANVAS') {
      try {
        return node.toDataURL('image/png');
      } catch (_) {}
    }
    var img = node.querySelector('img');
    if (img && img.src) {
      return img.src;
    }
    var canvas = node.querySelector('canvas');
    if (canvas) {
      try {
        return canvas.toDataURL('image/png');
      } catch (_) {}
    }
    return '';
  }

  function bindQrLongPress(node) {
    if (!node || node.getAttribute('data-qingyu-qr-save') === '1') {
      return;
    }
    node.setAttribute('data-qingyu-qr-save', '1');
    var timer = null;
    function clearTimer() {
      if (timer) {
        clearTimeout(timer);
        timer = null;
      }
    }
    function onLongPress() {
      notifySaveQr(getQrPayload(node));
    }
    node.addEventListener(
      'touchstart',
      function () {
        clearTimer();
        timer = setTimeout(onLongPress, LONG_PRESS_MS);
      },
      { passive: true }
    );
    node.addEventListener('touchend', clearTimer);
    node.addEventListener('touchmove', clearTimer);
    node.addEventListener('touchcancel', clearTimer);
    node.addEventListener('contextmenu', function (e) {
      e.preventDefault();
      onLongPress();
    });
  }

  function patchLoginModalMobile() {
    if (!isMobileViewport()) {
      return;
    }
    try {
      document.querySelectorAll('.wr_login_modal_lang').forEach(function (el) {
        var text = (el.textContent || '').replace(/\\s+/g, '');
        if (text.indexOf('扫一扫') >= 0 || text.indexOf('微信读书') >= 0) {
          el.textContent = LOGIN_HINT_NEW;
        }
      });
    } catch (_) {}
    try {
      [
        '.wr_login_modal_qr_img',
        '.wr_login_modal_qr_wrapper img',
        '.wr_login_modal_qr_wrapper canvas',
        '.login_qrcode_container img',
        '.login_qrcode_container canvas'
      ].forEach(function (selector) {
        document.querySelectorAll(selector).forEach(bindQrLongPress);
      });
      document
        .querySelectorAll('.wr_login_modal_qr_wrapper,.login_qrcode_container')
        .forEach(bindQrLongPress);
    } catch (_) {}
  }

  function run() {
    injectStyle();
    try {
      document.querySelectorAll('.wr_skillsFeaturesSection,.wr_skillsSetup_header').forEach(hideElement);
    } catch (_) {}
    try {
      document.querySelectorAll('.wr_skillsStepCard').forEach(function (card) {
        var h3 = card.querySelector('h3');
        if (h3 && containsText(h3, '复制 Skill 安装指令')) {
          hideElement(card);
          return;
        }
        if (h3 && containsText(h3, '获取 API Key')) {
          var num = card.querySelector('.wr_skillsStepNum');
          if (num) {
            hideElement(num);
          }
        }
      });
    } catch (_) {}
    patchLoginModalMobile();
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

function isWereadSkillsUrl(url: string): boolean {
  const trimmed = url.trim()
  if (trimmed.length === 0) {
    return false
  }
  return trimmed === WEREAD_SKILLS_URL || trimmed.includes('/r/weread-skills')
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
  private qrSaveBridge: WereadQrSaveBridge = new WereadQrSaveBridge()
  private readonly base64: util.Base64Helper = new util.Base64Helper()

  private shouldShowLoadingOverlay(): boolean {
    return this.isLoading &&
      (this.webUrl.startsWith('http://') || this.webUrl.startsWith('https://'))
  }

  aboutToAppear(): void {
    this.closeGuard.reset()
    this.qrSaveBridge.bind((payload: string) => {
      void this.saveWereadQr(payload)
    })
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

  private isMobileContainer(): boolean {
    return deviceInfo.deviceType !== '2in1'
  }

  private shouldEnableWereadQrBridge(): boolean {
    return isWereadSkillsUrl(this.webUrl) && this.isMobileContainer()
  }

  private showToast(message: string): void {
    if (message.trim().length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message.trim(),
        duration: 2000
      })
    } catch (_) {
    }
  }

  private async saveWereadQrToGallery(cachePath: string): Promise<boolean> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    const helper = photoAccessHelper.getPhotoAccessHelper(context)
    const srcFileUris: Array<string> = [fileUri.getUriFromPath(cachePath)]
    const photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [
      {
        title: `weread_login_qr_${Date.now()}`,
        fileNameExtension: 'png',
        photoType: photoAccessHelper.PhotoType.IMAGE,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT
      }
    ]
    const destUris: Array<string> =
      await helper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs)
    if (destUris.length === 0) {
      return false
    }
    const src = fileIo.openSync(cachePath, fileIo.OpenMode.READ_ONLY)
    const dest = await fileIo.open(destUris[0], fileIo.OpenMode.WRITE_ONLY)
    await fileIo.copyFile(src.fd, dest.fd)
    fileIo.closeSync(src)
    fileIo.closeSync(dest)
    return true
  }

  private async saveWereadQr(payload: string): Promise<void> {
    const trimmed = payload.trim()
    if (trimmed.length === 0 || !this.shouldEnableWereadQrBridge()) {
      return
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    const cachePath = `${context.cacheDir}/weread_login_qr_${Date.now()}.png`
    try {
      if (trimmed.startsWith('data:')) {
        const comma = trimmed.indexOf(',')
        if (comma < 0) {
          this.showToast('保存失败，请稍后重试')
          return
        }
        const bytes = this.base64.decodeSync(trimmed.substring(comma + 1), util.Type.BASIC)
        const f = fileIo.openSync(cachePath,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
        const outBuf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)
        fileIo.writeSync(f.fd, outBuf)
        fileIo.closeSync(f)
      } else {
        const req = http.createHttp()
        try {
          const resp = await req.request(trimmed, {
            method: http.RequestMethod.GET,
            expectDataType: http.HttpDataType.ARRAY_BUFFER,
            connectTimeout: 20000,
            readTimeout: 20000
          })
          if (resp.responseCode !== 200 || resp.result === undefined) {
            this.showToast('保存失败，请稍后重试')
            return
          }
          const f = fileIo.openSync(cachePath,
            fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
          fileIo.writeSync(f.fd, resp.result as ArrayBuffer)
          fileIo.closeSync(f)
        } finally {
          req.destroy()
        }
      }
      const ok = await this.saveWereadQrToGallery(cachePath)
      if (ok) {
        this.showToast('已保存到相册')
      }
    } catch (error) {
      console.error(`H5WebContainer saveWereadQr: ${JSON.stringify(error)}`)
      this.showToast('保存失败，请稍后重试')
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

  private runPageScriptsIfNeeded(): void {
    this.hideFeishuVoiceInputIfNeeded()
    this.hideWereadSkillsExtraIfNeeded()
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

  private hideWereadSkillsExtraIfNeeded(): void {
    if (!isWereadSkillsUrl(this.webUrl)) {
      return
    }
    try {
      this.webController.runJavaScript(HIDE_WEREAD_SKILLS_EXTRA_JS)
    } catch (e) {
      console.error(`H5WebContainer hideWereadSkillsExtra: ${JSON.stringify(e)}`)
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
          .javaScriptProxy({
            object: this.qrSaveBridge,
            name: 'QingyuWereadBridge',
            methodList: ['saveQrImage'],
            controller: this.webController
          })
          .onPageBegin(() => {
            this.isLoading = true
          })
          .onPageEnd(() => {
            this.runPageScriptsIfNeeded()
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
