import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/services.dart';

const _appLockMethodChannel = MethodChannel('chat.fluffy.app_lock/auth');

enum AppLockAuthMethod {
  pin,
  soter,
  systemBiometric;

  bool get isBiometric => this != AppLockAuthMethod.pin;

  bool get isSupportedOnCurrentPlatform => switch (this) {
    AppLockAuthMethod.pin => true,
    AppLockAuthMethod.soter => PlatformInfos.isAndroid,
    AppLockAuthMethod.systemBiometric =>
      PlatformInfos.isAndroid || PlatformInfos.isIOS,
  };

  String get storageValue => switch (this) {
    AppLockAuthMethod.pin => 'pin',
    AppLockAuthMethod.soter => 'soter',
    AppLockAuthMethod.systemBiometric => 'system_biometric',
  };

  static AppLockAuthMethod fromStorage(String? value) {
    return AppLockAuthMethod.values.firstWhere(
      (method) => method.storageValue == value,
      orElse: () => AppLockAuthMethod.pin,
    );
  }
}

class AppLockBiometricAvailability {
  final bool nativeSupported;
  final bool soterSupported;
  final bool soterReady;
  final String? message;

  const AppLockBiometricAvailability({
    this.nativeSupported = false,
    this.soterSupported = false,
    this.soterReady = false,
    this.message,
  });

  factory AppLockBiometricAvailability.fromMap(Map<String, Object?> map) {
    return AppLockBiometricAvailability(
      nativeSupported: map['nativeSupported'] == true,
      soterSupported: map['soterSupported'] == true,
      soterReady: map['soterReady'] == true,
      message: map['message'] as String?,
    );
  }
}

class AppLockBiometricResult {
  final bool success;
  final bool cancelled;
  final bool shouldFallbackToNative;
  final String? errorCode;
  final String? message;

  const AppLockBiometricResult({
    required this.success,
    this.cancelled = false,
    this.shouldFallbackToNative = false,
    this.errorCode,
    this.message,
  });

  factory AppLockBiometricResult.fromMap(Map<String, Object?> map) {
    return AppLockBiometricResult(
      success: map['success'] == true,
      cancelled: map['cancelled'] == true,
      shouldFallbackToNative: map['shouldFallbackToNative'] == true,
      errorCode: map['errorCode'] as String?,
      message: map['message'] as String?,
    );
  }
}

abstract class AppLockBiometricService {
  static Future<AppLockBiometricAvailability> getAvailability() async {
    if (!PlatformInfos.isAndroid && !PlatformInfos.isIOS) {
      return const AppLockBiometricAvailability();
    }
    try {
      final result = await _appLockMethodChannel.invokeMethod<Object?>(
        'getCapabilities',
      );
      final map = Map<String, Object?>.from((result as Map?) ?? const {});
      return AppLockBiometricAvailability.fromMap(map);
    } on PlatformException catch (e) {
      return AppLockBiometricAvailability(message: e.message);
    }
  }

  static Future<AppLockBiometricResult> prepareSoter() async {
    if (!PlatformInfos.isAndroid) {
      return const AppLockBiometricResult(success: false);
    }
    try {
      final result = await _appLockMethodChannel.invokeMethod<Object?>(
        'prepareSoter',
      );
      final map = Map<String, Object?>.from((result as Map?) ?? const {});
      return AppLockBiometricResult.fromMap(map);
    } on PlatformException catch (e) {
      return AppLockBiometricResult(
        success: false,
        shouldFallbackToNative: true,
        errorCode: e.code,
        message: e.message,
      );
    }
  }

  static Future<AppLockBiometricResult> authenticate(
    AppLockAuthMethod method, {
    String? title,
    String? subtitle,
    String? negativeButton,
  }) async {
    if (!method.isBiometric || !method.isSupportedOnCurrentPlatform) {
      return const AppLockBiometricResult(success: false);
    }
    try {
      final result = await _appLockMethodChannel.invokeMethod<Object?>(
        'authenticate',
        {
          'method': method.storageValue,
          ...?title == null ? null : {'title': title},
          ...?subtitle == null ? null : {'subtitle': subtitle},
          ...?negativeButton == null
              ? null
              : {'negativeButton': negativeButton},
        },
      );
      final map = Map<String, Object?>.from((result as Map?) ?? const {});
      return AppLockBiometricResult.fromMap(map);
    } on PlatformException catch (e) {
      return AppLockBiometricResult(
        success: false,
        shouldFallbackToNative: method == AppLockAuthMethod.soter,
        errorCode: e.code,
        message: e.message,
      );
    }
  }
}
