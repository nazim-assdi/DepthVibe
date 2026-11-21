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

    MotionPresetDefinition(
      id: 'fade_slide_up', name: 'Fade + Slide Up', category: 'Entrance',
      description: 'Rise gently into position with a soft opacity ramp.',
      durationMs: 820,
      tracks: [
        MotionPresetTrack('position.y', [
          MotionPresetFrame(0, 0.16, mode: MotionPresetValueMode.compositionHeightOffset),
          MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset),
        ]),
        MotionPresetTrack('opacity', [
          MotionPresetFrame(0, 0), MotionPresetFrame(1, 100),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'fade_slide_down', name: 'Fade + Slide Down', category: 'Entrance',
      description: 'Drop softly into place with a gradual fade.',
      durationMs: 820,
      tracks: [
        MotionPresetTrack('position.y', [
          MotionPresetFrame(0, -0.16, mode: MotionPresetValueMode.compositionHeightOffset),
          MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset),
        ]),
        MotionPresetTrack('opacity', [
          MotionPresetFrame(0, 0), MotionPresetFrame(1, 100),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'drop_in', name: 'Drop In', category: 'Entrance',
      description: 'Fall from above, overshoot slightly and settle.',
      durationMs: 900,
      tracks: [
        MotionPresetTrack('position.y', [
          MotionPresetFrame(0, -0.9, mode: MotionPresetValueMode.compositionHeightOffset),
          MotionPresetFrame(0.72, 0.06, mode: MotionPresetValueMode.compositionHeightOffset),
          MotionPresetFrame(0.88, -0.025, mode: MotionPresetValueMode.compositionHeightOffset),
          MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset),
        ]),
        MotionPresetTrack('opacity', [
          MotionPresetFrame(0, 0), MotionPresetFrame(0.22, 100),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'tilt_in', name: 'Tilt In', category: 'Entrance',
      description: 'Swing from a slight diagonal angle into a clean upright position.',
      durationMs: 760,
      tracks: [
        MotionPresetTrack('rotation.z', [
          MotionPresetFrame(0, -24, mode: MotionPresetValueMode.offset),
          MotionPresetFrame(0.72, 4, mode: MotionPresetValueMode.offset),
          MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset),
        ]),
        MotionPresetTrack('opacity', [
          MotionPresetFrame(0, 0), MotionPresetFrame(1, 100),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'tilt_out', name: 'Tilt Out', category: 'Exit',
      description: 'Tilt away while fading out.',
      durationMs: 680,
      tracks: [
        MotionPresetTrack('rotation.z', [
          MotionPresetFrame(0, 0, mode: MotionPresetValueMode.offset),
          MotionPresetFrame(1, 28, mode: MotionPresetValueMode.offset),
        ]),
        MotionPresetTrack('opacity', [
          MotionPresetFrame(0, 100), MotionPresetFrame(1, 0),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'flip_y_in', name: 'Vertical Flip In', category: 'Entrance',
      description: 'Reveal the layer from a compressed vertical edge.',
      durationMs: 700,
      tracks: [
        MotionPresetTrack('scale.y', [
          MotionPresetFrame(0, 0.02, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.82, 1.08, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier),
        ]),
        MotionPresetTrack('opacity', [
          MotionPresetFrame(0, 0), MotionPresetFrame(1, 100),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'zoom_bounce', name: 'Zoom Bounce', category: 'Scale',
      description: 'Zoom in with a playful overshoot and elastic settle.',
      durationMs: 960,
      tracks: [
        MotionPresetTrack('scale.x', [
          MotionPresetFrame(0, 0.25, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.62, 1.16, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.82, 0.94, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier),
        ]),
        MotionPresetTrack('scale.y', [
          MotionPresetFrame(0, 0.25, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.62, 1.16, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.82, 0.94, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier),
        ]),
        MotionPresetTrack('opacity', [
          MotionPresetFrame(0, 0), MotionPresetFrame(0.25, 100),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'overshoot_left', name: 'Overshoot Slide Left', category: 'Entrance',
      description: 'Slide in from the right, pass the mark and settle.',
      durationMs: 850,
      tracks: [
        MotionPresetTrack('position.x', [
          MotionPresetFrame(0, 1, mode: MotionPresetValueMode.compositionWidthOffset),
          MotionPresetFrame(0.72, -0.05, mode: MotionPresetValueMode.compositionWidthOffset),
          MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'overshoot_right', name: 'Overshoot Slide Right', category: 'Entrance',
      description: 'Slide in from the left, pass the mark and settle.',
      durationMs: 850,
      tracks: [
        MotionPresetTrack('position.x', [
          MotionPresetFrame(0, -1, mode: MotionPresetValueMode.compositionWidthOffset),
          MotionPresetFrame(0.72, 0.05, mode: MotionPresetValueMode.compositionWidthOffset),
          MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'wobble', name: 'Wobble', category: 'Attention',
      description: 'Rock side to side with diminishing rotation.',
      durationMs: 1000,
      interpolation: Interpolation.easeInOut,
      tracks: [
        MotionPresetTrack('rotation.z', [
          MotionPresetFrame(0, 0, mode: MotionPresetValueMode.offset),
          MotionPresetFrame(0.18, -12, mode: MotionPresetValueMode.offset),
          MotionPresetFrame(0.36, 10, mode: MotionPresetValueMode.offset),
          MotionPresetFrame(0.55, -7, mode: MotionPresetValueMode.offset),
          MotionPresetFrame(0.76, 4, mode: MotionPresetValueMode.offset),
          MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'heartbeat', name: 'Heartbeat', category: 'Attention',
      description: 'Two quick scale pulses with a smooth return to normal.',
      durationMs: 880,
      interpolation: Interpolation.easeInOut,
      tracks: [
        MotionPresetTrack('scale.x', [
          MotionPresetFrame(0, 1, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.22, 1.1, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.38, 1, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.54, 1.12, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier),
        ]),
        MotionPresetTrack('scale.y', [
          MotionPresetFrame(0, 1, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.22, 1.1, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.38, 1, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.54, 1.12, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'float', name: 'Float', category: 'Attention',
      description: 'Drift upward and gently return to the original position.',
      durationMs: 1400,
      interpolation: Interpolation.easeInOut,
      tracks: [
        MotionPresetTrack('position.y', [
          MotionPresetFrame(0, 0, mode: MotionPresetValueMode.offset),
          MotionPresetFrame(0.5, -0.035, mode: MotionPresetValueMode.compositionHeightOffset),
          MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset),
        ]),
      ],
    ),
    MotionPresetDefinition(
      id: 'jelly', name: 'Jelly', category: 'Attention',
      description: 'Combine alternating horizontal and vertical squash-stretch.',
      durationMs: 900,
      tracks: [
        MotionPresetTrack('scale.x', [
          MotionPresetFrame(0, 1, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.28, 1.18, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.55, 0.92, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.78, 1.04, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier),
        ]),
        MotionPresetTrack('scale.y', [
          MotionPresetFrame(0, 1, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.28, 0.86, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.55, 1.08, mode: MotionPresetValueMode.multiplier),
          MotionPresetFrame(0.78, 0.97, mode: MotionPresetValueMode.multiplier),
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
