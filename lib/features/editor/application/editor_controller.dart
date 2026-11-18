import 'package:flutter/foundation.dart';

import '../domain/editor_project.dart';

class EditorController extends ChangeNotifier {
  EditorProject _project = const EditorProject();
  int _playheadMs = 0;

  EditorProject get project => _project;
  int get playheadMs => _playheadMs;

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
      trimInMs: _project.trimInMs.clamp(0, totalMs - 1).toInt(),
      trimOutMs: totalMs,
    ));
  }

  void setPlayhead(Duration position) {
    final total = _project.sourceDurationMs;
    _playheadMs = total > 0
        ? position.inMilliseconds.clamp(0, total).toInt()
        : position.inMilliseconds.clamp(0, 1 << 30).toInt();
    notifyListeners();
  }

  void setTrimIn(double value) {
    final total = _project.sourceDurationMs;
    if (total <= 1) return;
    final next = value.round().clamp(0, total - 1).toInt();
    final end = _project.trimOutMs > next
        ? _project.trimOutMs
        : (next + 1).clamp(1, total).toInt();
    _update(_project.copyWith(trimInMs: next, trimOutMs: end));
  }

  void setTrimOut(double value) {
    final total = _project.sourceDurationMs;
    if (total <= 1) return;
    final next = value.round().clamp(1, total).toInt();
    final start = _project.trimInMs < next
        ? _project.trimInMs
        : (next - 1).clamp(0, total - 1).toInt();
    _update(_project.copyWith(trimInMs: start, trimOutMs: next));
  }

  void setSpeed(double value) {
    if (value < 0.25 || value > 2.0) {
      throw RangeError.range(value, 0.25, 2.0, 'speed');
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
