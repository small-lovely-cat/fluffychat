import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/config/isrg_x1.dart';
import 'package:fluffychat/utils/httpdns/httpdns_domain_helper.dart';
import 'package:fluffychat/utils/httpdns/httpdns_manager.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/retry.dart' as retry;

/// Custom Client to add an additional certificate. This is for the isrg X1
/// certificate which is needed for LetsEncrypt certificates. It is shipped
/// on Android since OS version 7.1. As long as we support older versions we
/// still have to ship this certificate by ourself.
class CustomHttpClient {
  /// Builds a cancelable socket task that preserves TLS for HTTPS requests.
  ///
  /// Parameters:
  ///   httpClient: The owning Dart HttpClient instance.
  ///   context: TLS context containing the bundled CA certificates.
  ///   uri: The original request URI.
  ///   proxyHost: Proxy host selected by HttpClient, if any.
  ///   proxyPort: Proxy port selected by HttpClient, if any.
  /// Returns:
  ///   A socket task that either uses HTTPDNS or the platform default path.
  static Future<ConnectionTask<Socket>> _createSocketTask(
    HttpClient httpClient,
    SecurityContext context,
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    final isSecure = uri.isScheme('https');
    final tlsHost = HttpDnsDomainHelper.normalizeHost(uri.host) ?? uri.host;
    var connectPort = proxyPort ?? uri.port;
    if (connectPort == 0) {
      connectPort = isSecure
          ? HttpClient.defaultHttpsPort
          : HttpClient.defaultHttpPort;
    }

    if (proxyHost != null && proxyPort != null) {
      return Socket.startConnect(proxyHost, proxyPort);
    }

    final httpDnsActive = HttpDnsManager.instance.lastStatus.isActive;
    final connectHost = httpDnsActive
        ? await HttpDnsManager.instance.resolveConnectHost(tlsHost)
        : tlsHost;

    if (!isSecure) {
      return Socket.startConnect(connectHost, connectPort);
    }

    if (connectHost == tlsHost) {
      return SecureSocket.startConnect(
        tlsHost,
        connectPort,
        context: context,
      );
    }

    final socketTask = await Socket.startConnect(connectHost, connectPort);
    return ConnectionTask.fromSocket<Socket>(
      socketTask.socket.then(
        (socket) => SecureSocket.secure(
          socket,
          host: tlsHost,
          context: context,
        ),
      ),
      socketTask.cancel,
    );
  }

  static HttpClient customHttpClient(String? cert) {
    final context = SecurityContext.defaultContext;

    try {
      if (cert != null) {
        final bytes = utf8.encode(cert);
        context.setTrustedCertificatesBytes(bytes);
      }
    } on TlsException catch (e) {
      if (e.osError != null &&
          e.osError!.message.contains('CERT_ALREADY_IN_HASH_TABLE')) {
      } else {
        rethrow;
      }
    }

    final httpClient = HttpClient(context: context);
    if (PlatformInfos.isAndroid) {
      httpClient.connectionFactory = (uri, proxyHost, proxyPort) =>
          _createSocketTask(httpClient, context, uri, proxyHost, proxyPort);
    }

    return httpClient;
  }

  static http.Client createHTTPClient() => retry.RetryClient(
    PlatformInfos.isAndroid
        ? IOClient(customHttpClient(ISRG_X1))
        : http.Client(),
  );
}
