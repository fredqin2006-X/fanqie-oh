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

// sqflite channel 移到自管理 worker 线程，修复 issue #45/#65（THREAD_BLOCK_6S appfreeze）。
// 移植自 dev 分支 commit 6c42dd2。
//
// 核心改造：不再用 MethodChannel.setMethodCallHandler（其 onMessage 在平台主线程
// 同步 StandardMethodCodec.decodeMethodCall，单次大 batch 的巨型 message 解码 >6s
// → appfreeze → 闪退）。改用 BinaryMessenger.setMessageHandler 拿【未 decode 的原始
// ArrayBuffer】，主线程只分配 seq + 存 pending[seq]=reply + postMessage 抛 worker，
// decode + 执行全在 SqfliteWorker.ets（worker 线程）。主线程 onmessage 只设一次
// 永不重写，按 seq 精确路由 reply，根治 engine 重写 onmessage 的串号 bug。
// 等价 Android makeBackgroundTaskQueue + DatabaseWorkerPool(THREAD_COUNT=1)。

import common from '@ohos.app.ability.common';
import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS';
import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import {
  BinaryMessageHandler,
  BinaryMessenger,
  BinaryReply
} from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { Constant } from './Constant';

export default class SqflitePlugin implements FlutterPlugin {
  private context: common.Context | null = null;
  private messenger: BinaryMessenger | null = null;
  private sqfliteWorker: worker.ThreadWorker | null = null;
  // seq -> reply：每条 message 的原始 BinaryReply，worker 回传时按 seq 精确匹配。
  private pending: Map<number, BinaryReply> = new Map<number, BinaryReply>();
  private seq: number = 0;

  getUniqueClassName(): string {
    return "SqflitePlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.messenger = binding.getBinaryMessenger();

    // 防御重复 attach（热重启 / 多引擎同实例）：先终止旧 worker，
    // 避免泄漏 worker 线程与 RdbStore 句柄。
    if (this.sqfliteWorker != null) {
      try {
        this.sqfliteWorker.terminate();
      } catch (e) {
        Log.e('SqflitePlugin', 'terminate previous worker failed: ' + e);
      }
      this.sqfliteWorker = null;
    }

    try {
      this.sqfliteWorker = new worker.ThreadWorker('./SqfliteWorker.ets', { name: 'SqfliteWorker' });
    } catch (e) {
      // worker 加载失败（scriptURL 解析不到 / ets 编译产物缺失）会让整条 channel 不可用。
      // 记录后继续注册 rawHandler（其对 null worker 兜底回 null reply），避免在主线程抛异常。
      Log.e('SqflitePlugin', 'create SqfliteWorker failed: ' + e);
      this.sqfliteWorker = null;
    }

    if (this.sqfliteWorker != null) {
      // 只设一次 onmessage：按 seq 精确路由 reply，永不重写——
      // 根治 engine 重写 onmessage 的串号 bug。
      this.sqfliteWorker.onmessage = (e: MessageEvents): void => {
        const data: SqfliteReply = e.data as SqfliteReply;
        const reply: BinaryReply | undefined = this.pending.get(data.seq);
        if (reply != null) {
          reply.reply(data.result);
          this.pending.delete(data.seq);
        }
      };
      this.sqfliteWorker.onerror = (e: ErrorEvent): void => {
        Log.e('SqflitePlugin', 'SqfliteWorker error: ' + e.message);
      };
    }

    // raw handler：默认（不传 taskQueue）在平台主线程执行，
    // 但拿到的是【未 decode 的原始 ArrayBuffer】。
    // decode + 执行全部丢给 worker（见 SqfliteWorker.ets），
    // 主线程只做分配 seq + 存 reply + 抛 worker。
    const rawHandler: BinaryMessageHandler = {
      onMessage: (message: ArrayBuffer, reply: BinaryReply): void => {
        // worker 不可用（构造失败或已 detach）：
        // 按 engine 契约回 null reply，不在主线程抛异常。
        if (this.sqfliteWorker == null) {
          Log.e('SqflitePlugin', 'SqfliteWorker unavailable, replying null');
          reply.reply(null);
          return;
        }
        const id: number = ++(this.seq);
        this.pending.set(id, reply);
        // context 随每条 message 透传进 worker（PR#25 同作者验证的 args 模式，
        // 避免 @Sendable 字段约束）。
        try {
          // 拷贝后转发：engine 在 onMessage 返回后可能复用该 message 的 ArrayBuffer。
          const messageCopy = message.slice(0);
          this.sqfliteWorker!.postMessageWithSharedSendable(
            { seq: id, message: messageCopy, context: this.context }, [messageCopy]);
        } catch (e) {
          // worker 在 null 检查后被终止 / 序列化失败：回滚 pending 并回 null，保证 Dart 不挂。
          Log.e('SqflitePlugin', 'postMessage to worker failed, replying null: ' + e);
          this.pending.delete(id);
          reply.reply(null);
        }
      }
    };
    this.messenger.setMessageHandler(Constant.PLUGIN_KEY, rawHandler);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.messenger != null) {
      this.messenger.setMessageHandler(Constant.PLUGIN_KEY, null);
    }
    // engine 契约要求每条 message 都必须有回执，否则 Dart 侧 reply handler 泄漏。
    // detach 时对尚在 pending（worker 尚未回执）的请求统一回 null。
    this.pending.forEach((reply: BinaryReply) => {
      try {
        reply.reply(null);
      } catch (e) {
        // ignore：引擎已关闭时 reply 可能已失效。
      }
    });
    this.pending.clear();
    this.sqfliteWorker?.terminate();
    this.sqfliteWorker = null;
  }
}

// worker 回传结构：seq 标识对应哪条原始 message，
// result 是编码后的 envelope（或 null=notImplemented）。
interface SqfliteReply {
  seq: number;
  result: ArrayBuffer | null;
}
