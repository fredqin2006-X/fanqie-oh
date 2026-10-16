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

import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { Constant } from '../Constant';
import { BaseOperation } from './BaseOperation';
import { OperationResult } from './OperationResult';

export class BatchOperation extends BaseOperation {
  private operationResult: BatchOperationResult = new BatchOperationResult();
  public map: Map<string, Object>;
  public noResult: boolean;

  /**
   * 构造函数
   * @param map 操作参数映射
   * @param noResult 是否不需要返回结果
   */
  constructor(map: Map<string, Object>, noResult: boolean) {
    super();
    this.map = map;
    this.noResult = noResult;
  }

  /**
   * 获取方法名称
   * @returns 方法名称字符串
   */
  getMethod(): string {
    return this.map.get(Constant.PARAM_METHOD) as string;
  }

  /**
   * 获取指定键的参数
   * @param key 参数键名
   * @returns 参数值
   */
  getArgument<T>(key: string): T {
    return this.map.get(key) as T;
  }

  /**
   * 检查是否包含指定键的参数
   * @param key 参数键名
   * @returns true 表示包含该参数，false 表示不包含
   */
  hasArgument(key: string): boolean {
    return this.map.has(key);
  }

  /**
   * 获取操作结果对象
   * @returns 操作结果对象
   */
  getOperationResult(): OperationResult {
    return this.operationResult;
  }

  /**
   * 获取操作成功结果
   * @returns 包含结果的成功映射
   */
  public getOperationSuccessResult(): Map<string, Object | null> {
    let results: Map<string, Object | null> = new Map<string, Object | null>();
    results.set(Constant.PARAM_RESULT, this.operationResult.result);
    return results;
  }

  /**
   * 获取操作错误信息
   * @returns 包含错误详情的错误映射
   */
  public getOperationError(): Map<string, Object> {
    let error: Map<string, Object> = new Map<string, Object>();
    let errorDetail: Map<string, Object> = new Map<string, Object>();
    errorDetail.set(Constant.PARAM_ERROR_CODE, this.operationResult.errorCode);
    errorDetail.set(Constant.PARAM_ERROR_MESSAGE, this.operationResult.errorMessage);
    errorDetail.set(Constant.PARAM_ERROR_DATA, this.operationResult.errorData);
    error.set(Constant.PARAM_ERROR, errorDetail);
    return error;
  }

  /**
   * 处理错误结果
   * @param result 方法结果对象
   */
  public handleError(result: MethodResult): void {
    result.error(this.operationResult.errorCode, this.operationResult.errorMessage, this.operationResult.errorData);
  }

  /**
   * 获取是否不需要返回结果
   * @returns true 表示不需要返回结果，false 表示需要返回结果
   */
  getNoResult(): boolean {
    return this.noResult;
  }

  /**
   * 处理成功结果
   * @param results 结果数组
   */
  public handleSuccess(results: Array<Map<string, Object | null>>): void {
    if(!this.getNoResult()) {
      results.push(this.getOperationSuccessResult());
    }
  }

  /**
   * 处理错误并继续执行
   * @param results 结果数组
   */
  public handleErrorContinue(results: Array<Map<string, Object>>): void {
    if(!this.getNoResult()) {
      results.push(this.getOperationError());
    }
  }
}

export class BatchOperationResult implements OperationResult {
  // success
  result: Object | null = null;
  // error
  errorCode: string = '';
  errorMessage: string = '';
  errorData: Object = '';

  /**
   * 报告错误结果
   * @param errorCode 错误代码
   * @param errorMessage 错误消息
   * @param data 错误数据
   */
  error(errorCode: string, errorMessage: string, data: Object): void {
    this.errorCode = errorCode;
    this.errorMessage = errorMessage;
    this.errorData = data;
  }

  /**
   * 报告成功结果
   * @param result 结果对象
   */
  success(result: Object): void {
    this.result = result;
  }
}

export class OperationError {
  public errorCode: string;
  public errorMessage: string;
  public errorData: Object;

  /**
   * 构造函数
   * @param errorCode 错误代码
   * @param errorMessage 错误消息
   * @param data 错误数据
   */
  constructor(errorCode: string, errorMessage: string, data: Object) {
    this.errorCode = errorCode;
    this.errorMessage = errorMessage;
    this.errorData = data;
  }
}