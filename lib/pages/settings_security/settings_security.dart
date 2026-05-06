import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/app_lock_biometric_service.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'settings_security_view.dart';

class SettingsSecurity extends StatefulWidget {
  const SettingsSecurity({super.key});

  @override
  SettingsSecurityController createState() => SettingsSecurityController();
}

class SettingsSecurityController extends State<SettingsSecurity> {
  String appLockSubtitle(BuildContext context) {
    final l10n = L10n.of(context);
    final appLock = AppLock.of(context);
    if (!appLock.isActive) {
      return l10n.appLockDescription;
    }
    return '${l10n.appLockDescription} (${_appLockMethodLabel(appLock.authMethod, l10n)})';
  }

  String _appLockMethodLabel(AppLockAuthMethod method, L10n l10n) {
    switch (method) {
      case AppLockAuthMethod.pin:
        return l10n.appLockMethodPin;
      case AppLockAuthMethod.soter:
        return l10n.appLockMethodSoter;
      case AppLockAuthMethod.systemBiometric:
        return l10n.appLockMethodSystemBiometric;
    }
  }

  Future<void> setAppLockAction() async {
    final l10n = L10n.of(context);
    final appLock = AppLock.of(context);
    await appLock.pauseWhile(() async {
      final newLock = await showTextInputDialog(
        useRootNavigator: false,
        context: context,
        title: l10n.pleaseChooseAPasscode,
        message: l10n.pleaseEnter4Digits,
        cancelLabel: l10n.cancel,
        validator: (text) {
          if (text.isEmpty) {
            return null;
          }
          if (text.length == 4 && int.tryParse(text) != null) {
            return null;
          }
          return l10n.pleaseEnter4Digits;
        },
        keyboardType: TextInputType.number,
        obscureText: true,
        maxLines: 1,
        minLines: 1,
        maxLength: 4,
      );
      if (newLock == null) {
        return;
      }
      if (newLock.isEmpty) {
        await appLock.changePincode(null);
        await appLock.changeAuthMethod(AppLockAuthMethod.pin);
        if (mounted) {
          setState(() {});
        }
        return;
      }

      var authMethod = AppLockAuthMethod.pin;
      if (PlatformInfos.isAndroid) {
        final selectedMethod = await _selectAppLockMethod();
        if (selectedMethod == null) {
          return;
        }
        authMethod = await _resolveAppLockMethod(selectedMethod);
        if (!mounted) return;
      }

      await appLock.changePincode(newLock);
      await appLock.changeAuthMethod(authMethod);
      if (mounted) {
        setState(() {});
      }
    }());
  }

  Future<AppLockAuthMethod?> _selectAppLockMethod() async {
    final l10n = L10n.of(context);
    final currentMethod = AppLock.of(context).authMethod;
    return showModalActionPopup<AppLockAuthMethod>(
      useRootNavigator: false,
      context: context,
      title: l10n.chooseAppLockMethod,
      message: l10n.appLockMethodDescription,
      cancelLabel: l10n.cancel,
      actions: [
        AdaptiveModalAction(
          label: l10n.appLockMethodPin,
          value: AppLockAuthMethod.pin,
          isDefaultAction: currentMethod == AppLockAuthMethod.pin,
          icon: const Icon(Icons.pin_outlined),
        ),
        AdaptiveModalAction(
          label: l10n.appLockMethodSoter,
          value: AppLockAuthMethod.soter,
          isDefaultAction: currentMethod == AppLockAuthMethod.soter,
          icon: const Icon(Icons.fingerprint_outlined),
        ),
        AdaptiveModalAction(
          label: l10n.appLockMethodSystemBiometric,
          value: AppLockAuthMethod.systemBiometric,
          isDefaultAction: currentMethod == AppLockAuthMethod.systemBiometric,
          icon: const Icon(Icons.security_outlined),
        ),
      ],
    );
  }

  Future<AppLockAuthMethod> _resolveAppLockMethod(
    AppLockAuthMethod method,
  ) async {
    final l10n = L10n.of(context);
    if (method == AppLockAuthMethod.pin) {
      return method;
    }

    final availability = await AppLockBiometricService.getAvailability();
    if (!mounted) return AppLockAuthMethod.pin;

    if (method == AppLockAuthMethod.systemBiometric) {
      if (availability.nativeSupported) {
        return method;
      }
      await showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: l10n.appLock,
        message: availability.message ?? l10n.biometricNotAvailable,
      );
      return AppLockAuthMethod.pin;
    }

    if (!availability.soterSupported) {
      return _promptUseSystemBiometric(
        availability.message ?? l10n.soterUnavailableUseSystemBiometric,
      );
    }

    final result = await AppLockBiometricService.prepareSoter();
    if (!mounted) return AppLockAuthMethod.pin;
    if (result.success) {
      return method;
    }
    return _promptUseSystemBiometric(
      result.message ?? l10n.soterUnavailableUseSystemBiometric,
    );
  }

  Future<AppLockAuthMethod> _promptUseSystemBiometric(String message) async {
    final l10n = L10n.of(context);
    final result = await showOkCancelAlertDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.useAndroidBiometric,
      message: message,
      okLabel: l10n.useAndroidBiometric,
      cancelLabel: l10n.cancel,
    );
    if (result != OkCancelResult.ok) {
      return AppLockAuthMethod.pin;
    }

    final availability = await AppLockBiometricService.getAvailability();
    if (!mounted) return AppLockAuthMethod.pin;
    if (availability.nativeSupported) {
      return AppLockAuthMethod.systemBiometric;
    }

    await showOkAlertDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.appLock,
      message: availability.message ?? l10n.biometricNotAvailable,
    );
    return AppLockAuthMethod.pin;
  }

  Future<void> deleteAccountAction() async {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    if (await showOkCancelAlertDialog(
          useRootNavigator: false,
          context: context,
          title: l10n.warning,
          message: l10n.deactivateAccountWarning,
          okLabel: l10n.ok,
          cancelLabel: l10n.cancel,
          isDestructive: true,
        ) ==
        OkCancelResult.cancel) {
      return;
    }
    if (!mounted) return;
    final supposedMxid = matrix.client.userID!;
    final mxid = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.confirmMatrixId,
      validator: (text) =>
          text == supposedMxid ? null : l10n.supposedMxid(supposedMxid),
      isDestructive: true,
      okLabel: l10n.delete,
      cancelLabel: l10n.cancel,
    );
    if (mxid == null || mxid.isEmpty || mxid != supposedMxid) {
      return;
    }
    if (!mounted) return;
    final resp = await showFutureLoadingDialog(
      context: context,
      delay: false,
      future: () => matrix.client.uiaRequestBackground<IdServerUnbindResult?>(
        (auth) => matrix.client.deactivateAccount(auth: auth, erase: true),
      ),
    );

    if (!resp.isError) {
      if (!mounted) return;
      await showFutureLoadingDialog(
        context: context,
        future: () => matrix.client.logout(),
      );
    }
  }

  Future<void> dehydrateAction() => Matrix.of(context).dehydrateAction(context);

  Future<void> changeShareKeysWith(ShareKeysWith? shareKeysWith) async {
    if (shareKeysWith == null) return;
    AppSettings.shareKeysWith.setItem(shareKeysWith.name);
    Matrix.of(context).client.shareKeysWith = shareKeysWith;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => SettingsSecurityView(this);
}
