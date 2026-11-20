import '../domain/composition_models.dart';

enum MotionPresetValueMode {
  absolute,
  offset,
  multiplier,
  compositionWidthOffset,
  compositionHeightOffset,
}

class MotionPresetFrame {
  const MotionPresetFrame(this.progress, this.value,
      {this.mode = MotionPresetValueMode.absolute});

  final double progress;
  final double value;
  final MotionPresetValueMode mode;
}

class MotionPresetTrack {
  const MotionPresetTrack(this.property, this.frames);

  final String property;
  final List<MotionPresetFrame> frames;
}

class MotionPresetDefinition {
  const MotionPresetDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    this.durationMs = 750,
    this.interpolation = Interpolation.cubicBezier,
    required this.tracks,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final int durationMs;
  final Interpolation interpolation;
  final List<MotionPresetTrack> tracks;
}

/// Original, editable recipes built from ordinary DepthVibe keyframe tracks.
/// No third-party preset files are bundled or redistributed.
class MotionPresetCatalog {
  MotionPresetCatalog._();

  static const List<MotionPresetDefinition> all = [
    MotionPresetDefinition(
      id: 'fade_in', name: 'Fade In', category: 'Entrance',
      description: 'Fade from transparent to fully visible.',
      tracks: [MotionPresetTrack('opacity', [
        MotionPresetFrame(0, 0), MotionPresetFrame(1, 100),
      ])],
    ),
    MotionPresetDefinition(
      id: 'fade_out', name: 'Fade Out', category: 'Exit',
      description: 'Fade the selected layer away.',
      tracks: [MotionPresetTrack('opacity', [
        MotionPresetFrame(0, 100), MotionPresetFrame(1, 0),
      ])],
    ),
    MotionPresetDefinition(
      id: 'slide_in_left', name: 'Slide In Left', category: 'Entrance',
      description: 'Move in from the left edge.',
      tracks: [MotionPresetTrack('position.x', [
        MotionPresetFrame(0, -1, mode: MotionPresetValueMode.compositionWidthOffset),
        MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset),
      ])],
    ),
    MotionPresetDefinition(
      id: 'slide_in_right', name: 'Slide In Right', category: 'Entrance',
      description: 'Move in from the right edge.',
      tracks: [MotionPresetTrack('position.x', [
        MotionPresetFrame(0, 1, mode: MotionPresetValueMode.compositionWidthOffset),
        MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset),
      ])],
    ),
    MotionPresetDefinition(
      id: 'slide_in_up', name: 'Slide In Up', category: 'Entrance',
      description: 'Move in from below the frame.',
      tracks: [MotionPresetTrack('position.y', [
        MotionPresetFrame(0, 1, mode: MotionPresetValueMode.compositionHeightOffset),
        MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset),
      ])],
    ),
    MotionPresetDefinition(
      id: 'slide_in_down', name: 'Slide In Down', category: 'Entrance',
      description: 'Move in from above the frame.',
      tracks: [MotionPresetTrack('position.y', [
        MotionPresetFrame(0, -1, mode: MotionPresetValueMode.compositionHeightOffset),
        MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset),
      ])],
    ),
    MotionPresetDefinition(
      id: 'slide_out_left', name: 'Slide Out Left', category: 'Exit',
      description: 'Move beyond the left frame edge.',
      tracks: [MotionPresetTrack('position.x', [
        MotionPresetFrame(0, 0, mode: MotionPresetValueMode.offset),
        MotionPresetFrame(1, -1, mode: MotionPresetValueMode.compositionWidthOffset),
      ])],
    ),
    MotionPresetDefinition(
      id: 'slide_out_right', name: 'Slide Out Right', category: 'Exit',
      description: 'Move beyond the right frame edge.',
      tracks: [MotionPresetTrack('position.x', [
        MotionPresetFrame(0, 0, mode: MotionPresetValueMode.offset),
        MotionPresetFrame(1, 1, mode: MotionPresetValueMode.compositionWidthOffset),
      ])],
    ),
    MotionPresetDefinition(
      id: 'slide_out_up', name: 'Slide Out Up', category: 'Exit',
      description: 'Move beyond the top frame edge.',
      tracks: [MotionPresetTrack('position.y', [
        MotionPresetFrame(0, 0, mode: MotionPresetValueMode.offset),
        MotionPresetFrame(1, -1, mode: MotionPresetValueMode.compositionHeightOffset),
      ])],
    ),
    MotionPresetDefinition(
      id: 'slide_out_down', name: 'Slide Out Down', category: 'Exit',
      description: 'Move beyond the bottom frame edge.',
      tracks: [MotionPresetTrack('position.y', [
        MotionPresetFrame(0, 0, mode: MotionPresetValueMode.offset),
        MotionPresetFrame(1, 1, mode: MotionPresetValueMode.compositionHeightOffset),
      ])],
    ),
    MotionPresetDefinition(
      id: 'zoom_in', name: 'Zoom In', category: 'Scale',
      description: 'Scale from 50% to the current size while fading in.',
      tracks: [
        MotionPresetTrack('scale.x', [
          MotionPresetFrame(0, 0.5, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier),
        ]),
        MotionPresetTrack('scale.y', [
          MotionPresetFrame(0, 0.5, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier),
        ]),
        MotionPresetTrack('opacity', [
          MotionPresetFrame(0, 0), MotionPresetFrame(1, 100),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'zoom_out', name: 'Zoom Out', category: 'Scale',
      description: 'Shrink the layer while fading out.',
      tracks: [
        MotionPresetTrack('scale.x', [
          MotionPresetFrame(0, 1, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(1, 0.45, mode: MotionPresetValueMode.multiplier),
        ]),
        MotionPresetTrack('scale.y', [
          MotionPresetFrame(0, 1, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(1, 0.45, mode: MotionPresetValueMode.multiplier),
        ]),
        MotionPresetTrack('opacity', [
          MotionPresetFrame(0, 100), MotionPresetFrame(1, 0),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'pop_bounce', name: 'Pop Bounce', category: 'Scale',
      description: 'Overshoot scale and settle to the original size.',
      tracks: [
        MotionPresetTrack('scale.x', [
          MotionPresetFrame(0, 0.65, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.68, 1.12, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.86, 0.96, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier),
        ]),
        MotionPresetTrack('scale.y', [
          MotionPresetFrame(0, 0.65, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.68, 1.12, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.86, 0.96, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'bounce_in', name: 'Bounce In', category: 'Entrance',
      description: 'Drop into place with a controlled bounce.',
      tracks: [
        MotionPresetTrack('position.y', [
          MotionPresetFrame(0, 0.75, mode: MotionPresetValueMode.compositionHeightOffset),
          MotionPresetFrame(0.68, -0.12, mode: MotionPresetValueMode.compositionHeightOffset),
          MotionPresetFrame(0.86, 0.04, mode: MotionPresetValueMode.compositionHeightOffset),
          MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset),
        ]),
        MotionPresetTrack('opacity', [
          MotionPresetFrame(0, 0), MotionPresetFrame(0.2, 100),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'rotate_in', name: 'Rotate In', category: 'Entrance',
      description: 'Rotate from -90 degrees while fading into view.',
      tracks: [
        MotionPresetTrack('rotation.z', [
          MotionPresetFrame(0, -90, mode: MotionPresetValueMode.offset),
          MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset),
        ]),
        MotionPresetTrack('opacity', [
          MotionPresetFrame(0, 0), MotionPresetFrame(1, 100),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'flip_in', name: 'Flip In', category: 'Entrance',
      description: 'Reveal the layer by scaling its X axis from edge-on.',
      tracks: [
        MotionPresetTrack('scale.x', [
          MotionPresetFrame(0, 0.01, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier),
        ]),
        MotionPresetTrack('opacity', [
          MotionPresetFrame(0, 0), MotionPresetFrame(1, 100),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'shake', name: 'Shake', category: 'Attention',
      description: 'Add a short horizontal impact shake.',
      durationMs: 520,
      interpolation: Interpolation.easeInOut,
      tracks: [MotionPresetTrack('position.x', [
        MotionPresetFrame(0, 0, mode: MotionPresetValueMode.offset),
        MotionPresetFrame(0.2, -0.018, mode: MotionPresetValueMode.compositionWidthOffset),
        MotionPresetFrame(0.42, 0.018, mode: MotionPresetValueMode.compositionWidthOffset),
        MotionPresetFrame(0.64, -0.01, mode: MotionPresetValueMode.compositionWidthOffset),
        MotionPresetFrame(0.82, 0.006, mode: MotionPresetValueMode.compositionWidthOffset),
        MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset),
      ])],
    ),
    MotionPresetDefinition(
      id: 'pulse', name: 'Pulse', category: 'Attention',
      description: 'Briefly scale up and return to normal size.',
      durationMs: 600,
      interpolation: Interpolation.easeInOut,
      tracks: [
        MotionPresetTrack('scale.x', [
          MotionPresetFrame(0, 1, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.5, 1.08, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier),
        ]),
        MotionPresetTrack('scale.y', [
          MotionPresetFrame(0, 1, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.5, 1.08, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'swing', name: 'Swing', category: 'Attention',
      description: 'Rotate side to side and settle at the original angle.',
      durationMs: 900,
      interpolation: Interpolation.easeInOut,
      tracks: [MotionPresetTrack('rotation.z', [
        MotionPresetFrame(0, -18, mode: MotionPresetValueMode.offset),
        MotionPresetFrame(0.35, 14, mode: MotionPresetValueMode.offset),
        MotionPresetFrame(0.68, -7, mode: MotionPresetValueMode.offset),
        MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset),
      ])],
    ),
    MotionPresetDefinition(
      id: 'text_rise', name: 'Text Rise', category: 'Typography',
      description: 'Lift text into place with a soft fade.',
      tracks: [
        MotionPresetTrack('position.y', [
          MotionPresetFrame(0, 0.12, mode: MotionPresetValueMode.compositionHeightOffset),
          MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset),
        ]),
        MotionPresetTrack('opacity', [
          MotionPresetFrame(0, 0), MotionPresetFrame(1, 100),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'elastic_pop', name: 'Elastic Pop', category: 'Scale',
      description: 'Overshoot, compress and settle for playful motion.',
      durationMs: 950,
      tracks: [
        MotionPresetTrack('scale.x', [
          MotionPresetFrame(0, 0.4, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.55, 1.2, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.76, 0.88, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.9, 1.04, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier),
        ]),
        MotionPresetTrack('scale.y', [
          MotionPresetFrame(0, 0.4, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.55, 1.2, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.76, 0.88, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.9, 1.04, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier),
        ]),
      ],
    ),
  ];

  static MotionPresetDefinition? find(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}
