import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'extension_manager_service.dart';
import 'marketplace_models.dart';
import 'publisher_trust_store.dart';

class MarketplaceUpdate {
  const MarketplaceUpdate({
    required this.entry,
    required this.installedVersion,
  });

  final MarketplaceExtension entry;
  final String installedVersion;
}

class ExtensionMarketplaceService extends ChangeNotifier {
  ExtensionMarketplaceService({
    ExtensionManagerService? manager,
    PublisherTrustStore? trustStore,
  })  : _manager = manager ?? ExtensionManagerService.instance,
        _trustStore = trustStore ?? PublisherTrustStore.instance;

  static final ExtensionMarketplaceService instance =
      ExtensionMarketplaceService();

  static const maxCatalogBytes = 2 * 1024 * 1024;
  static const maxPackageBytes = 128 * 1024 * 1024;
  static const defaultCatalogUrl = '';

  final ExtensionManagerService _manager;
  final PublisherTrustStore _trustStore;
  SignedMarketplaceCatalog? _catalog;
  List<MarketplaceUpdate> _updates = [];
  String? _lastError;
  String? _catalogUrl;
  bool _busy = false;
  bool _autoUpdateEnabled = false;
  Directory? _settingsDirectory;
  bool _initialized = false;
  Timer? _autoUpdateTimer;

  SignedMarketplaceCatalog? get catalog => _catalog;
  List<MarketplaceUpdate> get updates => List.unmodifiable(_updates);
  String? get lastError => _lastError;
  String get catalogUrl => _catalogUrl ?? defaultCatalogUrl;
  bool get isBusy => _busy;
  bool get autoUpdateEnabled => _autoUpdateEnabled;

  Future<void> initialize() async {
    if (_initialized) return;
    final documents = await getApplicationDocumentsDirectory();
    _settingsDirectory = Directory(
      documents.path +
          Platform.pathSeparator +
          'DepthVibe' +
          Platform.pathSeparator +
          'Extensions',
    );
    await _settingsDirectory!.create(recursive: true);
    final file = File(
      _settingsDirectory!.path +
          Platform.pathSeparator +
          'marketplace_settings.json',
    );
    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString());
        if (json is Map) {
          final url = json['catalogUrl'];
          if (url is String && _validCatalogUri(url) != null) {
            _catalogUrl = url;
          }
          _autoUpdateEnabled = json['autoUpdateEnabled'] == true;
        }
      } catch (_) {
        _lastError = 'Marketplace settings could not be read.';
      }
    }
    await _trustStore.initialize();
    await _manager.initialize();
    _initialized = true;
    notifyListeners();
  }

  Future<void> startAutoUpdater() async {
    await initialize();
    _autoUpdateTimer ??= Timer.periodic(
      const Duration(hours: 24),
      (_) => unawaited(_checkAutomaticUpdates()),
    );
    if (_autoUpdateEnabled) {
      unawaited(_checkAutomaticUpdates());
    }
  }

  Future<void> _checkAutomaticUpdates() async {
    if (!_autoUpdateEnabled || _busy) return;
    try {
      await refreshCatalog();
      await applyAutomaticDepthVibeUpdates();
    } catch (error) {
      _lastError = error.toString();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _autoUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> setCatalogUrl(String value) async {
    await initialize();
    final uri = _validCatalogUri(value);
    if (uri == null) {
      throw const FormatException('Marketplace feed must be an HTTPS URL.');
    }
    _catalogUrl = uri.toString();
    await _writeSettings();
    notifyListeners();
  }

  Future<void> setAutoUpdateEnabled(bool value) async {
    await initialize();
    _autoUpdateEnabled = value;
    await _writeSettings();
    notifyListeners();
  }

  Future<SignedMarketplaceCatalog> refreshCatalog({String? url}) async {
    await initialize();
    final selectedUrl = url ?? catalogUrl;
    if (selectedUrl.trim().isEmpty) {
      throw const FormatException(
        'Set a publisher HTTPS catalog URL before refreshing.',
      );
    }
    final uri = _validCatalogUri(selectedUrl);
    if (uri == null) {
      throw const FormatException('Marketplace feed must use HTTPS.');
    }
    _setBusy(true);
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      try {
        final request = await client.getUrl(uri).timeout(
              const Duration(seconds: 15),
            );
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close().timeout(
              const Duration(seconds: 25),
            );
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            'Marketplace server returned ' +
                response.statusCode.toString() +
                '.',
            uri: uri,
          );
        }
        final bytes = <int>[];
        await for (final chunk
            in response.timeout(const Duration(seconds: 25))) {
          bytes.addAll(chunk);
          if (bytes.length > maxCatalogBytes) {
            throw const FormatException('Marketplace catalog is too large.');
          }
        }
        final catalog = SignedMarketplaceCatalog.fromJson(
          jsonDecode(utf8.decode(bytes)),
        );
        final trusted = await _trustStore.verify(
          publisherId: catalog.publisherId,
          keyId: catalog.keyId,
          message: catalog.canonicalPayload,
          signatureBytes: base64Decode(catalog.signature),
        );
        if (!trusted) {
          throw StateError(
            'Marketplace publisher is not trusted or its signature is invalid. '
            'Import and verify the publisher .dvpub key first.',
          );
        }
        _catalog = catalog;
        _catalogUrl = uri.toString();
        _lastError = null;
        _updates = _findUpdates(catalog);
        await _writeSettings();
        notifyListeners();
        return catalog;
      } finally {
        client.close(force: true);
      }
    } catch (error) {
      _lastError = error.toString();
      notifyListeners();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> install(MarketplaceExtension entry) async {
    await initialize();
    _setBusy(true);
    File? downloaded;
    var keepDownloadedFile = false;
    try {
      downloaded = await _downloadVerified(entry);
      switch (entry.packageType) {
        case MarketplacePackageType.depthVibe:
          await _manager.installFromFile(
            downloaded,
            replaceExisting: _manager.installed.any(
              (item) => item.manifest.id == entry.id,
            ),
            expectedExtensionId: entry.id,
            expectedVersion: entry.version,
          );
          break;
        case MarketplacePackageType.premiereUxp:
        case MarketplacePackageType.afterEffectsCep:
        case MarketplacePackageType.afterEffectsUxpBeta:
          await _openExternalInstaller(downloaded);
          keepDownloadedFile = true;
          break;
      }
      if (_catalog != null) {
        _updates = _findUpdates(_catalog!);
      }
      _lastError = null;
      notifyListeners();
    } catch (error) {
      _lastError = error.toString();
      notifyListeners();
      rethrow;
    } finally {
      if (!keepDownloadedFile &&
          downloaded != null &&
          await downloaded.exists()) {
        await downloaded.delete();
      }
      _setBusy(false);
    }
  }

  Future<int> applyAutomaticDepthVibeUpdates() async {
    await initialize();
    if (!_autoUpdateEnabled || _catalog == null) return 0;
    var count = 0;
    for (final update in List<MarketplaceUpdate>.from(_updates)) {
      if (update.entry.packageType != MarketplacePackageType.depthVibe) {
        continue;
      }
      await install(update.entry);
      count++;
    }
    return count;
  }

  Future<File> _downloadVerified(MarketplaceExtension entry) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(entry.downloadUrl).timeout(
            const Duration(seconds: 20),
          );
      request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
      final response = await request.close().timeout(
            const Duration(seconds: 40),
          );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Package download returned ' +
              response.statusCode.toString() +
              '.',
          uri: entry.downloadUrl,
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk
          in response.timeout(const Duration(seconds: 45))) {
        builder.add(chunk);
        if (builder.length > maxPackageBytes) {
          throw const FormatException('Downloaded package exceeds size limit.');
        }
      }
      final bytes = builder.takeBytes();
      final digest = await Sha256().hash(bytes);
      final actual = digest.bytes
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      if (actual != entry.sha256) {
        throw const FormatException(
          'Downloaded package SHA-256 does not match the signed catalog.',
        );
      }
      final directory = Directory(
        _settingsDirectory!.path +
            Platform.pathSeparator +
            'MarketplaceDownloads',
      );
      await directory.create(recursive: true);
      final extension = switch (entry.packageType) {
        MarketplacePackageType.depthVibe => '.dvext',
        MarketplacePackageType.premiereUxp => '.ccx',
        MarketplacePackageType.afterEffectsCep => '.zip',
        MarketplacePackageType.afterEffectsUxpBeta => '.zip',
      };
      final file = File(
        directory.path +
            Platform.pathSeparator +
            entry.id +
            '-' +
            entry.version +
            extension,
      );
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } finally {
      client.close(force: true);
    }
  }

  List<MarketplaceUpdate> _findUpdates(SignedMarketplaceCatalog catalog) {
    final installed = {
      for (final item in _manager.installed)
        item.manifest.id: item.manifest.version,
    };
    final result = <MarketplaceUpdate>[];
    for (final entry in catalog.entries) {
      final current = installed[entry.id];
      if (current != null && _compareSemver(entry.version, current) > 0) {
        result.add(MarketplaceUpdate(
          entry: entry,
          installedVersion: current,
        ));
      }
    }
    return result;
  }

  Future<void> _openExternalInstaller(File file) async {
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [file.path]);
    } else if (Platform.isMacOS) {
      await Process.start('open', ['--', file.path]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', ['--', file.path]);
    } else {
      throw UnsupportedError(
        'Adobe desktop installers can only be opened on Windows, macOS or Linux.',
      );
    }
  }

  Future<void> _writeSettings() async {
    await _settingsDirectory!.create(recursive: true);
    final target = File(
      _settingsDirectory!.path +
          Platform.pathSeparator +
          'marketplace_settings.json',
    );
    await target.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'catalogUrl': catalogUrl,
        'autoUpdateEnabled': _autoUpdateEnabled,
      }),
      flush: true,
    );
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  static Uri? _validCatalogUri(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
        ? uri
        : null;
  }

  static int _compareSemver(String a, String b) {
    final pattern = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
    );
    final left = pattern.firstMatch(a);
    final right = pattern.firstMatch(b);
    if (left == null || right == null) {
      throw FormatException('Invalid semantic version comparison: $a / $b');
    }
    for (var index = 1; index <= 3; index++) {
      final comparison =
          int.parse(left.group(index)!).compareTo(int.parse(right.group(index)!));
      if (comparison != 0) return comparison;
    }

    final leftPre = left.group(4);
    final rightPre = right.group(4);
    if (leftPre == null && rightPre == null) return 0;
    if (leftPre == null) return 1;
    if (rightPre == null) return -1;

    final leftParts = leftPre.split('.');
    final rightParts = rightPre.split('.');
    final count = leftParts.length < rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < count; index++) {
      final leftPart = leftParts[index];
      final rightPart = rightParts[index];
      final leftNumeric = RegExp(r'^\d+$').hasMatch(leftPart);
      final rightNumeric = RegExp(r'^\d+$').hasMatch(rightPart);
      if (leftNumeric && rightNumeric) {
        final comparison = int.parse(leftPart).compareTo(int.parse(rightPart));
        if (comparison != 0) return comparison;
      } else if (leftNumeric != rightNumeric) {
        return leftNumeric ? -1 : 1;
      } else {
        final comparison = leftPart.compareTo(rightPart);
        if (comparison != 0) return comparison;
      }
    }
    return leftParts.length.compareTo(rightParts.length);
  }
}
