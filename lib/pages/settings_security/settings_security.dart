import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/app_lock_biometric_service.dart';
import 'package:fluffychat/utils/httpdns/httpdns_manager.dart';
import 'package:fluffychat/utils/httpdns/httpdns_types.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'httpdns_domain_lists_dialog.dart';
import 'settings_security_view.dart';

class SettingsSecurity extends StatefulWidget {
  const SettingsSecurity({super.key});

  @override
  SettingsSecurityController createState() => SettingsSecurityController();
}

class SettingsSecurityController extends State<SettingsSecurity> {
  /// Builds the app lock subtitle shown in the security menu.
  ///
  /// Parameters:
  ///   context: The current widget context.
  /// Returns:
  ///   A localized subtitle describing the active app lock method.
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
      if (PlatformInfos.isMobile) {
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
        if (PlatformInfos.isAndroid)
          AdaptiveModalAction(
            label: l10n.appLockMethodSoter,
            value: AppLockAuthMethod.soter,
            isDefaultAction: currentMethod == AppLockAuthMethod.soter,
            icon: const Icon(Icons.fingerprint_outlined),
          ),
        if (PlatformInfos.isAndroid || PlatformInfos.isIOS)
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

  /// Returns the currently selected HTTPDNS provider.
  ///
  /// Returns:
  ///   The persisted provider selection for the current device.
  HttpDnsProvider get httpDnsProvider =>
      HttpDnsManager.instance.selectedProvider;

  /// Returns a short description for the HTTPDNS provider section.
  ///
  /// Parameters:
  ///   context: The current widget context.
  /// Returns:
  ///   A platform-aware description for the HTTPDNS feature.
  String httpDnsProviderDescription(BuildContext context) {
    if (PlatformInfos.isAndroid) {
      return 'Routes Android requests through the selected HTTPDNS provider. Matrix homeserver domains are added to the keep-alive and preload lists automatically.';
    }
    if (PlatformInfos.isIOS) {
      return 'The iOS HTTPDNS bridge is reserved for a future release. This version only activates HTTPDNS on Android.';
    }
    return 'HTTPDNS is currently available on Android builds only.';
  }

  /// Summarizes the current HTTPDNS domain list configuration.
  ///
  /// Parameters:
  ///   context: The current widget context.
  /// Returns:
  ///   A short summary for the domain list editor entry.
  String httpDnsDomainListsSummary(BuildContext context) {
    final allClients = Matrix.of(context).widget.clients;
    final httpDnsManager = HttpDnsManager.instance;
    final autoAddedDomains = httpDnsManager.managedDomains(allClients);
    final keepAliveCount = httpDnsManager
        .effectiveKeepAliveDomains(allClients)
        .length;
    final preloadCount = httpDnsManager
        .effectivePreloadDomains(allClients)
        .length;
    final autoAddedSummary = autoAddedDomains.isEmpty
        ? 'No homeserver domains have been auto-added yet.'
        : 'Auto-added homeserver domains: ${autoAddedDomains.join(', ')}';
    return 'Keep-alive: $keepAliveCount, preload: $preloadCount. $autoAddedSummary';
  }

  /// Updates the selected HTTPDNS provider and syncs it to native Android.
  ///
  /// Parameters:
  ///   provider: The newly selected HTTPDNS provider.
  /// Returns:
  ///   A future that completes after the native bridge has been updated.
  Future<void> changeHttpDnsProvider(HttpDnsProvider? provider) async {
    if (provider == null) {
      return;
    }
    final allClients = Matrix.of(context).widget.clients;
    await AppSettings.httpDnsProvider.setItem(provider.storageValue);
    final status = await HttpDnsManager.instance.applyCurrentConfiguration(
      allClients,
    );
    if (!mounted) {
      return;
    }
    await _showHttpDnsStatusMessage(status);
    setState(() {});
  }

  /// Opens the HTTPDNS domain editor and persists the updated user lists.
  ///
  /// Parameters:
  ///   context: The current widget context.
  /// Returns:
  ///   A future that completes after the new lists are stored and applied.
  Future<void> editHttpDnsDomainLists(BuildContext context) async {
    final httpDnsManager = HttpDnsManager.instance;
    final allClients = Matrix.of(context).widget.clients;
    final result = await showHttpDnsDomainListsDialog(
      context: context,
      keepAliveDomains: httpDnsManager.userKeepAliveDomains,
      preloadDomains: httpDnsManager.userPreloadDomains,
      autoAddedDomains: httpDnsManager.managedDomains(allClients),
    );
    if (result == null) {
      return;
    }

    await AppSettings.httpDnsKeepAliveDomains.setItem(result.keepAliveDomains);
    await AppSettings.httpDnsPreloadDomains.setItem(result.preloadDomains);
    final status = await httpDnsManager.applyCurrentConfiguration(allClients);
    if (!mounted) {
      return;
    }
    await _showHttpDnsStatusMessage(status);
    setState(() {});
  }

  /// Shows a status dialog when the native HTTPDNS bridge reports a warning.
  ///
  /// Parameters:
  ///   status: The last status returned by the native bridge.
  /// Returns:
  ///   A future that completes after the alert is dismissed.
  Future<void> _showHttpDnsStatusMessage(HttpDnsStatus status) async {
    final message = status.message;
    if (message == null || message.isEmpty) {
      return;
    }
    await showOkAlertDialog(
      useRootNavigator: false,
      context: context,
      title: 'HTTPDNS',
      message: message,
    );
  }

  /// Starts the account deletion flow for the current Matrix account.
  ///
  /// Returns:
  ///   A future that completes after the deletion flow finishes.
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

  /// Starts the dehydrated device export flow for the active account.
  ///
  /// Returns:
  ///   A future that completes after the export dialog closes.
  Future<void> dehydrateAction() => Matrix.of(context).dehydrateAction(context);

  /// Updates the preferred key-sharing policy for the active Matrix client.
  ///
  /// Parameters:
  ///   shareKeysWith: The newly selected key-sharing strategy.
  /// Returns:
  ///   A future that completes after the choice has been stored.
  Future<void> changeShareKeysWith(ShareKeysWith? shareKeysWith) async {
    if (shareKeysWith == null) return;
    AppSettings.shareKeysWith.setItem(shareKeysWith.name);
    Matrix.of(context).client.shareKeysWith = shareKeysWith;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => SettingsSecurityView(this);
}
