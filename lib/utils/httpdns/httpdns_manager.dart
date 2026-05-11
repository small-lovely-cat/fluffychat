import 'dart:io';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/httpdns/httpdns_domain_helper.dart';
import 'package:fluffychat/utils/httpdns/httpdns_types.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

/// Coordinates Flutter-side HTTPDNS settings with the native Android bridge.
class HttpDnsManager {
  HttpDnsManager._();

  static final HttpDnsManager instance = HttpDnsManager._();
  static const MethodChannel _channel = MethodChannel(
    'chat.fluffy.fluffychat/httpdns',
  );

  HttpDnsStatus _lastStatus = const HttpDnsStatus.initial();

  /// The provider currently selected in app settings.
  HttpDnsProvider get selectedProvider =>
      HttpDnsProvider.fromStorage(AppSettings.httpDnsProvider.value);

  /// User-managed keep-alive domains from shared preferences.
  List<String> get userKeepAliveDomains => HttpDnsDomainHelper.normalizeDomains(
    AppSettings.httpDnsKeepAliveDomains.value,
  );

  /// User-managed preload domains from shared preferences.
  List<String> get userPreloadDomains => HttpDnsDomainHelper.normalizeDomains(
    AppSettings.httpDnsPreloadDomains.value,
  );

  /// Returns the most recently known native bridge status.
  HttpDnsStatus get lastStatus => _lastStatus;

  /// Derives managed domains from current Matrix client configuration.
  ///
  /// Parameters:
  ///   clients: Active Matrix clients that may contribute homeserver hosts.
  /// Returns:
  ///   A de-duplicated list of managed homeserver domains.
  List<String> managedDomains(Iterable<Client> clients) {
    final domains = <String>[];
    for (final client in clients) {
      final homeserverHost = client.homeserver?.host;
      final matrixDomain = client.userID?.domain;
      if (homeserverHost != null) {
        domains.add(homeserverHost);
      }
      if (matrixDomain != null) {
        domains.add(matrixDomain);
      }
    }
    return HttpDnsDomainHelper.normalizeDomains(domains);
  }

  /// Computes the effective keep-alive list passed to the native SDK.
  ///
  /// Parameters:
  ///   clients: Active Matrix clients used to auto-add homeserver domains.
  /// Returns:
  ///   A capped keep-alive list that prioritizes homeserver domains.
  List<String> effectiveKeepAliveDomains(Iterable<Client> clients) =>
      HttpDnsDomainHelper.limitKeepAliveDomains(
        managedDomains: managedDomains(clients),
        userDomains: userKeepAliveDomains,
      );

  /// Computes the effective preload list passed to the native SDK.
  ///
  /// Parameters:
  ///   clients: Active Matrix clients used to auto-add homeserver domains.
  /// Returns:
  ///   A de-duplicated preload list with homeserver domains first.
  List<String> effectivePreloadDomains(Iterable<Client> clients) =>
      HttpDnsDomainHelper.mergeDomains(
        managedDomains(clients),
        userPreloadDomains,
      );

  /// Pushes the persisted provider and domain settings to the native bridge.
  ///
  /// Returns:
  ///   The latest native bridge status after applying the stored configuration.
  Future<HttpDnsStatus> applyStoredConfiguration() =>
      _applyConfiguration(const <Client>[]);

  /// Pushes the provider and the current homeserver-derived domains to native.
  ///
  /// Parameters:
  ///   clients: Active Matrix clients used to derive managed domains.
  /// Returns:
  ///   The latest native bridge status after applying the combined config.
  Future<HttpDnsStatus> applyCurrentConfiguration(Iterable<Client> clients) =>
      _applyConfiguration(clients);

  /// Resolves a request host into the address that Dart should connect to.
  ///
  /// Parameters:
  ///   host: The original request host.
  /// Returns:
  ///   The IP address returned by HTTPDNS, or the original host when inactive.
  Future<String> resolveConnectHost(String host) async {
    final normalizedHost = HttpDnsDomainHelper.normalizeHost(host);
    final lookupHost = normalizedHost ?? host;

    if (!_shouldUseHttpDns(lookupHost)) {
      return host;
    }
    if (selectedProvider == HttpDnsProvider.none) {
      return host;
    }

    final ipv4Addresses = await _lookupIpv4Addresses(lookupHost);
    if (ipv4Addresses.isNotEmpty) {
      return ipv4Addresses.first;
    }

    if (_lastStatus.isActive) {
      Logs().w(
        'HTTPDNS returned no IPv4 address for original host "$host" '
        '(lookup host "$lookupHost"). Falling back to system DNS. '
        'Native status: ${_lastStatus.message ?? 'no extra detail'}.',
      );
    }

    return lookupHost;
  }

  /// Applies the current Flutter-side HTTPDNS configuration to native code.
  ///
  /// Parameters:
  ///   clients: Active Matrix clients used to derive managed domains.
  /// Returns:
  ///   The latest native bridge status.
  Future<HttpDnsStatus> _applyConfiguration(Iterable<Client> clients) async {
    if (!PlatformInfos.isAndroid) {
      _lastStatus = HttpDnsStatus(
        platformSupported: false,
        credentialsConfigured: false,
        selectedProvider: selectedProvider,
        effectiveProvider: HttpDnsProvider.none,
        message: PlatformInfos.isIOS
            ? 'The iOS HTTPDNS bridge is reserved for a future release.'
            : 'HTTPDNS is currently available on Android builds only.',
      );
      return _lastStatus;
    }

    try {
      final status = await _channel
          .invokeMapMethod<Object?, Object?>('configure', <String, Object>{
            'provider': selectedProvider.storageValue,
            'keepAliveDomains': effectiveKeepAliveDomains(clients),
            'preloadDomains': effectivePreloadDomains(clients),
          });
      _lastStatus = HttpDnsStatus.fromMap(status);
    } on MissingPluginException catch (error, stackTrace) {
      Logs().w('HTTPDNS native bridge is unavailable', error, stackTrace);
      _lastStatus = const HttpDnsStatus.initial();
    } on PlatformException catch (error, stackTrace) {
      Logs().e('Unable to apply HTTPDNS configuration', error, stackTrace);
      _lastStatus = HttpDnsStatus(
        platformSupported: true,
        credentialsConfigured: false,
        selectedProvider: selectedProvider,
        effectiveProvider: HttpDnsProvider.none,
        message: error.message,
      );
    }
    return _lastStatus;
  }

  /// Resolves a host through the native HTTPDNS bridge.
  ///
  /// Parameters:
  ///   host: The original request host.
  /// Returns:
  ///   A list of resolved IPv4 addresses, or an empty list when unavailable.
  Future<List<String>> _lookupIpv4Addresses(String host) async {
    final normalizedHost = HttpDnsDomainHelper.normalizeHost(host);
    if (!PlatformInfos.isAndroid ||
        selectedProvider == HttpDnsProvider.none ||
        normalizedHost == null) {
      return const [];
    }

    try {
      final addresses = await _channel.invokeListMethod<String>(
        'lookup',
        <String, Object>{'host': normalizedHost},
      );
      return addresses
              ?.where((address) => address.trim().isNotEmpty)
              .toList() ??
          const [];
    } on MissingPluginException catch (error, stackTrace) {
      Logs().w('HTTPDNS lookup bridge is unavailable', error, stackTrace);
      return const [];
    } on PlatformException catch (error, stackTrace) {
      Logs().e('HTTPDNS lookup failed for $host', error, stackTrace);
      return const [];
    }
  }

  /// Checks whether a host should be routed through HTTPDNS.
  ///
  /// Parameters:
  ///   host: The request host about to be resolved.
  /// Returns:
  ///   True when the host should use HTTPDNS, otherwise false.
  bool _shouldUseHttpDns(String host) {
    if (host.isEmpty || host == 'localhost') {
      return false;
    }
    return InternetAddress.tryParse(host) == null;
  }
}
