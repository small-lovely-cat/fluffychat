import 'dart:async';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/app_lock_biometric_service.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? _errorText;
  int _coolDownSeconds = 5;
  bool _inputBlocked = false;
  bool _biometricInProgress = false;
  bool _autoPromptedBiometric = false;
  final TextEditingController _textEditingController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_tryBiometricUnlock(autoPrompt: true));
    });
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    super.dispose();
  }

  Future<void> tryUnlock(String text) async {
    text = text.trim();
    setState(() {
      _errorText = null;
    });
    if (text.length < 4) return;

    final enteredPin = int.tryParse(text);
    if (enteredPin == null || text.length != 4) {
      setState(() {
        _errorText = L10n.of(context).invalidInput;
      });
      _textEditingController.clear();
      return;
    }

    if (AppLock.of(context).unlock(text)) {
      setState(() {
        _inputBlocked = false;
        _errorText = null;
      });
      _textEditingController.clear();
      return;
    }

    setState(() {
      _errorText = L10n.of(context).wrongPinEntered(_coolDownSeconds);
      _inputBlocked = true;
    });
    Future.delayed(Duration(seconds: _coolDownSeconds)).then((_) {
      setState(() {
        _inputBlocked = false;
        _coolDownSeconds *= 2;
        _errorText = null;
      });
    });
    _textEditingController.clear();
  }

  Future<void> _tryBiometricUnlock({
    bool autoPrompt = false,
    AppLockAuthMethod? method,
  }) async {
    final appLock = AppLock.of(context);
    final unlockMethod = method ?? appLock.authMethod;
    if (!appLock.canUseBiometricUnlock ||
        !unlockMethod.isBiometric ||
        _inputBlocked ||
        _biometricInProgress) {
      return;
    }
    if (autoPrompt && _autoPromptedBiometric) return;
    if (autoPrompt) {
      _autoPromptedBiometric = true;
    }
    setState(() {
      _errorText = null;
      _biometricInProgress = true;
    });
    final result = await appLock.unlockWithBiometric(
      method: unlockMethod,
      title: L10n.of(context).appLock,
      subtitle: L10n.of(context).unlockWithBiometric,
      negativeButton: L10n.of(context).pleaseEnterYourPin,
    );
    if (!mounted) return;
    setState(() {
      _biometricInProgress = false;
    });
    if (result.success || result.cancelled) return;

    if (unlockMethod == AppLockAuthMethod.soter &&
        result.shouldFallbackToNative) {
      final useSystemBiometric = await showOkCancelAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).useAndroidBiometric,
        message:
            result.message ??
            L10n.of(context).soterUnavailableUseSystemBiometric,
        okLabel: L10n.of(context).useAndroidBiometric,
        cancelLabel: L10n.of(context).cancel,
      );
      if (useSystemBiometric == OkCancelResult.ok) {
        await appLock.changeAuthMethod(AppLockAuthMethod.systemBiometric);
        if (!mounted) return;
        await _tryBiometricUnlock(method: AppLockAuthMethod.systemBiometric);
      }
      return;
    }

    setState(() {
      _errorText =
          result.message ?? L10n.of(context).biometricAuthenticationFailed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appLock = AppLock.of(context);
    return ScaffoldMessenger(
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.of(context).pleaseEnterYourPin),
          centerTitle: true,
        ),
        extendBodyBehindAppBar: true,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: FluffyThemes.columnWidth,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Center(
                    child: Image.asset('assets/info-logo.png', width: 256),
                  ),
                  TextField(
                    controller: _textEditingController,
                    textInputAction: TextInputAction.done,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    readOnly: _inputBlocked,
                    onChanged: tryUnlock,
                    onSubmitted: tryUnlock,
                    style: const TextStyle(fontSize: 40),
                    inputFormatters: [LengthLimitingTextInputFormatter(4)],
                    decoration: InputDecoration(
                      errorText: _errorText,
                      hintText: '****',
                      suffix: IconButton(
                        icon: const Icon(Icons.lock_open_outlined),
                        onPressed: _inputBlocked
                            ? null
                            : () => tryUnlock(_textEditingController.text),
                      ),
                    ),
                  ),
                  if (appLock.canUseBiometricUnlock)
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: FilledButton.icon(
                        onPressed: _inputBlocked || _biometricInProgress
                            ? null
                            : _tryBiometricUnlock,
                        icon: const Icon(Icons.fingerprint_outlined),
                        label: Text(L10n.of(context).unlockWithBiometric),
                      ),
                    ),
                  if (_inputBlocked || _biometricInProgress)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
