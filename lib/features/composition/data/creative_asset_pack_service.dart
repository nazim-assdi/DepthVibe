import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'creative_asset_pack_catalog.dart';

typedef AssetPackDownloadProgress = void Function(int receivedBytes, int totalBytes);

class InstalledCreativeAssetPack {
  const InstalledCreativeAssetPack({
    required this.id,
    required this.name,
    required this.directoryPath,
    required this.sourceUrl,
    required this.licenseLabel,
    required this.installedAt,
    required this.fileCount,
    required this.expandedBytes,
  });

  final String id;
  final String name;
  final String directoryPath;
  final String sourceUrl;
  final String licenseLabel;
  final DateTime installedAt;
  final int fileCount;
  final int expandedBytes;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'directoryPath': directoryPath,
    'sourceUrl': sourceUrl,
    'licenseLabel': licenseLabel,
    'installedAt': installedAt.toUtc().toIso8601String(),
    'fileCount': fileCount,
    'expandedBytes': expandedBytes,
  };

  factory InstalledCreativeAssetPack.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final path = json['directoryPath'];
    final source = json['sourceUrl'];
    final license = json['licenseLabel'];
    final date = json['installedAt'];
    final count = json['fileCount'];
    final bytes = json['expandedBytes'];
    if (id is! String ||
        name is! String ||
        path is! String ||
        source is! String ||
        license is! String ||
        date is! String ||
        count is! int ||
        bytes is! int) {
      throw const FormatException('Invalid installed creative asset pack metadata.');
    }
    return InstalledCreativeAssetPack(
      id: id,
      name: name,
      directoryPath: path,
      sourceUrl: source,
      licenseLabel: license,
      installedAt: DateTime.parse(date).toLocal(),
      fileCount: count,
      expandedBytes: bytes,
    );
  }
}

class CreativeAssetFile {
  const CreativeAssetFile({
    required this.file,
    required this.kind,
    required this.relativePath,
  });

  final File file;
  final String kind;
  final String relativePath;

  String get name => relativePath.split('/').last;
}

/// Downloads and locally installs redistributable creative asset archives.
/// Pack payloads are stored in application-support storage, never inside the
/// APK/installer. ZIPs are streamed to disk and extracted with path/link guards.
class CreativeAssetPackService extends ChangeNotifier {
  CreativeAssetPackService({Directory? rootDirectory})
      : _rootOverride = rootDirectory;

  static final CreativeAssetPackService instance = CreativeAssetPackService();

  static const int maxArchiveBytes = 8 * 1024 * 1024 * 1024;
  static const int maxExpandedBytes = 20 * 1024 * 1024 * 1024;
  static const int maxEntries = 100000;
  static const int maxEntryBytes = 8 * 1024 * 1024 * 1024;

  final Directory? _rootOverride;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30);

  Directory? _root;
  final List<InstalledCreativeAssetPack> _installed = [];
  bool _initialized = false;
  bool _busy = false;
  String? _activePackId;
  String? _lastError;
  int _receivedBytes = 0;
  int _totalBytes = 0;

  bool get isBusy => _busy;
  String? get activePackId => _activePackId;
  String? get lastError => _lastError;
  int get receivedBytes => _receivedBytes;
  int get totalBytes => _totalBytes;
  double get progress => _totalBytes <= 0
      ? 0
      : (_receivedBytes / _totalBytes).clamp(0.0, 1.0).toDouble();
  List<InstalledCreativeAssetPack> get installed =>
      List.unmodifiable(_installed);

  int get installedBytes =>
      _installed.fold(0, (total, pack) => total + pack.expandedBytes);

  Future<void> initialize() async {
    if (_initialized) return;
    final root = _rootOverride ??
        Directory(
          (await getApplicationSupportDirectory()).path +
              Platform.pathSeparator +
              'DepthVibe' +
              Platform.pathSeparator +
              'CreativeAssets',
        );
    await root.create(recursive: true);
    _root = root;
    await _scanInstalled();
    _initialized = true;
    notifyListeners();
  }

  bool isInstalled(String packId) =>
      _installed.any((pack) => pack.id == packId);

  InstalledCreativeAssetPack? installedPack(String packId) {
    for (final pack in _installed) {
      if (pack.id == packId) return pack;
    }
    return null;
  }

  Future<InstalledCreativeAssetPack> install(
    CreativeAssetPackDefinition definition, {
    AssetPackDownloadProgress? onProgress,
  }) async {
    await initialize();
    if (_busy) throw StateError('Another asset pack is currently installing.');
    if (isInstalled(definition.id)) {
      throw StateError('This asset pack is already installed.');
    }
    final root = _root!;
    _busy = true;
    _activePackId = definition.id;
    _lastError = null;
    _receivedBytes = 0;
    _totalBytes = definition.exactBytes ?? definition.estimatedBytes;
    notifyListeners();

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final archiveFile = File(
      root.path + Platform.pathSeparator +
          '.download-' + definition.id + '-' + stamp.toString() + '.part',
    );
    try {
      await _download(
        definition.downloadUrl,
        archiveFile,
        exactBytes: definition.exactBytes,
        estimateBytes: definition.estimatedBytes,
        onProgress: (received, total) {
          _receivedBytes = received;
          if (total > 0) _totalBytes = total;
          onProgress?.call(received, total);
          notifyListeners();
        },
      );
      final pack = await _installArchive(
        archiveFile,
        id: definition.id,
        name: definition.name,
        sourceUrl: definition.sourceUrl,
        licenseLabel: definition.licenseLabel,
      );
      _installed.add(pack);
      return pack;
    } catch (error) {
      _lastError = error.toString();
      rethrow;
    } finally {
      if (await archiveFile.exists()) {
        try {
          await archiveFile.delete();
        } catch (_) {}
      }
      _busy = false;
      _activePackId = null;
      _receivedBytes = 0;
      _totalBytes = 0;
      notifyListeners();
    }
  }

  /// Imports a user-selected ZIP (e.g. a custom CC0 SVG selection from
  /// AssetPolish). The ZIP must contain its own licence/source notice.
  Future<InstalledCreativeAssetPack> importArchive(
    File archiveFile, {
    required String name,
    required String licenseLabel,
    String sourceUrl = '',
  }) async {
    await initialize();
    if (_busy) throw StateError('Another asset pack is currently installing.');
    if (!await archiveFile.exists()) {
      throw StateError('The selected ZIP file does not exist.');
    }
    final safeName = _safeId(name);
    final id = 'imported_' + safeName + '_' +
        DateTime.now().millisecondsSinceEpoch.toString();
    _busy = true;
    _activePackId = id;
    _lastError = null;
    notifyListeners();
    try {
      final pack = await _installArchive(
        archiveFile,
        id: id,
        name: name.trim().isEmpty ? 'Imported asset pack' : name.trim(),
        sourceUrl: sourceUrl,
        licenseLabel: licenseLabel,
      );
      _installed.add(pack);
      return pack;
    } catch (error) {
      _lastError = error.toString();
      rethrow;
    } finally {
      _busy = false;
      _activePackId = null;
      notifyListeners();
    }
  }

  Future<void> _download(
    String url,
    File destination, {
    required int? exactBytes,
    required int estimateBytes,
    AssetPackDownloadProgress? onProgress,
  }) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('Asset pack downloads must use HTTPS.');
    }
    final request = await _client.getUrl(uri).timeout(
      const Duration(seconds: 30),
    );
    request.headers.set(HttpHeaders.userAgentHeader, 'DepthVibe Creative Asset Manager');
    request.followRedirects = true;
    final response = await request.close().timeout(
      const Duration(minutes: 3),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw HttpException(
        'Asset pack server returned HTTP ${response.statusCode}.',
        uri: uri,
      );
    }
    final total = response.contentLength > 0
        ? response.contentLength
        : (exactBytes ?? estimateBytes);
    if (exactBytes != null &&
        response.contentLength > 0 &&
        response.contentLength != exactBytes) {
      await response.drain<void>();
      throw HttpException(
        'The server file size changed. Expected ${exactBytes} bytes, '
        'received content-length ${response.contentLength}.',
        uri: uri,
      );
    }
    if (total > maxArchiveBytes) {
      await response.drain<void>();
      throw const FormatException('The asset archive exceeds the 8 GiB safety limit.');
    }

    final sink = destination.openWrite(mode: FileMode.writeOnly);
    var received = 0;
    try {
      await for (final chunk in response.timeout(
        const Duration(seconds: 90),
        onTimeout: (sink) {
          sink.addError(TimeoutException('Asset download stalled.'));
          sink.close();
        },
      )) {
        received += chunk.length;
        if (received > maxArchiveBytes ||
            (exactBytes != null && received > exactBytes)) {
          throw const FormatException('The downloaded asset archive exceeded its declared size.');
        }
        sink.add(chunk);
        onProgress?.call(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (received <= 0) {
      throw const FormatException('The downloaded asset archive is empty.');
    }
    if (exactBytes != null && received != exactBytes) {
      throw FormatException(
        'Incomplete download: expected ${exactBytes} bytes, received ${received}.',
      );
    }
  }

  Future<InstalledCreativeAssetPack> _installArchive(
    File archiveFile, {
    required String id,
    required String name,
    required String sourceUrl,
    required String licenseLabel,
  }) async {
    final root = _root!;
    final staging = Directory(
      root.path + Platform.pathSeparator +
          '.staging-' + _safeId(id) + '-' +
          DateTime.now().microsecondsSinceEpoch.toString(),
    );
    final destination = Directory(root.path + Platform.pathSeparator + _safeId(id));
    if (await destination.exists()) {
      throw StateError('Asset pack folder already exists: ${destination.path}');
    }
    await staging.create(recursive: true);
    InputFileStream? input;
    try {
      input = InputFileStream(archiveFile.path);
      final archive = ZipDecoder().decodeStream(input, verify: true);
      if (archive.length > maxEntries) {
        throw const FormatException('The asset pack contains too many ZIP entries.');
      }

      final seen = <String>{};
      final outputRoot = Directory(
        staging.path + Platform.pathSeparator + 'files',
      );
      await outputRoot.create(recursive: true);
      var totalExpanded = 0;
      var fileCount = 0;
      var hasLicenseFile = false;
      var hasReadme = false;

      for (final entry in archive) {
        final relative = _validateEntry(entry.name);
        if (!seen.add(relative.toLowerCase())) {
          throw FormatException('Duplicate ZIP entry: $relative');
        }
        if (entry.isSymbolicLink || entry.isHardLink) {
          throw const FormatException('Asset packs cannot contain file-system links.');
        }
        if (!entry.isFile) continue;
        if (entry.size < 0 || entry.size > maxEntryBytes) {
          throw FormatException('Invalid or oversized asset entry: $relative');
        }
        totalExpanded += entry.size;
        if (totalExpanded > maxExpandedBytes) {
          throw const FormatException('The expanded pack exceeds the 20 GiB safety limit.');
        }

        final upper = relative.toUpperCase();
        final baseName = upper.split('/').last;
        if (baseName == 'LICENSE' ||
            baseName.startsWith('LICENSE.') ||
            baseName.startsWith('LICENSES') ||
            baseName == 'COPYING' ||
            baseName.startsWith('COPYING.')) {
          hasLicenseFile = true;
        }
        if (baseName.startsWith('README')) hasReadme = true;

        final output = File(
          outputRoot.path + Platform.pathSeparator +
              relative.replaceAll('/', Platform.pathSeparator),
        );
        await output.parent.create(recursive: true);
        final stream = OutputFileStream(output.path);
        try {
          entry.writeContent(stream);
        } finally {
          stream.closeSync();
        }
        fileCount++;
      }

      if (!hasLicenseFile) {
        throw const FormatException(
          'The ZIP does not contain a LICENSE/LICENCES file. '
          'DepthVibe will not install an archive without its licence notice.',
        );
      }
      if (fileCount == 0) {
        throw const FormatException('The ZIP contains no files.');
      }

      final installedAt = DateTime.now();
      final installed = InstalledCreativeAssetPack(
        id: id,
        name: name,
        directoryPath: destination.path,
        sourceUrl: sourceUrl,
        licenseLabel: licenseLabel,
        installedAt: installedAt,
        fileCount: fileCount,
        expandedBytes: totalExpanded,
      );
      final metadata = File(
        staging.path + Platform.pathSeparator + 'pack.json',
      );
      await metadata.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          ...installed.toJson(),
          'containsLicenseFile': hasLicenseFile,
          'containsReadme': hasReadme,
          'archiveName': archiveFile.uri.pathSegments.isEmpty
              ? 'imported.zip'
              : archiveFile.uri.pathSegments.last,
        }),
        flush: true,
      );

      await staging.rename(destination.path);
      return installed;
    } catch (_) {
      if (await staging.exists()) {
        try {
          await staging.delete(recursive: true);
        } catch (_) {}
      }
      rethrow;
    } finally {
      input?.closeSync();
    }
  }

  String _validateEntry(String source) {
    final normalized = source.replaceAll('\\', '/');
    final cleaned = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    if (cleaned.isEmpty ||
        cleaned.startsWith('/') ||
        cleaned.contains('\u0000') ||
        RegExp(r'^[A-Za-z]:').hasMatch(cleaned)) {
      throw FormatException('Unsafe ZIP entry path: $source');
    }
    final parts = cleaned.split('/');
    if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw FormatException('Unsafe ZIP entry path: $source');
    }
    return parts.join('/');
  }

  String _safeId(String source) {
    final value = source.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_-]+'),
      '_',
    );
    if (value.isEmpty || value.length > 100) {
      throw const FormatException('Invalid asset pack identifier.');
    }
    return value;
  }

  Future<void> _scanInstalled() async {
    _installed.clear();
    final root = _root;
    if (root == null || !await root.exists()) return;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory || entity.path.split(Platform.pathSeparator).last.startsWith('.')) {
        continue;
      }
      final metadata = File(
        entity.path + Platform.pathSeparator + 'pack.json',
      );
      if (!await metadata.exists()) continue;
      try {
        final json = jsonDecode(await metadata.readAsString());
        if (json is Map) {
          _installed.add(
            InstalledCreativeAssetPack.fromJson(
              json.cast<String, Object?>(),
            ),
          );
        }
      } catch (_) {
        // Ignore a damaged entry; its source files are left untouched for recovery.
      }
    }
    _installed.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<List<CreativeAssetFile>> filesForPack(String packId) async {
    await initialize();
    final installed = installedPack(packId);
    if (installed == null) return const [];
    final folder = Directory(
      installed.directoryPath + Platform.pathSeparator + 'files',
    );
    if (!await folder.exists()) return const [];
    const imageExtensions = {'png','jpg','jpeg','webp','bmp','gif','svg'};
    const videoExtensions = {'mp4','mov','m4v','webm','mkv','avi'};
    const audioExtensions = {'wav','mp3','m4a','aac','flac','ogg','opus'};
    const lutExtensions = {'cube','3dl','look'};
    final result = <CreativeAssetFile>[];
    await for (final entity in folder.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      if (dot <= 0 || dot == name.length - 1) continue;
      final ext = name.substring(dot + 1).toLowerCase();
      final kind = imageExtensions.contains(ext)
          ? 'image'
          : videoExtensions.contains(ext)
              ? 'video'
              : audioExtensions.contains(ext)
                  ? 'audio'
                  : lutExtensions.contains(ext)
                      ? 'lut'
                      : 'other';
      if (kind == 'other') continue;
      final relative = entity.path
          .substring(folder.path.length + 1)
          .replaceAll('\\', '/');
      result.add(CreativeAssetFile(
        file: entity,
        kind: kind,
        relativePath: relative,
      ));
    }
    result.sort((a, b) => a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase()));
    return result;
  }

  Future<void> uninstall(String packId) async {
    await initialize();
    final pack = installedPack(packId);
    if (pack == null) return;
    final folder = Directory(pack.directoryPath);
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
    _installed.removeWhere((item) => item.id == packId);
    notifyListeners();
  }

  @override
  void dispose() {
    _client.close(force: true);
    super.dispose();
  }
}
