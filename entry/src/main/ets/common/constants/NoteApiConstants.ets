/** 轻羽云业务 API（与 Flutter `AppConst.noteApiBaseUrl` 保持一致，部署后可改为构建参数）。 */
export class NoteApiConstants {
  static readonly baseUrl: string = 'https://noteapi.kymjs.com'
  /** 须与 AGC、服务端 HUAWEI_REDIRECT_URI 完全一致；若客户端无需传则可留空字符串。 */
  static readonly huaweiOAuthRedirectUri: string = ''
}
