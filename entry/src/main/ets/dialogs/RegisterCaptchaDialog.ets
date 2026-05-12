import image from '@ohos.multimedia.image'
import { util } from '@kit.ArkTS'

import { AppContextHolder } from '../services/AppContextHolder'
import { NoteApiClient } from '../services/NoteApiClient'
import { PreferencesService } from '../services/PreferencesService'

/** 注册发短信前：图形验证码 + 短信接口（与 Flutter `_RegisterCaptchaDialog` 对齐）。 */
export interface RegisterCaptchaDialogParams {
  phone: string
  onDismiss: () => void
  onSmsSent: () => void
}

@Component
export struct RegisterCaptchaDialog {
  @Prop params: RegisterCaptchaDialogParams = {
    phone: '',
    onDismiss: (): void => {},
    onSmsSent: (): void => {}
  }
  @State captchaId: string = ''
  @State imagePixelMap: image.PixelMap | null = null
  @State loadingCaptcha: boolean = true
  @State captchaLoadError: string = ''
  @State draftCode: string = ''
  @State submitting: boolean = false

  private readonly base64: util.Base64Helper = new util.Base64Helper()

  aboutToAppear(): void {
    void (async (): Promise<void> => {
      await this.ensurePrefsInit()
      await this.refreshCaptcha()
    })()
  }

  private async ensurePrefsInit(): Promise<void> {
    const ctx = AppContextHolder.tryGetContext()
    if (ctx !== undefined) {
      await PreferencesService.getInstance().init(ctx)
    }
  }

  aboutToDisappear(): void {
    this.releasePixelMap()
  }

  private releasePixelMap(): void {
    const pm = this.imagePixelMap
    this.imagePixelMap = null
    if (pm !== null) {
      try {
        pm.release()
      } catch (_) {
        // ignore
      }
    }
  }

  private filterDigits(v: string): string {
    let s = ''
    for (let i = 0; i < v.length; i++) {
      const c = v.charAt(i)
      if (c >= '0' && c <= '9') {
        s += c
      }
    }
    if (s.length > 8) {
      s = s.substring(0, 8)
    }
    return s
  }

  /**
   * 将服务端 `image_base64`（Go `encoding/base64.StdEncoding`）解码为 PNG 再转 PixelMap。
   * 须使用 `Uint8Array` 对应区间的 `ArrayBuffer` 切片再交给 `createImageSource`：直接传整段 `buffer`
   * 在部分机型上会把 padding 后的无关尾部字节一并解码，导致 PNG 解码失败。
   */
  private async decodeCaptchaPngToPixelMap(imageBase64: string): Promise<image.PixelMap | null> {
    const trimmed = imageBase64.trim()
    if (trimmed.length === 0) {
      return null
    }
    let raw: Uint8Array
    try {
      raw = this.base64.decodeSync(trimmed, util.Type.BASIC)
    } catch (e) {
      console.error(`RegisterCaptchaDialog base64 decode: ${JSON.stringify(e)}`)
      return null
    }
    if (raw.length === 0) {
      return null
    }
    const ab = raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength)
    const src = image.createImageSource(ab)
    try {
      return await src.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 })
    } catch (e) {
      console.error(`RegisterCaptchaDialog createPixelMap: ${JSON.stringify(e)}`)
      return null
    } finally {
      try {
        await src.release()
      } catch (_) {
        // ignore
      }
    }
  }

  private async refreshCaptcha(): Promise<void> {
    this.loadingCaptcha = true
    this.captchaLoadError = ''
    this.releasePixelMap()
    const bundle = await NoteApiClient.getInstance().fetchRegisterCaptchaNew()
    if (bundle === null) {
      this.loadingCaptcha = false
      this.captchaLoadError = '加载失败，请检查网络'
      return
    }
    this.captchaId = bundle.captcha_id
    const pm = await this.decodeCaptchaPngToPixelMap(bundle.image_base64)
    if (pm === null) {
      this.loadingCaptcha = false
      this.captchaLoadError = '图片加载失败'
      return
    }
    this.imagePixelMap = pm
    this.loadingCaptcha = false
    this.captchaLoadError = ''
  }

  /** 注册发短信步骤错误映射；`sms_quota_exceeded` 见 `server/TECHNICAL.md` §2.11，对用户仅泛化提示。 */
  private mapErr(code: string): string {
    switch (code.trim()) {
      case 'captcha_required':
        return '请先完成图形验证'
      case 'captcha_invalid':
        return '图形验证码错误'
      case 'sms_not_configured':
        return '短信服务未配置'
      case 'already_registered':
        return '该手机号已注册'
      case 'invalid_phone':
        return '手机号格式无效'
      case 'sms_rate_limited':
        return '发送过于频繁，请稍后再试'
      case 'sms_limit_exceeded':
        return '今日发送次数已达上限'
      case 'sms_quota_exceeded':
        return '发送过于频繁，请稍后再试'
      case 'sms_send_failed':
        return '短信发送失败（请查看服务端日志中的阿里云返回详情）'
      case 'sms_feature_not_opened':
        return '请在阿里云开通号码认证/短信认证后再试'
      case 'sms_invalid_params':
        return '短信模板参数无效，请核对 ALIYUN_SMS_TEMPLATE_PARAM'
      case 'sms_sign_template_mismatch':
        return '签名或模板与控制台不一致，请核对赠送签名与模板 CODE'
      case 'sms_aliyun_auth':
        return '阿里云访问密钥或 RAM 权限有误'
      case 'sms_client_failed':
        return '短信服务暂时不可用'
      case 'invalid_body':
        return '请求无效'
      case 'network_error':
        return '网络异常'
      default:
        return '发送失败'
    }
  }

  private showToast(message: string): void {
    const msg = message.trim()
    if (msg.length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 })
    } catch (_) {
      console.error(`RegisterCaptchaDialog toast: ${msg}`)
    }
  }

  private async onConfirm(): Promise<void> {
    const code = this.filterDigits(this.draftCode)
    if (code.length === 0) {
      this.showToast('请输入图形验证码')
      return
    }
    if (this.submitting || this.captchaId.length === 0 || this.loadingCaptcha) {
      return
    }
    this.submitting = true
    const err =
      await NoteApiClient.getInstance().sendRegisterSms(this.params.phone.trim(), this.captchaId, code)
    this.submitting = false
    if (err !== null) {
      this.showToast(this.mapErr(err))
      if (err === 'captcha_invalid') {
        this.draftCode = ''
        void this.refreshCaptcha()
      }
      return
    }
    this.params.onSmsSent()
  }

  build() {
    Column({ space: 14 }) {
      Text('图形验证')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')

      if (this.loadingCaptcha) {
        Row() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color($r('app.color.accent'))
        }
        .width('100%')
        .height(88)
        .justifyContent(FlexAlign.Center)
      } else if (this.captchaLoadError.length > 0) {
        Text(this.captchaLoadError)
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
        Button('重新加载')
          .type(ButtonType.Normal)
          .fontSize(14)
          .height(40)
          .onClick((): void => {
            void this.refreshCaptcha()
          })
      } else if (this.imagePixelMap !== null) {
        Image(this.imagePixelMap)
          .width('100%')
          .height(88)
          .objectFit(ImageFit.Contain)
          .borderRadius(8)
          .backgroundColor($r('app.color.surface_muted'))
      }

      TextInput({ text: this.draftCode, placeholder: '请输入图中数字' })
        .width('100%')
        .height(44)
        .fontSize($r('app.float.body_font_size'))
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .padding({ left: 12, right: 12 })
        .type(InputType.Number)
        .onChange((v: string) => {
          this.draftCode = this.filterDigits(v)
        })

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .backgroundColor($r('app.color.surface_muted'))
          .fontColor($r('app.color.primary_text'))
          .onClick((): void => {
            this.params.onDismiss()
          })
        Button('换一张')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .backgroundColor($r('app.color.surface_muted'))
          .fontColor($r('app.color.primary_text'))
          .enabled(!this.loadingCaptcha && !this.submitting)
          .onClick((): void => {
            void this.refreshCaptcha()
          })
        Button(this.submitting ? '发送中…' : '确定')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .backgroundColor($r('app.color.login_primary_button'))
          .fontColor('#FFFFFFFF')
          .enabled(!this.submitting && !this.loadingCaptcha && this.captchaLoadError.length === 0 &&
            this.captchaId.length > 0)
          .onClick((): void => {
            void this.onConfirm()
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
export function buildRegisterCaptchaDialogContent(params: RegisterCaptchaDialogParams) {
  RegisterCaptchaDialog({
    params: params
  })
}
