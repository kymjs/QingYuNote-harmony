import { LocaleService } from '../../services/LocaleService'

/** Editor / share / flowchart UI strings shared across pages and dialogs. */
export class EditorUiStrings {
  static loc(zh: string, en: string, ja?: string): string {
    return LocaleService.loc(zh, en, ja)
  }

  static saveStatus(status: string): string {
    switch (status) {
      case '已保存':
        return EditorUiStrings.loc('已保存', 'Saved', '保存済み')
      case '未保存':
        return EditorUiStrings.loc('未保存', 'Unsaved', '未保存')
      case '保存中...':
        return EditorUiStrings.loc('保存中...', 'Saving…', '保存中…')
      case '保存失败':
        return EditorUiStrings.loc('保存失败', 'Save failed', '保存失敗')
      default:
        return status
    }
  }

  static previewModeLabel(mode: string): string {
    return mode === 'preview'
      ? EditorUiStrings.loc('预览模式', 'Preview mode', 'プレビューモード')
      : EditorUiStrings.loc('编辑模式', 'Edit mode', '編集モード')
    }

  static saveStatusDisplay(status: string, _mode: string): string {
    return EditorUiStrings.saveStatus(status)
  }

  static userSequenceLabel(id: string): string {
    const trimmed = id.trim()
    if (trimmed.length === 0) {
      return '—'
    }
    const lang = LocaleService.getInstance().getLanguage()
    if (lang === 'zh-Hant') {
      return `第${trimmed}名用戶`
    }
    if (lang === 'zh') {
      return `第${trimmed}名用户`
    }
    return `#${trimmed}`
  }

  static searchNotesHint(): string {
    return EditorUiStrings.loc(
      '搜索笔记、流程图节点',
      'Search notes & flowchart nodes',
      'ノートとフローチャートノードを検索'
    )
  }
}
