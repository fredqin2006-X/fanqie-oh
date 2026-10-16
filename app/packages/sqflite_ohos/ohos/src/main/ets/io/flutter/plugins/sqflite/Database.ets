/*
* Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import common from '@ohos.app.ability.common';
import relationalStore from '@ohos.data.relationalStore';
import { Operation } from './operation/Operation';
import { SqlCommand } from './SqlCommand';
import { ValueType } from '@ohos.data.ValuesBucket';
import { Constant } from './Constant';
import { BusinessError } from '@ohos.base';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { SqlErrorInfo } from './operation/SqlErrorInfo';
import { MethodCallOperation } from './operation/MethodCallOperation';
import { BatchOperation } from './operation/BatchOperation';
import { Any, Log } from '@ohos/flutter_ohos';
import {
  AttachHandler,
  BeginExclusiveHandler,
  BeginImmediateHandler,
  CommitHandler,
  DetachHandler,
  ISqlHandler,
  RollbackHandler
} from './SqlHandler';
import { deviceInfo } from '@kit.BasicServicesKit';
import { DatabaseHelper } from './DatabaseHelper';


type HandleCallback = (x: Object) => void;

export class Database {
  public context: common.Context;
  public path: string;
  public id: number;
  public singleInstance: boolean;
  public logLevel: number;
  // 事务ID计数器（全局唯一）
  private static lastTransactionId: number = 0;
  // 当前事务ID（临时存储，用于返回给调用方）
  private static currentTransactionId: number | null;
  // 游标管理用于分页查询
  private static cursorMap: Map<number, relationalStore.ResultSet> = new Map();
  private static lastCursorId: number = 0;

  constructor(context: common.Context, path: string, id: number, singleInstance: boolean, logLevel: number) {
    this.context = context;
    this.path = path;
    this.id = id;
    this.singleInstance = singleInstance;
    this.logLevel = logLevel;
  }

  private static handlers: ISqlHandler[] = [
    new BeginImmediateHandler(),
    new CommitHandler(),
    new RollbackHandler(),
    new BeginExclusiveHandler(),
    new AttachHandler(),
    new DetachHandler()
  ];

  private static async handleException(operation: Operation, err: BusinessError<void>,
    db?: relationalStore.RdbStore): Promise<void> {
    let code = err.code;
    let message = err.message;
    if (code == Constant.RDB_ERROR_CODE_14800000) {
      operation.success(null);
      return;
    } else if (code == Constant.RDB_ERROR_CODE_14800021) {
      Database.handleTableOrSyntaxError(operation, message);
    } else if (code == Constant.RDB_ERROR_CODE_14800032) {
      await Database.handleConstraintViolation(operation, db);
    } else if (code == Constant.RDB_ERROR_CODE_14800011) {
      // 14800011 表示数据库文件损坏（如非 sqlite 文件），对应 SQLite 的 "file is not a database"
      // 映射为 sqlite_error + "file is not a database"，与 Android/iOS 的查询阶段错误格式一致
      operation.error(Constant.SQLITE_ERROR, 'file is not a database', SqlErrorInfo.getMap(operation));
    } else if (code == Constant.RDB_ERROR_CODE_801) {
      operation.error(Constant.SQLITE_ERROR, 'error code:' + code + '。' + " Database is readonly",
        SqlErrorInfo.getMap(operation));
    } else {
      operation.error(Constant.SQLITE_ERROR, 'error code:' + code + '。' + message, SqlErrorInfo.getMap(operation));
    }
  }

  /**
   * 处理表不存在或语法错误（错误码 14800021）
   */
  private static handleTableOrSyntaxError(operation: Operation, message: string): void {
    let normalizedMessage = message;
    const sql = operation.getSqlCommand()?.getSql() || '';
    // CREATE TABLE 命中 14800021 时只可能是“表已存在”或保留字语法错误，不可能是 no such table，
    // 用于在 message 不含 “already exists” 字样时兜底。
    const createTableMatch = sql.match(/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)/i);

    // 表已存在（如 CREATE TABLE 重复建表）：OHOS 的通用文案
    // “Generic error...the updated data does not exist...table X already exists”
    // 同样包含 “does not exist” 字样，必须先于“表不存在”分支判定，避免误报。
    if (message.toLowerCase().includes('already exists')) {
      normalizedMessage = createTableMatch != null
        ? `table ${createTableMatch[1]} already exists`
        : `table already exists`;
    } else if (createTableMatch != null &&
      (message.includes('does not exist') || message.includes('Generic error'))) {
      // 部分设备实测 OHOS 抛出的 BusinessError.message 只含通用文案
      // “SQLite: Generic error...updated data does not exist.”，不含 “already exists” 字样，
      // 因此按 CREATE TABLE 语句类型兜底；保留字表名仍判为语法错误。
      const tableName = createTableMatch[1];
      const isReserved =
        Constant.SQL_RESERVED_WORDS.some(kw => tableName.toLowerCase() === kw.toLowerCase());
      normalizedMessage = isReserved ? `syntax error` : `table ${tableName} already exists`;
    } else if (message.includes('Insert failed') || message.includes('updated data does not') ||
      message.includes('does not exist')) {
      // 判断表不存在：Insert failed | updated data does not exist | does not exist
      normalizedMessage = Database.normalizeTableNotFoundError(operation, message);
    } else if (message.includes('not supported') ||
      (message.includes('Generic error') && !message.includes('Insert failed'))) {
      // 判断语法错误：not supported 或 纯粹的 Generic error（不包含 Insert failed）
      normalizedMessage = `syntax error`;
    }

    operation.error(Constant.SQLITE_ERROR, normalizedMessage, SqlErrorInfo.getMap(operation));
  }

  /**
   * 规范化表不存在错误消息
   */
  private static normalizeTableNotFoundError(operation: Operation, message: string): string {
    // 获取 SQL 语句用于错误类型推断
    const sql = operation.getSqlCommand()?.getSql() || '';
    // 从 SQL 中提取表名
    const tableMatch = sql.match(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|FROM|CREATE\s+TABLE)\s+(\w+)/i);

    if (tableMatch) {
      const tableName = tableMatch[1];
      // 检查表名是否为SQLite保留字(完整列表)
      const reservedWords = Constant.SQL_RESERVED_WORDS;
      if (reservedWords.some(kw => tableName.toLowerCase() === kw.toLowerCase())) {
        return `syntax error`;
      } else {
        return `no such table: ${tableName}`;
      }
    } else {
      // 无法提取表名时，也返回语法错误
      return `syntax error`;
    }
  }

  /**
   * 处理唯一约束或主键冲突（错误码 14800032）
   */
  private static async handleConstraintViolation(operation: Operation, db?: relationalStore.RdbStore): Promise<void> {
    const sql = operation.getSqlCommand()?.getSql() || '';
    let resultCode = Constant.SQLITE_CONSTRAINT_UNIQUE;
    let errorMessage = 'UNIQUE constraint failed';

    const insertMatch = sql.match(/INSERT\s+INTO\s+(\w+)\s*\((\w+)\)/i);

    if (insertMatch && db) {
      const tableName = insertMatch[1];
      const columnName = insertMatch[2];

      // 检查列是否为主键
      const isPrimaryKey = await Database.checkIfPrimaryKey(db, tableName, columnName);
      if (isPrimaryKey) {
        resultCode = Constant.SQLITE_CONSTRAINT_PRIMARYKEY; // 1555
      }

      errorMessage = `UNIQUE constraint failed: ${tableName}.${columnName}`;
    }

    const finalMessage = `${errorMessage} (code ${resultCode})`;
    operation.error(Constant.SQLITE_ERROR, finalMessage, SqlErrorInfo.getMap(operation));
  }

  /**
   * 检查列是否为主键
   */
  private static async checkIfPrimaryKey(db: relationalStore.RdbStore, tableName: string,
    columnName: string): Promise<boolean> {
    try {
      const resultSet = await db.querySql(`PRAGMA table_info(${tableName})`);
      while (resultSet.goToNextRow()) {
        const row = resultSet.getRow();
        if (row['name'] === columnName && row['pk'] === 1) {
          resultSet.close();
          return true;
        }
      }
      resultSet.close();
    } catch (e) {
      Log.e(Constant.TAG, `Failed to query table_info: ${e}`);
    }
    return false;
  }

  /**
   * 判断 SQL 是否为 DDL 语句 (需要使用 executeSql 而不是 execute)
   * @param sql SQL 语句
   * @returns true 如果是 DDL 语句
   */
  private static isDDL(sql: string): boolean {
    const upperSql = sql.trim().toUpperCase();
    return upperSql.startsWith('CREATE ') ||
    upperSql.startsWith('DROP ') ||
    upperSql.startsWith('ALTER ') ||
    upperSql.startsWith('TRUNCATE ');
  }

  private static async executeOrError(operation: Operation, db: relationalStore.RdbStore,
    callback?: HandleCallback): Promise<boolean> {
    let command: SqlCommand = operation.getSqlCommand();
    let sqlArguments: ValueType[] | undefined = operation.getArgument(Constant.PARAM_SQL_ARGUMENTS);
    let sql: string = command.getSql();
    let promise: ValueType | undefined;
    try {
      // 防御：并发下解码偶发损坏导致 sql 字段缺失时，返回明确错误，避免 isDDL 里
      // undefined.trim() 抛 TypeError 误导（曾误报为 “Cannot read property trim of undefined”）。
      if (!sql) {
        Log.e('Database', '[executeOrError] FAILED: sql is undefined (message decode corrupted)');
        operation.error(Constant.SQLITE_ERROR, 'invalid sql argument: missing sql field',
          SqlErrorInfo.getMap(operation));
        return false;
      }
      // DDL 语句(CREATE/DROP/ALTER)需要使用 executeSql
      const isDDL = Database.isDDL(sql);

      if (isDDL) {
        // executeSql 不支持参数，DDL 语句通常也不需要参数
        await db.executeSql(sql);
        // 如果在事务内且是CREATE TABLE,记录表名以处理ohos事务隔离问题
        // 使用按数据库隔离的事务深度，替代全局 transactionDepth
        const dbId: number | undefined = operation.getArgument<number>(Constant.PARAM_ID);
        if (dbId !== undefined) {
          const dbName: string | undefined = DatabaseHelper.dbIdMap.get(dbId);
          if (dbName !== undefined && DatabaseHelper.isDatabaseInTransaction(dbName)) {
            const createMatch = sql.match(/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)/i);
            if (createMatch) {
              const tableName = createMatch[1];
              // 使用按dbName隔离的事务创建表记录
              DatabaseHelper.addTransactionCreatedTable(dbName, tableName);
            }
          }
        }
        promise = undefined; // DDL 语句没有返回值
      } else {
        if (sqlArguments == undefined || sqlArguments.length < 1) {
          promise = await db.execute(sql) as ValueType;
        } else {
          promise = await db.execute(sql, sqlArguments) as ValueType;
        }
      }
      if (callback != undefined && promise !== undefined) {
        callback(promise);
      }
      return true;
    } catch (err) {
      const businessErr = err as BusinessError<void>;
      // 诊断：打印失败 SQL 与参数，便于定位 401（Parameter error）/ 14800021 等错误的具体操作。
      // 并发压力下若 sqlArguments 出现 undefined 元素，RDB 会报 "The X must be ValueObject"。
      Log.e('Database', `[executeOrError] FAILED sql="${sql}", code=${businessErr.code}, ` +
        `message=${businessErr.message}, argsLen=${sqlArguments?.length}, args0=${sqlArguments?.[0]}`);
      await Database.handleException(operation, err, db);
      return false;
    }
  }

  /**
   * execute
   * @param operation 操作对象
   * @param db 数据库实例
   */
  public static async execute(operation: Operation, db: relationalStore.RdbStore): Promise<void> {
    const sql = operation.getSqlCommand().getSql();
    const inTransactionChangeValue: object = operation.getArgument<object>(Constant.PARAM_IN_TRANSACTION_CHANGE);
    const inTransactionChange: boolean | null =
      (typeof inTransactionChangeValue === 'boolean') ? inTransactionChangeValue as boolean : null;
    const enteringTransaction: boolean = (inTransactionChange === true) && operation.hasNullTransactionId();

    if (enteringTransaction) {
      Database.currentTransactionId = ++(Database.lastTransactionId);
    }

    const handler = Database.handlers.find((h) => h.match(sql));
    let success: boolean;
    if (handler) {
      const result = handler.execute(sql, operation, db);
      success = result instanceof Promise ? await result : result;
    } else {
      success = await Database.executeOrError(operation, db);
    }

    if (handler?.needsPostProcess ?? true) {
      if (success && inTransactionChange !== null) {
        const dbId: number | undefined = operation.getArgument<number>(Constant.PARAM_ID);
        if (dbId !== undefined) {
          DatabaseHelper.noteTransactionChangeByDbId(dbId, inTransactionChange);

          // 如果是离开事务(COMMIT或ROLLBACK)，清空该数据库的事务创建表记录（按dbName隔离）
          if (inTransactionChange === false) {
            const dbName = DatabaseHelper.dbIdMap.get(dbId);
            if (dbName !== undefined) {
              DatabaseHelper.clearTransactionCreatedTablesByDbName(dbName);
            }
          }
        }
      }

      Database.handleExecute(success, enteringTransaction, operation, inTransactionChange);
    }
  }

  private static handleExecute(executeSuccess: boolean, enteringTransaction: boolean, operation: Operation,
    inTransactionChange: boolean | null) {
    if (!executeSuccess) {
      // Revert if needed
      if (enteringTransaction) {
        Database.currentTransactionId = null;
      }
    } else if (enteringTransaction) {
      /// Return the transaction id;
      if (Database.currentTransactionId != null) {
        let res: Map<String, Object> = new Map();
        res.set(Constant.PARAM_TRANSACTION_ID, Database.currentTransactionId);
        operation.success(res);
      } else {
        operation.success(null);
      }
    } else {
      if (inTransactionChange == false) {
        Database.currentTransactionId = null;
      }
      operation.success(null);
    }
  }

  public static async doExecute(operation: Operation, db: relationalStore.RdbStore): Promise<boolean> {
    let executeSuccess: boolean = await Database.executeOrError(operation, db);
    if (!executeSuccess) {
      return false;
    }
    operation.success(null);
    return true;
  }

  /**
   * insert
   * @param operation 操作对象
   * @param db 数据库实例
   */
  public static async insert(operation: Operation, db: relationalStore.RdbStore): Promise<void> {
    await Database.doInsert(operation, db);
  }

  private static async doInsert(operation: Operation, db: relationalStore.RdbStore): Promise<boolean> {
    let rowIdResult: number = 0;
    // 使用 callback 捕获 executeOrError 返回的 rowId
    let executeSuccess: boolean = await Database.executeOrError(operation, db, (rowId) => {
      rowIdResult = rowId as number;
    });
    if (!executeSuccess) {
      return false;
    }

    // 如果不需要返回结果，直接返回 null
    if (operation.getNoResult()) {
      operation.success(null);
      return true;
    }

    // 如果 rowId <= 0 (比如 ON CONFLICT IGNORE),直接返回 null 与android 和IOS 保持一致
    if (rowIdResult <= 0) {
      operation.success(null);
      return true;
    }

    // 正常情况,返回 executeOrError 已经设置的 rowId
    operation.success(rowIdResult);
    return true;
  }

  /**
   * update
   * @param operation 操作对象
   * @param db 数据库实例
   */
  public static async update(operation: Operation, db: relationalStore.RdbStore): Promise<void> {
    await Database.doUpdate(operation, db);
  }

  private static async doUpdate(operation: Operation, db: relationalStore.RdbStore): Promise<boolean> {
    let executeSuccess: boolean = await Database.executeOrError(operation, db, (rows) => {
      operation.success(rows);
    });
    if (!executeSuccess) {
      return false;
    }

    // don't get last id if not expected
    if (operation.getNoResult()) {
      operation.success(null);
      return true;
    }
    return true;
  }

  /**
   * query
   * @param operation 操作对象
   * @param db 数据库实例
   */
  public static async query(operation: Operation, db: relationalStore.RdbStore): Promise<void> {
    await Database.doQuery(operation, db);
  }

  /**
   * queryCursorNext - 获取游标的下一页数据
   * @param operation 操作对象
  */
  // 改为 async：worker 串行队列依赖 queryCursorNext 完成后 captured 才写入，
  // catch 里的 handleException 是异步的（14800032 分支 await handleConstraintViolation），
  // 不 await 会在 captured=null 时提前回 null reply -> MissingPluginException。
  public static async queryCursorNext(operation: Operation): Promise<void> {
    const cursorId: number = operation.getArgument(Constant.PARAM_CURSOR_ID);
    const cancel: boolean = operation.getArgument(Constant.PARAM_CANCEL) ?? false;

    // 如果是取消操作，关闭并删除游标
    if (cancel) {
      Database.closeCursor(cursorId);
      operation.success(null);
      return;
    }

    // 获取保存的 ResultSet
    const resultSet = Database.cursorMap.get(cursorId);
    if (!resultSet) {
      operation.error(Constant.SQLITE_ERROR, `Cursor not found: ${cursorId}`, SqlErrorInfo.getMap(operation));
      return;
    }

    const cursorPageSize: number | undefined = operation.getArgument(Constant.PARAM_CURSOR_PAGE_SIZE);
    let cursorHasMoreData = false;

    try {
      // 继续读取下一页数据
      let results = Database.handleQuerySqlResult(resultSet, cursorPageSize);

      // 判断是否还有更多数据
      cursorHasMoreData = !resultSet.isAtLastRow;

      if (cursorHasMoreData) {
        // 继续保存 cursorId
        results.set(Constant.PARAM_CURSOR_ID, cursorId as Object);
      }

      operation.success(results);
    } catch (err) {
      await Database.handleException(operation, err as BusinessError<void>);
      cursorHasMoreData = false;
    } finally {
      // 没有更多数据时关闭游标
      if (!cursorHasMoreData) {
        Database.closeCursor(cursorId);
      }
    }
  }

  /**
   * closeCursor - 关闭并删除游标
   * @param cursorId 游标ID
   */
  private static closeCursor(cursorId: number): void {
    const resultSet = Database.cursorMap.get(cursorId);
    if (resultSet) {
      try {
        resultSet.close();
        Database.cursorMap.delete(cursorId);
      } catch (err) {
        Log.e('Database', `Error closing cursor ${cursorId}: ${err}`);
      }
    }
  }

  /**
   * 处理用户版本查询
   */
  private static handleUserVersionQuery(operation: Operation, db: relationalStore.RdbStore): boolean {
    try {
      let versionMap: Map<String, object> = new Map<String, object>();
      versionMap.set(Constant.PARAM_COLUMNS, ['user_version']);
      versionMap.set(Constant.PARAM_ROWS, [[db.version]]);
      operation.success(versionMap);
      return true;
    } catch (err) {
      Database.handleException(operation, err);
      Log.e('Database', `doQuery err ${err}`);
      return false;
    }
  }

  /**
   * 执行 SQL 查询并返回 ResultSet
   */
  private static async executeQuery(sql: string, sqlArguments: ValueType[] | undefined,
    db: relationalStore.RdbStore): Promise<relationalStore.ResultSet> {
    if (sqlArguments != undefined) {
      return await db.querySql(sql, sqlArguments);
    } else {
      return await db.querySql(sql);
    }
  }

  /**
   * 验证查询结果，检查表是否存在
   */
  private static validateQueryResult(operation: Operation, resultSet: relationalStore.ResultSet, sql: string): boolean {
    // querySql 在表不存在或SQL语法错误时不会抛出异常，而是返回 columnCount=0 的空结果，需要检测这种情况并主动抛出异常
    if (resultSet.columnCount === 0) {
      return Database.handleEmptyResultSet(operation, sql);
    }
    return true;
  }

  /**
   * 处理空结果集（表不存在或语法错误）
   */
  private static handleEmptyResultSet(operation: Operation, sql: string): boolean {
    const tableMatch = sql.match(/FROM\s+(\w+)/i);

    if (tableMatch) {
      const tableName = tableMatch[1];
      const tableNameLower = tableName.toLowerCase();

      // 检查表是否在当前事务内创建
      // 使用按数据库隔离的事务深度，替代全局 transactionDepth
      const dbId: number | undefined = operation.getArgument<number>(Constant.PARAM_ID);
      let isInTransaction = false;
      let dbName: string | undefined = undefined;
      if (dbId !== undefined) {
        dbName = DatabaseHelper.dbIdMap.get(dbId);
        if (dbName !== undefined) {
          isInTransaction = DatabaseHelper.isDatabaseInTransaction(dbName);
        }
      }

      // 使用按dbName隔离的事务创建表记录检查
      const tableCreatedInTransaction = dbName !== undefined
        ? DatabaseHelper.hasTransactionCreatedTable(dbName, tableNameLower)
        : false;

      if (!isInTransaction || !tableCreatedInTransaction) {
        const reservedTableNames = ['table', 'index', 'group', 'order', 'select', 'where'];
        const isReservedTableName = reservedTableNames.includes(tableNameLower);

        const errorMessage = isReservedTableName ? 'Generic error' : `Table does not exist: ${tableName}`;
        Database.handleException(operation, {
          code: Constant.RDB_ERROR_CODE_14800021,
          message: errorMessage
        } as BusinessError<void>);
        return false;
      }
    } else {
      // 无法提取表名，说明SQL语法错误
      Database.handleException(operation, {
        code: Constant.RDB_ERROR_CODE_14800021,
        message: `syntax error`
      } as BusinessError<void>);
      return false;
    }

    return true;
  }

  /**
   * 处理游标分页（保存 ResultSet 以便后续分页）
   */
  private static handleCursorPagination(resultSet: relationalStore.ResultSet, cursorPageSize: number | undefined,
    results: Map<String, object>): number | null {
    // 判断是否需要保存 ResultSet
    let cursorHasMoreData = false;
    if (cursorPageSize != null && cursorPageSize > 0) {
      cursorHasMoreData = !resultSet.isAtLastRow;
    }

    if (cursorHasMoreData) {
      // 保存 ResultSet
      Database.lastCursorId++;
      const savedCursorId = Database.lastCursorId;
      Database.cursorMap.set(savedCursorId, resultSet);
      results.set(Constant.PARAM_CURSOR_ID, savedCursorId as Object);
      return savedCursorId;
    }

    return null;
  }

  private static async doQuery(operation: Operation, db: relationalStore.RdbStore): Promise<boolean> {
    let command: SqlCommand = operation.getSqlCommand();
    let sql: string = command.getSql();

    // 特殊处理：用户版本查询
    if (sql == Constant.SQL_PRAGMA_USER_VERSION) {
      return Database.handleUserVersionQuery(operation, db);
    }

    let cursorPageSize: number | undefined = operation.getArgument(Constant.PARAM_CURSOR_PAGE_SIZE);
    let sqlArguments: ValueType[] | undefined = operation.getArgument(Constant.PARAM_SQL_ARGUMENTS);
    let resultSet: relationalStore.ResultSet | null = null;
    let savedCursorId: number | null = null;

    try {
      // 执行查询
      resultSet = await Database.executeQuery(sql, sqlArguments, db);

      // 验证查询结果
      if (!Database.validateQueryResult(operation, resultSet, sql)) {
        return false;
      }

      // 读取数据
      let results = Database.handleQuerySqlResult(resultSet, cursorPageSize);

      // 处理游标分页
      savedCursorId = Database.handleCursorPagination(resultSet, cursorPageSize, results);

      operation.success(results);
      return true;

    } catch (err) {
      Log.e('Database',
        `doQuery caught exception: code=${(err as BusinessError<void>).code}, message=${(err as BusinessError<void>).message}`);
      Database.handleException(operation, err);
      // 异常时清理
      if (savedCursorId != null) {
        Database.cursorMap.delete(savedCursorId);
      }
      return false;
    } finally {
      // 如果没有保存，就关闭 ResultSet
      if (savedCursorId == null && resultSet != null) {
        resultSet.close();
      }
    }
  }

  private static handleQuerySqlResult(resultSet: relationalStore.ResultSet,
    cursorPageSize: number | undefined): Map<String, object> {
    let results: Map<String, object> = new Map<String, Object>();
    let rows: Array<Array<Object>> = new Array<Array<Object>>();
    let columns: Array<string> | null = null;
    let valuesType: Array<string> | null = null;
    let columnCount: number = 0;

    // resultSet是一个数据集合得游标，默认值想第-1个记录，有效的数据从0开始
    while (resultSet.goToNextRow()) {
      if (columns == null) {
        columnCount = resultSet.columnCount;
        columns = new Array<string>();
        valuesType = new Array<string>();
        let row: Record<string, ValueType> = resultSet.getRow() as Record<string, ValueType>;
        for (let i = 0; i < columnCount; i++) {
          let columnName = resultSet.getColumnName(i);
          columns.push(columnName);
          let valueType: string = typeof row[columnName];
          valuesType.push(valueType);
        }
        results.set(Constant.PARAM_COLUMNS, columns);
        results.set(Constant.PARAM_ROWS, rows);
      }

      let row = Database.cursorRowToList(resultSet, columnCount, valuesType);
      rows.push(row);

      // 分页支持：读够指定数量后停止
      if (cursorPageSize != null && cursorPageSize > 0) {
        if (rows.length >= cursorPageSize) {
          break;
        }
      }
    }

    return results;
  }

  static cursorRowToList(cursor: relationalStore.ResultSet, length: number,
    valuesType: Array<string> | null): Array<Object> {
    let list = new Array<Object>();

    for (let i = 0; i < length; i++) {
      let value: Object = Database.cursorValue(cursor, i, valuesType![i]);
      list.push(value);
    }
    return list;
  }

  static cursorValue(cursor: relationalStore.ResultSet, index: number, valueType: Any | null): Any {
    if ('number' == valueType) {
      let value = cursor.getString(index);
      let isIntegerString = /^-?\d+$/.test(value);
      if (value && isIntegerString) {
        let valueBig = BigInt(value);
        if (valueBig > Number.MAX_SAFE_INTEGER || valueBig < Number.MIN_SAFE_INTEGER) {
          return valueBig;
        } else {
          return Number.parseInt(valueBig.toString());
        }
      }
    }
    return cursor.getValue(index);
  }

  /// batch
  public static async batch(call: MethodCall, result: MethodResult, db: relationalStore.RdbStore): Promise<void> {

    let mainOperation: MethodCallOperation = new MethodCallOperation(call, result);
    let noResult: boolean = mainOperation.getNoResult();
    let continueOnError: boolean = mainOperation.getContinueOnError();

    let operations: Array<Map<string, Object>> =
      mainOperation.getArgument(Constant.PARAM_OPERATIONS) as Array<Map<string, Object>>;
    let results: Array<Map<string, Object>> = new Array();

    for (let index = 0; index < operations.length; index++) {

      const map: Map<string, Object> = operations[index];
      let operation: BatchOperation = new BatchOperation(map, noResult);
      const method: string = operation.getMethod();

      let executeSuc: boolean;
      switch (method) {
        case Constant.METHOD_EXECUTE:
          executeSuc = await Database.doExecute(operation, db);
          if (executeSuc) {
            operation.handleSuccess(results);
          } else if (continueOnError) {
            operation.handleErrorContinue(results);
          } else {
            operation.handleError(result);
            return;
          }
          break;
        case Constant.METHOD_INSERT:
          executeSuc = await Database.doInsert(operation, db);
          if (executeSuc) {
            operation.handleSuccess(results);
          } else if (continueOnError) {
            operation.handleErrorContinue(results);
          } else {
            operation.handleError(result);
            return;
          }
          break;
        case Constant.METHOD_QUERY:
          executeSuc = await Database.doQuery(operation, db);
          if (executeSuc) {
            operation.handleSuccess(results);
          } else if (continueOnError) {
            operation.handleErrorContinue(results);
          } else {
            operation.handleError(result);
            return;
          }
          break;
        case Constant.METHOD_UPDATE:
          executeSuc = await Database.doUpdate(operation, db);
          if (executeSuc) {
            operation.handleSuccess(results);
          } else if (continueOnError) {
            operation.handleErrorContinue(results);
          } else {
            operation.handleError(result);
            return;
          }
          break;
        default:
          result.error(Constant.ERROR_BAD_PARAM, "Batch method " + method + "not supported", null);
          return;
      }
    }
    if (noResult) {
      result.success(null);
    } else {
      result.success(results);
    }
  }
}