import 'dart:typed_data';

import 'package:depthvibe/features/fonts/data/font_manager_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FontManagerService file validation', () {
    test('accepts TrueType and OpenType font extensions case-insensitively', () {
      expect(FontManagerService.isSupportedFontFilePath('NotoSans.ttf'), isTrue);
      expect(FontManagerService.isSupportedFontFilePath('NotoSans.OTF'), isTrue);
    });

    test('rejects browser font formats and unrelated files', () {
      expect(FontManagerService.isSupportedFontFilePath('font.woff'), isFalse);
      expect(FontManagerService.isSupportedFontFilePath('font.woff2'), isFalse);
      expect(FontManagerService.isSupportedFontFilePath('font.ttc'), isFalse);
      expect(FontManagerService.isSupportedFontFilePath('font.txt'), isFalse);
    });

    test('recognizes standard TrueType and OpenType signatures', () {
      expect(
        FontManagerService.hasValidFontSignature(
          Uint8List.fromList([0, 1, 0, 0, 0, 0]),
        ),
        isTrue,
      );
      expect(
        FontManagerService.hasValidFontSignature(
          Uint8List.fromList('OTTO'.codeUnits),
        ),
        isTrue,
      );
      expect(
        FontManagerService.hasValidFontSignature(
          Uint8List.fromList('true'.codeUnits),
        ),
        isTrue,
      );
    });

    test('rejects truncated and invalid font headers', () {
      expect(FontManagerService.hasValidFontSignature(Uint8List(3)), isFalse);
      expect(
        FontManagerService.hasValidFontSignature(
          Uint8List.fromList('NOPE'.codeUnits),
        ),
        isFalse,
      );
    });
  });
}
