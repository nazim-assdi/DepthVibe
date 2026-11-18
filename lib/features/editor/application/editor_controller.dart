import 'package:flutter/foundation.dart';

import '../domain/editor_project.dart';

class EditorController extends ChangeNotifier {
  EditorProject _project = const EditorProject();
  int _playheadMs = 0;

  EditorProject get project => _project;
  int get playheadMs => _playheadMs;

  int _clampInt(int value, int lower, int upper) {
    if (value < lower) return lower;
    if (value > upper) return upper;
    return value;
  }

  void _update(EditorProject next) {
    _project = next;
    notifyListeners();
  }

  void loadVideo(String path) {
    _playheadMs = 0;
    _update(_project.copyWith(
      videoPath: path,
      sourceDurationMs: 0,
      trimInMs: 0,
      trimOutMs: 0,
      splitMarkersMs: const [],
    ));
  }

  void setSourceDuration(Duration duration) {
    final totalMs = duration.inMilliseconds;
    if (totalMs <= 0) return;
    _update(_project.copyWith(
      sourceDurationMs: totalMs,
      trimInMs: _clampInt(_project.trimInMs, 0, totalMs - 1),
      trimOutMs: totalMs,
    ));
  }

  void setPlayhead(Duration position) {
    final total = _project.sourceDurationMs;
    _playheadMs = total > 0
        ? _clampInt(position.inMilliseconds, 0, total)
        : _clampInt(position.inMilliseconds, 0, 1 << 30);
    notifyListeners();
  }

  void setTrimIn(double value) {
    final total = _project.sourceDurationMs;
    if (total <= 1) return;
    final next = _clampInt(value.round(), 0, total - 1);
    final end = _project.trimOutMs > next
        ? _project.trimOutMs
        : _clampInt(next + 1, 1, total);
    _update(_project.copyWith(trimInMs: next, trimOutMs: end));
  }

  void setTrimOut(double value) {
    final total = _project.sourceDurationMs;
    if (total <= 1) return;
    final next = _clampInt(value.round(), 1, total);
    final start = _project.trimInMs < next
        ? _project.trimInMs
        : _clampInt(next - 1, 0, total - 1);
    _update(_project.copyWith(trimInMs: start, trimOutMs: next));
  }

  void setSpeed(double value) {
    if (value < 0.25 || value > 2.0) {
      throw RangeError.value(
        value,
        'speed',
        'Playback speed must be between 0.25x and 2.0x.',
      );
    }
    _update(_project.copyWith(speed: value));
  }

  void rotateClockwise() {
    _update(_project.copyWith(
      rotationDegrees: (_project.rotationDegrees + 90) % 360,
    ));
  }

  void setMuted(bool value) => _update(_project.copyWith(muted: value));

  void setAspect(OutputAspect value) =>
      _update(_project.copyWith(aspect: value));

  void setCanvasFit(CanvasFit value) =>
      _update(_project.copyWith(canvasFit: value));

  void setTitle(String value) => _update(_project.copyWith(title: value));

  void setCaption(String value) => _update(_project.copyWith(caption: value));

  void addSplitMarker() {
    if (!_project.hasVideo || _playheadMs <= 0) return;
    final markers = {..._project.splitMarkersMs, _playheadMs}.toList()..sort();
    _update(_project.copyWith(splitMarkersMs: markers));
  }

  void removeSplitMarker(int markerMs) {
    final markers = _project.splitMarkersMs
        .where((value) => value != markerMs)
        .toList(growable: false);
    _update(_project.copyWith(splitMarkersMs: markers));
  }
}
