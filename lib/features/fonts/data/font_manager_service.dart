import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class FontFaceMetadata {
  const FontFaceMetadata({
    required this.family,
    required this.style,
    required this.fullName,
  });

  final String family;
  final String style;
  final String fullName;

  String get displayName =>
      style.isEmpty || style.toLowerCase() == 'regular'
          ? family
          : '$family · $style';
}

class FontCatalogEntry {
  const FontCatalogEntry({
    required this.family,
    required this.displayName,
    required this.path,
    required this.isImported,
    this.actualFamily,
    this.styleName,
  });

  /// Runtime family name used by TextStyle.fontFamily.
  ///
  /// Installed fonts use their real OS family name. Imported fonts receive a
  /// private DepthVibe alias so they do not collide with system registrations.
  final String family;
  final String displayName;
  final String path;
  final bool isImported;
  final String? actualFamily;
  final String? styleName;

  Map<String, Object?> toJson() => {
        'family': family,
        'displayName': displayName,
        'path': path,
        'actualFamily': actualFamily,
        'styleName': styleName,
      };

  factory FontCatalogEntry.fromJson(Map<String, Object?> json) =>
      FontCatalogEntry(
        family: json['family'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        path: json['path'] as String? ?? '',
        isImported: true,
        actualFamily: json['actualFamily'] as String?,
        styleName: json['styleName'] as String?,
      );
}

class FontFolderImportResult {
  const FontFolderImportResult({
    required this.imported,
    required this.skipped,
  });

  final int imported;
  final int skipped;
}

/// Discovers the device's installed fonts and loads user-owned TTF/OTF fonts.
///
/// System fonts use their real operating-system family names. Imported fonts
/// are registered through Flutter FontLoader using unique DepthVibe aliases.
class FontManagerService extends ChangeNotifier {
  FontManagerService._();

  static final FontManagerService instance = FontManagerService._();

  static const int maxFontBytes = 64 * 1024 * 1024;
  static const int maxSystemFontFilesPerRoot = 2500;
  static const List<String> defaultFallbackFamilies = [
    'Noto Sans',
    'Noto Sans Bengali',
    'Noto Sans Arabic',
    'Noto Sans Devanagari',
    'Noto Sans CJK SC',
    'Noto Sans Thai',
    'Noto Sans Symbols 2',
    'Noto Color Emoji',
    'Segoe UI Emoji',
    'Apple Color Emoji',
  ];

  Directory? _directory;
  final Set<String> _loadedFamilies = <String>{};
  List<FontCatalogEntry> _importedFonts = <FontCatalogEntry>[];
  List<FontCatalogEntry> _availableFonts = <FontCatalogEntry>[];
  List<String> _fallbackFamilies = List<String>.from(defaultFallbackFamilies);
  String? _activeFamily;
  String? _activeFontPath;
  bool _initialized = false;
  bool _scanning = false;

  List<FontCatalogEntry> get fonts =>
      List<FontCatalogEntry>.unmodifiable(_availableFonts);
  List<FontCatalogEntry> get importedFonts =>
      List<FontCatalogEntry>.unmodifiable(_importedFonts);
  List<String> get fallbackFamilies =>
      List<String>.unmodifiable(_fallbackFamilies);
  String? get activeFamily => _activeFamily;
  String? get activeFontPath => _activeFontPath;
  bool get isScanning => _scanning;

  /// Returns true for formats that can be inspected in system font folders.
  /// TTC collections are discoverable, but aren't imported as custom faces.
  static bool isSupportedFontFilePath(String path) {
    final extension = path.split('.').last.toLowerCase();
    return extension == 'ttf' || extension == 'otf' || extension == 'ttc';
  }

  static bool isImportableFontFilePath(String path) {
    final extension = path.split('.').last.toLowerCase();
    return extension == 'ttf' || extension == 'otf';
  }

  static int suggestedWeight(String? style) {
    final value = (style ?? '').toLowerCase();
    final compact = value.replaceAll(RegExp(r'[\\s_-]+'), '');
    if (compact.contains('thin')) return 100;
    if (compact.contains('extralight') || compact.contains('ultralight')) {
      return 200;
    }
    if (compact.contains('light')) return 300;
    if (compact.contains('extrabold') || compact.contains('ultrabold')) {
      return 800;
    }
    if (compact.contains('semibold') || compact.contains('demibold')) {
      return 600;
    }
    if (compact.contains('black') || compact.contains('heavy')) return 900;
    if (compact.contains('bold')) return 700;
    if (compact.contains('medium')) return 500;
    return 400;
  }

  static bool isItalicStyle(String? style) {
    final value = (style ?? '').toLowerCase();
    return value.contains('italic') || value.contains('oblique');
  }

  static bool hasValidFontSignature(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final signature = String.fromCharCodes(bytes.take(4));
    return signature == 'OTTO' ||
        signature == 'true' ||
        signature == 'ttcf' ||
        (bytes[0] == 0 && bytes[1] == 1 && bytes[2] == 0 && bytes[3] == 0);
  }

  /// Reads family/style metadata from the first face in an SFNT/TTC file.
  static FontFaceMetadata? readFontFaceMetadata(
    Uint8List bytes, {
    int faceIndex = 0,
  }) {
    if (!hasValidFontSignature(bytes) || bytes.length < 12) return null;

    final data = ByteData.sublistView(bytes);
    var faceOffset = 0;
    if (String.fromCharCodes(bytes.take(4)) == 'ttcf') {
      if (bytes.length < 20) return null;
      final faceCount = data.getUint32(8, Endian.big);
      if (faceCount == 0 ||
          faceCount > 4096 ||
          faceIndex < 0 ||
          faceIndex >= faceCount ||
          12 + faceCount * 4 > bytes.length) {
        return null;
      }
      faceOffset = data.getUint32(12 + faceIndex * 4, Endian.big);
    } else if (faceIndex != 0) {
      return null;
    }

    if (faceOffset < 0 || faceOffset + 12 > bytes.length) return null;
    final tableCount = data.getUint16(faceOffset + 4, Endian.big);
    if (tableCount == 0 ||
        tableCount > 4096 ||
        faceOffset + 12 + tableCount * 16 > bytes.length) {
      return null;
    }

    var nameOffset = -1;
    var nameLength = 0;
    for (var index = 0; index < tableCount; index++) {
      final record = faceOffset + 12 + index * 16;
      final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
      if (tag == 'name') {
        nameOffset = data.getUint32(record + 8, Endian.big);
        nameLength = data.getUint32(record + 12, Endian.big);
        break;
      }
    }

    if (nameOffset < 0 ||
        nameLength < 6 ||
        nameOffset + nameLength > bytes.length) {
      return null;
    }

    final format = data.getUint16(nameOffset, Endian.big);
    final count = data.getUint16(nameOffset + 2, Endian.big);
    final stringsOffset = data.getUint16(nameOffset + 4, Endian.big);
    if ((format != 0 && format != 1) ||
        count == 0 ||
        count > 8192 ||
        nameOffset + 6 + count * 12 > bytes.length) {
      return null;
    }

    final values = <int, List<(int, int, String)>>{};
    for (var index = 0; index < count; index++) {
      final record = nameOffset + 6 + index * 12;
      final platform = data.getUint16(record, Endian.big);
      final encoding = data.getUint16(record + 2, Endian.big);
      final language = data.getUint16(record + 4, Endian.big);
      final nameId = data.getUint16(record + 6, Endian.big);
      final length = data.getUint16(record + 8, Endian.big);
      final offset = data.getUint16(record + 10, Endian.big);

      if (nameId != 1 &&
          nameId != 2 &&
          nameId != 4 &&
          nameId != 6 &&
          nameId != 16 &&
          nameId != 17) {
        continue;
      }

      final start = nameOffset + stringsOffset + offset;
      final end = start + length;
      if (start < nameOffset ||
          end > nameOffset + nameLength ||
          end > bytes.length ||
          length == 0) {
        continue;
      }

      String decoded;
      if (platform == 0 || platform == 3) {
        if (length.isOdd ||
            (encoding != 0 && encoding != 1 && encoding != 10)) {
          continue;
        }
        final codeUnits = <int>[];
        for (var byte = start; byte + 1 < end; byte += 2) {
          codeUnits.add((bytes[byte] << 8) | bytes[byte + 1]);
        }
        decoded = String.fromCharCodes(codeUnits);
      } else if (platform == 1) {
        decoded = String.fromCharCodes(bytes.sublist(start, end));
      } else {
        continue;
      }

      decoded = decoded.replaceAll('\u0000', '').trim();
      if (decoded.isEmpty) continue;
      (values[nameId] ??= <(int, int, String)>[]).add(
        (language, platform, decoded),
      );
    }

    String? choose(int id) {
      final candidates = values[id];
      if (candidates == null || candidates.isEmpty) return null;
      candidates.sort((a, b) {
        int score((int, int, String) item) {
          final language = item.$1;
          final platform = item.$2;
          return (language == 0x0409 ? 0 : language == 0 ? 1 : 3) +
              (platform == 3 ? 0 : platform == 0 ? 1 : 2);
        }

        return score(a).compareTo(score(b));
      });
      return candidates.first.$3;
    }

    final family = choose(16) ?? choose(1);
    if (family == null || family.isEmpty) return null;
    final style = choose(17) ?? choose(2) ?? 'Regular';
    final fullName = choose(4) ??
        (style.toLowerCase() == 'regular' ? family : '$family $style');
    return FontFaceMetadata(
      family: family,
      style: style,
      fullName: fullName,
    );
  }

  static List<FontFaceMetadata> readFontFaces(Uint8List bytes) {
    if (!hasValidFontSignature(bytes) || bytes.length < 12) {
      return const <FontFaceMetadata>[];
    }
    if (String.fromCharCodes(bytes.take(4)) != 'ttcf') {
      final face = readFontFaceMetadata(bytes);
      return face == null ? const <FontFaceMetadata>[] : [face];
    }
    if (bytes.length < 20) return const <FontFaceMetadata>[];
    final data = ByteData.sublistView(bytes);
    final count = data.getUint32(8, Endian.big);
    if (count == 0 || count > 4096 || 12 + count * 4 > bytes.length) {
      return const <FontFaceMetadata>[];
    }
    final faces = <FontFaceMetadata>[];
    for (var index = 0; index < count; index++) {
      final face = readFontFaceMetadata(bytes, faceIndex: index);
      if (face != null) faces.add(face);
    }
    return faces;
  }

  static String familyAliasFor(FontFaceMetadata? metadata, String fallback) {
    final family = metadata?.family ?? fallback;
    final style = metadata?.style ?? 'Regular';
    final cleaned = '$family $style $fallback'
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? 'DepthVibe_Font' : 'DV_$cleaned';
  }

  String _fileName(String path) => path.split(RegExp(r'[/\\]')).last;

  String _fileStem(String path) {
    final name = _fileName(path);
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final support = await getApplicationSupportDirectory();
    _directory = Directory(
      support.path +
          Platform.pathSeparator +
          'DepthVibe' +
          Platform.pathSeparator +
          'Fonts',
    );
    await _directory!.create(recursive: true);
    await _readSettings();
    _availableFonts = List<FontCatalogEntry>.from(_importedFonts);

    if (_activeFamily != null && _activeFontPath != null) {
      try {
        await ensureFontLoaded(
          family: _activeFamily!,
          path: _activeFontPath!,
        );
      } catch (_) {
        _activeFamily = null;
        _activeFontPath = null;
        await _writeSettings();
      }
    }
    _initialized = true;
  }

  Future<void> refreshAvailableFonts() async {
    await initialize();
    if (_scanning) return;
    _scanning = true;
    notifyListeners();

    try {
      final entries = <FontCatalogEntry>[..._importedFonts];
      final seenPaths = <String>{for (final item in entries) item.path};
      final seenFaces = <String>{};

      for (final root in _systemFontRoots()) {
        final directory = Directory(root);
        if (!await directory.exists()) continue;
        var inspected = 0;

        try {
          await for (final entity
              in directory.list(recursive: true, followLinks: false)) {
            if (entity is! File ||
                !isSupportedFontFilePath(entity.path) ||
                !seenPaths.add(entity.path)) {
              continue;
            }

            inspected++;
            if (inspected > maxSystemFontFilesPerRoot) break;

            final stat = await entity.stat();
            if (stat.size < 4 || stat.size > maxFontBytes) continue;
            final bytes = await entity.readAsBytes();
            if (!hasValidFontSignature(bytes)) continue;

            final faces = readFontFaces(bytes);
            if (faces.isEmpty) {
              final fallbackFamily = _fileStem(entity.path);
              final faceKey = (fallbackFamily + '\u0000Regular').toLowerCase();
              if (seenFaces.add(faceKey)) {
                entries.add(FontCatalogEntry(
                  family: fallbackFamily,
                  displayName: fallbackFamily,
                  path: entity.path,
                  isImported: false,
                  actualFamily: fallbackFamily,
                  styleName: 'Regular',
                ));
              }
              continue;
            }

            for (final face in faces) {
              final faceKey =
                  (face.family + '\u0000' + face.style).toLowerCase();
              if (!seenFaces.add(faceKey)) continue;

              // System fonts are resolved by their actual OS family name.
              entries.add(FontCatalogEntry(
                family: face.family,
                displayName: face.displayName,
                path: entity.path,
                isImported: false,
                actualFamily: face.family,
                styleName: face.style,
              ));
            }
          }
        } catch (_) {
          // Some OS font directories contain protected or unreadable entries.
        }
      }

      entries.sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      _availableFonts = entries;
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  Future<FontCatalogEntry> importFont(
    String sourcePath, {
    bool persistSettings = true,
  }) async {
    await initialize();
    if (!isImportableFontFilePath(sourcePath)) {
      throw const FormatException(
        'Import a TrueType (.ttf) or OpenType (.otf) font. '
        'Installed .ttc collections are detected automatically.',
      );
    }

    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Font file does not exist.', sourcePath);
    }

    final stat = await source.stat();
    if (stat.size < 4 || stat.size > maxFontBytes) {
      throw const FormatException(
        'Font file size is invalid or exceeds 64 MiB.',
      );
    }

    final bytes = await source.readAsBytes();
    if (!hasValidFontSignature(bytes) ||
        String.fromCharCodes(bytes.take(4)) == 'ttcf') {
      throw const FormatException('The selected file is not a TTF/OTF font.');
    }

    final name = _fileName(sourcePath);
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    var destination = File(
      _directory!.path + Platform.pathSeparator + safeName,
    );
    var suffix = 2;
    while (await destination.exists()) {
      final dot = safeName.lastIndexOf('.');
      final stem = dot < 0 ? safeName : safeName.substring(0, dot);
      final extension = dot < 0 ? '' : safeName.substring(dot);
      destination = File(
        _directory!.path +
            Platform.pathSeparator +
            stem +
            '_' +
            suffix.toString() +
            extension,
      );
      suffix++;
    }

    await destination.writeAsBytes(bytes, flush: true);
    final face = readFontFaceMetadata(bytes);
    final base = familyAliasFor(face, _fileStem(destination.path));
    var family = base;
    var familySuffix = 2;
    while (_availableFonts.any((font) => font.family == family) ||
        _importedFonts.any((font) => font.family == family)) {
      family = base + '_' + familySuffix.toString();
      familySuffix++;
    }

    final entry = FontCatalogEntry(
      family: family,
      displayName: face?.displayName ?? _fileStem(sourcePath),
      path: destination.path,
      isImported: true,
      actualFamily: face?.family,
      styleName: face?.style,
    );

    try {
      await ensureFontLoaded(family: family, path: destination.path);
    } catch (_) {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }

    _importedFonts = [..._importedFonts, entry];
    _availableFonts = [..._availableFonts, entry]
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    if (persistSettings) {
      await _writeSettings();
      notifyListeners();
    }
    return entry;
  }

  Future<FontFolderImportResult> importFontFolder(String directoryPath) async {
    await initialize();
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      throw FileSystemException('Font folder does not exist.', directoryPath);
    }

    var imported = 0;
    var skipped = 0;
    var inspected = 0;
    var totalBytes = 0;
    const maxBulkImportBytes = 1024 * 1024 * 1024;

    await for (final entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File ||
          !isImportableFontFilePath(entity.path)) {
        continue;
      }
      if (inspected >= 2000) {
        skipped++;
        break;
      }
      inspected++;

      try {
        final size = await entity.length();
        if (size < 4 ||
            size > maxFontBytes ||
            totalBytes + size > maxBulkImportBytes) {
          skipped++;
          continue;
        }
        await importFont(entity.path, persistSettings: false);
        totalBytes += size;
        imported++;
      } catch (_) {
        skipped++;
      }
    }

    if (imported > 0) {
      await _writeSettings();
      notifyListeners();
    }
    return FontFolderImportResult(imported: imported, skipped: skipped);
  }

  FontCatalogEntry? _entryForFamily(String family) {
    for (final entry in _availableFonts) {
      if (entry.family == family) return entry;
    }
    return null;
  }

  Future<void> ensureFontsLoaded({
    String? family,
    String? path,
    Iterable<String> fallbackFamilies = const [],
  }) async {
    await initialize();

    if (family != null && family.isNotEmpty) {
      final entry = _entryForFamily(family);
      if (entry != null && !entry.isImported) {
        // Installed fonts are resolved by their OS family name.
        _loadedFamilies.add(family);
      } else {
        final resolvedPath = path ?? entry?.path;
        if (resolvedPath != null) {
          await ensureFontLoaded(family: family, path: resolvedPath);
        }
      }
    }

    for (final fallback in fallbackFamilies.toSet()) {
      if (fallback.isEmpty || _loadedFamilies.contains(fallback)) continue;
      final entry = _entryForFamily(fallback);
      if (entry == null) continue;
      if (!entry.isImported) {
        _loadedFamilies.add(fallback);
      } else {
        await ensureFontLoaded(
          family: entry.family,
          path: entry.path,
        );
      }
    }
  }

  Future<void> ensureFontLoaded({
    required String family,
    required String path,
  }) async {
    if (_loadedFamilies.contains(family)) return;
    final entry = _entryForFamily(family);
    if (entry != null && !entry.isImported) {
      _loadedFamilies.add(family);
      return;
    }

    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Font file is missing.', path);
    }
    final stat = await file.stat();
    if (stat.size < 4 || stat.size > maxFontBytes) {
      throw const FormatException('Font file size is invalid or exceeds 64 MiB.');
    }

    final bytes = await file.readAsBytes();
    if (!hasValidFontSignature(bytes) ||
        String.fromCharCodes(bytes.take(4)) == 'ttcf') {
      throw const FormatException(
        'Only TTF and OTF files can be loaded as imported fonts.',
      );
    }

    final loader = FontLoader(family);
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loadedFamilies.add(family);
  }

  Future<void> setAppDefault(FontCatalogEntry? entry) async {
    await initialize();
    if (entry == null) {
      _activeFamily = null;
      _activeFontPath = null;
    } else {
      if (entry.isImported) {
        await ensureFontLoaded(
          family: entry.family,
          path: entry.path,
        );
        _activeFontPath = entry.path;
      } else {
        _activeFontPath = null;
      }
      _activeFamily = entry.family;
    }

    await _writeSettings();
    notifyListeners();
  }

  Future<void> setFallbackFamilies(String commaSeparated) async {
    final values = commaSeparated
        .split(RegExp(r'[,;\n]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .take(30)
        .toSet()
        .toList();

    _fallbackFamilies = values.isEmpty
        ? List<String>.from(defaultFallbackFamilies)
        : values;
    await _writeSettings();
    notifyListeners();
  }

  Future<void> removeImportedFont(FontCatalogEntry entry) async {
    if (!entry.isImported) {
      throw StateError('System fonts cannot be removed from this device.');
    }

    _importedFonts = _importedFonts
        .where((font) => font.path != entry.path)
        .toList();
    _availableFonts = _availableFonts
        .where((font) => font.path != entry.path)
        .toList();

    final file = File(entry.path);
    if (await file.exists()) await file.delete();
    if (_activeFontPath == entry.path) {
      _activeFamily = null;
      _activeFontPath = null;
    }

    await _writeSettings();
    notifyListeners();
  }

  Future<void> _readSettings() async {
    final file = File(
      _directory!.path + Platform.pathSeparator + 'font-settings.json',
    );
    if (!await file.exists()) return;

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;

      _activeFamily = decoded['activeFamily'] as String?;
      _activeFontPath = decoded['activeFontPath'] as String?;

      final fallback = decoded['fallbackFamilies'];
      if (fallback is List) {
        final values = fallback
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .take(30)
            .toList();
        if (values.isNotEmpty) _fallbackFamilies = values;
      }

      final rawFonts = decoded['importedFonts'];
      if (rawFonts is List) {
        final parsed = rawFonts
            .whereType<Map>()
            .map((item) => FontCatalogEntry.fromJson(
                  item.cast<String, Object?>(),
                ))
            .where((item) => item.family.isNotEmpty && item.path.isNotEmpty);

        final validFonts = <FontCatalogEntry>[];
        for (final font in parsed) {
          if (await File(font.path).exists()) validFonts.add(font);
        }
        _importedFonts = validFonts;
      }
    } catch (_) {
      _importedFonts = <FontCatalogEntry>[];
      _activeFamily = null;
      _activeFontPath = null;
    }
  }

  Future<void> _writeSettings() async {
    final directory = _directory;
    if (directory == null) return;

    final file = File(
      directory.path + Platform.pathSeparator + 'font-settings.json',
    );
    final temporary = File(file.path + '.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 2,
        'activeFamily': _activeFamily,
        'activeFontPath': _activeFontPath,
        'fallbackFamilies': _fallbackFamilies,
        'importedFonts': _importedFonts.map((font) => font.toJson()).toList(),
      }),
      flush: true,
    );

    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  List<String> _systemFontRoots() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';

    if (Platform.isWindows) {
      final windows = Platform.environment['WINDIR'] ?? r'C:\Windows';
      final localFonts = Platform.environment['LOCALAPPDATA'] ??
          (home.isEmpty ? '' : home + r'\AppData\Local');
      return [
        windows + r'\Fonts',
        if (localFonts.isNotEmpty)
          localFonts + r'\Microsoft\Windows\Fonts',
      ];
    }

    if (Platform.isMacOS) {
      return [
        '/System/Library/Fonts',
        '/Library/Fonts',
        if (home.isNotEmpty) home + '/Library/Fonts',
      ];
    }

    if (Platform.isLinux) {
      return [
        '/usr/share/fonts',
        '/usr/local/share/fonts',
        if (home.isNotEmpty) home + '/.local/share/fonts',
        if (home.isNotEmpty) home + '/.fonts',
      ];
    }

    if (Platform.isAndroid) return ['/system/fonts'];
    return <String>[];
  }
}
