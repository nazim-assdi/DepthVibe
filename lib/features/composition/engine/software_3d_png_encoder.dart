import 'dart:io';
import 'dart:typed_data';

/// Small dependency-free RGBA PNG encoder for transparent CPU 3D export plates.
class Software3dPngEncoder {
  const Software3dPngEncoder();

  Uint8List encodeRgba({
    required int width,
    required int height,
    required Uint8List rgba,
    int compressionLevel = 6,
  }) {
    if (width <= 0 || height <= 0 || rgba.length != width * height * 4) {
      throw ArgumentError('RGBA buffer must match the requested image dimensions.');
    }
    final stride = width * 4;
    final scanlines = Uint8List((stride + 1) * height);
    for (var y = 0; y < height; y++) {
      final target = y * (stride + 1);
      scanlines[target] = 0; // PNG filter: None.
      scanlines.setRange(
        target + 1,
        target + stride + 1,
        rgba,
        y * stride,
      );
    }

    final compressed = ZLibEncoder(level: compressionLevel.clamp(0, 9).toInt())
        .convert(scanlines);
    final output = BytesBuilder(copy: false)
      ..add(const [137, 80, 78, 71, 13, 10, 26, 10])
      ..add(_chunk('IHDR', _header(width, height)))
      ..add(_chunk('IDAT', Uint8List.fromList(compressed)))
      ..add(_chunk('IEND', Uint8List(0)));
    return output.takeBytes();
  }

  Uint8List _header(int width, int height) {
    final header = ByteData(13)
      ..setUint32(0, width, Endian.big)
      ..setUint32(4, height, Endian.big)
      ..setUint8(8, 8) // bit depth
      ..setUint8(9, 6) // RGBA
      ..setUint8(10, 0)
      ..setUint8(11, 0)
      ..setUint8(12, 0);
    return header.buffer.asUint8List();
  }

  Uint8List _chunk(String type, Uint8List data) {
    final typeBytes = type.codeUnits;
    final header = ByteData(4)..setUint32(0, data.length, Endian.big);
    final crcData = Uint8List(4 + data.length)
      ..setRange(0, 4, typeBytes)
      ..setRange(4, 4 + data.length, data);
    final crc = _crc32(crcData);
    final checksum = ByteData(4)..setUint32(0, crc, Endian.big);
    return Uint8List(12 + data.length)
      ..setRange(0, 4, header.buffer.asUint8List())
      ..setRange(4, 8, typeBytes)
      ..setRange(8, 8 + data.length, data)
      ..setRange(8 + data.length, 12 + data.length, checksum.buffer.asUint8List());
  }

  int _crc32(Uint8List bytes) {
    var crc = 0xFFFFFFFF;
    for (final value in bytes) {
      crc ^= value;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
