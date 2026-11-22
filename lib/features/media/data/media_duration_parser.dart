/// Parses FFprobe's duration (seconds) without relying on a video surface.
class MediaDurationParser {
  const MediaDurationParser._();

  static Duration? parseSeconds(String? value) {
    final seconds = double.tryParse(value?.trim() ?? '');
    if (seconds == null || !seconds.isFinite || seconds <= 0) return null;

    final milliseconds = (seconds * 1000).round();
    if (milliseconds <= 0) return null;
    return Duration(milliseconds: milliseconds);
  }
}
