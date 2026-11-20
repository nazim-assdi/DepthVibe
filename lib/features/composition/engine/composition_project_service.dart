import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import '../domain/composition_models.dart';
import 'composition_project_codec.dart';

class CompositionProjectExportResult {
  const CompositionProjectExportResult({
    required this.file,
    required this.embeddedAssetCount,
    required this.missingAssetPaths,
  });
  final File file;
  final int embeddedAssetCount;
  final List<String> missingAssetPaths;
}

class CompositionProjectImportResult {
  const CompositionProjectImportResult({
    required this.document,
    required this.projectDirectory,
    required this.extractedAssetCount,
  });
  final CompositionDocument document;
  final Directory projectDirectory;
  final int extractedAssetCount;
}

/// Portable .dvproj ZIP package. Media is streamed as ZIP entries rather than
/// base64 embedded in JSON so large video/audio/PSD files do not inflate RAM use.
class CompositionProjectService {
  const CompositionProjectService();

  static const projectFileName = 'project.json';
  static const maxProjectArchiveBytes = 100 * 1024 * 1024 * 1024;
  static const maxUncompressedBytes = 100 * 1024 * 1024 * 1024;
  static const maxEntryBytes = 40 * 1024 * 1024 * 1024;
  static const maxEntries = 10000;
  static const maxManifestBytes = 64 * 1024 * 1024;

  Future<CompositionProjectExportResult> exportProject(
    CompositionDocument document, {
    required File outputFile,
  }) async {
    final staging = await Directory.systemTemp.createTemp('depthvibe_dvproj_export_');
    final missing = <String>[];
    final embeddedByPath = <String, String>{};
    final canonicalPaths = <String, String>{};
    var assetIndex = 0;
    try {
      await Directory(_join(staging.path, 'assets')).create(recursive: true);

      Future<String?> embed(String? uri) async {
        if (uri == null || uri.isEmpty) return uri;
        final previous = embeddedByPath[uri];
        if (previous != null) return previous;
        if (_isNonFileUri(uri)) {
          missing.add(uri);
          return uri;
        }
        final source = File(_filePath(uri));
        if (!await source.exists()) {
          missing.add(uri);
          return uri;
        }
        if ((await source.stat()).type != FileSystemEntityType.file) {
          missing.add(uri);
          return uri;
        }
        final canonical = await source.resolveSymbolicLinks();
        final duplicate = canonicalPaths[canonical];
        if (duplicate != null) {
          embeddedByPath[uri] = duplicate;
          return duplicate;
        }

        final relative = 'assets/asset_' +
            assetIndex.toString().padLeft(5, '0') +
            _extension(source.path);
        assetIndex++;
        final destination = File(_join(staging.path, relative));
        await destination.parent.create(recursive: true);
        await source.copy(destination.path);
        embeddedByPath[uri] = relative;
        canonicalPaths[canonical] = relative;
        return relative;
      }

      for (final layer in document.layers) {
        await embed(layer.sourceUri);
        await embed(layer.sourceDocumentUri);
        await embed(layer.smartObjectSourceUri);
        for (final effect in layer.effects) {
          await embed(effect.assetUri);
        }
      }

      final manifest = <String, Object?>{
        'format': CompositionProjectCodec.formatId,
        'version': CompositionProjectCodec.schemaVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'document': CompositionProjectCodec.encodeDocument(
          document,
          rewriteAssetUri: (uri) =>
              uri == null ? null : embeddedByPath[uri] ?? uri,
        ),
        'embeddedAssetCount': canonicalPaths.length,
        'missingAssetCount': missing.length,
      };
      await File(_join(staging.path, projectFileName)).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
        flush: true,
      );

      await outputFile.parent.create(recursive: true);
      final temporaryOutput = File(
        outputFile.path + '.writing_' +
            DateTime.now().microsecondsSinceEpoch.toString(),
      );
      final backupOutput = File(outputFile.path + '.replacing_backup');
      final encoder = ZipFileEncoder();
      try {
        encoder.create(temporaryOutput.path, level: 1);
        try {
          await encoder.addDirectory(staging, includeDirName: false, level: 1);
        } finally {
          await encoder.close();
        }
      } catch (_) {
        if (await temporaryOutput.exists()) {
          await temporaryOutput.delete();
        }
        rethrow;
      }

      var movedExistingOutput = false;
      try {
        if (await backupOutput.exists()) {
          if (!await outputFile.exists()) {
            await backupOutput.rename(outputFile.path);
          } else {
            await backupOutput.delete();
          }
        }
        if (await outputFile.exists()) {
          await outputFile.rename(backupOutput.path);
          movedExistingOutput = true;
        }
        await temporaryOutput.rename(outputFile.path);
        if (await backupOutput.exists()) await backupOutput.delete();
      } catch (_) {
        if (movedExistingOutput &&
            await backupOutput.exists() &&
            !await outputFile.exists()) {
          await backupOutput.rename(outputFile.path);
        }
        rethrow;
      } finally {
        if (await temporaryOutput.exists()) {
          await temporaryOutput.delete();
        }
      }
      return CompositionProjectExportResult(
        file: outputFile,
        embeddedAssetCount: canonicalPaths.length,
        missingAssetPaths: List.unmodifiable(missing),
      );
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  static const maxVersionHistory = 10;

  /// Keeps the previous saved package before replacing it with a new version.
  Future<CompositionProjectExportResult> exportVersionedProject(
    CompositionDocument document, {
    required File outputFile,
  }) async {
    if (await outputFile.exists() && await outputFile.length() > 0) {
      final historyDirectory = Directory(outputFile.path + '.versions');
      await historyDirectory.create(recursive: true);
      final stamp = DateTime.now().toUtc().toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      var versionFile = File(
        _join(historyDirectory.path, stamp + '_previous.dvproj'),
      );
      var suffix = 1;
      while (await versionFile.exists()) {
        versionFile = File(
          _join(historyDirectory.path, stamp + '_previous_' +
              suffix.toString() + '.dvproj'),
        );
        suffix++;
      }
      await outputFile.copy(versionFile.path);
      await _pruneVersions(historyDirectory);
    }
    return exportProject(document, outputFile: outputFile);
  }

  Future<List<CompositionProjectVersion>> listProjectVersions(
    File projectFile,
  ) async {
    final historyDirectory = Directory(projectFile.path + '.versions');
    if (!await historyDirectory.exists()) {
      return const <CompositionProjectVersion>[];
    }
    final versions = <CompositionProjectVersion>[];
    await for (final entity in historyDirectory.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.dvproj')) {
        continue;
      }
      final stat = await entity.stat();
      if (stat.type != FileSystemEntityType.file || stat.size <= 0) continue;
      versions.add(CompositionProjectVersion(
        file: entity,
        modifiedAt: stat.modified,
        sizeBytes: stat.size,
      ));
    }
    versions.sort((a, b) => b.file.uri.pathSegments.last
        .compareTo(a.file.uri.pathSegments.last));
    return List.unmodifiable(versions);
  }

  Future<void> _pruneVersions(Directory historyDirectory) async {
    final versions = <File>[];
    await for (final entity in historyDirectory.list(followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.dvproj')) {
        versions.add(entity);
      }
    }
    versions.sort((a, b) => b.uri.pathSegments.last
        .compareTo(a.uri.pathSegments.last));
    for (final oldVersion in versions.skip(maxVersionHistory)) {
      await oldVersion.delete();
    }
  }

  Future<CompositionProjectImportResult> importProject(
    File projectFile, {
    required Directory projectsDirectory,
  }) async {
    if (!await projectFile.exists()) {
      throw const FileSystemException('The selected project file does not exist.');
    }
    final archiveLength = await projectFile.length();
    if (archiveLength <= 0 || archiveLength > maxProjectArchiveBytes) {
      throw const FormatException('The .dvproj archive size is invalid.');
    }

    await projectsDirectory.create(recursive: true);
    final staging = await projectsDirectory.createTemp('.dvproj_import_');
    InputFileStream? input;
    var keepStaging = false;
    try {
      input = InputFileStream(projectFile.path);
      final archive = ZipDecoder().decodeStream(input, verify: true);
      final seen = <String>{};
      final assetEntries = <ArchiveFile>[];
      var totalBytes = 0;
      ArchiveFile? manifestEntry;

      if (archive.length > maxEntries) {
        throw const FormatException('The project contains too many files.');
      }
      for (final entry in archive) {
        final name = _validateArchiveEntry(entry);
        if (!seen.add(name)) throw FormatException('Duplicate ZIP entry: $name');
        if (entry.isSymbolicLink || entry.isHardLink) {
          throw const FormatException('Project archives cannot contain links.');
        }
        if (!entry.isFile) continue;
        if (entry.size < 0 || entry.size > maxEntryBytes) {
          throw FormatException('Project entry is too large: $name');
        }
        totalBytes += entry.size;
        if (totalBytes > maxUncompressedBytes) {
          throw const FormatException('The project exceeds the extraction limit.');
        }
        if (name == projectFileName) {
          if (entry.size > maxManifestBytes) {
            throw const FormatException('The project manifest is too large.');
          }
          manifestEntry = entry;
        } else if (name.startsWith('assets/')) {
          assetEntries.add(entry);
        } else {
          throw FormatException('Unsupported project entry: $name');
        }
      }

      if (manifestEntry == null) {
        throw const FormatException('The archive does not contain project.json.');
      }
      final manifestBytes = manifestEntry.readBytes();
      if (manifestBytes == null || manifestBytes.isEmpty) {
        throw const FormatException('The project manifest is empty.');
      }
      final manifest = _map(jsonDecode(utf8.decode(manifestBytes)), 'manifest');
      if (manifest['format'] != CompositionProjectCodec.formatId) {
        throw const FormatException('This is not a DepthVibe project.');
      }
      if (manifest['version'] != CompositionProjectCodec.schemaVersion) {
        throw FormatException(
          'Unsupported project version: ' + manifest['version'].toString(),
        );
      }

      for (final entry in assetEntries) {
        final name = _validateArchiveEntry(entry);
        final destination = File(_join(staging.path, name));
        await destination.parent.create(recursive: true);
        final output = OutputFileStream(destination.path);
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
      }

      final rawDocument = _map(manifest['document'], 'document');
      final projectName = _safeName(
        rawDocument['name'] is String
            ? rawDocument['name'] as String
            : 'Untitled Composition',
      );
      final finalDirectory = await _uniqueProjectDirectory(
        projectsDirectory,
        projectName,
      );

      final document = CompositionProjectCodec.decodeDocument(
        rawDocument,
        resolveAssetUri: (uri) {
          if (uri == null || !uri.startsWith('assets/')) return uri;
          final relative = uri.substring('assets/'.length);
          if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$')
              .hasMatch(relative)) {
            throw const FormatException('A project asset filename is invalid.');
          }
          final extractedPath = _join(staging.path, _join('assets', relative));
          if (!_isInside(staging.path, extractedPath)) {
            throw const FormatException('A project asset path is unsafe.');
          }
          if (!File(extractedPath).existsSync()) {
            throw FormatException('A referenced project asset is missing: ' + relative);
          }
          return _join(finalDirectory.path, _join('assets', relative));
        },
      );

      await staging.rename(finalDirectory.path);
      keepStaging = true;
      return CompositionProjectImportResult(
        document: document,
        projectDirectory: finalDirectory,
        extractedAssetCount: assetEntries.length,
      );
    } finally {
      input?.closeSync();
      if (!keepStaging && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  static String _validateArchiveEntry(ArchiveFile entry) {
    var name = entry.name.replaceAll(String.fromCharCode(92), '/');
    while (name.startsWith('./')) {
      name = name.substring(2);
    }
    if (name.isEmpty ||
        name.startsWith('/') ||
        name.contains('\u0000') ||
        RegExp(r'^[A-Za-z]:').hasMatch(name)) {
      throw const FormatException('The project contains an unsafe ZIP path.');
    }
    final isDirectory = entry.isDirectory || name.endsWith('/');
    final normalized = isDirectory ? name.substring(0, name.length - 1) : name;
    final segments = normalized.split('/');
    if (segments.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    )) {
      throw const FormatException('The project contains a traversal path.');
    }
    final allowedAssetsDirectory = isDirectory && normalized == 'assets';
    if (normalized != projectFileName &&
        !normalized.startsWith('assets/') &&
        !allowedAssetsDirectory) {
      throw FormatException('Unexpected project entry: ' + normalized);
    }
    return isDirectory ? normalized + '/' : normalized;
  }

  static Map<String, Object?> _map(Object? raw, String label) {
    if (raw is! Map) throw FormatException('The $label must be an object.');
    final result = <String, Object?>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) throw FormatException('Invalid key in $label.');
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static bool _isInside(String root, String path) =>
      path.replaceAll('/', Platform.pathSeparator)
          .replaceAll(String.fromCharCode(92), Platform.pathSeparator)
          .startsWith(root.endsWith(Platform.pathSeparator)
              ? root
              : root + Platform.pathSeparator);

  static String _join(String first, String second) {
    final cleaned = second
        .replaceAll('/', Platform.pathSeparator)
        .replaceAll(String.fromCharCode(92), Platform.pathSeparator);
    return first.endsWith(Platform.pathSeparator)
        ? first + cleaned
        : first + Platform.pathSeparator + cleaned;
  }

  static String _safeName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\u0000-\u001F]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^\.+'), '')
        .trim();
    if (cleaned.isEmpty) return 'Untitled_Composition';
    return cleaned.length > 64 ? cleaned.substring(0, 64) : cleaned;
  }

  static Future<Directory> _uniqueProjectDirectory(
    Directory parent,
    String name,
  ) async {
    final base = name + '_' + DateTime.now().millisecondsSinceEpoch.toString();
    var candidate = Directory(_join(parent.path, base));
    var suffix = 1;
    while (await candidate.exists()) {
      candidate = Directory(_join(parent.path, base + '_' + suffix.toString()));
      suffix++;
    }
    return candidate;
  }

  static bool _isNonFileUri(String value) =>
      RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*://').hasMatch(value) &&
      !value.toLowerCase().startsWith('file://');

  static String _filePath(String value) {
    if (value.toLowerCase().startsWith('file://')) {
      try {
        return Uri.parse(value).toFilePath();
      } on FormatException {
        return value;
      }
    }
    return value;
  }

  static String _extension(String path) {
    final name = path.replaceAll(String.fromCharCode(92), '/').split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '.bin';
    final extension = name.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,12}$').hasMatch(extension)
        ? extension
        : '.bin';
  }
}


class CompositionProjectVersion {
  const CompositionProjectVersion({
    required this.file,
    required this.modifiedAt,
    required this.sizeBytes,
  });

  final File file;
  final DateTime modifiedAt;
  final int sizeBytes;
}
