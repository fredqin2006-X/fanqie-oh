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

import ArrayList from '@ohos.util.ArrayList';
import { ValueType } from '@ohos.data.ValuesBucket';

export class SqlCommand {
  sql: string;
  rawArguments: Array<ValueType>;

  /**
   * 构造函数
   * @param sql SQL 语句
   * @param rawArguments SQL 参数数组
   */
  constructor(sql: string, rawArguments: Array<ValueType> | undefined) {
    this.sql = sql;
    if(rawArguments == undefined) {
      rawArguments = new Array;
    }
    this.rawArguments = rawArguments;
  }

  /**
   * Handle list of int as byte[]
   * @param value 值类型
   * @returns 转换后的值
   */
  static toValue(value: ValueType): ValueType {
    return value;
  }

  /**
   * 获取 SQL 语句
   * @returns SQL 语句字符串
   */
  public getSql(): string {
    return this.sql;
  }

  /**
   * 获取原始 SQL 参数
   * @returns SQL 参数数组
   */
  public getRawSqlArguments(): Array<Object> {
    return this.rawArguments;
  }
}