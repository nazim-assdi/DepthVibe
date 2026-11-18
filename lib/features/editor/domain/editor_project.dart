enum OutputAspect {
  landscape16x9(1920, 1080, '16:9'),
  portrait9x16(1080, 1920, '9:16'),
  square1x1(1080, 1080, '1:1'),
  portrait4x5(1080, 1350, '4:5');

  const OutputAspect(this.width, this.height, this.label);

  final int width;
  final int height;
  final String label;

  double get ratio => width / height;

  static OutputAspect fromName(String? name) =>
      OutputAspect.values.firstWhere(
        (value) => value.name == name,
        orElse: () => OutputAspect.landscape16x9,
      );
}

enum CanvasFit { fit, fill }

class EditorProject {
  const EditorProject({
    this.name = 'Untitled Project',
    this.videoPath,
    this.sourceDurationMs = 0,
    this.trimInMs = 0,
    this.trimOutMs = 0,
    this.speed = 1,
    this.rotationDegrees = 0,
    this.muted = false,
    this.aspect = OutputAspect.landscape16x9,
    this.canvasFit = CanvasFit.fit,
    this.title = '',
    this.caption = '',
    this.splitMarkersMs = const [],
  });

  final String name;
  final String? videoPath;
  final int sourceDurationMs;
  final int trimInMs;
  final int trimOutMs;
  final double speed;
  final int rotationDegrees;
  final bool muted;
  final OutputAspect aspect;
  final CanvasFit canvasFit;
  final String title;
  final String caption;
  final List<int> splitMarkersMs;

  bool get hasVideo => videoPath != null && videoPath!.isNotEmpty;
  bool get hasValidTrim => trimOutMs > trimInMs;
  int get selectedDurationMs => hasValidTrim ? trimOutMs - trimInMs : 0;
  int get renderedDurationMs =>
      speed > 0 ? (selectedDurationMs / speed).round() : 0;

  EditorProject copyWith({
    String? name,
    String? videoPath,
    bool clearVideoPath = false,
    int? sourceDurationMs,
    int? trimInMs,
    int? trimOutMs,
    double? speed,
    int? rotationDegrees,
    bool? muted,
    OutputAspect? aspect,
    CanvasFit? canvasFit,
    String? title,
    String? caption,
    List<int>? splitMarkersMs,
  }) {
    return EditorProject(
      name: name ?? this.name,
      videoPath: clearVideoPath ? null : (videoPath ?? this.videoPath),
      sourceDurationMs: sourceDurationMs ?? this.sourceDurationMs,
      trimInMs: trimInMs ?? this.trimInMs,
      trimOutMs: trimOutMs ?? this.trimOutMs,
      speed: speed ?? this.speed,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      muted: muted ?? this.muted,
      aspect: aspect ?? this.aspect,
      canvasFit: canvasFit ?? this.canvasFit,
      title: title ?? this.title,
      caption: caption ?? this.caption,
      splitMarkersMs: splitMarkersMs ?? this.splitMarkersMs,
    );
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'videoPath': videoPath,
        'sourceDurationMs': sourceDurationMs,
        'trimInMs': trimInMs,
        'trimOutMs': trimOutMs,
        'speed': speed,
        'rotationDegrees': rotationDegrees,
        'muted': muted,
        'aspect': aspect.name,
        'canvasFit': canvasFit.name,
        'title': title,
        'caption': caption,
        'splitMarkersMs': splitMarkersMs,
      };

  factory EditorProject.fromJson(Map<String, Object?> json) {
    final rawMarkers = json['splitMarkersMs'];
    return EditorProject(
      name: json['name'] as String? ?? 'Untitled Project',
      videoPath: json['videoPath'] as String?,
      sourceDurationMs: (json['sourceDurationMs'] as num?)?.toInt() ?? 0,
      trimInMs: (json['trimInMs'] as num?)?.toInt() ?? 0,
      trimOutMs: (json['trimOutMs'] as num?)?.toInt() ?? 0,
      speed: (json['speed'] as num?)?.toDouble() ?? 1,
      rotationDegrees: (json['rotationDegrees'] as num?)?.toInt() ?? 0,
      muted: json['muted'] as bool? ?? false,
      aspect: OutputAspect.fromName(json['aspect'] as String?),
      canvasFit: CanvasFit.values.firstWhere(
        (value) => value.name == json['canvasFit'],
        orElse: () => CanvasFit.fit,
      ),
      title: json['title'] as String? ?? '',
      caption: json['caption'] as String? ?? '',
      splitMarkersMs: rawMarkers is List
          ? rawMarkers.whereType<num>().map((value) => value.toInt()).toList()
          : const [],
    );
  }
}
