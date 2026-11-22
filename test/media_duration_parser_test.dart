import 'package:depthvibe/features/media/data/media_duration_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaDurationParser', () {
    test('parses integer and fractional seconds', () {
      expect(
        MediaDurationParser.parseSeconds('90'),
        const Duration(seconds: 90),
      );
      expect(
        MediaDurationParser.parseSeconds('12.3456'),
        const Duration(milliseconds: 12346),
      );
    });

    test('rejects missing, invalid and non-finite durations', () {
      expect(MediaDurationParser.parseSeconds(null), isNull);
      expect(MediaDurationParser.parseSeconds(''), isNull);
      expect(MediaDurationParser.parseSeconds('unknown'), isNull);
      expect(MediaDurationParser.parseSeconds('NaN'), isNull);
      expect(MediaDurationParser.parseSeconds('Infinity'), isNull);
      expect(MediaDurationParser.parseSeconds('0'), isNull);
      expect(MediaDurationParser.parseSeconds('-1'), isNull);
    });

    test('rejects values that round down to zero milliseconds', () {
      expect(MediaDurationParser.parseSeconds('0.0001'), isNull);
    });
  });
}
