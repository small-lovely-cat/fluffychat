/// This library contains a workaround neccessary to open dynamic libraries on
/// old Android versions (6.0.1).
///
/// The purpose of the `sqlcipher_flutter_libs` package is to provide `sqlite3`
/// compatible native libraries when building Flutter apps for Android and iOS.
///
/// Android 端在当前项目中已改为通过 WCDB 提供底层 `sqlite3` / SQLCipher
/// 符号。这里保留原库名与 API，仅用于兼容现有 Flutter/Dart 代码。
// @dart=2.12
library sqlcipher_flutter_libs;

import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

const _platform = MethodChannel('sqlcipher_flutter_libs');

/// Workaround to open WCDB on old Android versions.
///
/// On old Android versions, this method can help if you're having issues
/// opening sqlite3 (e.g. if you're seeing crashes about `libWCDB.so` not
/// being available). To be safe, call this method before using apis from
/// `package:sqlite3` or `package:moor/ffi.dart`.
///
/// Big thanks to [@knaeckeKami](https://github.com/knaeckeKami) for finding
/// this workaround!!
Future<void> applyWorkaroundToOpenSqlCipherOnOldAndroidVersions() async {
  if (!Platform.isAndroid) return;

  try {
    DynamicLibrary.open('libWCDB.so');
  } on ArgumentError {
    // Ok, the regular approach failed. Try to open sqlite3 in Java, which seems
    // to fix the problem.
    await _platform.invokeMethod('doesnt_matter');

    // Try again. If it still fails we're out of luck.
    DynamicLibrary.open('libWCDB.so');
  }
}

DynamicLibrary openCipherOnAndroid() {
  try {
    return DynamicLibrary.open('libWCDB.so');
  } catch (_) {
    // On some (especially old) Android devices, we somehow can't dlopen
    // libraries shipped with the apk. We need to find the full path of the
    // library (/data/data/<id>/lib/libWCDB.so) and open that one.
    // For details, see https://github.com/simolus3/moor/issues/420
    final appIdAsBytes = File('/proc/self/cmdline').readAsBytesSync();

    // app id ends with the first \0 character in here.
    final endOfAppId = max(appIdAsBytes.indexOf(0), 0);
    final appId = String.fromCharCodes(appIdAsBytes.sublist(0, endOfAppId));

    return DynamicLibrary.open('/data/data/$appId/lib/libWCDB.so');
  }
}
