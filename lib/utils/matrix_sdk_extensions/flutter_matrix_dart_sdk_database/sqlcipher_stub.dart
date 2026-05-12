import 'dart:ffi';

Future<void> applyWorkaroundToOpenSqlCipherOnOldAndroidVersions() =>
    Future.value();

DynamicLibrary openCipherOnAndroid() =>
    throw UnsupportedError('WCDB native library is only available on IO');
