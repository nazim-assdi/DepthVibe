
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../composition/data/effect_catalog.dart';
import '../../composition/engine/cube_lut_validator.dart';
import 'extension_manifest.dart';

class InstalledExtension {
  const InstalledExtension({
    required this.manifest,
    required this.directoryPath,
    required this.enabled,
  });

  final DepthVibeExtensionManifest manifest;
  final String directoryPath;
  final bool enabled;

  int get effectCount => manifest.effects.length;
}

class ExtensionManagerService extends ChangeNotifier {
  ExtensionManagerService({Directory? rootDirectory})
      : _rootDirectoryOverride = rootDirectory;

  static final ExtensionManagerService instance = ExtensionManagerService();

  static const maxPackageBytes = 64 * 1024 * 1024;
  static const maxExpandedBytes = 128 * 1024 * 1024;
  static const maxEntryBytes = 64 * 1024 * 1024;
  static const maxEntries = 100;
  static const maxManifestBytes = 512 * 1024;

  final Directory? _rootDirectoryOverride;
  Directory? _rootDirectory;
  final List<InstalledExtension> _installed = [];
  final Set<String> _disabledIds = {};
  final List<String> _loadWarnings = [];
  bool _initialized = false;
  String? _initializationError;

  List<InstalledExtension> get installed => List.unmodifiable(_installed);
  List<String> get loadWarnings => List.unmodifiable(_loadWarnings);
  String? get initializationError => _initializationError;
  bool get isInitialized => _initialized;

  int get enabledEffectCount => _installed
      .where((item) => item.enabled)
      .fold(0, (count, item) => count + item.effectCount);

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _rootDirectory = _rootDirectoryOverride ??
          Directory(
            (await getApplicationDocumentsDirectory()).path +
                Platform.pathSeparator +
                'DepthVibe' +
                Platform.pathSeparator +
                'Extensions',
          );
      await _rootDirectory!.create(recursive: true);
      await _readRegistry();
      await _scanInstalled();
      _refreshEffectCatalog();
      _initialized = true;
      _initializationError = null;
    } catch (error) {
      _initializationError = error.toString();
      _refreshEffectCatalog();
    }
    notifyListeners();
  }

  Future<InstalledExtension> installFromFile(
    File packageFile, {
    bool replaceExisting = false,
    String? expectedExtensionId,
    String? expectedVersion,
  }) async {
    await _ensureInitialized();
    if (!await packageFile.exists()) {
      throw const FileSystemException('The extension package does not exist.');
    }
    final packageBytes = await packageFile.length();
    if (packageBytes <= 0 || packageBytes > maxPackageBytes) {
      throw const FormatException('The extension package size is invalid.');
    }

    final root = _rootDirectory!;
    final staging = await root.createTemp('.extension_install_');
    final canonicalStagingRoot = await staging.resolveSymbolicLinks();
    InputFileStream? input;
    var installedDirectory = false;
    try {
      input = InputFileStream(packageFile.path);
      final archive = ZipDecoder().decodeStream(input, verify: true);
      if (archive.length > maxEntries) {
        throw const FormatException('The extension contains too many files.');
      }

      final seen = <String>{};
      ArchiveFile? manifestEntry;
      final assetEntries = <ArchiveFile>[];
      var expandedBytes = 0;
      for (final entry in archive) {
        final name = _validateArchiveEntry(entry);
        if (!seen.add(name)) {
          throw FormatException('Duplicate ZIP entry: ' + name);
        }
        if (entry.isSymbolicLink || entry.isHardLink) {
          throw const FormatException(
            'Extension packages cannot contain links.',
          );
        }
        if (!entry.isFile) continue;
        if (entry.size < 0 || entry.size > maxEntryBytes) {
          throw FormatException('Extension entry is too large: ' + name);
        }
        expandedBytes += entry.size;
        if (expandedBytes > maxExpandedBytes) {
          throw const FormatException(
            'The extension exceeds the extraction limit.',
          );
        }
        if (name == 'manifest.json') {
          if (entry.size > maxManifestBytes) {
            throw const FormatException('The extension manifest is too large.');
          }
          manifestEntry = entry;
        } else if (name.startsWith('assets/')) {
          assetEntries.add(entry);
        }
      }

      if (manifestEntry == null) {
        throw const FormatException(
          'The ZIP package must contain manifest.json at its root.',
        );
      }
      final manifestBytes = manifestEntry.readBytes();
      if (manifestBytes == null || manifestBytes.isEmpty) {
        throw const FormatException('The extension manifest is empty.');
      }
      final manifest = DepthVibeExtensionManifest.fromJson(
        jsonDecode(utf8.decode(manifestBytes)),
      );
      if (expectedExtensionId != null &&
          manifest.id != expectedExtensionId) {
        throw const FormatException(
          'The installed package ID does not match the signed marketplace entry.',
        );
      }
      if (expectedVersion != null && manifest.version != expectedVersion) {
        throw const FormatException(
          'The installed package version does not match the signed marketplace entry.',
        );
      }

      final manifestFile = File(
        _join(staging.path, 'manifest.json'),
      );
      await manifestFile.writeAsBytes(manifestBytes, flush: true);
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

      for (final effect in manifest.effects) {
        final asset = effect.asset;
        if (asset == null) continue;
        final assetFile = File(_join(staging.path, asset));
        if (!await assetFile.exists()) {
          throw FormatException('Missing extension asset: ' + asset);
        }
        final stat = await assetFile.stat();
        if (stat.type != FileSystemEntityType.file) {
          throw FormatException('Extension asset is not a file: ' + asset);
        }
        final canonical = await assetFile.resolveSymbolicLinks();
        if (!_isInside(canonicalStagingRoot, canonical)) {
          throw const FormatException(
            'An extension asset resolves outside its package.',
          );
        }
        CubeLutValidator.parse(await assetFile.readAsString());
      }

      final destination = Directory(_join(root.path, manifest.id));
      final existingDirectory = await destination.exists();
      if (existingDirectory && !replaceExisting) {
        throw FormatException(
          'Extension "' + manifest.id + '" is already installed.',
        );
      }
      final wasDisabled = _disabledIds.contains(manifest.id);
      final backupRoot = Directory(_join(root.path, '.updates'));
      final backup = Directory(_join(backupRoot.path, manifest.id));
      var movedExisting = false;
      try {
        if (existingDirectory) {
          await backupRoot.create(recursive: true);
          if (await backup.exists()) {
            await backup.delete(recursive: true);
          }
          await destination.rename(backup.path);
          movedExisting = true;
        }
        await staging.rename(destination.path);
        installedDirectory = true;
        if (existingDirectory && wasDisabled) {
          _disabledIds.add(manifest.id);
        } else {
          _disabledIds.remove(manifest.id);
        }
        await _scanInstalled();
        await _writeRegistry();
      } catch (_) {
        if (installedDirectory && await destination.exists()) {
          await destination.delete(recursive: true);
        }
        if (movedExisting && await backup.exists()) {
          await backup.rename(destination.path);
        }
        if (wasDisabled) {
          _disabledIds.add(manifest.id);
        } else {
          _disabledIds.remove(manifest.id);
        }
        await _scanInstalled();
        _refreshEffectCatalog();
        rethrow;
      }
      if (movedExisting && await backup.exists()) {
        try {
          await backup.delete(recursive: true);
        } catch (_) {
          // Retain the previous version in the hidden .updates folder.
        }
      }
      _refreshEffectCatalog();
      notifyListeners();

      return _installed.firstWhere(
        (item) => item.manifest.id == manifest.id,
      );
    } finally {
      input?.closeSync();
      if (!installedDirectory && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  Future<void> setEnabled(String extensionId, bool enabled) async {
    await _ensureInitialized();
    if (!_installed.any((item) => item.manifest.id == extensionId)) {
      throw StateError('Extension is not installed: ' + extensionId);
    }
    if (enabled) {
      _disabledIds.remove(extensionId);
    } else {
      _disabledIds.add(extensionId);
    }
    await _writeRegistry();
    await _scanInstalled();
    _refreshEffectCatalog();
    notifyListeners();
  }

  Future<void> uninstall(String extensionId) async {
    await _ensureInitialized();
    final index = _installed.indexWhere(
      (item) => item.manifest.id == extensionId,
    );
    if (index < 0) return;
    final directory = Directory(_installed[index].directoryPath);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    _disabledIds.remove(extensionId);
    await _writeRegistry();
    await _scanInstalled();
    _refreshEffectCatalog();
    notifyListeners();
  }

  Future<void> refresh() async {
    _initialized = false;
    _initializationError = null;
    await initialize();
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
    if (!_initialized || _rootDirectory == null) {
      throw StateError(
        _initializationError ?? 'Extension storage is unavailable.',
      );
    }
  }

  Future<void> _readRegistry() async {
    _disabledIds.clear();
    final registry = File(_join(_rootDirectory!.path, 'registry.json'));
    if (!await registry.exists()) return;
    try {
      final raw = jsonDecode(await registry.readAsString());
      if (raw is Map && raw['disabled'] is List) {
        for (final value in raw['disabled'] as List) {
          if (value is String) _disabledIds.add(value);
        }
      }
    } catch (_) {
      final backup = File(registry.path + '.bak');
      if (await backup.exists()) {
        try {
          final raw = jsonDecode(await backup.readAsString());
          if (raw is Map && raw['disabled'] is List) {
            for (final value in raw['disabled'] as List) {
              if (value is String) _disabledIds.add(value);
            }
          }
        } catch (_) {
          _loadWarnings.add('Extension settings could not be recovered.');
        }
      } else {
        _loadWarnings.add('Extension settings could not be read.');
      }
    }
  }

  Future<void> _scanInstalled() async {
    _installed.clear();
    await for (final entity in _rootDirectory!.list(followLinks: false)) {
      if (entity is! Directory) continue;
      try {
        final manifestFile = File(_join(entity.path, 'manifest.json'));
        if (!await manifestFile.exists()) continue;
        final manifest = DepthVibeExtensionManifest.fromJson(
          jsonDecode(await manifestFile.readAsString()),
        );
        final folderName = entity.uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .last;
        if (folderName != manifest.id) {
          throw const FormatException(
            'Extension folder and manifest id do not match.',
          );
        }
        for (final effect in manifest.effects) {
          final asset = effect.asset;
          if (asset != null &&
              !await File(_join(entity.path, asset)).exists()) {
            throw FormatException('Missing extension asset: ' + asset);
          }
        }
        _installed.add(InstalledExtension(
          manifest: manifest,
          directoryPath: entity.path,
          enabled: !_disabledIds.contains(manifest.id),
        ));
      } catch (error) {
        _loadWarnings.add(entity.path + ': ' + error.toString());
      }
    }
    _installed.sort(
      (a, b) => a.manifest.name.toLowerCase().compareTo(
            b.manifest.name.toLowerCase(),
          ),
    );
  }

  void _refreshEffectCatalog() {
    final definitions = <EffectDefinition>[];
    for (final extension in _installed.where((item) => item.enabled)) {
      for (final spec in extension.manifest.effects) {
        final renderer = EffectCatalog.findBuiltin(spec.operation);
        if (renderer == null) continue;
        final parameters = renderer.parameters.map((parameter) {
          return EffectParameterDefinition(
            id: parameter.id,
            label: parameter.label,
            min: parameter.min,
            max: parameter.max,
            defaultValue: spec.defaultOverrides[parameter.id] ??
                parameter.defaultValue,
            unit: parameter.unit,
          );
        }).toList(growable: false);
        definitions.add(EffectDefinition(
          id: 'extension.' +
              extension.manifest.id +
              '.' +
              spec.id,
          name: spec.name,
          category: spec.category,
          description: spec.description,
          parameters: parameters,
          ffmpegFilter: renderer.ffmpegFilter,
          rendererId: spec.operation,
          extensionId: extension.manifest.id,
          assetUri: spec.asset == null
              ? null
              : _join(extension.directoryPath, spec.asset!),
        ));
      }
    }
    EffectCatalog.setExtensionEffects(definitions);
  }

  Future<void> _writeRegistry() async {
    final root = _rootDirectory!;
    final target = File(_join(root.path, 'registry.json'));
    final temporary = File(target.path + '.tmp');
    final backup = File(target.path + '.bak');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'disabled': (_disabledIds.toList()..sort()),
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

  static String _validateArchiveEntry(ArchiveFile entry) {
    var name = entry.name.replaceAll(String.fromCharCode(92), '/');
    while (name.startsWith('./')) {
      name = name.substring(2);
    }
    if (name.isEmpty ||
        name.startsWith('/') ||
        name.contains(String.fromCharCode(0)) ||
        RegExp(r'^[A-Za-z]:').hasMatch(name)) {
      throw const FormatException('The extension contains an unsafe ZIP path.');
    }
    final isDirectory = entry.isDirectory || name.endsWith('/');
    final normalized =
        isDirectory ? name.substring(0, name.length - 1) : name;
    final segments = normalized.split('/');
    if (segments.any((segment) =>
        segment.isEmpty || segment == '.' || segment == '..')) {
      throw const FormatException('The extension contains a traversal path.');
    }
    if (isDirectory) {
      if (normalized != 'assets' && !normalized.startsWith('assets/')) {
        throw FormatException('Unexpected extension folder: ' + normalized);
      }
      return normalized + '/';
    }
    if (normalized == 'manifest.json') return normalized;
    if (!normalized.startsWith('assets/') ||
        !normalized.toLowerCase().endsWith('.cube')) {
      throw FormatException('Unsupported extension entry: ' + normalized);
    }
    return normalized;
  }

  static String _normalizeContainmentPath(String value) {
    var normalized = value.replaceAll(String.fromCharCode(92), '/');
    if (Platform.isWindows) {
      normalized = normalized.toLowerCase();
      if (normalized.startsWith('//?/unc/')) {
        normalized = '//' + normalized.substring(8);
      } else if (normalized.startsWith('//?/')) {
        normalized = normalized.substring(4);
      } else if (normalized.startsWith('//./')) {
        normalized = normalized.substring(4);
      }
    }
    final isUnc = normalized.startsWith('//');
    final remainder = isUnc ? normalized.substring(2) : normalized;
    final collapsed = remainder.replaceAll(RegExp(r'/+'), '/');
    final joined = (isUnc ? '//' : '') + collapsed;
    return joined.endsWith('/') ? joined : '$joined/';
  }

  static bool _isInside(String root, String path) {
    final normalizedRoot = _normalizeContainmentPath(root);
    final normalizedPath = _normalizeContainmentPath(path);
    return normalizedPath.length > normalizedRoot.length &&
        normalizedPath.startsWith(normalizedRoot);
  }

  static String _join(String first, String second) {
    final cleaned = second
        .replaceAll('/', Platform.pathSeparator)
        .replaceAll(String.fromCharCode(92), Platform.pathSeparator);
    return first.endsWith(Platform.pathSeparator)
        ? first + cleaned
        : first + Platform.pathSeparator + cleaned;
  }
}
