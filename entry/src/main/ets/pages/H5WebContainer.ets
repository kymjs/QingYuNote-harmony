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
import { YoudaoApiKeyBridge } from '../common/utils/YoudaoApiKeyBridge'
import { YinxiangApiKeyBridge } from '../common/utils/YinxiangApiKeyBridge'
import { QingyuVipBridge } from '../common/utils/QingyuVipBridge'
import { isQingyuVipPageUrl, vipPageLangQuery } from '../common/utils/OpenQingyuVipPage'
import { PreferencesService } from '../services/PreferencesService'
import { QingyuVipPayService } from '../services/QingyuVipPayService'
import { WebViewSessionCleaner } from '../common/utils/WebViewSessionCleaner'

/** 微信读书 Skill / API Key 页（导入笔记「获取 API Key」入口，与 Flutter `kWereadSkillsUrl` 对齐）。 */
const WEREAD_SKILLS_URL = 'https://weread.qq.com/r/weread-skills'

/** 有道云笔记 mopen 申请 API Key 页（与 Flutter `kYoudaoSkillsUrl` 对齐）。 */
const YOUDAO_API_KEY_URL = 'https://mopen.163.com'

/** 印象笔记 Developer Token 申请页（与 Flutter `kYinxiangSkillsUrl` 对齐）。 */
const YINXIANG_API_KEY_URL = 'https://app.yinxiang.com/api/DeveloperToken.action'

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

function isYoudaoApiKeyUrl(url: string): boolean {
  const trimmed = url.trim()
  if (trimmed.length === 0) {
    return false
  }
  return trimmed.startsWith(YOUDAO_API_KEY_URL) || trimmed.includes('mopen.163.com')
}

function isYinxiangApiKeyUrl(url: string): boolean {
  const trimmed = url.trim()
  if (trimmed.length === 0) {
    return false
  }
  return trimmed.startsWith(YINXIANG_API_KEY_URL) || trimmed.includes('/api/DeveloperToken.action')
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

/** 有道云 mopen 申请 API Key 流程（与 Flutter `_kYoudaoApiKeyPageJs` 对齐）：
 *  1) 进入"创建 API Key"弹窗时，把名称自动填成"轻羽云笔记"并自动点创建按钮；
 *  2) "API Key 已生成"弹窗在移动端全屏宽；
 *  3) 点击"复制"按钮时通过 `QingyuYoudaoApiKeyBridge` 通知原生层读取系统剪贴板并关掉 WebView。 */
const YOUDAO_API_KEY_PAGE_JS: string = `(function () {
  if (window.__qingyuYoudaoApiKeyPageInstalled) {
    return;
  }
  window.__qingyuYoudaoApiKeyPageInstalled = true;

  var DEFAULT_NAME = '轻羽云笔记';
  var NAME_FILL_ATTR = 'data-qingyu-youdao-name-filled';
  var CREATE_CLICK_ATTR = 'data-qingyu-youdao-create-clicked';
  var COPY_BOUND_ATTR = 'data-qingyu-youdao-copy-bound';
  var DIALOG_PATCHED_ATTR = 'data-qingyu-youdao-dialog-patched';

  function isMobileViewport() {
    return (
      window.matchMedia('(max-width: 640px)').matches ||
      /Android|iPhone|iPod|Mobile|HarmonyOS/i.test(navigator.userAgent)
    );
  }

  function notifyApiKeyCopied() {
    try {
      if (window.QingyuYoudaoApiKeyBridge &&
          typeof window.QingyuYoudaoApiKeyBridge.onApiKeyCopied === 'function') {
        setTimeout(function () {
          try { window.QingyuYoudaoApiKeyBridge.onApiKeyCopied(''); } catch (_) {}
        }, 60);
      }
    } catch (_) {}
  }

  function isNameInput(el) {
    if (!el || el.nodeType !== 1) {
      return false;
    }
    var tag = (el.tagName || '').toUpperCase();
    if (tag !== 'INPUT' && tag !== 'TEXTAREA') {
      return false;
    }
    var type = (el.getAttribute('type') || 'text').toLowerCase();
    if (type === 'hidden' || type === 'file' || type === 'checkbox' || type === 'radio') {
      return false;
    }
    var placeholder = el.getAttribute('placeholder') || '';
    var ariaLabel = el.getAttribute('aria-label') || '';
    var name = el.getAttribute('name') || el.getAttribute('id') || '';
    var combined = (placeholder + ' ' + ariaLabel + ' ' + name).toLowerCase();
    if (combined.indexOf('name') >= 0 || combined.indexOf('名称') >= 0 ||
        combined.indexOf('应用') >= 0 || combined.indexOf('app') >= 0) {
      return true;
    }
    return false;
  }

  function isCreateButton(el) {
    if (!el || el.nodeType !== 1) {
      return false;
    }
    var tag = (el.tagName || '').toUpperCase();
    if (tag !== 'BUTTON' && tag !== 'A' && tag !== 'DIV' && tag !== 'SPAN') {
      return false;
    }
    var role = (el.getAttribute('role') || '').toLowerCase();
    if (tag === 'BUTTON' || role === 'button') {
      // OK
    } else if (tag !== 'A') {
      return false;
    }
    var text = (el.textContent || '').replace(/\\s+/g, '').toLowerCase();
    if (!text) {
      return false;
    }
    if (text.indexOf('创建') >= 0 || text.indexOf('生成') >= 0 ||
        text.indexOf('create') >= 0 || text.indexOf('submit') >= 0 ||
        text.indexOf('确定') >= 0 || text.indexOf('confirm') >= 0) {
      if (text === '取消' || text === 'cancel') {
        return false;
      }
      return true;
    }
    return false;
  }

  function setInputValue(el, value) {
    if (!el) {
      return;
    }
    try {
      var proto = el.tagName === 'TEXTAREA'
        ? window.HTMLTextAreaElement.prototype
        : window.HTMLInputElement.prototype;
      var setter = Object.getOwnPropertyDescriptor(proto, 'value');
      if (setter && setter.set) {
        setter.set.call(el, value);
      } else {
        el.value = value;
      }
    } catch (_) {
      try { el.value = value; } catch (__) {}
    }
    try {
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      el.dispatchEvent(new Event('blur', { bubbles: true }));
    } catch (_) {}
  }

  function tryAutoFillAndCreate() {
    try {
      var dialogs = document.querySelectorAll(
        '.ant-modal, .el-dialog, .ant-drawer, [role="dialog"], [class*="modal"], [class*="dialog"], [class*="Modal"], [class*="Dialog"]'
      );
      var scopes = dialogs.length > 0 ? Array.from(dialogs) : [document.body];
      for (var s = 0; s < scopes.length; s++) {
        var scope = scopes[s];
        var inputs = scope.querySelectorAll('input, textarea');
        for (var i = 0; i < inputs.length; i++) {
          var input = inputs[i];
          if (input.getAttribute(NAME_FILL_ATTR) === '1') {
            continue;
          }
          if (!isNameInput(input)) {
            continue;
          }
          input.setAttribute(NAME_FILL_ATTR, '1');
          setInputValue(input, DEFAULT_NAME);
        }
        var buttons = scope.querySelectorAll(
          'button, [role="button"], a, .ant-btn, .el-button, div[class*="button"]'
        );
        for (var b = 0; b < buttons.length; b++) {
          var btn = buttons[b];
          if (btn.getAttribute(CREATE_CLICK_ATTR) === '1') {
            continue;
          }
          if (!isCreateButton(btn)) {
            continue;
          }
          if (scopes.length > 1 && scope.contains(btn)) {
            btn.setAttribute(CREATE_CLICK_ATTR, '1');
            setTimeout(function () {
              try { btn.click(); } catch (_) {}
            }, 200);
          } else if (scopes.length === 1) {
            btn.setAttribute(CREATE_CLICK_ATTR, '1');
            setTimeout(function () {
              try { btn.click(); } catch (_) {}
            }, 200);
          }
        }
      }
    } catch (_) {}
  }

  function findSuccessDialog() {
    var candidates = document.querySelectorAll(
      '.ant-modal, .el-dialog, [role="dialog"], [class*="modal"], [class*="dialog"], [class*="Modal"], [class*="Dialog"]'
    );
    for (var i = 0; i < candidates.length; i++) {
      var d = candidates[i];
      var text = (d.textContent || '');
      if (text.indexOf('API Key') >= 0 || text.indexOf('已生成') >= 0 ||
          text.indexOf('生成成功') >= 0 || text.indexOf('已创建') >= 0) {
        return d;
      }
    }
    return null;
  }

  function patchSuccessDialogWidth() {
    if (!isMobileViewport()) {
      return;
    }
    try {
      var dialog = findSuccessDialog();
      if (!dialog) {
        return;
      }
      if (dialog.getAttribute(DIALOG_PATCHED_ATTR) === '1') {
        return;
      }
      dialog.setAttribute(DIALOG_PATCHED_ATTR, '1');
      dialog.style.setProperty('width', '100vw', 'important');
      dialog.style.setProperty('max-width', '100vw', 'important');
      dialog.style.setProperty('min-width', '0', 'important');
      dialog.style.setProperty('left', '0', 'important');
      dialog.style.setProperty('right', '0', 'important');
      dialog.style.setProperty('margin', '0', 'important');
      dialog.style.setProperty('transform', 'none', 'important');
      try {
        var inner = dialog.querySelectorAll(
          '.el-dialog__body, .ant-modal-body, .ant-modal-content, .el-dialog, [class*="body"], [class*="content"]'
        );
        for (var i = 0; i < inner.length; i++) {
          var el = inner[i];
          el.style.setProperty('width', '100%', 'important');
          el.style.setProperty('max-width', '100%', 'important');
        }
      } catch (_) {}
    } catch (_) {}
  }

  function isCopyButton(el) {
    if (!el || el.nodeType !== 1) {
      return false;
    }
    var tag = (el.tagName || '').toUpperCase();
    if (tag !== 'BUTTON' && tag !== 'A' && tag !== 'DIV' && tag !== 'SPAN' &&
        tag !== 'I' && tag !== 'SVG') {
      return false;
    }
    var role = (el.getAttribute('role') || '').toLowerCase();
    if (tag === 'BUTTON' || role === 'button') {
      // OK
    } else if (tag !== 'A') {
      var cls = (el.getAttribute('class') || '').toLowerCase();
      if (cls.indexOf('copy') < 0 && cls.indexOf('clipboard') < 0) {
        return false;
      }
    }
    var text = (el.textContent || '').replace(/\\s+/g, '').toLowerCase();
    if (text.indexOf('复制') >= 0 || text.indexOf('copy') >= 0) {
      return true;
    }
    var ariaLabel = (el.getAttribute('aria-label') || '').toLowerCase();
    if (ariaLabel.indexOf('复制') >= 0 || ariaLabel.indexOf('copy') >= 0) {
      return true;
    }
    return false;
  }

  function bindCopyButton() {
    try {
      var dialog = findSuccessDialog();
      var scope = dialog || document.body;
      var candidates = scope.querySelectorAll(
        'button, [role="button"], a, .ant-btn, .el-button, div, span, i, svg'
      );
      for (var i = 0; i < candidates.length; i++) {
        var el = candidates[i];
        if (el.getAttribute(COPY_BOUND_ATTR) === '1') {
          continue;
        }
        if (!isCopyButton(el)) {
          continue;
        }
        el.setAttribute(COPY_BOUND_ATTR, '1');
        el.addEventListener('click', function () {
          notifyApiKeyCopied();
        }, true);
        return true;
      }
    } catch (_) {}
    return false;
  }

  function hookClipboard() {
    if (window.__qingyuYoudaoClipboardHooked) {
      return;
    }
    window.__qingyuYoudaoClipboardHooked = true;
    try {
      var cb = navigator.clipboard;
      if (!cb || typeof cb.writeText !== 'function') {
        return;
      }
      var original = cb.writeText.bind(cb);
      cb.writeText = function (text) {
        try {
          if (typeof text === 'string' && text.length > 8) {
            notifyApiKeyCopied();
          }
        } catch (_) {}
        return original(text);
      };
    } catch (_) {}
  }

  function run() {
    hookClipboard();
    tryAutoFillAndCreate();
    patchSuccessDialogWidth();
    bindCopyButton();
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

/** 印象笔记 Developer Token 页（与 Flutter `_kYinxiangApiKeyPageJs` 对齐）：
 *  1) 无 Token 时自动点击「Create a developer token」；
 *  2) 检测到 Developer Token 与 NoteStore URL 后通知原生层保存并关闭 WebView。 */
const YINXIANG_API_KEY_PAGE_JS: string = `(function () {
  if (window.__qingyuYinxiangApiKeyPageInstalled) {
    return;
  }
  window.__qingyuYinxiangApiKeyPageInstalled = true;

  var CREATE_CLICKED_ATTR = 'data-qingyu-yinxiang-create-clicked';
  var NOTIFIED_ATTR = 'data-qingyu-yinxiang-notified';
  var DELAY_MS = 80;

  function isDeveloperToken(text) {
    if (!text) {
      return false;
    }
    var t = String(text).trim();
    return t.indexOf('S=') === 0 && t.length > 10;
  }

  function isNoteStoreUrl(text) {
    if (!text) {
      return false;
    }
    var t = String(text).trim();
    return /^https?:\\/\\/.+\\/notestore/i.test(t);
  }

  function collectFieldValues() {
    var values = [];
    try {
      var nodes = document.querySelectorAll('input, textarea, pre, code, a, span, p, li, td');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        var val = '';
        if (el.value !== undefined && el.value !== null && String(el.value).trim()) {
          val = String(el.value).trim();
        } else {
          val = String(el.textContent || '').trim();
        }
        if (val) {
          values.push(val);
        }
      }
    } catch (_) {}
    return values;
  }

  function extractCredentials() {
    var token = '';
    var noteStoreUrl = '';
    var values = collectFieldValues();
    for (var i = 0; i < values.length; i++) {
      var v = values[i];
      if (!token && isDeveloperToken(v)) {
        token = v;
      }
      if (!noteStoreUrl && isNoteStoreUrl(v)) {
        noteStoreUrl = v;
      }
    }
    if (!token || !noteStoreUrl) {
      try {
        var bodyText = document.body ? (document.body.innerText || '') : '';
        if (!token) {
          var tokenMatch = bodyText.match(/S=[^\\s"'<>]+/);
          if (tokenMatch && tokenMatch[0]) {
            token = tokenMatch[0].trim();
          }
        }
        if (!noteStoreUrl) {
          var urlMatch = bodyText.match(/https?:\\/\\/[^\\s"'<>]+notestore[^\\s"'<>]*/i);
          if (urlMatch && urlMatch[0]) {
            noteStoreUrl = urlMatch[0].trim();
          }
        }
      } catch (_) {}
    }
    return { token: token, noteStoreUrl: noteStoreUrl };
  }

  function notifyTokenReady(token, noteStoreUrl) {
    try {
      if (window.QingyuYinxiangApiKeyBridge &&
          typeof window.QingyuYinxiangApiKeyBridge.onTokenReady === 'function') {
        setTimeout(function () {
          try { window.QingyuYinxiangApiKeyBridge.onTokenReady(token || '', noteStoreUrl || ''); } catch (_) {}
        }, DELAY_MS);
      }
    } catch (_) {}
    try {
      var cb = navigator.clipboard;
      if (cb && typeof cb.writeText === 'function' && token) {
        cb.writeText(token);
      }
    } catch (_) {}
  }

  function isCreateDevTokenButton(el) {
    if (!el || el.nodeType !== 1) {
      return false;
    }
    var text = (el.textContent || el.value || '').replace(/\\s+/g, ' ').trim().toLowerCase();
    if (!text) {
      return false;
    }
    return text.indexOf('create a developer token') >= 0 ||
      text.indexOf('create developer token') >= 0;
  }

  function tryClickCreateButton() {
    try {
      var candidates = document.querySelectorAll(
        'button, input[type="submit"], input[type="button"], a, [role="button"]'
      );
      for (var i = 0; i < candidates.length; i++) {
        var el = candidates[i];
        if (el.getAttribute(CREATE_CLICKED_ATTR) === '1') {
          continue;
        }
        if (!isCreateDevTokenButton(el)) {
          continue;
        }
        el.setAttribute(CREATE_CLICKED_ATTR, '1');
        setTimeout(function () {
          try { el.click(); } catch (_) {}
        }, 300);
        return true;
      }
    } catch (_) {}
    return false;
  }

  function run() {
    var creds = extractCredentials();
    if (creds.token) {
      if (document.documentElement.getAttribute(NOTIFIED_ATTR) === '1') {
        return;
      }
      document.documentElement.setAttribute(NOTIFIED_ATTR, '1');
      notifyTokenReady(creds.token, creds.noteStoreUrl);
      return;
    }
    tryClickCreateButton();
  }

  run();
  new MutationObserver(run).observe(document.documentElement, {
    childList: true,
    subtree: true
  });
  for (var i = 1; i <= 30; i++) {
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
  private youdaoBridge: YoudaoApiKeyBridge = new YoudaoApiKeyBridge()
  private yinxiangBridge: YinxiangApiKeyBridge = new YinxiangApiKeyBridge()
  private vipBridge: QingyuVipBridge = new QingyuVipBridge()
  private vipSessionCache: string = '{}'
  private readonly base64: util.Base64Helper = new util.Base64Helper()
  // 「复制 API Key」流程已被处理,防止用户连点/动画期间再次 Router.back() 把上一页(导入笔记页面)也弹掉
  private apiKeyHandled: boolean = false
  // 有道云「复制 API Key」流程的独立守卫,避免和微信读书互相干扰
  private youdaoApiKeyHandled: boolean = false
  // 印象笔记 Developer Token 流程的独立守卫
  private yinxiangApiKeyHandled: boolean = false

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
    this.youdaoBridge.bindKeyCopied((key: string) => {
      this.handleYoudaoApiKeyCopiedFromJs(key)
    })
    this.yinxiangBridge.bindTokenReady((token: string, noteStoreUrl: string) => {
      void this.handleYinxiangTokenFromJs(token, noteStoreUrl)
    })
    this.vipBridge.bindClose(() => {
      this.handleToolbarBack()
    })
    this.vipBridge.bindSessionProvider(() => this.vipSessionCache)
    this.vipBridge.bindPay((planId: string, requestId: string) => {
      void this.handleVipPayFromJs(planId, requestId)
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

  private shouldEnableYoudaoApiKeyBridge(): boolean {
    return isYoudaoApiKeyUrl(this.webUrl) && this.isMobileContainer()
  }

  private shouldEnableYinxiangApiKeyBridge(): boolean {
    return isYinxiangApiKeyUrl(this.webUrl) && this.isMobileContainer()
  }

  /** 印象笔记 Developer Token 页检测到 Token 后：持久化 Token / NoteStore URL，写入 AppStorage 并关闭 WebView。 */
  private async handleYinxiangTokenFromJs(token: string, noteStoreUrl: string): Promise<void> {
    if (!this.shouldEnableYinxiangApiKeyBridge()) {
      return
    }
    if (this.yinxiangApiKeyHandled) {
      return
    }
    const trimmed = (token ?? '').trim()
    if (trimmed.length === 0 || trimmed.indexOf('S=') !== 0) {
      return
    }
    this.yinxiangApiKeyHandled = true
    const noteStore = (noteStoreUrl ?? '').trim()
    try {
      await PreferencesService.getInstance().setYinxiangApiKey(trimmed)
      if (noteStore.length > 0) {
        await PreferencesService.getInstance().setYinxiangNoteStoreUrl(noteStore)
      }
    } catch (e) {
      console.error(`H5WebContainer handleYinxiangTokenFromJs savePrefs: ${JSON.stringify(e)}`)
    }
    try {
      AppStorage.setOrCreate<string>('pendingYinxiangApiKey', trimmed)
    } catch (e) {
      console.error(`H5WebContainer handleYinxiangTokenFromJs setAppStorage: ${JSON.stringify(e)}`)
    }
    try {
      this.getUIContext().getRouter().back()
    } catch (e) {
      console.error(`H5WebContainer handleYinxiangTokenFromJs back: ${JSON.stringify(e)}`)
    }
  }

  /** 有道云 mopen 申请 API Key 流程的「复制」回调：
   * 主动申请 READ_PASTEBOARD 权限,读取系统剪贴板内容,写入 AppStorage 后关闭 WebView。 */
  private async handleYoudaoApiKeyCopiedFromJs(key: string): Promise<void> {
    if (!this.shouldEnableYoudaoApiKeyBridge()) {
      return
    }
    if (this.youdaoApiKeyHandled) {
      return
    }
    this.youdaoApiKeyHandled = true
    // 与微信读书流程保持一致：申请系统剪贴板读权限。
    let trimmed: string = ''
    try {
      const granted = await this.requestReadPasteboardPermission()
      if (!granted) {
        console.error('H5WebContainer handleYoudaoApiKeyCopiedFromJs: READ_PASTEBOARD denied')
        this.showToast('读取剪贴板权限被拒绝,无法自动导入 API Key')
        try {
          this.getUIContext().getRouter().back()
        } catch (e) {
          console.error(`H5WebContainer handleYoudaoApiKeyCopiedFromJs back: ${JSON.stringify(e)}`)
        }
        return
      }
      const systemPasteboard = pasteboard.getSystemPasteboard()
      const data = await systemPasteboard.getData()
      const text = data.getPrimaryText()
      trimmed = (text ?? '').trim()
    } catch (e) {
      console.error(`H5WebContainer handleYoudaoApiKeyCopiedFromJs readClipboard: ${JSON.stringify(e)}`)
      try {
        this.getUIContext().getRouter().back()
      } catch (err) {
        console.error(`H5WebContainer handleYoudaoApiKeyCopiedFromJs back: ${JSON.stringify(err)}`)
      }
      return
    }
    // 兜底:如果系统剪贴板为空(用户授权后又手动清空),用 JS 传回的 key 兜底。
    if (trimmed.length === 0 && typeof key === 'string') {
      const fromJs = key.trim()
      if (fromJs.length > 0) {
        trimmed = fromJs
      }
    }
    if (trimmed.length > 0) {
      try {
        AppStorage.setOrCreate<string>('pendingYoudaoApiKey', trimmed)
      } catch (e) {
        console.error(`H5WebContainer handleYoudaoApiKeyCopiedFromJs setAppStorage: ${JSON.stringify(e)}`)
      }
    } else {
      console.error('H5WebContainer handleYoudaoApiKeyCopiedFromJs: empty clipboard content')
      this.showToast('剪贴板内容为空,无法自动导入 API Key')
    }
    // 只关 WebView;启动导入由导入笔记页面 onPageShow 统一处理。
    try {
      this.getUIContext().getRouter().back()
    } catch (e) {
      console.error(`H5WebContainer handleYoudaoApiKeyCopiedFromJs: ${JSON.stringify(e)}`)
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
    this.patchYoudaoApiKeyPageIfNeeded()
    this.patchYinxiangApiKeyPageIfNeeded()
    void this.pushVipSessionIfNeeded()
  }

  private async handleVipPayFromJs(planId: string, requestId: string): Promise<void> {
    if (!isQingyuVipPageUrl(this.webUrl)) {
      return
    }
    const result = await QingyuVipPayService.getInstance().startPay(planId)
    if (result.message.trim().length > 0) {
      this.showToast(result.message)
    }
    const payload: Record<string, string> = {
      'type': 'payResult',
      'requestId': requestId,
      'status': result.status,
      'message': result.message
    }
    this.emitVipNativeEvent(JSON.stringify(payload))
  }

  private async pushVipSessionIfNeeded(): Promise<void> {
    if (!isQingyuVipPageUrl(this.webUrl)) {
      return
    }
    try {
      const json = await QingyuVipPayService.getInstance().buildSessionJson(vipPageLangQuery())
      this.vipSessionCache = json
      this.emitVipNativeEvent(json)
    } catch (e) {
      console.error(`H5WebContainer pushVipSession: ${JSON.stringify(e)}`)
    }
  }

  private emitVipNativeEvent(json: string): void {
    try {
      this.webController.runJavaScript(
        `window.__qingyuVipOnNativeEvent && window.__qingyuVipOnNativeEvent(${json});`
      )
    } catch (e) {
      console.error(`H5WebContainer emitVipNativeEvent: ${JSON.stringify(e)}`)
    }
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

  private patchYoudaoApiKeyPageIfNeeded(): void {
    if (!isYoudaoApiKeyUrl(this.webUrl) || !this.isMobileContainer()) {
      return
    }
    try {
      this.webController.runJavaScript(YOUDAO_API_KEY_PAGE_JS)
    } catch (e) {
      console.error(`H5WebContainer patchYoudaoApiKeyPage: ${JSON.stringify(e)}`)
    }
  }

  private patchYinxiangApiKeyPageIfNeeded(): void {
    if (!isYinxiangApiKeyUrl(this.webUrl) || !this.isMobileContainer()) {
      return
    }
    try {
      this.webController.runJavaScript(YINXIANG_API_KEY_PAGE_JS)
    } catch (e) {
      console.error(`H5WebContainer patchYinxiangApiKeyPage: ${JSON.stringify(e)}`)
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
          .javaScriptProxy({
            object: this.youdaoBridge,
            name: 'QingyuYoudaoApiKeyBridge',
            methodList: ['onApiKeyCopied'],
            controller: this.webController
          })
          .javaScriptProxy({
            object: this.yinxiangBridge,
            name: 'QingyuYinxiangApiKeyBridge',
            methodList: ['onTokenReady'],
            controller: this.webController
          })
          .javaScriptProxy({
            object: this.vipBridge,
            name: 'QingyuVipBridge',
            methodList: ['pay', 'close', 'getSession'],
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
