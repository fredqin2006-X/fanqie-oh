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

import { Constant } from '../Constant';
import { SqlCommand } from '../SqlCommand';
import { Operation } from './Operation';
import { OperationResult } from './OperationResult';
import { ValueType } from '@ohos.data.ValuesBucket';

export abstract class BaseReadOperation implements Operation {
  /**
   * 获取 SQL 语句
   * @returns SQL 语句字符串
   */
  private getSql(): string {
    return this.getArgument(Constant.PARAM_SQL);
  }

  /**
   * 获取 SQL 参数
   * @returns SQL 参数数组
   */
  private getSqlArguments(): Array<ValueType> {
    return this.getArgument(Constant.PARAM_SQL_ARGUMENTS);
  }

  /**
   * 获取事务ID
   * @returns 事务ID，如果不在事务中则返回 null
   */
  public getTransactionId(): number | null {
    return this.getArgument(Constant.PARAM_TRANSACTION_ID);
  }

  /**
   * 检查是否有 null 的事务ID
   * @returns true 表示有 null 的事务ID，false 表示没有
   */
  public hasNullTransactionId(): boolean {
    return this.hasArgument(Constant.PARAM_TRANSACTION_ID) && this.getTransactionId() == null;
  }

  /**
   * 获取 SQL 命令对象
   * @returns SQL 命令对象
   */
  public getSqlCommand(): SqlCommand {
    return new SqlCommand(this.getSql(), this.getSqlArguments());
  }

  /**
   * 获取事务变化状态
   * @returns true 表示进入事务，false 表示退出事务
   */
  public getInTransactionChange(): boolean {
    return this.getBoolean(Constant.PARAM_IN_TRANSACTION_CHANGE);
  }

  /**
   * 获取是否不需要返回结果
   * @returns true 表示不需要返回结果，false 表示需要返回结果
   */
  getNoResult(): boolean {
    if(this.getArgument<object>(Constant.PARAM_NO_RESULT)) {
      return true;
    }
    return false;
  }

  /**
   * 获取是否忽略错误继续执行
   * @returns true 表示忽略错误继续执行，false 表示遇到错误停止
   */
  getContinueOnError(): boolean {
    if(this.getArgument<object>(Constant.PARAM_CONTINUE_OR_ERROR)) {
      return true;
    }
    return false;
  }

  /**
   * 获取指定键的布尔值
   * @param key 参数键名
   * @returns 布尔值
   */
  private getBoolean(key: string): boolean {
    let value: object = this.getArgument(key);
    if(typeof value == 'boolean') {
      return value;
    }
    return false;
  }

  /**
   * 获取操作结果对象
   * @returns 操作结果对象
   */
  protected abstract getOperationResult(): OperationResult;

  /**
   * 获取字符串表示
   * @returns 字符串表示
   */
  public toString(): string {
    return "" + this.getMethod() + "" + this.getSql() + "" + this.getSqlArguments();
  }

  /**
   * 获取方法名称
   * @returns 方法名称字符串
   */
  getMethod(): string {
    throw new Error('Method not implemented.');
  }

  /**
   * 获取指定键的参数
   * @param key 参数键名
   * @returns 参数值
   */
  getArgument<T>(key: string): T {
    throw new Error('Method not implemented.');
  }

  /**
   * 检查是否包含指定键的参数
   * @param key 参数键名
   * @returns true 表示包含该参数，false 表示不包含
   */
  hasArgument(key: string): boolean {
    throw new Error('Method not implemented.');
  }

  /**
   * 报告错误结果
   * @param errorCode 错误代码
   * @param errorMessage 错误消息
   * @param data 错误数据
   */
  error(errorCode: string, errorMessage: String, data: object): void {
    throw new Error('Method not implemented.');
  }

  /**
   * 报告成功结果
   * @param result 结果对象
   */
  success(result: object): void {
    throw new Error('Method not implemented.');
  }
}