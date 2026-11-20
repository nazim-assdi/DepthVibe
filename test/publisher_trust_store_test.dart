import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/extensions/data/publisher_trust_store.dart';

void main() {
  group('PublisherTrustStore', () {
    late Directory directory;
    late PublisherTrustStore store;
    late SimpleKeyPair keyPair;
    late SimplePublicKey publicKey;
    late String fingerprint;
    late File keyFile;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('depthvibe_publishers_');
      store = PublisherTrustStore(directory: directory);
      keyPair = await Ed25519().newKeyPair();
      publicKey = await keyPair.extractPublicKey();
      final digest = await Sha256().hash(publicKey.bytes);
      fingerprint = digest.bytes
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      keyFile = File(directory.path + Platform.pathSeparator + 'publisher.dvpub');
      await keyFile.writeAsString(jsonEncode({
        'format': 'DepthVibe.PublisherKey',
        'schemaVersion': 1,
        'algorithm': 'Ed25519',
        'publisherId': 'com.example.publisher',
        'displayName': 'Example Publisher',
        'keyId': 'key-2026',
        'publicKey': base64Encode(publicKey.bytes),
        'fingerprint': fingerprint,
      }));
    });

    tearDown(() async {
      store.dispose();
      keyPair.destroy();
      await directory.delete(recursive: true);
    });

    test('trusts a fingerprint-checked key and verifies Ed25519 signatures',
        () async {
      final candidate = await store.parsePublisherKeyFile(keyFile);
      expect(candidate.fingerprint, fingerprint);
      await store.trustPublisher(candidate);

      final message = utf8.encode('DepthVibe signed marketplace payload');
      final signature = await Ed25519().sign(message, keyPair: keyPair);

      expect(
        await store.verify(
          publisherId: candidate.publisherId,
          keyId: candidate.keyId,
          message: message,
          signatureBytes: signature.bytes,
        ),
        isTrue,
      );

      final modified = utf8.encode('DepthVibe modified marketplace payload');
      expect(
        await store.verify(
          publisherId: candidate.publisherId,
          keyId: candidate.keyId,
          message: modified,
          signatureBytes: signature.bytes,
        ),
        isFalse,
      );
    });

    test('revokes a publisher key', () async {
      final candidate = await store.parsePublisherKeyFile(keyFile);
      await store.trustPublisher(candidate);
      final message = utf8.encode('publisher revocation test');
      final signature = await Ed25519().sign(message, keyPair: keyPair);

      await store.revokePublisher(candidate.publisherId, candidate.keyId);

      expect(
        await store.verify(
          publisherId: candidate.publisherId,
          keyId: candidate.keyId,
          message: message,
          signatureBytes: signature.bytes,
        ),
        isFalse,
      );
      expect(store.publishers, isEmpty);
    });

    test('rejects a key with a forged fingerprint', () async {
      final json = jsonDecode(await keyFile.readAsString())
          as Map<String, Object?>;
      json['fingerprint'] = '0000000000000000000000000000000000000000000000000000000000000000';
      await keyFile.writeAsString(jsonEncode(json));

      await expectLater(
        store.parsePublisherKeyFile(keyFile),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a non-Ed25519 key document', () async {
      final json = jsonDecode(await keyFile.readAsString())
          as Map<String, Object?>;
      json['algorithm'] = 'RSA';
      await keyFile.writeAsString(jsonEncode(json));

      await expectLater(
        store.parsePublisherKeyFile(keyFile),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
