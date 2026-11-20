import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class MotionBroPresetAsset {
  const MotionBroPresetAsset({
    required this.relativePath,
    required this.fileName,
    required this.extension,
    required this.category,
    required this.sizeBytes,
    required this.previewRelativePath,
  });

  final String relativePath;
  final String fileName;
  final String extension;
  final String category;
  final int sizeBytes;
  final String? previewRelativePath;

  bool get isScript => extension == 'jsx' || extension == 'jsxbin';
  bool get isAfterEffectsPreset => extension == 'ffx';
  bool get isPremiereMotionGraphicsTemplate => extension == 'mogrt';
  bool get isAfterEffectsProject => extension == 'aep';

  Map<String, Object?> toJson(
    String packId,
    String packName,
    String root,
  ) => {
    'packId': packId,
    'packName': packName,
    'relativePath': relativePath,
    'path': MotionBroPackService.join(root, relativePath),
    'fileName': fileName,
    'extension': extension,
    'category': category,
    'sizeBytes': sizeBytes,
    'isScript': isScript,
    'isAfterEffectsPreset': isAfterEffectsPreset,
    'isPremiereMotionGraphicsTemplate': isPremiereMotionGraphicsTemplate,
    'isAfterEffectsProject': isAfterEffectsProject,
    if (previewRelativePath != null)
      'previewPath': MotionBroPackService.join(root, previewRelativePath!),
  };
}

class MotionBroPresetPack {
  const MotionBroPresetPack({
    required this.id,
    required this.name,
    required this.author,
    required this.version,
    required this.apps,
    required this.directoryPath,
    required this.assets,
    required this.importedAt,
  });

  final String id;
  final String name;
  final String author;
  final String version;
  final List<String> apps;
  final String directoryPath;
  final List<MotionBroPresetAsset> assets;
  final DateTime importedAt;

  int get afterEffectsPresetCount =>
      assets.where((asset) => asset.isAfterEffectsPreset).length;
  int get premiereTemplateCount =>
      assets.where((asset) => asset.isPremiereMotionGraphicsTemplate).length;
  int get scriptCount => assets.where((asset) => asset.isScript).length;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'author': author,
    'version': version,
    'apps': apps,
    'directoryPath': directoryPath,
    'importedAt': importedAt.toIso8601String(),
    'assetCount': assets.length,
    'afterEffectsPresetCount': afterEffectsPresetCount,
    'premiereTemplateCount': premiereTemplateCount,
    'scriptCount': scriptCount,
  };
}

/// Reads and preserves user-supplied Motion Bro .MBR ZIP packs. It never
/// removes license checks, executes bundled scripts, or redistributes packs.
class MotionBroPackService extends ChangeNotifier {
  MotionBroPackService({Directory? rootDirectory})
      : _rootOverride = rootDirectory;

  static final MotionBroPackService instance = MotionBroPackService();

  static const maxPackageBytes = 512 * 1024 * 1024;
  static const maxExpandedBytes = 2 * 1024 * 1024 * 1024;
  static const maxEntryBytes = 1024 * 1024 * 1024;
  static const maxEntries = 4096;
  static const maxInfoBytes = 256 * 1024;
  static const metadataFileName = '.depthvibe-motionbro.json';
  static const supportedPresetExtensions = <String>{
    'aep', 'mogrt', 'mp4', 'mov', 'mp3', 'wav', 'jpg', 'jpeg', 'png',
    'gif', 'ai', 'eps', 'pdf', 'ffx', 'jsx', 'jsxbin',
  };

  final Directory? _rootOverride;
  Directory? _root;
  final List<MotionBroPresetPack> _packs = [];
  bool _initialized = false;
  String? _error;

  List<MotionBroPresetPack> get packs => List.unmodifiable(_packs);
  String? get error => _error;
  bool get isInitialized => _initialized;

  static String join(String base, String relative) =>
      base + Platform.pathSeparator +
      relative.replaceAll('/', Platform.pathSeparator);

  Future<Directory> _ensureRoot() async {
    if (_root != null) return _root!;
    final documents = _rootOverride ??
        Directory(join(
          (await getApplicationDocumentsDirectory()).path,
          'DepthVibe/MotionBroPacks',
        ));
    _root = documents;
    await _root!.create(recursive: true);
    return _root!;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final root = await _ensureRoot();
    _packs.clear();
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory ||
          entity.path.split(Platform.pathSeparator).last.startsWith('.')) {
        continue;
      }
      final metaFile = File(join(entity.path, metadataFileName));
      if (!await metaFile.exists()) continue;
      try {
        final meta = jsonDecode(await metaFile.readAsString());
        if (meta is! Map ||
            meta['format'] != 'DepthVibe.MotionBroPack' ||
            meta['schemaVersion'] != 1) {
          continue;
        }
        final infoFile = File(join(entity.path, 'pack.info'));
        if (!await infoFile.exists()) continue;
        final info = _parsePackInfo(await infoFile.readAsString());
        final assets = await _scanAssets(entity);
        _packs.add(MotionBroPresetPack(
          id: meta['id']?.toString() ?? entity.path.split(Platform.pathSeparator).last,
          name: meta['name']?.toString() ?? info['packname'] ?? 'Motion Bro Pack',
          author: meta['author']?.toString() ?? info['author'] ?? '',
          version: meta['version']?.toString() ?? info['version'] ?? '1.0',
          apps: _parseApps(meta['apps']?.toString() ?? info['apps'] ?? ''),
          directoryPath: entity.path,
          assets: assets,
          importedAt: DateTime.tryParse(meta['importedAt']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ));
      } catch (error) {
        _error = 'Could not read pack: $error';
      }
    }
    _packs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _initialized = true;
    notifyListeners();
  }

  Future<MotionBroPresetPack> importPackage(
    File packageFile, {
    bool replaceExisting = false,
  }) async {
    await initialize();
    if (!await packageFile.exists()) {
      throw const FileSystemException('The Motion Bro package does not exist.');
    }
    final compressedBytes = await packageFile.length();
    if (compressedBytes <= 0 || compressedBytes > maxPackageBytes) {
      throw const FormatException('The .MBR package is invalid or exceeds 512 MB.');
    }

    final root = await _ensureRoot();
    final input = InputFileStream(packageFile.path);
    final staging = await root.createTemp('.mbr-import-');
    var installed = false;
    try {
      final archive = ZipDecoder().decodeStream(input, verify: true);
      if (archive.length > maxEntries) {
        throw const FormatException('The pack contains too many files.');
      }
      final entries = <({ArchiveFile file, String path})>[];
      final seen = <String>{};
      ArchiveFile? infoEntry;
      var totalBytes = 0;
      for (final entry in archive) {
        final normalized = _validatePath(entry.name);
        if (!seen.add(normalized.toLowerCase())) {
          throw FormatException('Duplicate archive path: ' + normalized);
        }
        if (entry.isSymbolicLink || entry.isHardLink) {
          throw const FormatException('Motion Bro packs cannot contain links.');
        }
        if (!entry.isFile) continue;
        if (entry.size < 0 || entry.size > maxEntryBytes) {
          throw FormatException('Archive entry is too large: ' + normalized);
        }
        totalBytes += entry.size;
        if (totalBytes > maxExpandedBytes) {
          throw const FormatException('The pack expands beyond the 2 GB limit.');
        }
        if (normalized.toLowerCase() == 'pack.info') {
          if (entry.size > maxInfoBytes) {
            throw const FormatException('pack.info exceeds the size limit.');
          }
          infoEntry = entry;
        }
        entries.add((file: entry, path: normalized));
      }
      if (infoEntry == null) {
        throw const FormatException('A Motion Bro .MBR pack must contain pack.info at its root.');
      }
      final infoBytes = infoEntry.readBytes();
      if (infoBytes == null || infoBytes.isEmpty) {
        throw const FormatException('pack.info is empty.');
      }
      final info = _parsePackInfo(utf8.decode(infoBytes));
      final name = (info['packname'] ?? '').trim();
      if (name.isEmpty) {
        throw const FormatException('pack.info must include packName.');
      }
      final version = (info['version'] ?? '1.0').trim();
      final id = _slug(name) + '_' + _slug(version);
      final destination = Directory(join(root.path, id));
      if (await destination.exists() && !replaceExisting) {
        throw FormatException('Pack "' + name + '" is already imported.');
      }

      for (final item in entries) {
        final outputFile = File(join(staging.path, item.path));
        await outputFile.parent.create(recursive: true);
        final output = OutputFileStream(outputFile.path);
        try {
          item.file.writeContent(output);
        } finally {
          output.closeSync();
        }
      }

      final assets = await _scanAssets(staging);
      if (assets.isEmpty) {
        throw const FormatException('The pack contains no supported preset/media assets.');
      }
      final importedAt = DateTime.now().toUtc();
      final apps = _parseApps(info['apps'] ?? '');
      final metadata = <String, Object?>{
        'format': 'DepthVibe.MotionBroPack',
        'schemaVersion': 1,
        'id': id,
        'name': name,
        'author': info['author'] ?? '',
        'version': version,
        'apps': apps,
        'importedAt': importedAt.toIso8601String(),
        'assetCount': assets.length,
      };
      await File(join(staging.path, metadataFileName)).writeAsString(
        const JsonEncoder.withIndent('  ').convert(metadata),
        flush: true,
      );

      final backupRoot = Directory(join(root.path, '.updates'));
      final backup = Directory(join(backupRoot.path, id));
      var movedExisting = false;
      try {
        if (await destination.exists()) {
          await backupRoot.create(recursive: true);
          if (await backup.exists()) await backup.delete(recursive: true);
          await destination.rename(backup.path);
          movedExisting = true;
        }
        await staging.rename(destination.path);
        installed = true;
      } catch (_) {
        if (movedExisting && await backup.exists() && !await destination.exists()) {
          await backup.rename(destination.path);
        }
        rethrow;
      }
      if (movedExisting && await backup.exists()) {
        try {
          await backup.delete(recursive: true);
        } catch (_) {
          // Keep the previous imported pack for manual recovery.
        }
      }
      final pack = MotionBroPresetPack(
        id: id,
        name: name,
        author: info['author'] ?? '',
        version: version,
        apps: apps,
        directoryPath: destination.path,
        assets: assets,
        importedAt: importedAt,
      );
      _packs.removeWhere((item) => item.id == id);
      _packs.add(pack);
      _packs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      notifyListeners();
      return pack;
    } finally {
      input.closeSync();
      if (!installed && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  Future<void> uninstall(String packId) async {
    await initialize();
    final pack = _packs.where((item) => item.id == packId).firstOrNull;
    if (pack == null) return;
    final folder = Directory(pack.directoryPath);
    if (await folder.exists()) await folder.delete(recursive: true);
    _packs.removeWhere((item) => item.id == packId);
    notifyListeners();
  }

  Future<File> exportPackage(
    String packId, {
    required File outputFile,
  }) async {
    await initialize();
    final pack = _packs.where((item) => item.id == packId).firstOrNull;
    if (pack == null) throw StateError('Motion Bro pack not found: ' + packId);
    final source = Directory(pack.directoryPath);
    final staging = await Directory.systemTemp.createTemp('mbr-export-');
    final output = File(outputFile.path + '.writing');
    try {
      await for (final entity in source.list(recursive: true, followLinks: false)) {
        if (entity is! File || entity.path.endsWith(metadataFileName)) continue;
        final relative = entity.path.substring(source.path.length + 1);
        final destination = File(join(staging.path, relative.replaceAll(Platform.pathSeparator, '/')));
        await destination.parent.create(recursive: true);
        await entity.copy(destination.path);
      }
      await outputFile.parent.create(recursive: true);
      final encoder = ZipFileEncoder();
      encoder.create(output.path, level: 1);
      try {
        await encoder.addDirectory(staging, includeDirName: false, level: 1);
      } finally {
        await encoder.close();
      }
      if (await outputFile.exists()) await outputFile.delete();
      await output.rename(outputFile.path);
      return outputFile;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
      if (await output.exists()) await output.delete();
    }
  }

  Future<List<Map<String, Object?>>> bridgeAssetCatalog() async {
    await initialize();
    return [
      for (final pack in _packs)
        for (final asset in pack.assets)
          {
            ...asset.toJson(pack.id, pack.name, pack.directoryPath),
            'apps': pack.apps,
            'author': pack.author,
            'packVersion': pack.version,
          },
    ];
  }

  Future<List<MotionBroPresetAsset>> _scanAssets(Directory directory) async {
    final files = <String, int>{};
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File || entity.path.endsWith(metadataFileName)) continue;
      final relative = entity.path.substring(directory.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      final ext = _extension(relative);
      if (!supportedPresetExtensions.contains(ext) ||
          relative.split('/').any((part) => part.toLowerCase() == '(preview)')) {
        continue;
      }
      files[relative] = (await entity.stat()).size;
    }
    final allPaths = <String>{};
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        allPaths.add(entity.path.substring(directory.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/').toLowerCase());
      }
    }
    return [
      for (final entry in files.entries)
        MotionBroPresetAsset(
          relativePath: entry.key,
          fileName: entry.key.split('/').last,
          extension: _extension(entry.key),
          category: _category(entry.key),
          sizeBytes: entry.value,
          previewRelativePath: _previewFor(entry.key, allPaths),
        ),
    ];
  }

  static Map<String, String> _parsePackInfo(String content) {
    final result = <String, String>{};
    for (final raw in const LineSplitter().convert(content)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;
      final equals = line.indexOf('=');
      if (equals <= 0) continue;
      final key = line.substring(0, equals).trim().toLowerCase();
      var value = line.substring(equals + 1).trim();
      // Motion Bro's published pack.info examples include inline "// comments".
      final inlineComment = value.indexOf('//');
      if (inlineComment >= 0) value = value.substring(0, inlineComment).trim();
      final hashComment = value.indexOf(' #');
      if (hashComment >= 0) value = value.substring(0, hashComment).trim();
      if (key.isNotEmpty && value.isNotEmpty) result[key] = value;
    }
    return result;
  }

  static List<String> _parseApps(String value) => value
      .split(RegExp(r'[,;]'))
      .map((item) => item.trim().toUpperCase())
      .where((item) => item == 'AE' || item == 'PP')
      .toSet()
      .toList();

  static String _validatePath(String raw) {
    final path = raw.replaceAll(r'\', '/');
    if (path.isEmpty || path.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:').hasMatch(path) ||
        path.contains('\u0000')) {
      throw FormatException('Unsafe .MBR archive path: ' + raw);
    }
    final parts = path.split('/');
    if (parts.any((part) => part == '.' || part == '..')) {
      throw FormatException('Unsafe .MBR archive path: ' + raw);
    }
    if (path.length > 1024) throw const FormatException('Archive path is too long.');
    return parts.where((part) => part.isNotEmpty).join('/');
  }

  static String _slug(String value) {
    final slug = value.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (slug.isEmpty) throw const FormatException('Pack name is invalid.');
    return slug.length > 48 ? slug.substring(0, 48) : slug;
  }

  static String _extension(String path) {
    final name = path.split('/').last;
    final index = name.lastIndexOf('.');
    return index < 0 ? '' : name.substring(index + 1).toLowerCase();
  }

  static String _category(String path) {
    final parts = path.split('/')..removeLast();
    final visible = parts.where((part) => part.toLowerCase() != '(preview)').toList();
    return visible.isEmpty ? 'General' : visible.last;
  }

  static String? _previewFor(String relativePath, Set<String> allPaths) {
    final parts = relativePath.split('/');
    final fileName = parts.removeLast();
    final separator = fileName.lastIndexOf('.');
    final stem = separator < 0 ? fileName : fileName.substring(0, separator);
    final previewDirectory = [...parts, '(Preview)'].join('/');
    // Motion Bro allows preview video/image formats independent of preset type
    // (for example, an FFX preset may have a same-name MP4/JPG preview).
    for (final extension in const ['mp4', 'jpg', 'jpeg', 'png', 'gif']) {
      final candidate = (previewDirectory.isEmpty ? '' : '$previewDirectory/') +
          stem + '.' + extension;
      if (allPaths.contains(candidate.toLowerCase())) return candidate;
    }
    return null;
  }
}
