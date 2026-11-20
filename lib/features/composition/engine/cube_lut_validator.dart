class CubeLutInfo {
  const CubeLutInfo({
    required this.title,
    required this.size,
    required this.entryCount,
  });

  final String title;
  final int size;
  final int entryCount;
}

/// Validates common Iridas/Resolve .cube 3D LUT files before import.
class CubeLutValidator {
  const CubeLutValidator._();

  static CubeLutInfo parse(String contents) {
    var title = 'Untitled LUT';
    int? size;
    var dataRows = 0;
    var sawDomainMin = false;
    var sawDomainMax = false;

    for (final rawLine in contents.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('TITLE ')) {
        title = line.substring(6).trim().replaceAll('"', '');
        continue;
      }
      if (line.startsWith('LUT_1D_SIZE')) {
        throw const FormatException(
          '1D .cube LUTs are not supported. Import a 3D LUT instead.',
        );
      }
      if (line.startsWith('LUT_3D_SIZE')) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length != 2 || size != null) {
          throw const FormatException('Invalid or duplicate LUT_3D_SIZE.');
        }
        size = int.tryParse(parts[1]);
        if (size == null || size < 2 || size > 65) {
          throw const FormatException('3D LUT size must be between 2 and 65.');
        }
        continue;
      }
      if (line.startsWith('DOMAIN_MIN')) {
        if (sawDomainMin || !_isDomainLine(line)) {
          throw const FormatException('Invalid DOMAIN_MIN declaration.');
        }
        sawDomainMin = true;
        continue;
      }
      if (line.startsWith('DOMAIN_MAX')) {
        if (sawDomainMax || !_isDomainLine(line)) {
          throw const FormatException('Invalid DOMAIN_MAX declaration.');
        }
        sawDomainMax = true;
        continue;
      }

      final parts = line.split(RegExp(r'\s+'));
      if (parts.length != 3) {
        throw FormatException('Invalid LUT data row: $line');
      }
      final values = parts.map(double.tryParse).toList();
      if (values.any((value) => value == null || !value.isFinite)) {
        throw FormatException('Non-numeric LUT data row: $line');
      }
      dataRows++;
    }

    if (size == null) {
      throw const FormatException('Missing LUT_3D_SIZE declaration.');
    }
    final expected = size * size * size;
    if (dataRows != expected) {
      throw FormatException(
        'LUT has $dataRows entries; $expected are required for size $size.',
      );
    }
    return CubeLutInfo(title: title, size: size, entryCount: dataRows);
  }

  static bool _isDomainLine(String line) {
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length != 4) return false;
    final values = parts.skip(1).map(double.tryParse).toList();
    return values.every((value) => value != null && value.isFinite);
  }
}
