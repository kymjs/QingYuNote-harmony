import bundleManager from '@ohos.bundle.bundleManager'
import fs from '@ohos.file.fs'
import http from '@ohos.net.http'
import { AppContextHolder } from './AppContextHolder'

/** 与 CDN `harmony.json`、Flutter `ReleaseManifest` 字段一致。 */
export interface ReleaseManifest {
  latestRelease: string
  latestVersion: string
  downloadUrl: string
  upgradeText: string
  forceUpgradeText: string
}

const HARMONY_MANIFEST_URL = 'https://cdn.kymjs.com:8843/note/harmony.json'
const RELEASE_MANIFEST_CACHE_FILE = 'release_manifest_cache.json'

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

export function needsForceUpdate(currentVersion: string, manifest: ReleaseManifest): boolean {
  if (!manifestUsable(manifest) || manifest.latestVersion.length === 0) {
    return false
  }
  return compareSemanticVersions(currentVersion, manifest.latestVersion) < 0
}

export function needsOptionalUpdate(currentVersion: string, manifest: ReleaseManifest): boolean {
  if (!manifestUsable(manifest) || manifest.latestRelease.length === 0) {
    return false
  }
  return compareSemanticVersions(currentVersion, manifest.latestRelease) < 0
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

function manifestCachePath(): string {
  const context = AppContextHolder.tryGetContext()
  const filesDir = context?.filesDir ?? ''
  if (filesDir.length === 0) {
    return ''
  }
  return `${filesDir}/${RELEASE_MANIFEST_CACHE_FILE}`
}

async function writeReleaseManifestCache(manifest: ReleaseManifest): Promise<void> {
  const path = manifestCachePath()
  if (path.length === 0) {
    return
  }
  try {
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    try {
      await fs.write(file.fd, JSON.stringify(manifest), { encoding: 'utf-8' })
    } finally {
      fs.closeSync(file)
    }
  } catch (e) {
    console.error(`writeReleaseManifestCache: ${JSON.stringify(e)}`)
  }
}

function readReleaseManifestCache(): ReleaseManifest | null {
  const path = manifestCachePath()
  if (path.length === 0) {
    return null
  }
  try {
    if (!fs.accessSync(path)) {
      return null
    }
    const content = fs.readTextSync(path, { encoding: 'utf-8' })
    const raw = JSON.parse(content) as ManifestWire
    const manifest = parseManifestJson(raw)
    if (!manifestUsable(manifest)) {
      return null
    }
    return manifest
  } catch (e) {
    console.error(`readReleaseManifestCache: ${JSON.stringify(e)}`)
    return null
  }
}

async function fetchReleaseManifestFromNetwork(): Promise<ReleaseManifest | null> {
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
    const manifest = parseManifestJson(obj)
    if (!manifestUsable(manifest)) {
      return null
    }
    await writeReleaseManifestCache(manifest)
    return manifest
  } catch (e) {
    console.error(`fetchReleaseManifest: ${JSON.stringify(e)}`)
    return null
  } finally {
    req.destroy()
  }
}

/** 优先 CDN；失败时读本地缓存。 */
export async function fetchReleaseManifestWithCache(): Promise<ReleaseManifest | null> {
  const fresh = await fetchReleaseManifestFromNetwork()
  if (fresh !== null) {
    return fresh
  }
  return readReleaseManifestCache()
}

export async function getAppVersionName(): Promise<string> {
  const info = await bundleManager.getBundleInfoForSelf(
    bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
  )
  return info.versionName
}

/** 强更/可选更新比较用；读取失败视为 0.0.0。 */
export async function getAppVersionNameForCompare(): Promise<string> {
  try {
    const v = (await getAppVersionName()).trim()
    return v.length > 0 ? v : '0.0.0'
  } catch (e) {
    console.error(`getAppVersionNameForCompare: ${JSON.stringify(e)}`)
    return '0.0.0'
  }
}
