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

import { Any, Log } from '@ohos/flutter_ohos';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { BaseOperation } from './BaseOperation';
import { OperationResult } from './OperationResult';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Constant } from '../Constant';

export class MethodCallOperation extends BaseOperation {
  public result: Result;
  private methodCall: MethodCall;

  /**
   * 构造函数
   * @param methodCall 方法调用对象
   * @param result 方法结果对象
   */
  constructor(methodCall: MethodCall, result: MethodResult) {
    super();
    this.methodCall = methodCall;
    this.result = new Result(result);
  }

  /**
   * 获取方法名称
   * @returns 方法名称字符串
   */
  getMethod(): string {
    return this.methodCall.method;
  }

  /**
   * 获取指定键的参数
   * @param key 参数键名
   * @returns 参数值
   */
  getArgument<T>(key: string): T {
    let argument: Any = this.methodCall.argument(key);
    let sdkApiVersion = deviceInfo.sdkApiVersion;
    let isApproved =
      ((key == Constant.PARAM_SQL_ARGUMENTS) || (key == Constant.PARAM_OPERATIONS)) && (argument instanceof Array) &&
        (sdkApiVersion >= Constant.API_20);
    if (isApproved) {
      if (key == Constant.PARAM_OPERATIONS) {
        argument.forEach((argument_map: Any) => {
          let list_value: Any = argument_map.get("arguments");
          if(list_value){
            list_value.forEach((value: Any, index: number) => {
              if (typeof value == "bigint") {
                list_value.fill(value.toString(), index, index + 1);
              }
            })
          }
        })
      } else {
        argument.forEach((value: Any, index: number) => {
          if (typeof value == "bigint") {
            argument.fill(value.toString(), index, index + 1);
          }
        })
      }
    }
    return argument;
  }

  /**
   * 检查是否包含指定键的参数
   * @param key 参数键名
   * @returns true 表示包含该参数，false 表示不包含
   */
  hasArgument(key: string): boolean {
    return this.methodCall.hasArgument(key);
  }

  /**
   * 获取操作结果对象
   * @returns 操作结果对象
   */
  protected getOperationResult(): OperationResult {
    return this.result;
  }
}

class Result implements OperationResult {
  private result: MethodResult;

  /**
   * 构造函数
   * @param result 方法结果对象
   */
  constructor(result: MethodResult) {
    this.result = result;
  }

  /**
   * 报告成功结果
   * @param result 结果对象
   */
  success(result: Object): void {
    this.result.success(result);
  }

  /**
   * 报告错误结果
   * @param errorCode 错误代码
   * @param errorMessage 错误消息
   * @param data 错误数据
   */
  error(errorCode: string, errorMessage: string, data: Object): void {
    this.result.error(errorCode, errorMessage, data);
  }
}