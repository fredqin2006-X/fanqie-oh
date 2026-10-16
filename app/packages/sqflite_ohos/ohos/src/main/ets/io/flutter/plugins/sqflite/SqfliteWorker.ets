/*
 * Copyright (C) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
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

// 本 worker 由 SqflitePlugin 自建，主线程按 seq 路由 reply，物理上不串号。
// decode + handler 全在 worker 线程（治 B 层解码应用无响应 + A 层执行掉帧），
// 等价 Android makeBackgroundTaskQueue + DatabaseWorkerPool(THREAD_COUNT=1)。
// context 不存字段，随每条 message 透传。
// worker 内串行队列（queue + running 逐条 await）：worker async onmessage 会并发，
// 必须串行化以保证全局 static（transactionDepth/cursorMap/currentTransactionId）不竞态，
// 等价 Android 单工作线程 FIFO。
//
// 移植自 dev 分支 commit 6c42dd2（修复 issue #45/#65）。
// 当前分支 br_v2.4.2_ohos_dev 适配点：
//   - Constant 文件名为 ./Constant（dev 为 ./OhosConstant）
//   - 当前分支事务按 dbName 隔离（DatabaseHelper 管理），无 Database.resetTransactionDepth()，
//     故 handleCloseDatabaseCall 不调用它（由 DatabaseHelper.closeDatabase 处理清理）。

import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import common from '@ohos.app.ability.common';
import relationalStore from '@ohos.data.relationalStore';
// 用非 Sendable 的 StandardMethodCodec，而非 SendableStandardMethodCodec：
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';
import StringUtils from '@ohos/flutter_ohos/src/main/ets/util/StringUtils';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import Any from '@ohos/flutter_ohos/src/main/ets/plugin/common/Any';
import { Database } from './Database';
import { DatabaseHelper } from './DatabaseHelper';
import { MethodCallOperation } from './operation/MethodCallOperation';
import { Constant } from './Constant';

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;
// worker 本地实例（非 Sendable 类每个 worker 各自模块静态），不与主线程共享。
const codec = StandardMethodCodec.INSTANCE;

interface SqfliteTask {
  seq: number;
  message: ArrayBuffer;
  context: common.Context;
}

// 串行队列：逐条 await，保证 worker 内一次只处理一条 message（等价 Android THREAD_COUNT=1）。
const queue: SqfliteTask[] = [];
let running: boolean = false;

workerPort.onmessage = (e: MessageEvents): void => {
  queue.push(e.data as SqfliteTask);
  if (!running) {
    runQueue();
  }
};

// running 必须在 finally 里复位：若 handleOne reject（例如 postMessage 传输失败），
// 不复位会让此后到达的每条 message 永久滞留队列、never 派发，整条 sqflite 通道假死。
async function runQueue(): Promise<void> {
  running = true;
  try {
    while (queue.length > 0) {
      const task: SqfliteTask = queue.shift() as SqfliteTask;
      await handleOne(task.seq, task.message, task.context);
    }
  } finally {
    running = false;
  }
}

async function handleOne(seq: number, message: ArrayBuffer, context: common.Context): Promise<void> {
  let result: ArrayBuffer | null = null;
  try {
    const call: MethodCall = codec.decodeMethodCall(message);
    // reply 包装：success/error/notImplemented 把编码后的 envelope 写入 captured，
    // dispatch 完成后随 seq 回主线程（主线程按 seq 精确路由，不重写 onmessage）。
    let captured: ArrayBuffer | null = null;
    const methodResult: MethodResult = {
      success: (r: Any): void => {
        captured = codec.encodeSuccessEnvelope(r);
      },
      error: (errorCode: string, errorMessage: string, errorDetails: Any): void => {
        captured = codec.encodeErrorEnvelope(errorCode, errorMessage, errorDetails);
      },
      notImplemented: (): void => {
        captured = StringUtils.stringToArrayBuffer('');
      }
    };
    await dispatch(call, methodResult, context);
    result = captured;
    // 回执必须在 try 内发出：postMessage 自身若抛（transfer 失败/worker 已终止），
    // 走 catch 回 error envelope，并由 runQueue 的 finally 兜底复位 running，不会假死。
    workerPort.postMessage({ seq: seq, result: result }, result ? [result] : []);
  } catch (err) {
    // 兜底：保证每条 message 一定有回执（哪怕是 error），
    // 否则主线程 pending 永久残留该 seq。
    Log.e('SqfliteWorker', `handleOne error seq=${seq}: ${err}`);
    result = codec.encodeErrorEnvelope('error', String(err), null);
    try {
      workerPort.postMessage({ seq: seq, result: result }, [result]);
    } catch (e) {
      // workerPort 彻底不可用，已无法回执；记录后只能放弃
      // （runQueue 的 finally 仍会让队列复位）。
      Log.e('SqfliteWorker', `postMessage failed for seq=${seq}: ${e}`);
    }
  }
}

async function dispatch(call: MethodCall, result: MethodResult, context: common.Context): Promise<void> {
  switch (call.method) {
    case Constant.METHOD_OPEN_DATABASE:
      await DatabaseHelper.openDatabase(context, call, result);
      break;
    case Constant.METHOD_GET_DATABASES_PATH:
      handleGetDatabasesPathCall(context, result);
      break;
    case Constant.METHOD_DATABASE_EXISTS:
      await handleDatabaseExistsCall(call, result);
      break;
    case Constant.METHOD_EXECUTE:
      await handleExecuteCall(call, result);
      break;
    case Constant.METHOD_INSERT:
      await handleInsertCall(call, result);
      break;
    case Constant.METHOD_QUERY:
      await handleQueryCall(call, result);
      break;
    case Constant.METHOD_QUERY_CURSOR_NEXT:
      await handleQueryCursorNextCall(call, result);
      break;
    case Constant.METHOD_UPDATE:
      await handleUpdateCall(call, result);
      break;
    case Constant.METHOD_BATCH:
      await handleBatchCall(call, result);
      break;
    case Constant.METHOD_OPTIONS:
      DatabaseHelper.options(call, result);
      break;
    case Constant.METHOD_DEBUG:
      DatabaseHelper.onDebug(call, result);
      break;
    case Constant.METHOD_DEBUG_MODE:
      DatabaseHelper.debugMode(call, result);
      break;
    case Constant.METHOD_GET_PLATFORM_VERSION:
      DatabaseHelper.getPlatformVersion(call, result);
      break;
    case Constant.METHOD_CLOSE_DATABASE:
      await handleCloseDatabaseCall(call, result);
      break;
    case Constant.METHOD_DELETE_DATABASE:
      await handleDeleteDatabaseCall(context, call, result);
      break;
    default:
      result.notImplemented();
      break;
  }
}

///获取数据库路径
function handleGetDatabasesPathCall(context: common.Context, result: MethodResult): void {
  let appContext = context.getApplicationContext();
  let path: string = appContext.databaseDir + '/rdb';
  result.success(path);
}

///检查数据库是否存在
async function handleDatabaseExistsCall(call: MethodCall, result: MethodResult): Promise<void> {
  let dbPath: string = call.argument(Constant.PARAM_PATH) as string;
  let isExist: boolean = await DatabaseHelper.checkDatabaseExisted(dbPath);
  result.success(isExist);
}

///执行Sql
async function handleExecuteCall(call: MethodCall, result: MethodResult): Promise<void> {
  let rdbStore: relationalStore.RdbStore | null = DatabaseHelper.getDatabaseOrError(call, result);
  if (rdbStore == null) {
    return;
  }
  let operation: MethodCallOperation = new MethodCallOperation(call, result);
  await Database.execute(operation, rdbStore);
}

///插入数据
async function handleInsertCall(call: MethodCall, result: MethodResult): Promise<void> {
  let rdbStore: relationalStore.RdbStore | null = DatabaseHelper.getDatabaseOrError(call, result);
  if (rdbStore == null) {
    return;
  }
  let operation: MethodCallOperation = new MethodCallOperation(call, result);
  await Database.insert(operation, rdbStore);
}

///查询数据
async function handleQueryCall(call: MethodCall, result: MethodResult): Promise<void> {
  let rdbStore: relationalStore.RdbStore | null = DatabaseHelper.getDatabaseOrError(call, result);
  if (rdbStore == null) {
    return;
  }
  const operation: MethodCallOperation = new MethodCallOperation(call, result);
  await Database.query(operation, rdbStore);
}

///查询游标下一页数据
async function handleQueryCursorNextCall(call: MethodCall, result: MethodResult): Promise<void> {
  let operation: MethodCallOperation = new MethodCallOperation(call, result);
  await Database.queryCursorNext(operation);
}

///更新（包括删除）数据
async function handleUpdateCall(call: MethodCall, result: MethodResult): Promise<void> {
  let rdbStore: relationalStore.RdbStore | null = DatabaseHelper.getDatabaseOrError(call, result);
  if (rdbStore == null) {
    return;
  }
  let operation: MethodCallOperation = new MethodCallOperation(call, result);
  await Database.update(operation, rdbStore);
}

///batch操作
async function handleBatchCall(call: MethodCall, result: MethodResult): Promise<void> {
  let rdbStore: relationalStore.RdbStore | null = DatabaseHelper.getDatabaseOrError(call, result);
  if (rdbStore == null) {
    return;
  }
  await Database.batch(call, result, rdbStore);
}

///关闭数据库
async function handleCloseDatabaseCall(call: MethodCall, result: MethodResult): Promise<void> {
  let rdbStore: relationalStore.RdbStore | null = DatabaseHelper.getDatabaseOrError(call, result);
  if (rdbStore == null) {
    return;
  }
  // 当前分支事务按 dbName 隔离（由 DatabaseHelper 管理），closeDatabase 内部处理清理，
  // 不需要 dev 的 Database.resetTransactionDepth()（该方法在当前分支不存在）。
  await DatabaseHelper.closeDatabase(call, result);
}

///删除数据库
async function handleDeleteDatabaseCall(context: common.Context, call: MethodCall,
  result: MethodResult): Promise<void> {
  let dataBaseName: string = call.argument(Constant.PARAM_PATH) as string;
  let res = await DatabaseHelper.deleteDatabase(context, dataBaseName);
  if (res) {
    result.success(null);
  } else {
    result.error('-1', 'Delete database failed', '');
  }
}
