import type { Note } from '../common/model/Note'

/** 首页笔记列表 `LazyForEach` 数据源；与 `Index.updateNotes` 同步刷新。 */
export class IndexNotesDataSource implements IDataSource {
  private listeners: DataChangeListener[] = []
  private notes: Note[] = []

  totalCount(): number {
    return this.notes.length
  }

  getData(index: number): Object {
    return this.notes[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener)
    if (pos >= 0) {
      this.listeners.splice(pos, 1)
    }
  }

  replaceAll(notes: Note[]): void {
    this.notes = notes.slice()
    this.notifyDataReload()
  }

  private notifyDataReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded()
    })
  }
}
