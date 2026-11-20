import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class TrustedPublisher {
  const TrustedPublisher({
    required this.publisherId,
    required this.displayName,
    required this.keyId,
    required this.publicKeyBase64,
    required this.fingerprint,
    required this.trustedAt,
  });

  final String publisherId;
  final String displayName;
  final String keyId;
  final String publicKeyBase64;
  final String fingerprint;
  final DateTime trustedAt;

  Map<String, Object?> toJson() => {
        'publisherId': publisherId,
        'displayName': displayName,
        'keyId': keyId,
        'publicKey': publicKeyBase64,
        'fingerprint': fingerprint,
        'trustedAt': trustedAt.toUtc().toIso8601String(),
      };

  factory TrustedPublisher.fromJson(Object? value) {
    final json = _asMap(value);
    return TrustedPublisher(
      publisherId: _required(json['publisherId'], 'publisherId', 80),
      displayName: _required(json['displayName'], 'displayName', 100),
      keyId: _required(json['keyId'], 'keyId', 80),
      publicKeyBase64: _required(json['publicKey'], 'publicKey', 256),
      fingerprint: _required(json['fingerprint'], 'fingerprint', 64),
      trustedAt: DateTime.tryParse(
            _required(json['trustedAt'], 'trustedAt', 48),
          )?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

class PublisherTrustStore extends ChangeNotifier {
  PublisherTrustStore({Directory? directory}) : _directoryOverride = directory;

  static final PublisherTrustStore instance = PublisherTrustStore();

  final Directory? _directoryOverride;
  final List<TrustedPublisher> _publishers = [];
  Directory? _directory;
  bool _initialized = false;

  List<TrustedPublisher> get publishers => List.unmodifiable(_publishers);

  Future<void> initialize() async {
    if (_initialized) return;
    _directory = _directoryOverride ??
        Directory(
          (await getApplicationDocumentsDirectory()).path +
              Platform.pathSeparator +
              'DepthVibe' +
              Platform.pathSeparator +
              'Extensions',
        );
    await _directory!.create(recursive: true);
    final file = File(
      _directory!.path + Platform.pathSeparator + 'trusted_publishers.json',
    );
    if (await file.exists()) {
      final decoded = jsonDecode(await file.readAsString());
      final json = _asMap(decoded);
      if (json['format'] != 'DepthVibe.TrustedPublishers' ||
          json['schemaVersion'] != 1 ||
          json['publishers'] is! List) {
        throw const FormatException('Publisher trust store is invalid.');
      }
      _publishers
        ..clear()
        ..addAll(
          (json['publishers'] as List).map(TrustedPublisher.fromJson),
        );
    }
    _initialized = true;
    notifyListeners();
  }

  Future<TrustedPublisher> parsePublisherKeyFile(File file) async {
    if (!await file.exists() || await file.length() > 16 * 1024) {
      throw const FormatException('Publisher key file is missing or too large.');
    }
    final json = _asMap(jsonDecode(await file.readAsString()));
    if (json['format'] != 'DepthVibe.PublisherKey' ||
        json['schemaVersion'] != 1 ||
        json['algorithm'] != 'Ed25519') {
      throw const FormatException('Unsupported publisher key file.');
    }
    final publicKeyBase64 = _required(json['publicKey'], 'publicKey', 256);
    final publicKeyBytes = base64Decode(publicKeyBase64);
    if (publicKeyBytes.length != 32) {
      throw const FormatException('Ed25519 public keys must contain 32 bytes.');
    }
    final fingerprintBytes = await Sha256().hash(publicKeyBytes);
    final fingerprint = _hex(fingerprintBytes.bytes);
    final claimedFingerprint = _required(json['fingerprint'], 'fingerprint', 64);
    if (claimedFingerprint.toLowerCase() != fingerprint) {
      throw const FormatException('Publisher key fingerprint does not match.');
    }

    return TrustedPublisher(
      publisherId: _required(json['publisherId'], 'publisherId', 80),
      displayName: _required(json['displayName'], 'displayName', 100),
      keyId: _required(json['keyId'], 'keyId', 80),
      publicKeyBase64: publicKeyBase64,
      fingerprint: fingerprint,
      trustedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> trustPublisher(TrustedPublisher publisher) async {
    await initialize();
    final existingIndex = _publishers.indexWhere(
      (item) =>
          item.publisherId == publisher.publisherId &&
          item.keyId == publisher.keyId,
    );
    if (existingIndex >= 0) {
      if (_publishers[existingIndex].fingerprint != publisher.fingerprint) {
        throw StateError(
          'A different key is already trusted for this publisher key ID.',
        );
      }
      return;
    }
    _publishers.add(publisher);
    await _write();
    notifyListeners();
  }

  Future<void> revokePublisher(String publisherId, String keyId) async {
    await initialize();
    _publishers.removeWhere(
      (item) => item.publisherId == publisherId && item.keyId == keyId,
    );
    await _write();
    notifyListeners();
  }

  Future<bool> verify({
    required String publisherId,
    required String keyId,
    required List<int> message,
    required List<int> signatureBytes,
  }) async {
    await initialize();
    final trusted = _publishers.where(
      (item) =>
          item.publisherId == publisherId && item.keyId == keyId,
    );
    if (trusted.isEmpty) return false;
    final publisher = trusted.first;
    final key = SimplePublicKey(
      base64Decode(publisher.publicKeyBase64),
      type: KeyPairType.ed25519,
    );
    return Ed25519().verify(
      message,
      signature: Signature(signatureBytes, publicKey: key),
    );
  }

  Future<void> _write() async {
    await _directory!.create(recursive: true);
    final target = File(
      _directory!.path + Platform.pathSeparator + 'trusted_publishers.json',
    );
    final temporary = File(target.path + '.tmp');
    final backup = File(target.path + '.bak');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'format': 'DepthVibe.TrustedPublishers',
        'schemaVersion': 1,
        'publishers': _publishers.map((item) => item.toJson()).toList(),
      }),
      flush: true,
    );
    var movedOld = false;
    try {
      if (await backup.exists()) await backup.delete();
      if (await target.exists()) {
        await target.rename(backup.path);
        movedOld = true;
      }
      await temporary.rename(target.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (movedOld && await backup.exists() && !await target.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected a JSON object.');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('Object keys must be strings.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _required(Object? value, String field, int maxLength) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.trim().length > maxLength) {
    throw FormatException('Invalid publisher key field: ' + field + '.');
  }
  return value.trim();
}

String _hex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
