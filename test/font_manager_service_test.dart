import 'dart:typed_data';

import 'package:depthvibe/features/fonts/data/font_manager_service.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _fontFixture({
  required String family,
  required String style,
}) {
  Uint8List utf16(String value) {
    final result = Uint8List(value.length * 2);
    final data = ByteData.sublistView(result);
    for (var index = 0; index < value.length; index++) {
      data.setUint16(index * 2, value.codeUnitAt(index), Endian.big);
    }
    return result;
  }

  final familyBytes = utf16(family);
  final styleBytes = utf16(style);
  const nameTableOffset = 28;
  const stringsOffset = 30;
  final nameTableLength =
      stringsOffset + familyBytes.length + styleBytes.length;
  final bytes = Uint8List(nameTableOffset + nameTableLength);
  final data = ByteData.sublistView(bytes);

  bytes.setRange(0, 4, [0, 1, 0, 0]);
  data.setUint16(4, 1, Endian.big);
  bytes.setRange(12, 16, 'name'.codeUnits);
  data.setUint32(20, nameTableOffset, Endian.big);
  data.setUint32(24, nameTableLength, Endian.big);

  data.setUint16(nameTableOffset, 0, Endian.big);
  data.setUint16(nameTableOffset + 2, 2, Endian.big);
  data.setUint16(nameTableOffset + 4, stringsOffset, Endian.big);

  final firstRecord = nameTableOffset + 6;
  data.setUint16(firstRecord, 3, Endian.big);
  data.setUint16(firstRecord + 2, 1, Endian.big);
  data.setUint16(firstRecord + 4, 0x0409, Endian.big);
  data.setUint16(firstRecord + 6, 1, Endian.big);
  data.setUint16(firstRecord + 8, familyBytes.length, Endian.big);
  data.setUint16(firstRecord + 10, 0, Endian.big);

  final secondRecord = firstRecord + 12;
  data.setUint16(secondRecord, 3, Endian.big);
  data.setUint16(secondRecord + 2, 1, Endian.big);
  data.setUint16(secondRecord + 4, 0x0409, Endian.big);
  data.setUint16(secondRecord + 6, 2, Endian.big);
  data.setUint16(secondRecord + 8, styleBytes.length, Endian.big);
  data.setUint16(secondRecord + 10, familyBytes.length, Endian.big);

  final stringsStart = nameTableOffset + stringsOffset;
  bytes.setRange(
    stringsStart,
    stringsStart + familyBytes.length,
    familyBytes,
  );
  bytes.setRange(
    stringsStart + familyBytes.length,
    stringsStart + familyBytes.length + styleBytes.length,
    styleBytes,
  );
  return bytes;
}


Uint8List _ttcFixture(List<Uint8List> faces) {
  final headerLength = 12 + faces.length * 4;
  final totalLength = headerLength + faces.fold<int>(
    0,
    (sum, face) => sum + face.length,
  );
  final bytes = Uint8List(totalLength);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'ttcf'.codeUnits);
  data.setUint32(4, 0x00010000, Endian.big);
  data.setUint32(8, faces.length, Endian.big);

  var offset = headerLength;
  for (var index = 0; index < faces.length; index++) {
    final face = faces[index];
    data.setUint32(12 + index * 4, offset, Endian.big);
    bytes.setRange(offset, offset + face.length, face);

    // The fixture's name-table record is at face offset + 12; TTC table
    // offsets are absolute from the beginning of the collection.
    data.setUint32(offset + 20, offset + 28, Endian.big);
    offset += face.length;
  }
  return bytes;
}

void main() {
  group('FontManagerService file validation', () {
    test('accepts TrueType, OpenType and collection extensions', () {
      expect(FontManagerService.isSupportedFontFilePath('NotoSans.ttf'), isTrue);
      expect(FontManagerService.isSupportedFontFilePath('NotoSans.OTF'), isTrue);
      expect(FontManagerService.isSupportedFontFilePath('Fonts.ttc'), isTrue);
    });

    test('rejects browser font formats and unrelated files', () {
      expect(FontManagerService.isSupportedFontFilePath('font.woff'), isFalse);
      expect(FontManagerService.isSupportedFontFilePath('font.woff2'), isFalse);
      expect(FontManagerService.isSupportedFontFilePath('font.txt'), isFalse);
    });

    test('recognizes standard TrueType, OpenType and collection signatures', () {
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
      expect(
        FontManagerService.hasValidFontSignature(
          Uint8List.fromList('ttcf'.codeUnits),
        ),
        isTrue,
      );
    });

    test('reads the real typographic family and subfamily from the name table', () {
      final bytes = _fontFixture(
        family: 'Depth Sans',
        style: 'SemiBold',
      );
      final face = FontManagerService.readFontFaceMetadata(bytes);

      expect(face, isNotNull);
      expect(face!.family, 'Depth Sans');
      expect(face.style, 'SemiBold');
      expect(face.fullName, 'Depth Sans SemiBold');
      expect(face.displayName, 'Depth Sans · SemiBold');
    });

    test('reads every face from an installed TrueType collection', () {
      final collection = _ttcFixture([
        _fontFixture(family: 'Depth Sans', style: 'Regular'),
        _fontFixture(family: 'Depth Sans', style: 'Bold'),
      ]);

      final faces = FontManagerService.readFontFaces(collection);
      final secondFace = FontManagerService.readFontFaceMetadata(
        collection,
        faceIndex: 1,
      );

      expect(faces, hasLength(2));
      expect(faces.map((face) => face.style), ['Regular', 'Bold']);
      expect(secondFace?.family, 'Depth Sans');
      expect(secondFace?.style, 'Bold');
    });

    test('rejects truncated and invalid font headers', () {
      expect(FontManagerService.hasValidFontSignature(Uint8List(3)), isFalse);
      expect(
        FontManagerService.readFontFaceMetadata(Uint8List(100)),
        isNull,
      );
      expect(
        FontManagerService.hasValidFontSignature(
          Uint8List.fromList('NOPE'.codeUnits),
        ),
        isFalse,
      );
    });
  });
}
