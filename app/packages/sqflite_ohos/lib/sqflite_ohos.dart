// Copyright (c) 2025 Huawei Device Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_HW file.
// Based on Camera.java originally written by
// Copyright 2013 The Flutter Authors.

import 'package:sqflite_platform_interface/sqflite_platform_interface.dart';

/// sqflite_darwin plugin
class SqfliteOhos extends SqflitePlatform {
  /// Main entry point called by the Flutter platform.
  ///
  /// Registers this plugin as the default database factory (if not already set).
  static void registerWith() {
    SqflitePlatform.initWithDatabaseFactoryMethodChannel();
  }
}
