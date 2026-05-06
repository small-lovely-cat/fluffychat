import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/app_lock_biometric_service.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class AppLockWidget extends StatefulWidget {
  const AppLockWidget({
    required this.child,
    required this.pincode,
    required this.clients,
    super.key,
  });

  final List<Client> clients;
  final String? pincode;
  final Widget child;

  @override
  State<AppLockWidget> createState() => AppLock();
}

class AppLock extends State<AppLockWidget> with WidgetsBindingObserver {
  static const _secureStorage = FlutterSecureStorage();
  static const _pincodeStorageKey = 'chat.fluffy.app_lock';

  String? _pincode;
  late AppLockAuthMethod _authMethod;
  bool _isLocked = false;
  bool _paused = false;

  bool get isActive => _hasValidPincode(_pincode) && !_paused;

  bool get hasPincode => _hasValidPincode(_pincode);
  bool get canUseBiometricUnlock =>
      PlatformInfos.isAndroid && isActive && _authMethod.isBiometric;
  AppLockAuthMethod get authMethod => _authMethod;

  bool _hasValidPincode(String? pincode) =>
      pincode != null && int.tryParse(pincode) != null && pincode.length == 4;

  @override
  void initState() {
    _pincode = widget.pincode;
    _authMethod = AppLockAuthMethod.fromStorage(
      AppSettings.appLockAuthMethod.value,
    );
    _isLocked = isActive;
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(_checkLoggedIn);
  }

  Future<void> _checkLoggedIn(_) async {
    if (widget.clients.any((client) => client.isLogged())) return;

    await changePincode(null);
    setState(() {
      _isLocked = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (isActive &&
        state == AppLifecycleState.hidden &&
        !_isLocked &&
        isActive) {
      showLockScreen();
    }
  }

  bool get isLocked => _isLocked;

  Future<void> changePincode(String? pincode) async {
    final normalizedPincode = _hasValidPincode(pincode) ? pincode : null;
    if (normalizedPincode == null) {
      await _secureStorage.delete(key: _pincodeStorageKey);
    } else {
      await _secureStorage.write(
        key: _pincodeStorageKey,
        value: normalizedPincode,
      );
    }
    if (!mounted) return;
    setState(() {
      _pincode = normalizedPincode;
      if (!isActive) {
        _isLocked = false;
      }
    });
  }

  bool unlock(String pincode) {
    final isCorrect = pincode == _pincode;
    if (isCorrect) {
      setState(() {
        _isLocked = false;
      });
    }
    return isCorrect;
  }

  Future<void> changeAuthMethod(AppLockAuthMethod method) async {
    await AppSettings.appLockAuthMethod.setItem(method.storageValue);
    if (!mounted) return;
    setState(() {
      _authMethod = method;
    });
  }

  Future<AppLockBiometricResult> unlockWithBiometric({
    AppLockAuthMethod? method,
    String? title,
    String? subtitle,
    String? negativeButton,
  }) async {
    final unlockMethod = method ?? _authMethod;
    final result = await AppLockBiometricService.authenticate(
      unlockMethod,
      title: title,
      subtitle: subtitle,
      negativeButton: negativeButton,
    );
    if (result.success && mounted) {
      setState(() {
        _isLocked = false;
      });
    }
    return result;
  }

  void showLockScreen() {
    if (!isActive) return;
    setState(() {
      _isLocked = true;
    });
  }

  Future<T> pauseWhile<T>(Future<T> future) async {
    _paused = true;
    try {
      return await future;
    } finally {
      _paused = false;
    }
  }

  static AppLock of(BuildContext context) =>
      Provider.of<AppLock>(context, listen: false);

  @override
  Widget build(BuildContext context) => Provider<AppLock>(
    create: (_) => this,
    child: Stack(
      fit: StackFit.expand,
      children: [widget.child, if (isLocked) const LockScreen()],
    ),
  );
}
