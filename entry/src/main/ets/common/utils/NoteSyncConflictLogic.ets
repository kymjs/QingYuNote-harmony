/// 多端同时编辑时，是否把「尚未合入本地的远端版本」存进版本历史。
///
/// 比较的是远端笔记最后编辑时间，与**本地开始本次编辑之前**的最后编辑时间。
export class NoteSyncConflictLogic {
  static resolveRemoteLastEditAt(parsedUpdatedAt: number, parsedUserUpdatedAt: number,
    httpRemoteModified: number): number {
    let lastEdit = parsedUpdatedAt
    if (parsedUserUpdatedAt > lastEdit) {
      lastEdit = parsedUserUpdatedAt
    }
    if (lastEdit <= 0) {
      lastEdit = httpRemoteModified
    }
    return lastEdit
  }

  /// 远端最后编辑时间晚于本地编辑前的时间，说明拉取到了本次本地编辑未覆盖的远端改动。
  static shouldSaveRemoteToHistory(remoteLastEditAt: number, localLastEditAtBeforeEdit: number): boolean {
    if (remoteLastEditAt <= 0) {
      return false
    }
    if (localLastEditAtBeforeEdit <= 0) {
      return true
    }
    return remoteLastEditAt > localLastEditAtBeforeEdit
  }
}
