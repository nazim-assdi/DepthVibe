import 'dart:convert';
import 'dart:io';

import '../domain/composition_models.dart';
import 'composition_project_codec.dart';

class CompositionRecoverySnapshot {
  const CompositionRecoverySnapshot({
    required this.document,
    required this.savedAt,
    required this.file,
  });

  final CompositionDocument document;
  final DateTime savedAt;
  final File file;
}

/// Crash-recovery snapshot for the current device. Asset references remain
/// local paths; the normal .dvproj project save embeds media for portability.
class CompositionRecoveryService {
  const CompositionRecoveryService();

  static const fileName = 'active_recovery.json';
  static const formatId = 'DepthVibe.Recovery';
  static const schemaVersion = 1;
  static const maxSnapshotBytes = 64 * 1024 * 1024;

  Future<File> save(
    CompositionDocument document, {
    required Directory recoveryDirectory,
  }) async {
    await recoveryDirectory.create(recursive: true);
    final target = File(_join(recoveryDirectory.path, fileName));
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final temporary = File(target.path + '.tmp_' + suffix);
    final backup = File(target.path + '.bak');

    final payload = <String, Object?>{
      'format': formatId,
      'version': schemaVersion,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'document': CompositionProjectCodec.encodeDocument(document),
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);
    if (encoded.length > maxSnapshotBytes) {
      throw const FormatException('The recovery snapshot exceeds the size limit.');
    }

    await temporary.writeAsString(encoded, flush: true);
    var movedOldSnapshot = false;
    try {
      if (await backup.exists()) await backup.delete();
      if (await target.exists()) {
        await target.rename(backup.path);
        movedOldSnapshot = true;
      }
      await temporary.rename(target.path);
      if (await backup.exists()) await backup.delete();
      return target;
    } catch (_) {
      if (movedOldSnapshot && await backup.exists() && !await target.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<CompositionRecoverySnapshot?> load({
    required Directory recoveryDirectory,
  }) async {
    final file = File(_join(recoveryDirectory.path, fileName));
    final backup = File(file.path + '.bak');
    final candidates = [
      if (await file.exists()) file,
      if (await backup.exists()) backup,
    ];
    if (candidates.isEmpty) return null;

    Object? lastError;
    for (final candidate in candidates) {
      try {
        final length = await candidate.length();
        if (length <= 0 || length > maxSnapshotBytes) {
          throw const FormatException('The recovery snapshot size is invalid.');
        }
        final decoded = jsonDecode(await candidate.readAsString());
        final map = _map(decoded);
        if (map['format'] != formatId) {
          throw const FormatException('The recovery file format is invalid.');
        }
        if (map['version'] != schemaVersion) {
          throw FormatException(
            'Unsupported recovery snapshot version: ' +
                map['version'].toString(),
          );
        }
        final savedAtText = map['savedAt'];
        if (savedAtText is! String) {
          throw const FormatException('The recovery timestamp is invalid.');
        }
        final savedAt = DateTime.tryParse(savedAtText);
        if (savedAt == null) {
          throw const FormatException('The recovery timestamp cannot be parsed.');
        }

        return CompositionRecoverySnapshot(
          document: CompositionProjectCodec.decodeDocument(map['document']),
          savedAt: savedAt.toLocal(),
          file: candidate,
        );
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) {
      throw FormatException(
        'No valid recovery snapshot could be opened: ' + lastError.toString(),
      );
    }
    return null;
  }

  Future<void> clear({required Directory recoveryDirectory}) async {
    final file = File(_join(recoveryDirectory.path, fileName));
    final backup = File(file.path + '.bak');
    if (await file.exists()) await file.delete();
    if (await backup.exists()) await backup.delete();

    if (await recoveryDirectory.exists()) {
      await for (final entity in recoveryDirectory.list()) {
        if (entity is File && entity.path.contains('.tmp_')) {
          await entity.delete();
        }
      }
    }
  }

  static Map<String, Object?> _map(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('The recovery payload must be an object.');
    }
    final result = <String, Object?>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) {
        throw const FormatException('The recovery payload has an invalid key.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static String _join(String first, String second) =>
      first.endsWith(Platform.pathSeparator)
          ? first + second
          : first + Platform.pathSeparator + second;
}
