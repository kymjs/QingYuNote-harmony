/** 第三方导入页共享的进度状态文案（有道 / 印象 / 微信读书）。 */

export interface NoteImportProgressLike {
  processedNotes: number
  totalNotes: number
  currentNoteTitle: string
}

export interface BookImportProgressLike {
  processedBooks: number
  totalBooks: number
  currentBookTitle: string
}

export function noteImportStatusText(
  progress: NoteImportProgressLike | null,
  running: boolean
): string {
  if (!running) {
    return ''
  }
  if (progress === null) {
    return '正在获取笔记列表…'
  }
  if (progress.currentNoteTitle.length > 0) {
    return `正在导入《${progress.currentNoteTitle}》（${progress.processedNotes + 1}/${progress.totalNotes}）`
  }
  if (progress.totalNotes > 0 && progress.processedNotes >= progress.totalNotes) {
    return '导入完成'
  }
  return '正在获取笔记列表…'
}

export function bookImportStatusText(
  progress: BookImportProgressLike | null,
  running: boolean
): string {
  if (!running) {
    return ''
  }
  if (progress === null) {
    return '正在获取笔记本列表…'
  }
  if (progress.currentBookTitle.length > 0) {
    return `正在导入《${progress.currentBookTitle}》（${progress.processedBooks + 1}/${progress.totalBooks}）`
  }
  if (progress.totalBooks > 0 && progress.processedBooks >= progress.totalBooks) {
    return '导入完成'
  }
  return '正在获取笔记本列表…'
}
