import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln(
      'Usage: dart run tool/sign_marketplace_catalog.dart '
      '<draft.json> <publisher-private.json> <signed-index.json>',
    );
    exitCode = 64;
    return;
  }

  final draftFile = File(args[0]);
  final privateFile = File(args[1]);
  final outputFile = File(args[2]);
  if (!await draftFile.exists() || !await privateFile.exists()) {
    stderr.writeln('Catalog draft or private key file does not exist.');
    exitCode = 66;
    return;
  }
  if (await draftFile.length() > 2 * 1024 * 1024 ||
      await privateFile.length() > 16 * 1024) {
    stderr.writeln('Catalog or private key exceeds its size limit.');
    exitCode = 65;
    return;
  }
  if (await outputFile.exists()) {
    stderr.writeln('Refusing to overwrite an existing signed catalog.');
    exitCode = 73;
    return;
  }

  final key = _asMap(jsonDecode(await privateFile.readAsString()));
  if (key['format'] != 'DepthVibe.PublisherPrivateKey' ||
      key['schemaVersion'] != 1 ||
      key['algorithm'] != 'Ed25519') {
    throw const FormatException('Unsupported publisher private key format.');
  }
  final publisherId = _required(key['publisherId'], 'publisherId');
  final keyId = _required(key['keyId'], 'keyId');
  final seed = base64Decode(_required(key['privateSeed'], 'privateSeed'));
  final publicBytes = base64Decode(_required(key['publicKey'], 'publicKey'));
  if (seed.length != 32 || publicBytes.length != 32) {
    throw const FormatException('Ed25519 key material must contain 32 bytes.');
  }
  final fingerprint = _hex((await Sha256().hash(publicBytes)).bytes);
  if (_required(key['fingerprint'], 'fingerprint').toLowerCase() !=
      fingerprint) {
    throw const FormatException('Publisher key fingerprint is invalid.');
  }

  final draft = _asMap(jsonDecode(await draftFile.readAsString()));
  if (draft['format'] != 'DepthVibe.Marketplace' ||
      draft['schemaVersion'] != 1 ||
      draft['publisherId'] != publisherId ||
      draft['keyId'] != keyId) {
    throw const FormatException('Catalog identity does not match publisher key.');
  }
  final rawEntries = draft['entries'];
  if (rawEntries is! List || rawEntries.length > 2000) {
    throw const FormatException('Catalog entries must be a list of up to 2000 items.');
  }
  final seenIds = <String>{};
  for (final raw in rawEntries) {
    final entry = _asMap(raw);
    final id = _required(entry['id'], 'extension id');
    if (!seenIds.add(id)) {
      throw FormatException('Duplicate catalog extension ID: ' + id);
    }
    if (entry['publisherId'] != publisherId || entry['keyId'] != keyId) {
      throw const FormatException(
        'Every entry must use the catalog publisher key.',
      );
    }
    final url = Uri.tryParse(_required(entry['downloadUrl'], 'downloadUrl'));
    if (url == null || url.scheme != 'https') {
      throw const FormatException('Every package URL must use HTTPS.');
    }
    final digest = _required(entry['sha256'], 'sha256').toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Package SHA-256 is invalid.');
    }
  }

  draft.remove('signature');
  final payload = _canonicalJson(draft);
  final keyPair = SimpleKeyPairData(
    seed,
    publicKey: SimplePublicKey(publicBytes, type: KeyPairType.ed25519),
    type: KeyPairType.ed25519,
  );
  try {
    const challenge = 'DepthVibe publisher signing-key consistency check';
    final probe = await Ed25519().sign(
      utf8.encode(challenge),
      keyPair: keyPair,
    );
    final matches = await Ed25519().verify(
      utf8.encode(challenge),
      signature: Signature(
        probe.bytes,
        publicKey: SimplePublicKey(
          publicBytes,
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!matches) {
      throw const FormatException(
        'Private seed does not match the supplied public key.',
      );
    }
    final signature = await Ed25519().sign(payload, keyPair: keyPair);
    draft['signature'] = base64Encode(signature.bytes);
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(draft),
      flush: true,
    );
    stdout.writeln('Signed catalog: ' + outputFile.path);
    stdout.writeln('Publisher: ' + publisherId + ' / ' + keyId);
  } finally {
    keyPair.destroy();
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected a JSON object.');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('Invalid JSON object key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _required(Object? value, String field) {
  if (value is! String || value.trim().isEmpty || value.length > 4096) {
    throw FormatException('Invalid ' + field + '.');
  }
  return value.trim();
}

List<int> _canonicalJson(Object? value) {
  Object? sortValue(Object? item) {
    if (item is Map) {
      final keys = item.keys.whereType<String>().toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: sortValue(item[key]),
      };
    }
    if (item is List) return item.map(sortValue).toList();
    return item;
  }

  return utf8.encode(jsonEncode(sortValue(value)));
}

String _hex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
