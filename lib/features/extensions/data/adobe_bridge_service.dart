import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../composition/application/composition_controller.dart';
import '../../composition/data/effect_catalog.dart';
import '../../composition/engine/composition_project_codec.dart';

class AdobeHostSession {
  const AdobeHostSession({
    required this.sessionId,
    required this.hostApp,
    required this.hostVersion,
    required this.connectedAt,
    required this.lastSeenAt,
  });

  final String sessionId;
  final String hostApp;
  final String hostVersion;
  final DateTime connectedAt;
  final DateTime lastSeenAt;
}

class _AuthorizedAdobeSession {
  const _AuthorizedAdobeSession({
    required this.id,
    required this.session,
  });

  final String id;
  final AdobeHostSession session;
}

class AdobeBridgeService extends ChangeNotifier {
  AdobeBridgeService();

  static final AdobeBridgeService instance = AdobeBridgeService();
  static const int defaultPort = 47653;
  static const int maxRequestBytes = 32 * 1024 * 1024;

  HttpServer? _server;
  CompositionController? _controller;
  String? _pairingCode;
  String? _lastError;
  final Map<String, AdobeHostSession> _sessions = {};
  final Map<String, String> _sessionTokens = {};
  final Random _random = Random.secure();
  int _pairingFailures = 0;
  DateTime? _lastPairingFailure;
  bool _secure = false;
  Map<String, Object?>? _lastHostMetadata;

  bool get isRunning => _server != null;
  Map<String, Object?>? get lastHostMetadata =>
      _lastHostMetadata == null
          ? null
          : Map<String, Object?>.unmodifiable(_lastHostMetadata!);
  int get port => _server?.port ?? defaultPort;
  String get scheme => _secure ? 'https' : 'http';
  String get baseUrl => scheme + '://127.0.0.1:' + port.toString();
  String? get pairingCode => _pairingCode;
  String? get lastError => _lastError;
  List<AdobeHostSession> get sessions => List.unmodifiable(_sessions.values);

  Future<void> start({int port = defaultPort}) async {
    if (!_desktopSupported || _server != null) return;
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );
      _activate(server, secure: false);
    } catch (error) {
      _server = null;
      _pairingCode = null;
      _secure = false;
      _lastError = error.toString();
    }
    notifyListeners();
  }

  Future<void> startSecure({
    required File certificateChain,
    required File privateKey,
    String? password,
    int port = defaultPort,
  }) async {
    if (!_desktopSupported) return;
    if (!await certificateChain.exists() ||
        !await privateKey.exists() ||
        await certificateChain.length() > 1024 * 1024 ||
        await privateKey.length() > 128 * 1024) {
      throw const FormatException(
        'The TLS certificate or private key is missing or too large.',
      );
    }
    await stop();
    try {
      final context = SecurityContext();
      context.useCertificateChain(
        certificateChain.path,
        password: password,
      );
      context.usePrivateKey(
        privateKey.path,
        password: password,
      );
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        port,
        context,
        shared: false,
      );
      _activate(server, secure: true);
      _lastError = null;
    } catch (error) {
      _server = null;
      _pairingCode = null;
      _secure = false;
      _lastError = error.toString();
    }
    notifyListeners();
  }

  bool get _desktopSupported =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  void _activate(HttpServer server, {required bool secure}) {
    _server = server;
    _secure = secure;
    _pairingCode = _newPairingCode();
    _lastError = null;
    server.listen(
      _handleRequest,
      onError: (Object error) {
        _lastError = error.toString();
        notifyListeners();
      },
    );
  }

  void attachController(CompositionController controller) {
    _controller = controller;
  }

  void disconnectSession(String sessionId) {
    _sessionTokens.remove(sessionId);
    _sessions.remove(sessionId);
    notifyListeners();
  }

  void detachController(CompositionController controller) {
    if (identical(_controller, controller)) _controller = null;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _pairingCode = null;
    _secure = false;
    _sessions.clear();
    _sessionTokens.clear();
    _lastHostMetadata = null;
    notifyListeners();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    response.headers
      ..set(HttpHeaders.accessControlAllowOriginHeader, '*')
      ..set(
        HttpHeaders.accessControlAllowMethodsHeader,
        'GET, POST, OPTIONS',
      )
      ..set(
        HttpHeaders.accessControlAllowHeadersHeader,
        'Content-Type, Authorization',
      )
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..contentType = ContentType.json;

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
      await response.close();
      return;
    }

    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/v1/health') {
        _writeJson(response, HttpStatus.ok, {
          'ok': true,
          'service': 'DepthVibe Adobe Bridge',
          'version': 1,
          'pairingRequired': true,
        });
        return;
      }
      if (request.method == 'POST' && path == '/v1/pair') {
        await _pair(request);
        return;
      }

      final token = _readBearer(request);
      final authorized =
          token == null ? null : _sessionForToken(token);
      if (authorized == null) {
        _writeJson(response, HttpStatus.unauthorized, {
          'ok': false,
          'error': 'Pair this Adobe panel with the code shown in DepthVibe.',
        });
        return;
      }

      switch (request.method + ' ' + request.uri.path) {
        case 'GET /v1/session':
          final session = _touchSession(authorized);
          _writeJson(response, HttpStatus.ok, {
            'ok': true,
            'hostApp': session.hostApp,
            'hostVersion': session.hostVersion,
            'connectedAt': session.connectedAt.toIso8601String(),
            'lastSeenAt': session.lastSeenAt.toIso8601String(),
          });
          return;

        case 'GET /v1/effects':
          _touchSession(authorized);
          _writeJson(response, HttpStatus.ok, {
            'ok': true,
            'effects': EffectCatalog.allEffects.map((effect) => {
              'id': effect.id,
              'name': effect.name,
              'category': effect.category,
              'description': effect.description,
              'parameters': [
                for (final parameter in effect.parameters)
                  {
                    'id': parameter.id,
                    'label': parameter.label,
                    'min': parameter.min,
                    'max': parameter.max,
                    'defaultValue': parameter.defaultValue,
                  },
              ],
            }).toList(),
          });
          return;

        case 'GET /v1/composition':
          _touchSession(authorized);
          final controller = _controller;
          if (controller == null) {
            _writeJson(response, HttpStatus.conflict, {
              'ok': false,
              'error': 'Open the DepthVibe Compositor first.',
            });
            return;
          }
          _writeJson(response, HttpStatus.ok, {
            'ok': true,
            'document': CompositionProjectCodec.encodeDocument(
              controller.document,
            ),
          });
          return;

        case 'POST /v1/composition':
          _touchSession(authorized);
          final controller = _controller;
          if (controller == null) {
            _writeJson(response, HttpStatus.conflict, {
              'ok': false,
              'error': 'Open the DepthVibe Compositor first.',
            });
            return;
          }
          final body = await _readJsonBody(request);
          final imported = CompositionProjectCodec.decodeDocument(
            body['document'],
          );
          controller.replaceDocument(imported);
          _writeJson(response, HttpStatus.ok, {
            'ok': true,
            'importedLayers': imported.layers.length,
            'message': 'Composition imported into DepthVibe.',
          });
          return;

        case 'GET /v1/adobe/metadata':
          _touchSession(authorized);
          final snapshot = _lastHostMetadata;
          if (snapshot == null) {
            _writeJson(response, HttpStatus.notFound, {
              'ok': false,
              'error': 'No Adobe host snapshot has been received yet.',
            });
            return;
          }
          _writeJson(response, HttpStatus.ok, {
            'ok': true,
            'snapshot': snapshot,
          });
          return;

        case 'POST /v1/adobe/metadata':
          final body = await _readJsonBody(request);
          final snapshot = body['snapshot'];
          if (snapshot is! Map) {
            throw const FormatException(
              'Adobe metadata request must include a snapshot object.',
            );
          }
          final snapshotMap = <String, Object?>{
            for (final entry in snapshot.entries)
              if (entry.key is String) entry.key as String: entry.value,
          };
          if (snapshotMap['schemaVersion'] != 1 ||
              snapshotMap['hostApp'] != authorized.session.hostApp ||
              snapshotMap['hostVersion'] != authorized.session.hostVersion ||
              snapshotMap['payload'] is! Map) {
            throw const FormatException(
              'Adobe snapshot schema or host identity does not match the paired session.',
            );
          }
          final serializedSnapshot = jsonEncode(snapshotMap);
          if (utf8.encode(serializedSnapshot).length > 16 * 1024 * 1024) {
            throw const FormatException(
              'Adobe snapshot exceeds the 16 MiB storage limit.',
            );
          }
          final session = _touchSession(authorized);
          _lastHostMetadata = {
            ...snapshotMap,
            'receivedAt': DateTime.now().toUtc().toIso8601String(),
            'pairedHostVersion': session.hostVersion,
            'sessionId': session.sessionId,
          };
          notifyListeners();
          _writeJson(response, HttpStatus.ok, {
            'ok': true,
            'message': 'Adobe host snapshot received.',
            'hostApp': session.hostApp,
            'payloadKeys': (snapshotMap['payload'] as Map).keys.length,
          });
          return;

        case 'POST /v1/disconnect':
          disconnectSession(authorized.id);
          _writeJson(response, HttpStatus.ok, {'ok': true});
          return;

        default:
          _writeJson(response, HttpStatus.notFound, {
            'ok': false,
            'error': 'Unknown bridge endpoint.',
          });
          return;
      }
    } on FormatException catch (error) {
      _writeJson(response, HttpStatus.badRequest, {
        'ok': false,
        'error': error.message,
      });
    } catch (error) {
      _writeJson(response, HttpStatus.internalServerError, {
        'ok': false,
        'error': error.toString(),
      });
    }
  }

  Future<void> _pair(HttpRequest request) async {
    if (_pairingFailures >= 5 &&
        _lastPairingFailure != null &&
        DateTime.now().difference(_lastPairingFailure!) <
            const Duration(minutes: 5)) {
      _writeJson(request.response, HttpStatus.tooManyRequests, {
        'ok': false,
        'error': 'Too many pairing attempts. Try again in five minutes.',
      });
      return;
    }

    final body = await _readJsonBody(request);
    final code = body['code'];
    final hostApp = body['hostApp'];
    final hostVersion = body['hostVersion'];
    const supportedHosts = {
      'premierepro',
      'aftereffects',
      'aftereffects-beta',
    };
    if (code is! String ||
        code != _pairingCode ||
        hostApp is! String ||
        !supportedHosts.contains(hostApp) ||
        hostVersion is! String ||
        hostVersion.length > 40) {
      _pairingFailures++;
      _lastPairingFailure = DateTime.now();
      _writeJson(request.response, HttpStatus.forbidden, {
        'ok': false,
        'error': 'Pairing code or Adobe host information is invalid.',
      });
      return;
    }

    _pairingFailures = 0;
    final sessionId = _randomHex(12);
    final token = _randomHex(32);
    final now = DateTime.now().toUtc();
    _sessions[sessionId] = AdobeHostSession(
      sessionId: sessionId,
      hostApp: hostApp,
      hostVersion: hostVersion,
      connectedAt: now,
      lastSeenAt: now,
    );
    _sessionTokens[sessionId] = token;
    _pairingCode = _newPairingCode();
    notifyListeners();
    _writeJson(request.response, HttpStatus.ok, {
      'ok': true,
      'sessionId': sessionId,
      'token': token,
      'hostApp': hostApp,
      'bridgeVersion': 1,
    });
  }

  _AuthorizedAdobeSession? _sessionForToken(String token) {
    for (final entry in _sessionTokens.entries) {
      if (entry.value == token) {
        final session = _sessions[entry.key];
        if (session != null) {
          return _AuthorizedAdobeSession(
            id: entry.key,
            session: session,
          );
        }
      }
    }
    return null;
  }

  AdobeHostSession _touchSession(_AuthorizedAdobeSession authorized) {
    final session = authorized.session;
    final updated = AdobeHostSession(
      sessionId: session.sessionId,
      hostApp: session.hostApp,
      hostVersion: session.hostVersion,
      connectedAt: session.connectedAt,
      lastSeenAt: DateTime.now().toUtc(),
    );
    _sessions[authorized.id] = updated;
    notifyListeners();
    return updated;
  }

  String? _readBearer(HttpRequest request) {
    final value = request.headers.value(HttpHeaders.authorizationHeader);
    if (value == null || !value.startsWith('Bearer ')) return null;
    return value.substring(7);
  }

  Future<Map<String, Object?>> _readJsonBody(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request.timeout(const Duration(seconds: 10))) {
      bytes.addAll(chunk);
      if (bytes.length > maxRequestBytes) {
        throw const FormatException('Bridge request exceeds the size limit.');
      }
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('Bridge request must be a JSON object.');
    }
    return <String, Object?>{
      for (final entry in decoded.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  void _writeJson(
    HttpResponse response,
    int status,
    Map<String, Object?> body,
  ) {
    response.statusCode = status;
    response.write(jsonEncode(body));
    unawaited(response.close());
  }

  String _newPairingCode() {
    String code;
    do {
      code = (100000 + _random.nextInt(900000)).toString();
    } while (code == _pairingCode);
    return code;
  }

  String _randomHex(int bytes) {
    final values = List<int>.generate(bytes, (_) => _random.nextInt(256));
    return values
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
