import { http } from '@kit.NetworkKit'
import type { CreateNoteInput, Note, UpdateNoteInput } from '../common/model/Note'
import { Logger } from '../common/utils/Logger'
import { SyncConstants, WereadImportToastPayload } from '../common/constants/SyncConstants'
import { AppContextHolder } from './AppContextHolder'
import { AiNoteTitleService } from './AiNoteTitleService'
import { NoteRepository } from './NoteRepository'
import { PreferencesService } from './PreferencesService'

const WEREAD_GATEWAY_URL = 'https://i.weread.qq.com/api/agent/gateway'
const WEREAD_SKILL_VERSION = '1.0.3'
const WEREAD_BOOK_ID_USER_DATA_KEY = 'wereadBookId'
const WEREAD_KIND_USER_DATA_KEY = 'wereadKind'
const WEREAD_ITEM_KEY_USER_DATA_KEY = 'wereadKey'
const KIND_HIGHLIGHT = 'highlight'
const KIND_IDEA_PAIR = 'idea_pair'
const KIND_IDEA = 'idea'
const KIND_REVIEW = 'review'

export class WereadImportProgress {
  processedBooks: number = 0
  totalBooks: number = 0
  currentBookTitle: string = ''
}

export class WereadImportResult {
  importedCount: number = 0
  skippedCount: number = 0
}

export class WereadImportException extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'WereadImportException'
  }
}

interface WereadNotebookItem {
  bookId?: string
  title?: string
  noteCount?: number
  reviewCount?: number
  sort?: number
  book?: WereadBookInfo
}

interface WereadBookInfo {
  bookId?: string
  title?: string
}

interface WereadHighlightItem {
  bookmarkId?: string
  markText?: string
  chapterUid?: number
  range?: string
  createTime?: number
}

interface WereadChapterItem {
  chapterUid?: number
  chapterIdx?: number
  title?: string
}

interface WereadReviewWrapper {
  review?: WereadReviewItem
}

interface WereadReviewItem {
  reviewId?: string
  content?: string
  chapterName?: string
  createTime?: number
  star?: number
  isFinish?: number
  abstract?: string
  range?: string
  chapterUid?: number
  bookmarkId?: string
}

class WereadHighlight {
  bookmarkId: string = ''
  text: string = ''
  chapterUid: number = 0
  range: string = ''
  createTime: number = 0
}

class WereadReview {
  reviewId: string = ''
  content: string = ''
  chapterName: string = ''
  createTime: number = 0
  star: number = -1
  isFinish: number = -1
  abstract: string = ''
  range: string = ''
  chapterUid: number = 0
  bookmarkId: string = ''
}

class WereadHighlightBundle {
  highlights: WereadHighlight[] = []
  chapterTitles: Map<number, string> = new Map()
  chapterOrder: Map<number, number> = new Map()
}

class WereadUserDataMeta {
  bookId: string = ''
  kind: string = ''
  itemKey: string = ''
}

class WereadHighlightLookups {
  all: WereadHighlight[] = []
  byBookmarkId: Map<string, WereadHighlight> = new Map()
  byRange: Map<string, WereadHighlight> = new Map()
  byText: Map<string, WereadHighlight> = new Map()
  byKey: Map<string, WereadHighlight> = new Map()
}

class WereadImportIndex {
  private byItem: Map<string, Note> = new Map()

  register(note: Note, bookId: string, kind: string, itemKey: string): void {
    this.byItem.set(
      WereadImportService.itemIndexKey(bookId, kind, itemKey),
      this.preferNewer(this.byItem.get(WereadImportService.itemIndexKey(bookId, kind, itemKey)), note)
    )
  }

  findNoteId(bookId: string, kind: string, itemKey: string): string {
    const note = this.byItem.get(WereadImportService.itemIndexKey(bookId, kind, itemKey))
    return note !== undefined ? note.id : ''
  }

  private preferNewer(existing: Note | undefined, candidate: Note): Note {
    if (existing === undefined) {
      return candidate
    }
    return candidate.updatedAt >= existing.updatedAt ? candidate : existing
  }
}

export class WereadImportService {
  private static instance: WereadImportService = new WereadImportService()
  private inFlight: Promise<WereadImportResult> | null = null
  private running: boolean = false
  private currentProgress: WereadImportProgress | null = null

  static getInstance(): WereadImportService {
    return WereadImportService.instance
  }

  isImportRunning(): boolean {
    return this.running
  }

  getProgress(): WereadImportProgress | null {
    return this.currentProgress
  }

  static itemIndexKey(bookId: string, kind: string, itemKey: string): string {
    return `${bookId}\u0000${kind}\u0000${itemKey}`
  }

  importAllNotes(
    apiKey: string,
    onProgress?: (progress: WereadImportProgress) => void
  ): Promise<WereadImportResult> {
    if (this.inFlight !== null) {
      return this.inFlight
    }
    this.running = true
    this.inFlight = this.importAllNotesImpl(apiKey, onProgress).finally(() => {
      this.running = false
      this.inFlight = null
      this.currentProgress = null
    })
    return this.inFlight
  }

  private async importAllNotesImpl(
    apiKey: string,
    onProgress?: (progress: WereadImportProgress) => void
  ): Promise<WereadImportResult> {
    const token = apiKey.trim()
    if (token.length === 0) {
      throw new WereadImportException('请输入微信读书 API Key')
    }

    try {
      await PreferencesService.getInstance().setWereadApiKey(token)
      const notebooks = await this.fetchAllNotebooks(token)
      const exportable: WereadNotebookItem[] = []
      for (const item of notebooks) {
        const noteCount = this.asInt(item.noteCount)
        const reviewCount = this.asInt(item.reviewCount)
        if (noteCount + reviewCount > 0) {
          exportable.push(item)
        }
      }

      const result = new WereadImportResult()
      if (exportable.length === 0) {
        this.emitToast(this.completionMessage(result))
        return result
      }

      await NoteRepository.getInstance().init()
      const importIndex = await this.buildImportIndex()
      NoteRepository.getInstance().beginBulkNotification()
      try {
        for (let i = 0; i < exportable.length; i++) {
          const item = exportable[i]
          const bookId = this.bookIdFromNotebook(item)
          const bookTitle = this.bookTitleFromNotebook(item)
          const progress = new WereadImportProgress()
          progress.processedBooks = i
          progress.totalBooks = exportable.length
          progress.currentBookTitle = bookTitle
          this.emitProgress(progress, onProgress)

          const count = await this.importBookNotes(token, bookId, bookTitle, importIndex)
          if (count === 0) {
            result.skippedCount += 1
          } else {
            result.importedCount += count
          }
        }
      } finally {
        NoteRepository.getInstance().endBulkNotification()
      }

      const done = new WereadImportProgress()
      done.processedBooks = exportable.length
      done.totalBooks = exportable.length
      this.emitProgress(done, onProgress)

      this.emitToast(this.completionMessage(result))
      return result
    } catch (error) {
      if (error instanceof WereadImportException) {
        this.emitToast(error.message)
        throw error
      }
      this.emitToast('导入失败，请稍后重试')
      throw error instanceof Error ? error : new WereadImportException('导入失败，请稍后重试')
    }
  }

  private emitProgress(
    progress: WereadImportProgress,
    onProgress?: (progress: WereadImportProgress) => void
  ): void {
    this.currentProgress = progress
    onProgress?.(progress)
  }

  private completionMessage(result: WereadImportResult): string {
    if (result.importedCount === 0 && result.skippedCount === 0) {
      return '没有可导入的笔记'
    }
    const skipPart = result.skippedCount > 0 ? `，${result.skippedCount} 本书无内容` : ''
    return `已导入 ${result.importedCount} 条笔记${skipPart}`
  }

  private emitToast(message: string): void {
    if (message.trim().length === 0) {
      return
    }
    try {
      const hub = AppContextHolder.tryGetContext()?.eventHub
      hub?.emit(
        SyncConstants.wereadImportToastEvent,
        new WereadImportToastPayload(message.trim())
      )
    } catch (_) {
    }
  }

  private async importBookNotes(
    token: string,
    bookId: string,
    bookTitle: string,
    index: WereadImportIndex
  ): Promise<number> {
    const tag = this.sanitizeBookTag(bookTitle)
    const bundle = await this.fetchHighlights(token, bookId)
    const reviews = await this.fetchReviews(token, bookId)
    if (bundle.highlights.length === 0 && reviews.length === 0) {
      return 0
    }

    const lookups = this.buildHighlightLookups(bundle.highlights)
    const bookReviews: WereadReview[] = []
    const orphanIdeas: WereadReview[] = []
    const ideasByHighlightKey: Map<string, WereadReview[]> = new Map()
    const matchedHighlightKeys: Set<string> = new Set()

    for (const review of reviews) {
      if (this.isBookReview(review)) {
        bookReviews.push(review)
        continue
      }
      const highlight = this.matchHighlight(review, lookups)
      if (highlight !== undefined) {
        const hKey = this.highlightKey(highlight)
        const list = ideasByHighlightKey.get(hKey) ?? []
        list.push(review)
        ideasByHighlightKey.set(hKey, list)
        matchedHighlightKeys.add(hKey)
      } else {
        orphanIdeas.push(review)
      }
    }

    let count = 0

    for (const highlight of bundle.highlights) {
      const hKey = this.highlightKey(highlight)
      if (matchedHighlightKeys.has(hKey)) {
        continue
      }
      const chapterTitle = bundle.chapterTitles.get(highlight.chapterUid) ?? ''
      await this.saveImportedNote(
        index,
        bookId,
        KIND_HIGHLIGHT,
        hKey,
        this.formatHighlightOnlyContent(highlight, chapterTitle),
        bookTitle,
        tag
      )
      count += 1
    }

    const pairKeys = Array.from(ideasByHighlightKey.keys())
    for (let i = 0; i < pairKeys.length; i++) {
      const hKey = pairKeys[i]
      const highlight = lookups.byKey.get(hKey)
      if (highlight === undefined) {
        continue
      }
      const ideas = ideasByHighlightKey.get(hKey) ?? []
      const chapterTitle = bundle.chapterTitles.get(highlight.chapterUid) ?? ''
      await this.saveImportedNote(
        index,
        bookId,
        KIND_IDEA_PAIR,
        hKey,
        this.formatIdeaPairContent(highlight, ideas, chapterTitle),
        bookTitle,
        tag
      )
      count += 1
    }

    for (const idea of orphanIdeas) {
      const itemKey = idea.reviewId.length > 0 ?
        idea.reviewId :
        `t:${idea.createTime}:${this.normalizeText(idea.content)}`
      await this.saveImportedNote(
        index,
        bookId,
        KIND_IDEA,
        itemKey,
        this.formatOrphanIdeaContent(idea),
        bookTitle,
        tag
      )
      count += 1
    }

    for (const review of bookReviews) {
      const itemKey = review.reviewId.length > 0 ?
        review.reviewId :
        `t:${review.createTime}:${this.normalizeText(review.content)}`
      await this.saveImportedNote(
        index,
        bookId,
        KIND_REVIEW,
        itemKey,
        this.formatBookReviewContent(review),
        bookTitle,
        tag
      )
      count += 1
    }

    return count
  }

  private async saveImportedNote(
    index: WereadImportIndex,
    bookId: string,
    kind: string,
    itemKey: string,
    body: string,
    bookTitle: string,
    tag: string
  ): Promise<void> {
    const title = await this.resolveNoteTitle(body)
    const content = this.appendBookFooter(body, bookTitle)
    await this.upsertImportedNote(index, bookId, kind, itemKey, title, content, tag)
  }

  private async upsertImportedNote(
    index: WereadImportIndex,
    bookId: string,
    kind: string,
    itemKey: string,
    title: string,
    content: string,
    tag: string
  ): Promise<void> {
    const existingId = index.findNoteId(bookId, kind, itemKey)
    if (existingId.length > 0) {
      const patch: UpdateNoteInput = {
        title: title,
        content: content,
        tags: [tag]
      }
      await NoteRepository.getInstance().saveDraft(existingId, patch)
      return
    }
    const input: CreateNoteInput = {
      title: title,
      content: content,
      tags: [tag],
      userData: this.wereadUserData(bookId, kind, itemKey)
    }
    const note = await NoteRepository.getInstance().createNote(input)
    index.register(note, bookId, kind, itemKey)
  }

  private isBookReview(review: WereadReview): boolean {
    if (review.bookmarkId.length > 0 || review.abstract.length > 0 || review.range.length > 0) {
      return false
    }
    if (review.chapterName.length > 0) {
      return false
    }
    return review.isFinish >= 0 || review.star >= 0
  }

  private matchHighlight(review: WereadReview, lookups: WereadHighlightLookups): WereadHighlight | undefined {
    if (review.bookmarkId.length > 0) {
      const byId = lookups.byBookmarkId.get(review.bookmarkId)
      if (byId !== undefined) {
        return byId
      }
    }
    if (review.range.length > 0 && review.chapterUid > 0) {
      const byRange = lookups.byRange.get(`${review.chapterUid}:${review.range}`)
      if (byRange !== undefined) {
        return byRange
      }
    }
    if (review.abstract.length > 0) {
      const normalized = this.normalizeText(review.abstract)
      const exact = lookups.byText.get(normalized)
      if (exact !== undefined) {
        return exact
      }
      for (const highlight of lookups.all) {
        if (this.fuzzyTextMatch(normalized, this.normalizeText(highlight.text))) {
          return highlight
        }
      }
    }
    if (review.chapterUid > 0 && review.range.length > 0) {
      for (const highlight of lookups.all) {
        if (highlight.chapterUid === review.chapterUid && highlight.range === review.range) {
          return highlight
        }
      }
    }
    return undefined
  }

  private fuzzyTextMatch(a: string, b: string): boolean {
    if (a.length === 0 || b.length === 0) {
      return false
    }
    if (a === b) {
      return true
    }
    if (a.length >= 6 && b.includes(a)) {
      return true
    }
    if (b.length >= 6 && a.includes(b)) {
      return true
    }
    return false
  }

  private highlightKey(highlight: WereadHighlight): string {
    if (highlight.bookmarkId.length > 0) {
      return `bm:${highlight.bookmarkId}`
    }
    if (highlight.range.length > 0 && highlight.chapterUid > 0) {
      return `rg:${highlight.chapterUid}:${highlight.range}`
    }
    return `tx:${this.normalizeText(highlight.text)}`
  }

  private buildHighlightLookups(highlights: WereadHighlight[]): WereadHighlightLookups {
    const lookups = new WereadHighlightLookups()
    lookups.all = highlights
    for (const highlight of highlights) {
      if (highlight.bookmarkId.length > 0) {
        lookups.byBookmarkId.set(highlight.bookmarkId, highlight)
      }
      if (highlight.range.length > 0 && highlight.chapterUid > 0) {
        lookups.byRange.set(`${highlight.chapterUid}:${highlight.range}`, highlight)
      }
      const normalized = this.normalizeText(highlight.text)
      if (normalized.length > 0) {
        lookups.byText.set(normalized, highlight)
      }
      lookups.byKey.set(this.highlightKey(highlight), highlight)
    }
    return lookups
  }

  private formatHighlightOnlyContent(highlight: WereadHighlight, chapterTitle: string): string {
    const lines: string[] = []
    if (chapterTitle.length > 0) {
      lines.push(`**${chapterTitle}**`)
      lines.push('')
    }
    lines.push(this.blockquote(highlight.text))
    return lines.join('\n').trim()
  }

  private formatIdeaPairContent(
    highlight: WereadHighlight,
    ideas: WereadReview[],
    chapterTitle: string
  ): string {
    const lines: string[] = []
    if (chapterTitle.length > 0) {
      lines.push(`**${chapterTitle}**`)
      lines.push('')
    }
    lines.push(this.blockquote(highlight.text))
    lines.push('')
    for (let i = 0; i < ideas.length; i++) {
      if (i > 0) {
        lines.push('')
      }
      lines.push(ideas[i].content)
    }
    return lines.join('\n').trim()
  }

  private formatOrphanIdeaContent(idea: WereadReview): string {
    const lines: string[] = []
    if (idea.chapterName.length > 0) {
      lines.push(`**${idea.chapterName}**`)
      lines.push('')
    }
    if (idea.abstract.length > 0) {
      lines.push(this.blockquote(idea.abstract))
      lines.push('')
    }
    lines.push(idea.content)
    return lines.join('\n').trim()
  }

  private formatBookReviewContent(review: WereadReview): string {
    const lines: string[] = []
    if (review.star >= 0) {
      lines.push(`评分：${review.star} 星`)
      lines.push('')
    }
    lines.push(review.content)
    return lines.join('\n').trim()
  }

  private sanitizeBookTag(raw: string): string {
    let name = raw.trim()
    if (name.length === 0) {
      return '微信读书'
    }
    while (true) {
      const next = name
        .replace(/（[^）]*）/g, '')
        .replace(/\([^)]*\)/g, '')
      if (next === name) {
        break
      }
      name = next
    }
    name = name.trim()
    const colonIndex = this.firstIndexOfAny(name, ['：', ':'])
    if (colonIndex >= 0) {
      name = name.substring(0, colonIndex).trim()
    }
    const dashIndex = this.firstIndexOfAny(name, ['—', '–', '-', '－'])
    if (dashIndex >= 0) {
      name = name.substring(0, dashIndex).trim()
    }
    return name.length === 0 ? '微信读书' : name
  }

  private firstIndexOfAny(text: string, needles: string[]): number {
    let min = -1
    for (let i = 0; i < needles.length; i++) {
      const index = text.indexOf(needles[i])
      if (index >= 0 && (min < 0 || index < min)) {
        min = index
      }
    }
    return min
  }

  private appendBookFooter(body: string, bookTitle: string): string {
    const trimmedBody = body.trim()
    const name = bookTitle.trim()
    if (name.length === 0) {
      return trimmedBody
    }
    if (trimmedBody.length === 0) {
      return `《${name}》`
    }
    return `${trimmedBody}\n\n《${name}》`
  }

  private async resolveNoteTitle(body: string): Promise<string> {
    try {
      return await AiNoteTitleService.getInstance().suggestTitle(body)
    } catch (_) {
      return this.fallbackTitleFromContent(body)
    }
  }

  private fallbackTitleFromContent(content: string): string {
    const text = this.plainTextForTitle(content)
    if (text.length === 0) {
      return '笔记'
    }
    if (text.length <= 10) {
      return text
    }
    return text.substring(0, 10)
  }

  private plainTextForTitle(content: string): string {
    const parts: string[] = []
    const lines = content.split('\n')
    for (let i = 0; i < lines.length; i++) {
      let lineText = lines[i].trim()
      if (lineText.length === 0) {
        continue
      }
      if (lineText.startsWith('>')) {
        lineText = lineText.substring(1).trim()
      }
      lineText = lineText.replace(/\*\*/g, '')
      if (lineText.length > 0) {
        parts.push(lineText)
      }
    }
    return parts.join('')
  }

  private normalizeText(text: string): string {
    return text.replace(/\s+/g, '').toLowerCase()
  }

  private wereadUserData(bookId: string, kind: string, itemKey: string): string {
    const payload: Record<string, string> = {}
    payload[WEREAD_BOOK_ID_USER_DATA_KEY] = bookId
    payload[WEREAD_KIND_USER_DATA_KEY] = kind
    payload[WEREAD_ITEM_KEY_USER_DATA_KEY] = itemKey
    return JSON.stringify(payload)
  }

  private parseWereadUserData(userData: string): WereadUserDataMeta | undefined {
    const trimmed = userData.trim()
    if (trimmed.length === 0) {
      return undefined
    }
    try {
      const parsed = JSON.parse(trimmed) as Record<string, Object>
      const bookId = `${parsed[WEREAD_BOOK_ID_USER_DATA_KEY] ?? ''}`.trim()
      const kind = `${parsed[WEREAD_KIND_USER_DATA_KEY] ?? ''}`.trim()
      const itemKey = `${parsed[WEREAD_ITEM_KEY_USER_DATA_KEY] ?? ''}`.trim()
      if (bookId.length === 0 || kind.length === 0 || itemKey.length === 0) {
        return undefined
      }
      const meta = new WereadUserDataMeta()
      meta.bookId = bookId
      meta.kind = kind
      meta.itemKey = itemKey
      return meta
    } catch (_) {
      return undefined
    }
  }

  private async buildImportIndex(): Promise<WereadImportIndex> {
    const index = new WereadImportIndex()
    const notes = await NoteRepository.getInstance().listAllNotes()
    for (const note of notes) {
      if (note.deleted || note.deletedTime > 0) {
        continue
      }
      const meta = this.parseWereadUserData(note.userData)
      if (meta !== undefined) {
        index.register(note, meta.bookId, meta.kind, meta.itemKey)
      }
    }
    return index
  }

  private async fetchAllNotebooks(token: string): Promise<WereadNotebookItem[]> {
    const all: WereadNotebookItem[] = []
    let lastSort: number | undefined = undefined
    while (true) {
      const body: Record<string, Object> = {
        'api_name': '/user/notebooks',
        'count': 100,
        'skill_version': WEREAD_SKILL_VERSION
      }
      if (lastSort !== undefined) {
        body['lastSort'] = lastSort
      }
      const data = await this.gateway(token, body)
      const books = data['books']
      if (Array.isArray(books)) {
        for (const raw of books as Object[]) {
          all.push(raw as WereadNotebookItem)
        }
      }
      const hasMore = this.asInt(data['hasMore'])
      if (hasMore !== 1 || all.length === 0) {
        break
      }
      const last = all[all.length - 1]
      const sort = this.asInt(last.sort)
      if (sort <= 0) {
        break
      }
      lastSort = sort
    }
    return all
  }

  private async fetchHighlights(token: string, bookId: string): Promise<WereadHighlightBundle> {
    const data = await this.gateway(token, {
      'api_name': '/book/bookmarklist',
      'bookId': bookId,
      'skill_version': WEREAD_SKILL_VERSION
    })
    const bundle = new WereadHighlightBundle()
    const chapters = data['chapters']
    if (Array.isArray(chapters)) {
      for (const raw of chapters as WereadChapterItem[]) {
        const uid = this.asInt(raw.chapterUid)
        if (uid <= 0) {
          continue
        }
        bundle.chapterTitles.set(uid, `${raw.title ?? ''}`.trim())
        bundle.chapterOrder.set(uid, this.asInt(raw.chapterIdx))
      }
    }
    const updated = data['updated']
    if (Array.isArray(updated)) {
      for (const raw of updated as WereadHighlightItem[]) {
        const text = `${raw.markText ?? ''}`.trim()
        if (text.length === 0) {
          continue
        }
        const h = new WereadHighlight()
        h.bookmarkId = `${raw.bookmarkId ?? ''}`.trim()
        h.text = text
        h.chapterUid = this.asInt(raw.chapterUid)
        h.range = `${raw.range ?? ''}`.trim()
        h.createTime = this.asInt(raw.createTime)
        bundle.highlights.push(h)
      }
    }
    bundle.highlights.sort((a, b) => {
      const ao = bundle.chapterOrder.get(a.chapterUid) ?? a.chapterUid
      const bo = bundle.chapterOrder.get(b.chapterUid) ?? b.chapterUid
      if (ao !== bo) {
        return ao - bo
      }
      return a.createTime - b.createTime
    })
    return bundle
  }

  private async fetchReviews(token: string, bookId: string): Promise<WereadReview[]> {
    const all: WereadReview[] = []
    let synckey = 0
    while (true) {
      const data = await this.gateway(token, {
        'api_name': '/review/list/mine',
        'bookid': bookId,
        'synckey': synckey,
        'count': 50,
        'skill_version': WEREAD_SKILL_VERSION
      })
      const reviewsRaw = data['reviews']
      if (Array.isArray(reviewsRaw)) {
        for (const wrapper of reviewsRaw as WereadReviewWrapper[]) {
          const review = wrapper.review
          if (review === undefined) {
            continue
          }
          const content = `${review.content ?? ''}`.trim()
          if (content.length === 0) {
            continue
          }
          const r = new WereadReview()
          r.reviewId = `${review.reviewId ?? ''}`.trim()
          r.content = content
          r.chapterName = `${review.chapterName ?? ''}`.trim()
          r.createTime = this.asInt(review.createTime)
          r.star = this.asInt(review.star)
          r.isFinish = this.asInt(review.isFinish)
          r.abstract = `${review.abstract ?? ''}`.trim()
          r.range = `${review.range ?? ''}`.trim()
          r.chapterUid = this.asInt(review.chapterUid)
          r.bookmarkId = `${review.bookmarkId ?? ''}`.trim()
          all.push(r)
        }
      }
      const hasMore = this.asInt(data['hasMore'])
      const nextKey = this.asInt(data['synckey'])
      if (hasMore !== 1 || nextKey === synckey) {
        break
      }
      synckey = nextKey
    }
    all.sort((a, b) => a.createTime - b.createTime)
    return all
  }

  private blockquote(text: string): string {
    return text.split('\n').map((line: string) => `> ${line}`).join('\n')
  }

  private async gateway(token: string, body: Record<string, Object>): Promise<Record<string, Object>> {
    const req = http.createHttp()
    try {
      const resp = await req.request(WEREAD_GATEWAY_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 20000,
        readTimeout: 60000
      })
      const code = resp.responseCode
      if (code === 401 || code === 403) {
        throw new WereadImportException('API Key 无效或已过期，请重新获取')
      }
      if (code < 200 || code >= 300) {
        throw new WereadImportException('网络请求失败，请检查网络后重试')
      }
      const text = (resp.result as string) ?? ''
      let parsed: Record<string, Object> = {}
      if (text.trim().length > 0) {
        parsed = JSON.parse(text) as Record<string, Object>
      }
      const errcode = parsed['errcode']
      if (typeof errcode === 'number' && errcode !== 0) {
        const msg = `${parsed['errmsg'] ?? parsed['message'] ?? '请求失败'}`.trim()
        throw new WereadImportException(msg.length > 0 ? msg : `微信读书接口错误（${errcode}）`)
      }
      return parsed
    } catch (error) {
      if (error instanceof WereadImportException) {
        throw error as WereadImportException
      }
      Logger.warn('WereadImportService', `gateway failed: ${JSON.stringify(error)}`)
      throw new WereadImportException('导入失败，请稍后重试')
    } finally {
      req.destroy()
    }
  }

  private bookIdFromNotebook(item: WereadNotebookItem): string {
    const id = `${item.bookId ?? ''}`.trim()
    if (id.length > 0) {
      return id
    }
    return `${item.book?.bookId ?? ''}`.trim()
  }

  private bookTitleFromNotebook(item: WereadNotebookItem): string {
    const title = `${item.book?.title ?? ''}`.trim()
    if (title.length > 0) {
      return title
    }
    return `${item.title ?? ''}`.trim()
  }

  private asInt(value: Object | undefined): number {
    if (value === undefined || value === null) {
      return -1
    }
    if (typeof value === 'number' && Number.isFinite(value)) {
      return Math.trunc(value)
    }
    if (typeof value === 'string') {
      const n = Number.parseInt(value.trim(), 10)
      return Number.isNaN(n) ? -1 : n
    }
    return -1
  }
}
