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

import { BaseReadOperation } from './BaseReadOperation';
import { OperationResult } from './OperationResult';

export abstract class BaseOperation extends BaseReadOperation {
  /**
   * 获取操作结果对象
   * @returns 操作结果对象
   */
  protected abstract getOperationResult(): OperationResult;

  /**
   * 报告成功结果
   * @param result 结果对象
   */
  success(result: object): void {
    this.getOperationResult().success(result);
  }

  /**
   * 报告错误结果
   * @param errorCode 错误代码
   * @param errorMessage 错误消息
   * @param data 错误数据
   */
  error(errorCode: string, errorMessage: string, data: object): void {
    this.getOperationResult().error(errorCode, errorMessage, data);
  }
}