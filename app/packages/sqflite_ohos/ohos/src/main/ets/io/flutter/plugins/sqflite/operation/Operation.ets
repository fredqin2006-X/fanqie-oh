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

import { SqlCommand } from '../SqlCommand';
import { OperationResult } from './OperationResult';

export interface Operation extends OperationResult {
  /**
   * 获取方法名称
   * @returns 方法名称字符串
   */
  getMethod(): string;

  /**
   * 获取指定键的参数
   * @param key 参数键名
   * @returns 参数值
   */
  getArgument<T>(key: string): T;

  /**
   * 检查是否包含指定键的参数
   * @param key 参数键名
   * @returns true 表示包含该参数，false 表示不包含
   */
  hasArgument(key: string): boolean;

  /**
   * 获取 SQL 命令对象
   * @returns SQL 命令对象
   */
  getSqlCommand(): SqlCommand;

  /**
   * 获取是否不需要返回结果
   * @returns true 表示不需要返回结果，false 表示需要返回结果
   */
  getNoResult(): boolean;

  /**
   * In batch, means ignoring the error
   * @returns true 表示忽略错误继续执行，false 表示遇到错误停止
   */
  getContinueOnError(): boolean;

  /**
   * Only for execute command, true when entering a transaction, false when exiting
   * @returns true 表示进入事务，false 表示退出事务，null 表示无事务变化
   */
  getInTransactionChange(): boolean | null;

  /**
   * transaction id if any, only for within a transaction
   * @returns 事务ID，如果不在事务中则返回 null
   */
   getTransactionId(): number | null;

  /**
   * Transaction v2 support
   * @returns true 表示有 null 的事务ID，false 表示没有
   */
  hasNullTransactionId(): boolean;
}