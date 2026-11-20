import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../lib/features/extensions/data/marketplace_models.dart';

void main() {
  Map<String, Object?> entry({
    String packageType = 'dvext',
    String url = 'https://example.com/test.dvext',
    String sha256 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    String publisherId = 'com.example.publisher',
    String keyId = 'key-2026',
    String id = 'com.example.effects',
  }) =>
      {
        'id': id,
        'name': 'Example Effects',
        'version': '1.0.0',
        'description': 'A signed test package.',
        'publisherId': publisherId,
        'publisherName': 'Example Publisher',
        'keyId': keyId,
        'packageType': packageType,
        'targetHosts': ['DepthVibe'],
        'downloadUrl': url,
        'sha256': sha256,
        'releaseNotes': 'Initial release',
        'minimumHostVersion': '0.5.0',
      };

  Map<String, Object?> catalog(
    List<Map<String, Object?>> entries,
  ) =>
      {
        'format': 'DepthVibe.Marketplace',
        'schemaVersion': 1,
        'publisherId': 'com.example.publisher',
        'keyId': 'key-2026',
        'generatedAt': '2026-11-20T00:00:00.000Z',
        'entries': entries,
        'signature': base64Encode(List<int>.filled(64, 0)),
      };

  test('parses a signed catalog and canonicalizes the signed payload', () {
    final parsed = SignedMarketplaceCatalog.fromJson(
      catalog([entry()]),
    );

    expect(parsed.publisherId, 'com.example.publisher');
    expect(parsed.keyId, 'key-2026');
    expect(parsed.entries.single.packageType, MarketplacePackageType.depthVibe);
    expect(parsed.entries.single.downloadUrl.scheme, 'https');
    expect(parsed.entries.single.sha256, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');

    final payload = jsonDecode(utf8.decode(parsed.canonicalPayload))
        as Map<String, Object?>;
    expect(payload.containsKey('signature'), isFalse);
    expect(payload['format'], 'DepthVibe.Marketplace');
  });

  test('accepts the Adobe host package types', () {
    final parsed = SignedMarketplaceCatalog.fromJson(
      catalog([
        entry(
          packageType: 'premiere-uxp',
          id: 'com.example.premiere',
        ),
        entry(
          packageType: 'after-effects-cep',
          id: 'com.example.ae-cep',
        ),
        entry(
          packageType: 'after-effects-uxp-beta',
          id: 'com.example.ae-uxp',
        ),
      ]),
    );

    expect(
      parsed.entries.map((item) => item.packageType).toList(),
      [
        MarketplacePackageType.premiereUxp,
        MarketplacePackageType.afterEffectsCep,
        MarketplacePackageType.afterEffectsUxpBeta,
      ],
    );
  });

  test('rejects non-HTTPS downloads', () {
    expect(
      () => SignedMarketplaceCatalog.fromJson(
        catalog([entry(url: 'http://example.com/test.dvext')]),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects malformed SHA-256 digests', () {
    expect(
      () => SignedMarketplaceCatalog.fromJson(
        catalog([entry(sha256: 'not-a-digest')]),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects mixed publisher keys in one catalog', () {
    expect(
      () => SignedMarketplaceCatalog.fromJson(
        catalog([entry(publisherId: 'com.other.publisher')]),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects duplicate extension IDs', () {
    expect(
      () => SignedMarketplaceCatalog.fromJson(
        catalog([entry(), entry()]),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
