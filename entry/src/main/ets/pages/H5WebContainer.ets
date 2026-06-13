import { webview } from '@kit.ArkWeb'
import { http } from '@kit.NetworkKit'
import { abilityAccessCtrl, common } from '@kit.AbilityKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { util } from '@kit.ArkTS'
import { deviceInfo } from '@kit.BasicServicesKit'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'
import { WereadQrSaveBridge } from '../common/utils/WereadQrSaveBridge'
import { WebViewSessionCleaner } from '../common/utils/WebViewSessionCleaner'

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

/** 监听微信读书 Skill 页「复制 API Key」按钮的点击（与 Flutter `_kWatchWereadApiKeyCopyJs` 对齐）。 */
const WATCH_WEREAD_API_KEY_COPY_JS: string = `(function () {
  if (window.__qingyuWatchWereadApiKeyCopyInstalled) {
    return;
  }
  window.__qingyuWatchWereadApiKeyCopyInstalled = true;

  var BOUND_ATTR = 'data-qingyu-key-copy-bound';
  var DELAY_MS = 60;

  function notifyApiKeyCopied() {
    try {
      // 不再从 DOM 抓 key(WeRead 页面结构会变,DOM 抓取不可靠)。
      // 具体 key 的内容由原生侧读取系统剪贴板拿到;
      // 这里把 writeText 的入参透传给原生,作为剪贴板读取失败/被清空时的兑底。
      if (window.QingyuWereadBridge && typeof window.QingyuWereadBridge.onApiKeyCopied === 'function') {
        setTimeout(function () {
          try { window.QingyuWereadBridge.onApiKeyCopied(''); } catch (_) {}
        }, DELAY_MS);
      }
    } catch (_) {}
  }

  function isApiKeyCopyText(text) {
    if (!text) {
      return false;
    }
    var trimmed = String(text).trim();
    if (trimmed.length === 0 || trimmed.length > 30) {
      return false;
    }
    if (!/复制|copy/i.test(trimmed)) {
      return false;
    }
    if (!/key/i.test(trimmed)) {
      return false;
    }
    return true;
  }

  function findApiKeyCard() {
    var cards = document.querySelectorAll('.wr_skillsStepCard');
    for (var i = 0; i < cards.length; i++) {
      var card = cards[i];
      var h3 = card.querySelector('h3');
      if (h3 && (h3.textContent || '').indexOf('获取 API Key') >= 0) {
        return card;
      }
    }
    return null;
  }

  function bindCopyKeyInCard(card) {
    if (!card) {
      return false;
    }
    var candidates = card.querySelectorAll(
      'button, [role="button"], .ant-btn, a, div, span'
    );
    for (var i = 0; i < candidates.length; i++) {
      var el = candidates[i];
      if (el.getAttribute(BOUND_ATTR) === '1') {
        continue;
      }
      var text = el.textContent || '';
      if (!isApiKeyCopyText(text)) {
        continue;
      }
      el.setAttribute(BOUND_ATTR, '1');
      el.addEventListener('click', function () {
        notifyApiKeyCopied();
      }, true);
      return true;
    }
    return false;
  }

  function hookClipboard() {
    if (window.__qingyuWereadClipboardHooked) {
      return;
    }
    window.__qingyuWereadClipboardHooked = true;
    try {
      var cb = navigator.clipboard;
      if (!cb || typeof cb.writeText !== 'function') {
        return;
      }
      var original = cb.writeText.bind(cb);
      cb.writeText = function (text) {
        try {
          if (typeof text === 'string' && text.indexOf('wrk-') === 0) {
            notifyApiKeyCopied();
          }
        } catch (_) {}
        return original(text);
      };
    } catch (_) {}
  }

  function run() {
    hookClipboard();
    if (bindCopyKeyInCard(findApiKeyCard())) {
      return;
    }
    try {
      var all = document.querySelectorAll(
        'button, [role="button"], .ant-btn, a, div, span'
      );
      for (var j = 0; j < all.length; j++) {
        var node = all[j];
        if (node.getAttribute(BOUND_ATTR) === '1') {
          continue;
        }
        if (!isApiKeyCopyText(node.textContent || '')) {
          continue;
        }
        node.setAttribute(BOUND_ATTR, '1');
        node.addEventListener('click', function () {
          notifyApiKeyCopied();
        }, true);
        return;
      }
    } catch (_) {}
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

interface H5WebContainerParams {
  title?: string
  url?: string
}

interface PermissionRequestResult {
  permission: string
  grantStatus: number
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
  // 「复制 API Key」流程已被处理,防止用户连点/动画期间再次 Router.back() 把上一页(导入笔记页面)也弹掉
  private apiKeyHandled: boolean = false

  private shouldShowLoadingOverlay(): boolean {
    return this.isLoading &&
      (this.webUrl.startsWith('http://') || this.webUrl.startsWith('https://'))
  }

  aboutToAppear(): void {
    this.closeGuard.reset()
    this.qrSaveBridge.bind((payload: string) => {
      void this.saveWereadQr(payload)
    })
    this.qrSaveBridge.bindKeyCopied((key: string) => {
      this.handleApiKeyCopiedFromJs(key)
    })
    // 登出时统一清理缓存（与 Flutter `WebViewSessionCleaner.register` 对齐）。
    WebViewSessionCleaner.registerController(this.webController)
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

  aboutToDisappear(): void {
    WebViewSessionCleaner.unregisterController(this.webController)
  }

  private isMobileContainer(): boolean {
    return deviceInfo.deviceType !== '2in1'
  }

  private shouldEnableWereadQrBridge(): boolean {
    return isWereadSkillsUrl(this.webUrl) && this.isMobileContainer()
  }

  private async handleApiKeyCopiedFromJs(key: string): Promise<void> {
    if (!this.shouldEnableWereadQrBridge()) {
      return
    }
    if (this.apiKeyHandled) {
      return
    }
    this.apiKeyHandled = true
    // WeRead 的「复制 API Key」按钮在用户点击后通过 navigator.clipboard.writeText 把
    // wrk- 开头的 key 写入 WebView 剪贴板(HarmonyOS NEXT 上 WebView 剪贴板与系统剪贴板互通),
    // JS 侧只负责通知「Key 已被复制」,具体 key 的内容由原生侧读取系统剪贴板拿到。
    // 主动申请 READ_PASTEBOARD 用户授权(在点击复制按钮的瞬间触发,与 Flutter 行为对齐)。
    let trimmed: string = ''
    try {
      const granted = await this.requestReadPasteboardPermission()
      if (!granted) {
        console.error('H5WebContainer handleApiKeyCopiedFromJs: READ_PASTEBOARD denied')
        this.showToast('读取剪贴板权限被拒绝,无法自动导入 API Key')
        try {
          this.getUIContext().getRouter().back()
        } catch (e) {
          console.error(`H5WebContainer handleApiKeyCopiedFromJs back: ${JSON.stringify(e)}`)
        }
        return
      }
      const systemPasteboard = pasteboard.getSystemPasteboard()
      const data = await systemPasteboard.getData()
      const text = data.getPrimaryText()
      trimmed = (text ?? '').trim()
    } catch (e) {
      console.error(`H5WebContainer readClipboard: ${JSON.stringify(e)}`)
      try {
        this.getUIContext().getRouter().back()
      } catch (err) {
        console.error(`H5WebContainer handleApiKeyCopiedFromJs back: ${JSON.stringify(err)}`)
      }
      return
    }
    // 兜底:JS 侧 hook 时把 writeText 的参数(text)也带回来了,如果读剪贴板失败/被清空,
    // 可以用 key 参数兜底(只有当 text 看起来像 wrk- key 时)。
    if ((trimmed.length === 0 || trimmed.indexOf('wrk-') !== 0) &&
      typeof key === 'string') {
      const fromJs = key.trim()
      if (fromJs.length > 0 && fromJs.indexOf('wrk-') === 0) {
        trimmed = fromJs
      }
    }
    if (trimmed.length > 0 && trimmed.indexOf('wrk-') === 0) {
      try {
        AppStorage.setOrCreate<string>('pendingWereadApiKey', trimmed)
      } catch (e) {
        console.error(`H5WebContainer setAppStorage: ${JSON.stringify(e)}`)
      }
    } else {
      console.error(`H5WebContainer handleApiKeyCopiedFromJs: invalid clipboard content`)
      this.showToast('剪贴板内容不是有效的微信读书 API Key')
    }
    // 只关 WebView;启动导入由导入笔记页面 onPageShow 统一处理。
    try {
      this.getUIContext().getRouter().back()
    } catch (e) {
      console.error(`H5WebContainer handleApiKeyCopiedFromJs: ${JSON.stringify(e)}`)
    }
  }

  private async requestReadPasteboardPermission(): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager()
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      const result = await atManager.requestPermissionsFromUser(context, ['ohos.permission.READ_PASTEBOARD'])
      if (!Array.isArray(result)) {
        return false
      }
      return result.some((r: PermissionRequestResult) =>
        r.permission === 'ohos.permission.READ_PASTEBOARD' &&
        r.grantStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
      )
    } catch (e) {
      console.error(`H5WebContainer requestReadPasteboardPermission: ${JSON.stringify(e)}`)
      return false
    }
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
    this.watchWereadApiKeyCopyIfNeeded()
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

  private watchWereadApiKeyCopyIfNeeded(): void {
    if (!isWereadSkillsUrl(this.webUrl) || !this.isMobileContainer()) {
      return
    }
    try {
      this.webController.runJavaScript(WATCH_WEREAD_API_KEY_COPY_JS)
    } catch (e) {
      console.error(`H5WebContainer watchWereadApiKeyCopy: ${JSON.stringify(e)}`)
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
            methodList: ['saveQrImage', 'onApiKeyCopied'],
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
