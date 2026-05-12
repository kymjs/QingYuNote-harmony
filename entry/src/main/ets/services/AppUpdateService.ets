import bundleManager from '@ohos.bundle.bundleManager'
import http from '@ohos.net.http'

/** 与 CDN `harmony.json`、Flutter `ReleaseManifest` 字段一致。 */
export interface ReleaseManifest {
  latestRelease: string
  latestVersion: string
  downloadUrl: string
  upgradeText: string
  forceUpgradeText: string
}

const HARMONY_MANIFEST_URL = 'https://cdn.kymjs.com:8843/note/harmony.json'

function parseVersionSegments(version: string): number[] {
  const core = version.split('+')[0].trim()
  if (core.length === 0) {
    return []
  }
  return core.split('.').map((s: string): number => {
    const n = parseInt(s.trim(), 10)
    return Number.isNaN(n) ? 0 : n
  })
}

/** 当前 [a] 相对 [b]：小为 -1，大为 1，否则 0。 */
export function compareSemanticVersions(a: string, b: string): number {
  const pa = parseVersionSegments(a)
  const pb = parseVersionSegments(b)
  const len = pa.length > pb.length ? pa.length : pb.length
  for (let i = 0; i < len; i++) {
    const va = i < pa.length ? pa[i] : 0
    const vb = i < pb.length ? pb[i] : 0
    if (va < vb) {
      return -1
    }
    if (va > vb) {
      return 1
    }
  }
  return 0
}

export function manifestUsable(m: ReleaseManifest): boolean {
  return m.downloadUrl.length > 0 &&
    (m.latestRelease.length > 0 || m.latestVersion.length > 0)
}

interface ManifestWire {
  latestRelease?: string
  latestVersion?: string
  downloadUrl?: string
  upgradeText?: string
  forceUpgradeText?: string
}

function parseManifestJson(raw: ManifestWire): ReleaseManifest {
  return {
    latestRelease: raw.latestRelease ?? '',
    latestVersion: raw.latestVersion ?? '',
    downloadUrl: raw.downloadUrl ?? '',
    upgradeText: raw.upgradeText ?? '',
    forceUpgradeText: raw.forceUpgradeText ?? ''
  }
}

export async function fetchReleaseManifest(): Promise<ReleaseManifest | null> {
  const req = http.createHttp()
  try {
    const response = await req.request(HARMONY_MANIFEST_URL, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 10000
    })
    if (response.responseCode !== 200) {
      return null
    }
    const body = response.result as string
    const obj = JSON.parse(body) as ManifestWire
    return parseManifestJson(obj)
  } catch (e) {
    console.error(`fetchReleaseManifest: ${JSON.stringify(e)}`)
    return null
  } finally {
    req.destroy()
  }
}

export async function getAppVersionName(): Promise<string> {
  try {
    const info = await bundleManager.getBundleInfoForSelf(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
    )
    return info.versionName
  } catch (e) {
    console.error(`getAppVersionName: ${JSON.stringify(e)}`)
    return '1.0.1'
  }
}
