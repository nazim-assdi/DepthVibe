import 'dart:convert';
import 'dart:io';

import 'package:depthvibe/features/composition/application/composition_controller.dart';
import 'package:depthvibe/features/extensions/data/adobe_bridge_service.dart';
import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/composition_project_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdobeBridgeService', () {
    late AdobeBridgeService bridge;
    late CompositionController controller;
    late HttpClient client;

    setUp(() async {
      bridge = AdobeBridgeService();
      controller = CompositionController();
      client = HttpClient();
      bridge.attachController(controller);
      await bridge.start(port: 0);
    });

    tearDown(() async {
      await bridge.stop();
      bridge.dispose();
      controller.dispose();
      client.close(force: true);
    });

    Future<Map<String, Object?>> send(
      String method,
      String path, {
      String? token,
      Map<String, Object?>? body,
    }) async {
      final uri = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: bridge.port,
        path: path,
      );
      final request = await client.openUrl(method, uri);
      request.headers.contentType = ContentType.json;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ' + token);
      }
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      final content = await utf8.decoder.bind(response).join();
      return {
        'status': response.statusCode,
        'body': jsonDecode(content) as Map<String, Object?>,
      };
    }

    test('pairs an Adobe panel, reads composition/effects and revokes session',
        () async {
      expect(bridge.isRunning, isTrue);
      final pairingCode = bridge.pairingCode;
      expect(pairingCode, matches(RegExp(r'^\d{6}$')));

      final health = await send('GET', '/v1/health');
      expect(health['status'], HttpStatus.ok);

      final unauthenticated = await send('GET', '/v1/effects');
      expect(unauthenticated['status'], HttpStatus.unauthorized);

      final paired = await send(
        'POST',
        '/v1/pair',
        body: {
          'code': pairingCode,
          'hostApp': 'premierepro',
          'hostVersion': '25.6.0',
        },
      );
      expect(paired['status'], HttpStatus.ok);
      final pairBody = paired['body'] as Map<String, Object?>;
      final token = pairBody['token'] as String;
      final sessionId = pairBody['sessionId'] as String;
      expect(bridge.pairingCode, isNot(pairingCode));

      final session = await send('GET', '/v1/session', token: token);
      expect(session['status'], HttpStatus.ok);
      expect(
        (session['body'] as Map<String, Object?>)['hostApp'],
        'premierepro',
      );

      final effects = await send('GET', '/v1/effects', token: token);
      expect(effects['status'], HttpStatus.ok);
      expect(
        (effects['body'] as Map<String, Object?>)['effects'],
        isA<List>(),
      );

      final composition = await send(
        'GET',
        '/v1/composition',
        token: token,
      );
      expect(composition['status'], HttpStatus.ok);
      expect(
        (composition['body'] as Map<String, Object?>)['document'],
        isA<Map>(),
      );

      final imported = await send(
        'POST',
        '/v1/composition',
        token: token,
        body: {
          'document': CompositionProjectCodec.encodeDocument(
            const CompositionDocument(name: 'Adobe exchange', durationMs: 5000),
          ),
        },
      );
      expect(imported['status'], HttpStatus.ok);
      expect(controller.document.name, 'Adobe exchange');

      final disconnected = await send(
        'POST',
        '/v1/disconnect',
        token: token,
      );
      expect(disconnected['status'], HttpStatus.ok);
      expect(bridge.sessions, isEmpty);

      final revoked = await send('GET', '/v1/session', token: token);
      expect(revoked['status'], HttpStatus.unauthorized);
      expect(sessionId, isNotEmpty);
    });
  });
}
