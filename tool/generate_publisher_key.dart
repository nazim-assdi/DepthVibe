import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> args) async {
  if (args.length != 5) {
    stderr.writeln(
      'Usage: dart run tool/generate_publisher_key.dart '
      '<publisherId> <displayName> <keyId> <public.dvpub> <private.json>',
    );
    exitCode = 64;
    return;
  }
  final publisherId = args[0].trim();
  final displayName = args[1].trim();
  final keyId = args[2].trim();
  final publicFile = File(args[3]);
  final privateFile = File(args[4]);

  if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,79}$').hasMatch(publisherId) ||
      displayName.isEmpty ||
      displayName.length > 100 ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{1,79}$').hasMatch(keyId)) {
    stderr.writeln('Invalid publisher identity fields.');
    exitCode = 64;
    return;
  }
  if (await publicFile.exists() || await privateFile.exists()) {
    stderr.writeln('Refusing to overwrite an existing key file.');
    exitCode = 73;
    return;
  }

  final pair = await Ed25519().newKeyPair();
  try {
    final extracted = await pair.extract();
    final seed = extracted.bytes;
    final publicBytes = extracted.publicKey.bytes;
    if (seed.length != 32 || publicBytes.length != 32) {
      throw StateError('Unexpected Ed25519 key length.');
    }
    final fingerprint = _hex((await Sha256().hash(publicBytes)).bytes);
    final now = DateTime.now().toUtc().toIso8601String();
    final publicJson = {
      'format': 'DepthVibe.PublisherKey',
      'schemaVersion': 1,
      'algorithm': 'Ed25519',
      'publisherId': publisherId,
      'displayName': displayName,
      'keyId': keyId,
      'publicKey': base64Encode(publicBytes),
      'fingerprint': fingerprint,
      'createdAt': now,
    };
    final privateJson = {
      'format': 'DepthVibe.PublisherPrivateKey',
      'schemaVersion': 1,
      'algorithm': 'Ed25519',
      'publisherId': publisherId,
      'displayName': displayName,
      'keyId': keyId,
      'privateSeed': base64Encode(seed),
      'publicKey': base64Encode(publicBytes),
      'fingerprint': fingerprint,
      'createdAt': now,
    };

    await publicFile.parent.create(recursive: true);
    await privateFile.parent.create(recursive: true);
    await publicFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(publicJson),
      flush: true,
    );
    await privateFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(privateJson),
      flush: true,
    );
    if (!Platform.isWindows) {
      final chmod = await Process.run('chmod', ['600', privateFile.path]);
      if (chmod.exitCode != 0) {
        stderr.writeln(
          'Warning: manually restrict private-key file permissions.',
        );
      }
    }
    stdout.writeln('Public key: ' + publicFile.path);
    stdout.writeln('Private key: ' + privateFile.path);
    stdout.writeln('SHA-256 fingerprint: ' + fingerprint);
    stdout.writeln('Keep the private key offline. Share only the .dvpub file.');
  } finally {
    pair.destroy();
  }
}

String _hex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
