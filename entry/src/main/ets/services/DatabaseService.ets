import { relationalStore } from '@kit.ArkData'
import type common from '@ohos.app.ability.common'
import type { NoteSyncState, SyncStatus } from '../common/model/Note'
import { Logger } from '../common/utils/Logger'

const DB_NAME = 'qingyu_notes.db'
const TABLE_NAME = 'note_sync_state'
const LEGACY_TABLE_NAME = 'notes'

interface SyncStateColumnIndexes {
  id: number
  remoteModified: number
  deleted: number
  deletedAt: number
  lastOperationAt: number
  syncStatus: number
}

export class DatabaseService {
  private static instance: DatabaseService = new DatabaseService()
  private context?: common.Context
  private store?: relationalStore.RdbStore
  private initialized: boolean = false

  static getInstance(): DatabaseService {
    return DatabaseService.instance
  }

  async init(context: common.Context): Promise<void> {
    if (this.initialized) {
      return
    }
    try {
      this.context = context
      const config: relationalStore.StoreConfig = {
        name: DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      }
      this.store = await relationalStore.getRdbStore(this.context, config)
      await this.store.executeSql(`
        CREATE TABLE IF NOT EXISTS ${TABLE_NAME} (
          id TEXT PRIMARY KEY,
          remote_modified INTEGER NOT NULL DEFAULT 0,
          deleted INTEGER NOT NULL DEFAULT 0,
          deleted_at INTEGER NOT NULL DEFAULT 0,
          last_operation_at INTEGER NOT NULL DEFAULT 0,
          sync_status TEXT NOT NULL
        )
      `)
      await this.store.executeSql(`CREATE INDEX IF NOT EXISTS idx_note_sync_last_operation_at ON ${TABLE_NAME}(last_operation_at DESC)`)
      await this.store.executeSql(`CREATE INDEX IF NOT EXISTS idx_note_sync_status ON ${TABLE_NAME}(sync_status)`)
      await this.store.executeSql(`CREATE INDEX IF NOT EXISTS idx_note_sync_deleted ON ${TABLE_NAME}(deleted)`)
      await this.migrateLegacyRows()
      this.initialized = true
    } catch (error) {
      Logger.error('DatabaseService', `init failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async getSyncState(id: string): Promise<NoteSyncState | null> {
    try {
      const store = await this.ensureStore()
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME)
      predicates.equalTo('id', id)
      const resultSet = await store.query(predicates)
      try {
        if (!resultSet || resultSet.rowCount === 0 || !resultSet.goToFirstRow()) {
          return null
        }
        return this.fromResultSet(resultSet, this.resolveColumnIndexes(resultSet))
      } finally {
        if (resultSet) {
          resultSet.close()
        }
      }
    } catch (error) {
      Logger.error('DatabaseService', `getSyncState failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async listAllSyncStates(): Promise<NoteSyncState[]> {
    try {
      const store = await this.ensureStore()
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME)
      predicates.orderByDesc('last_operation_at')
      const resultSet = await store.query(predicates)
      return this.collectRows(resultSet)
    } catch (error) {
      Logger.error('DatabaseService', `listAllSyncStates failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async listPendingNoteIds(): Promise<string[]> {
    try {
      const store = await this.ensureStore()
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME)
      predicates.notEqualTo('sync_status', 'synced')
      predicates.orderByDesc('last_operation_at')
      const resultSet = await store.query(predicates)
      return await this.collectIds(resultSet)
    } catch (error) {
      Logger.error('DatabaseService', `listPendingNoteIds failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async listDeletedSyncStates(): Promise<NoteSyncState[]> {
    try {
      const store = await this.ensureStore()
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME)
      predicates.equalTo('deleted', 1)
      predicates.orderByDesc('last_operation_at')
      const resultSet = await store.query(predicates)
      return this.collectRows(resultSet)
    } catch (error) {
      Logger.error('DatabaseService', `listDeletedSyncStates failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async upsertSyncState(state: NoteSyncState): Promise<void> {
    try {
      const store = await this.ensureStore()
      const existing = await this.getSyncState(state.noteId)
      if (!existing) {
        await store.insert(TABLE_NAME, this.toValuesBucket(state))
        return
      }
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME)
      predicates.equalTo('id', state.noteId)
      await store.update(this.toValuesBucket(state), predicates)
    } catch (error) {
      Logger.error('DatabaseService', `upsertSyncState failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async markDeleted(id: string, deletedAt: number): Promise<void> {
    const existing = await this.getSyncState(id)
    await this.upsertSyncState({
      noteId: id,
      remoteModified: existing?.remoteModified ?? 0,
      deleted: true,
      deletedAt,
      lastOperationAt: deletedAt,
      syncStatus: 'pending'
    })
  }

  async deleteSyncState(id: string): Promise<void> {
    try {
      const store = await this.ensureStore()
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME)
      predicates.equalTo('id', id)
      await store.delete(predicates)
    } catch (error) {
      Logger.error('DatabaseService', `deleteSyncState failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  async clearDeleted(id: string, remoteModified: number = 0, lastOperationAt: number = Date.now(),
    syncStatus: SyncStatus = 'synced'): Promise<void> {
    const existing = await this.getSyncState(id)
    await this.upsertSyncState({
      noteId: id,
      remoteModified: remoteModified > 0 ? remoteModified : existing?.remoteModified ?? 0,
      deleted: false,
      deletedAt: 0,
      lastOperationAt,
      syncStatus
    })
  }

  async updateSyncStatus(id: string, status: SyncStatus, remoteModified?: number, lastOperationAt?: number): Promise<boolean> {
    const existing = await this.getSyncState(id)
    const nextRemoteModified = remoteModified !== undefined ? remoteModified : existing?.remoteModified ?? 0
    const nextLastOperationAt = lastOperationAt !== undefined ? lastOperationAt : existing?.lastOperationAt ?? 0
    const nextDeleted = existing?.deleted ?? false
    const nextDeletedAt = existing?.deletedAt ?? 0
    if (existing && existing.syncStatus === status && existing.remoteModified === nextRemoteModified
      && existing.lastOperationAt === nextLastOperationAt) {
      return false
    }
    await this.upsertSyncState({
      noteId: id,
      remoteModified: nextRemoteModified,
      deleted: nextDeleted,
      deletedAt: nextDeletedAt,
      lastOperationAt: nextLastOperationAt,
      syncStatus: status
    })
    return true
  }

  async purgeDeletedBefore(deadline: number): Promise<void> {
    try {
      const store = await this.ensureStore()
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME)
      predicates.equalTo('deleted', 1)
      predicates.lessThan('deleted_at', deadline)
      await store.delete(predicates)
    } catch (error) {
      Logger.error('DatabaseService', `purgeDeletedBefore failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  private async ensureStore(): Promise<relationalStore.RdbStore> {
    if (!this.store) {
      throw new Error('DatabaseService has not been initialized')
    }
    return this.store
  }

  private async collectRows(resultSet: relationalStore.ResultSet): Promise<NoteSyncState[]> {
    const states: NoteSyncState[] = []
    try {
      if (!resultSet || resultSet.rowCount === 0 || !resultSet.goToFirstRow()) {
        return states
      }
      const indexes = this.resolveColumnIndexes(resultSet)
      states.push(this.fromResultSet(resultSet, indexes))
      while (resultSet.goToNextRow()) {
        states.push(this.fromResultSet(resultSet, indexes))
      }
      return states
    } catch (error) {
      Logger.error('DatabaseService', `collectRows failed: ${JSON.stringify(error)}`)
      throw new Error(`collectRows failed: ${JSON.stringify(error)}`)
    } finally {
      this.closeResultSet(resultSet)
    }
  }

  private async collectIds(resultSet: relationalStore.ResultSet): Promise<string[]> {
    const ids: string[] = []
    try {
      if (!resultSet || resultSet.rowCount === 0 || !resultSet.goToFirstRow()) {
        return ids
      }
      const idIndex = resultSet.getColumnIndex('id')
      ids.push(resultSet.getString(idIndex))
      while (resultSet.goToNextRow()) {
        ids.push(resultSet.getString(idIndex))
      }
      return ids
    } catch (error) {
      Logger.error('DatabaseService', `collectIds failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    } finally {
      this.closeResultSet(resultSet)
    }
  }

  private resolveColumnIndexes(resultSet: relationalStore.ResultSet): SyncStateColumnIndexes {
    try {
      return {
        id: resultSet.getColumnIndex('id'),
        remoteModified: resultSet.getColumnIndex('remote_modified'),
        deleted: resultSet.getColumnIndex('deleted'),
        deletedAt: resultSet.getColumnIndex('deleted_at'),
        lastOperationAt: resultSet.getColumnIndex('last_operation_at'),
        syncStatus: resultSet.getColumnIndex('sync_status')
      }
    } catch (error) {
      Logger.error('DatabaseService', `resolveColumnIndexes failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  private fromResultSet(resultSet: relationalStore.ResultSet, indexes: SyncStateColumnIndexes): NoteSyncState {
    try {
      return {
        noteId: resultSet.getString(indexes.id),
        remoteModified: resultSet.getLong(indexes.remoteModified),
        deleted: resultSet.getLong(indexes.deleted) === 1,
        deletedAt: resultSet.getLong(indexes.deletedAt),
        lastOperationAt: resultSet.getLong(indexes.lastOperationAt),
        syncStatus: resultSet.getString(indexes.syncStatus) as SyncStatus
      }
    } catch (error) {
      Logger.error('DatabaseService', `fromResultSet failed: ${this.describeError(error as Object)}`)
      throw this.toRuntimeError(error as Object)
    }
  }

  private toValuesBucket(state: NoteSyncState): relationalStore.ValuesBucket {
    return {
      id: state.noteId,
      remote_modified: state.remoteModified,
      deleted: state.deleted ? 1 : 0,
      deleted_at: state.deletedAt,
      last_operation_at: state.lastOperationAt,
      sync_status: state.syncStatus
    }
  }

  private async migrateLegacyRows(): Promise<void> {
    const store = await this.ensureStore()
    try {
      await store.executeSql(`
        INSERT OR IGNORE INTO ${TABLE_NAME} (id, remote_modified, deleted, deleted_at, last_operation_at, sync_status)
        SELECT id, remote_modified, deleted, deleted_at, last_operation_at, sync_status
        FROM ${LEGACY_TABLE_NAME}
      `)
    } catch (error) {
      Logger.info('DatabaseService', `migrateLegacyRows skipped: ${JSON.stringify(error)}`)
    }
  }

  private closeResultSet(resultSet?: relationalStore.ResultSet): void {
    if (!resultSet) {
      return
    }
    try {
      resultSet.close()
    } catch (error) {
      Logger.warn('DatabaseService', `closeResultSet failed: ${this.describeError(error as Object)}`)
    }
  }

  private describeError(error: Object): string {
    const raw = JSON.stringify(error)
    return raw.length > 0 && raw !== '{}' ? raw : `${error}`
  }

  private toRuntimeError(error: Object): Error {
    return new Error(this.describeError(error))
  }
}
