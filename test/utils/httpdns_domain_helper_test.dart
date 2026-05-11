import 'package:fluffychat/utils/httpdns/httpdns_domain_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeDomains strips schemes, ports, paths, and duplicates', () {
    final normalizedDomains = HttpDnsDomainHelper.normalizeDomains([
      'https://Matrix.EXAMPLE.com:8448/_matrix',
      'matrix.example.com',
      'media.example.com/path',
      '192.168.0.1',
      '',
    ]);

    expect(
      normalizedDomains,
      equals(['matrix.example.com', 'media.example.com']),
    );
  });

  test('limitKeepAliveDomains prioritizes managed homeserver domains', () {
    final limitedDomains = HttpDnsDomainHelper.limitKeepAliveDomains(
      managedDomains: ['hs1.example.com', 'hs2.example.com'],
      userDomains: [
        'user1.example.com',
        'user2.example.com',
        'user3.example.com',
        'user4.example.com',
        'user5.example.com',
        'user6.example.com',
        'user7.example.com',
        'user8.example.com',
        'user9.example.com',
      ],
    );

    expect(limitedDomains.length, HttpDnsDomainHelper.maxKeepAliveDomains);
    expect(limitedDomains.first, 'hs1.example.com');
    expect(limitedDomains[1], 'hs2.example.com');
    expect(limitedDomains.contains('user9.example.com'), isFalse);
  });
}
