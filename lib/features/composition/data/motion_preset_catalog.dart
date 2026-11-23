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
    MotionPresetDefinition(
      id: 'cinematic_push_in', name: 'Cinematic Push In', category: 'Cinematic',
      description: 'A restrained camera push with a soft settle.',
      durationMs: 1100,
      tracks: [
        MotionPresetTrack('scale.x', [MotionPresetFrame(0, 0.92, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(0.78, 1.035, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier)]),
        MotionPresetTrack('scale.y', [MotionPresetFrame(0, 0.92, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(0.78, 1.035, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'cinematic_pull_out', name: 'Cinematic Pull Out', category: 'Cinematic',
      description: 'Ease away from the subject with a subtle opacity finish.',
      durationMs: 1050,
      tracks: [
        MotionPresetTrack('scale.x', [MotionPresetFrame(0, 1.12, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier)]),
        MotionPresetTrack('scale.y', [MotionPresetFrame(0, 1.12, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'spin_pop_in', name: 'Spin Pop In', category: 'Entrance',
      description: 'Rotate and scale into place with a clean landing.',
      durationMs: 850,
      tracks: [
        MotionPresetTrack('rotation.z', [MotionPresetFrame(0, -150, mode: MotionPresetValueMode.offset), MotionPresetFrame(0.78, 7, mode: MotionPresetValueMode.offset), MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset)]),
        MotionPresetTrack('scale.x', [MotionPresetFrame(0, 0.35, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(0.72, 1.08, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier)]),
        MotionPresetTrack('scale.y', [MotionPresetFrame(0, 0.35, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(0.72, 1.08, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier)]),
        MotionPresetTrack('opacity', [MotionPresetFrame(0, 0), MotionPresetFrame(0.24, 100)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'spin_reveal', name: 'Spin Reveal', category: 'Entrance',
      description: 'A fast half-turn that resolves into the final angle.',
      durationMs: 760,
      tracks: [
        MotionPresetTrack('rotation.z', [MotionPresetFrame(0, 180, mode: MotionPresetValueMode.offset), MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset)]),
        MotionPresetTrack('opacity', [MotionPresetFrame(0, 0), MotionPresetFrame(0.35, 100)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'headline_drop', name: 'Headline Drop', category: 'Typography',
      description: 'Drop a title from above with a controlled overshoot.',
      durationMs: 820,
      tracks: [
        MotionPresetTrack('position.y', [MotionPresetFrame(0, -0.34, mode: MotionPresetValueMode.compositionHeightOffset), MotionPresetFrame(0.72, 0.035, mode: MotionPresetValueMode.compositionHeightOffset), MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset)]),
        MotionPresetTrack('opacity', [MotionPresetFrame(0, 0), MotionPresetFrame(0.22, 100)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'lower_third_rise', name: 'Lower Third Rise', category: 'Typography',
      description: 'A clean broadcast lower-third entrance from below.',
      durationMs: 720,
      tracks: [
        MotionPresetTrack('position.y', [MotionPresetFrame(0, 0.12, mode: MotionPresetValueMode.compositionHeightOffset), MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset)]),
        MotionPresetTrack('position.x', [MotionPresetFrame(0, -0.025, mode: MotionPresetValueMode.compositionWidthOffset), MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset)]),
        MotionPresetTrack('opacity', [MotionPresetFrame(0, 0), MotionPresetFrame(1, 100)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'lower_third_exit', name: 'Lower Third Exit', category: 'Exit',
      description: 'Slide a broadcast caption away while fading.',
      durationMs: 560,
      tracks: [
        MotionPresetTrack('position.x', [MotionPresetFrame(0, 0, mode: MotionPresetValueMode.offset), MotionPresetFrame(1, -0.11, mode: MotionPresetValueMode.compositionWidthOffset)]),
        MotionPresetTrack('opacity', [MotionPresetFrame(0, 100), MotionPresetFrame(1, 0)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'spring_left_in', name: 'Spring from Left', category: 'Entrance',
      description: 'Spring in from the left edge and settle naturally.',
      durationMs: 900,
      tracks: [
        MotionPresetTrack('position.x', [MotionPresetFrame(0, -1, mode: MotionPresetValueMode.compositionWidthOffset), MotionPresetFrame(0.7, 0.06, mode: MotionPresetValueMode.compositionWidthOffset), MotionPresetFrame(0.86, -0.025, mode: MotionPresetValueMode.compositionWidthOffset), MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'spring_right_in', name: 'Spring from Right', category: 'Entrance',
      description: 'Spring in from the right edge and settle naturally.',
      durationMs: 900,
      tracks: [
        MotionPresetTrack('position.x', [MotionPresetFrame(0, 1, mode: MotionPresetValueMode.compositionWidthOffset), MotionPresetFrame(0.7, -0.06, mode: MotionPresetValueMode.compositionWidthOffset), MotionPresetFrame(0.86, 0.025, mode: MotionPresetValueMode.compositionWidthOffset), MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'elastic_up', name: 'Elastic Rise', category: 'Entrance',
      description: 'Rise vertically with a soft elastic landing.',
      durationMs: 880,
      tracks: [
        MotionPresetTrack('position.y', [MotionPresetFrame(0, 0.42, mode: MotionPresetValueMode.compositionHeightOffset), MotionPresetFrame(0.7, -0.045, mode: MotionPresetValueMode.compositionHeightOffset), MotionPresetFrame(0.88, 0.018, mode: MotionPresetValueMode.compositionHeightOffset), MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset)]),
        MotionPresetTrack('opacity', [MotionPresetFrame(0, 0), MotionPresetFrame(0.25, 100)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'elastic_down', name: 'Elastic Drop', category: 'Entrance',
      description: 'Drop vertically with a soft elastic landing.',
      durationMs: 880,
      tracks: [
        MotionPresetTrack('position.y', [MotionPresetFrame(0, -0.42, mode: MotionPresetValueMode.compositionHeightOffset), MotionPresetFrame(0.7, 0.045, mode: MotionPresetValueMode.compositionHeightOffset), MotionPresetFrame(0.88, -0.018, mode: MotionPresetValueMode.compositionHeightOffset), MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset)]),
        MotionPresetTrack('opacity', [MotionPresetFrame(0, 0), MotionPresetFrame(0.25, 100)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'squash_stomp', name: 'Squash Stomp', category: 'Attention',
      description: 'Compress on impact, stretch upward, then return to normal.',
      durationMs: 720,
      tracks: [
        MotionPresetTrack('scale.x', [MotionPresetFrame(0, 1, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(0.25, 1.2, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(0.52, 0.94, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(0.76, 1.035, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier)]),
        MotionPresetTrack('scale.y', [MotionPresetFrame(0, 1, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(0.25, 0.78, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(0.52, 1.08, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(0.76, 0.98, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'pulse_soft', name: 'Soft Pulse', category: 'Attention',
      description: 'A subtle breathing pulse for selected titles or objects.',
      durationMs: 1200,
      interpolation: Interpolation.easeInOut,
      tracks: [
        MotionPresetTrack('scale.x', [MotionPresetFrame(0, 1, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(0.5, 1.045, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier)]),
        MotionPresetTrack('scale.y', [MotionPresetFrame(0, 1, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(0.5, 1.045, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'pendulum_swing', name: 'Pendulum Swing', category: 'Attention',
      description: 'A weighted side-to-side swing with a controlled stop.',
      durationMs: 1200,
      interpolation: Interpolation.easeInOut,
      tracks: [
        MotionPresetTrack('rotation.z', [MotionPresetFrame(0, -26, mode: MotionPresetValueMode.offset), MotionPresetFrame(0.32, 19, mode: MotionPresetValueMode.offset), MotionPresetFrame(0.62, -11, mode: MotionPresetValueMode.offset), MotionPresetFrame(0.82, 5, mode: MotionPresetValueMode.offset), MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'hover_drift', name: 'Hover Drift', category: 'Attention',
      description: 'Float gently upward and return without changing scale.',
      durationMs: 1500,
      interpolation: Interpolation.easeInOut,
      tracks: [
        MotionPresetTrack('position.y', [MotionPresetFrame(0, 0, mode: MotionPresetValueMode.offset), MotionPresetFrame(0.5, -0.045, mode: MotionPresetValueMode.compositionHeightOffset), MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'slide_zoom_left', name: 'Slide + Zoom Left', category: 'Entrance',
      description: 'Combine lateral movement and a gentle camera zoom.',
      durationMs: 900,
      tracks: [
        MotionPresetTrack('position.x', [MotionPresetFrame(0, 0.22, mode: MotionPresetValueMode.compositionWidthOffset), MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset)]),
        MotionPresetTrack('scale.x', [MotionPresetFrame(0, 0.86, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier)]),
        MotionPresetTrack('scale.y', [MotionPresetFrame(0, 0.86, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier)]),
        MotionPresetTrack('opacity', [MotionPresetFrame(0, 0), MotionPresetFrame(1, 100)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'slide_zoom_right', name: 'Slide + Zoom Right', category: 'Entrance',
      description: 'Combine opposite lateral movement and a gentle camera zoom.',
      durationMs: 900,
      tracks: [
        MotionPresetTrack('position.x', [MotionPresetFrame(0, -0.22, mode: MotionPresetValueMode.compositionWidthOffset), MotionPresetFrame(1, 0, mode: MotionPresetValueMode.offset)]),
        MotionPresetTrack('scale.x', [MotionPresetFrame(0, 0.86, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier)]),
        MotionPresetTrack('scale.y', [MotionPresetFrame(0, 0.86, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier)]),
        MotionPresetTrack('opacity', [MotionPresetFrame(0, 0), MotionPresetFrame(1, 100)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'rotate_out', name: 'Rotate Away', category: 'Exit',
      description: 'Rotate out of frame while fading to zero opacity.',
      durationMs: 620,
      tracks: [
        MotionPresetTrack('rotation.z', [MotionPresetFrame(0, 0, mode: MotionPresetValueMode.offset), MotionPresetFrame(1, 32, mode: MotionPresetValueMode.offset)]),
        MotionPresetTrack('scale.x', [MotionPresetFrame(0, 1, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 0.82, mode: MotionPresetValueMode.multiplier)]),
        MotionPresetTrack('scale.y', [MotionPresetFrame(0, 1, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 0.82, mode: MotionPresetValueMode.multiplier)]),
        MotionPresetTrack('opacity', [MotionPresetFrame(0, 100), MotionPresetFrame(1, 0)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'shrink_out', name: 'Shrink Out', category: 'Exit',
      description: 'Contract smoothly toward the anchor point and fade away.',
      durationMs: 560,
      tracks: [
        MotionPresetTrack('scale.x', [MotionPresetFrame(0, 1, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 0.2, mode: MotionPresetValueMode.multiplier)]),
        MotionPresetTrack('scale.y', [MotionPresetFrame(0, 1, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 0.2, mode: MotionPresetValueMode.multiplier)]),
        MotionPresetTrack('opacity', [MotionPresetFrame(0, 100), MotionPresetFrame(1, 0)]),
      ],
    ),
    MotionPresetDefinition(
      id: 'snap_zoom', name: 'Snap Zoom', category: 'Attention',
      description: 'Quick push-in with a sharp overshoot and a tight settle.',
      durationMs: 520,
      tracks: [
        MotionPresetTrack('scale.x', [MotionPresetFrame(0, 0.82, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(0.58, 1.14, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier)]),
        MotionPresetTrack('scale.y', [MotionPresetFrame(0, 0.82, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(0.58, 1.14, mode: MotionPresetValueMode.multiplier), MotionPresetFrame(1, 1, mode: MotionPresetValueMode.multiplier)]),
      ],
    ),

    MotionPresetDefinition(id:'tilt_3d_in',name:'3D Tilt In',category:'3D Motion',description:'Tilt forward and settle.',durationMs:860,tracks:[MotionPresetTrack('rotation.x',[MotionPresetFrame(0,52,mode:MotionPresetValueMode.offset),MotionPresetFrame(0.76,-5,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,0,mode:MotionPresetValueMode.offset)]),MotionPresetTrack('opacity',[MotionPresetFrame(0,0),MotionPresetFrame(1,100)])]),
    MotionPresetDefinition(id:'flip_3d_x_in',name:'3D Flip X In',category:'3D Motion',description:'Flip around X with an opacity reveal.',durationMs:820,tracks:[MotionPresetTrack('rotation.x',[MotionPresetFrame(0,-88,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,0,mode:MotionPresetValueMode.offset)]),MotionPresetTrack('opacity',[MotionPresetFrame(0,0),MotionPresetFrame(1,100)])]),
    MotionPresetDefinition(id:'flip_3d_y_in',name:'3D Flip Y In',category:'3D Motion',description:'Flip around Y and settle.',durationMs:820,tracks:[MotionPresetTrack('rotation.y',[MotionPresetFrame(0,88,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,0,mode:MotionPresetValueMode.offset)]),MotionPresetTrack('opacity',[MotionPresetFrame(0,0),MotionPresetFrame(1,100)])]),
    MotionPresetDefinition(id:'depth_push_in',name:'Depth Push In',category:'3D Motion',description:'Move forward through Z space and settle.',durationMs:900,tracks:[MotionPresetTrack('position.z',[MotionPresetFrame(0,520,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,0,mode:MotionPresetValueMode.offset)])]),
    MotionPresetDefinition(id:'depth_pull_out',name:'Depth Pull Out',category:'3D Motion',description:'Pull back into depth while fading.',durationMs:900,tracks:[MotionPresetTrack('position.z',[MotionPresetFrame(0,0,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,-480,mode:MotionPresetValueMode.offset)]),MotionPresetTrack('opacity',[MotionPresetFrame(0,100),MotionPresetFrame(1,0)])]),
    MotionPresetDefinition(id:'camera_pan_left',name:'Camera Pan Left',category:'Cinematic Motion',description:'Drift horizontally across the frame.',durationMs:1400,tracks:[MotionPresetTrack('position.x',[MotionPresetFrame(0,0,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,-0.12,mode:MotionPresetValueMode.compositionWidthOffset)])]),
    MotionPresetDefinition(id:'camera_pan_right',name:'Camera Pan Right',category:'Cinematic Motion',description:'Drift horizontally to the right.',durationMs:1400,tracks:[MotionPresetTrack('position.x',[MotionPresetFrame(0,0,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,0.12,mode:MotionPresetValueMode.compositionWidthOffset)])]),
    MotionPresetDefinition(id:'camera_pan_up',name:'Camera Pan Up',category:'Cinematic Motion',description:'Create a slow upward drift.',durationMs:1400,tracks:[MotionPresetTrack('position.y',[MotionPresetFrame(0,0,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,-0.1,mode:MotionPresetValueMode.compositionHeightOffset)])]),
    MotionPresetDefinition(id:'camera_pan_down',name:'Camera Pan Down',category:'Cinematic Motion',description:'Create a slow downward drift.',durationMs:1400,tracks:[MotionPresetTrack('position.y',[MotionPresetFrame(0,0,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,0.1,mode:MotionPresetValueMode.compositionHeightOffset)])]),
    MotionPresetDefinition(id:'ken_burns_push',name:'Ken Burns Push',category:'Cinematic Motion',description:'Slowly push into an image layer.',durationMs:1600,tracks:[MotionPresetTrack('scale.x',[MotionPresetFrame(0,1,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(1,1.14,mode:MotionPresetValueMode.multiplier)]),MotionPresetTrack('scale.y',[MotionPresetFrame(0,1,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(1,1.14,mode:MotionPresetValueMode.multiplier)])]),
    MotionPresetDefinition(id:'ken_burns_pull',name:'Ken Burns Pull',category:'Cinematic Motion',description:'Slowly pull back from an image layer.',durationMs:1600,tracks:[MotionPresetTrack('scale.x',[MotionPresetFrame(0,1.14,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(1,1,mode:MotionPresetValueMode.multiplier)]),MotionPresetTrack('scale.y',[MotionPresetFrame(0,1.14,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(1,1,mode:MotionPresetValueMode.multiplier)])]),
    MotionPresetDefinition(id:'diagonal_swoop_in',name:'Diagonal Swoop In',category:'Entrance',description:'Enter diagonally with rotational settle.',durationMs:840,tracks:[MotionPresetTrack('position.x',[MotionPresetFrame(0,0.7,mode:MotionPresetValueMode.compositionWidthOffset),MotionPresetFrame(1,0,mode:MotionPresetValueMode.offset)]),MotionPresetTrack('position.y',[MotionPresetFrame(0,0.35,mode:MotionPresetValueMode.compositionHeightOffset),MotionPresetFrame(1,0,mode:MotionPresetValueMode.offset)]),MotionPresetTrack('rotation.z',[MotionPresetFrame(0,16,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,0,mode:MotionPresetValueMode.offset)]),MotionPresetTrack('opacity',[MotionPresetFrame(0,0),MotionPresetFrame(1,100)])]),
    MotionPresetDefinition(id:'diagonal_swoop_out',name:'Diagonal Swoop Out',category:'Exit',description:'Exit diagonally with rotation and fade.',durationMs:760,tracks:[MotionPresetTrack('position.x',[MotionPresetFrame(0,0,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,-0.75,mode:MotionPresetValueMode.compositionWidthOffset)]),MotionPresetTrack('position.y',[MotionPresetFrame(0,0,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,0.35,mode:MotionPresetValueMode.compositionHeightOffset)]),MotionPresetTrack('rotation.z',[MotionPresetFrame(0,0,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,-18,mode:MotionPresetValueMode.offset)]),MotionPresetTrack('opacity',[MotionPresetFrame(0,100),MotionPresetFrame(1,0)])]),
    MotionPresetDefinition(id:'soft_zoom_fade',name:'Soft Zoom Fade',category:'Entrance',description:'Gentle zoom with an opacity ramp.',durationMs:760,tracks:[MotionPresetTrack('scale.x',[MotionPresetFrame(0,0.86,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(1,1,mode:MotionPresetValueMode.multiplier)]),MotionPresetTrack('scale.y',[MotionPresetFrame(0,0.86,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(1,1,mode:MotionPresetValueMode.multiplier)]),MotionPresetTrack('opacity',[MotionPresetFrame(0,0),MotionPresetFrame(1,100)])]),
    MotionPresetDefinition(id:'subtle_float',name:'Subtle Float',category:'Ambient Motion',description:'Gentle vertical drift and return.',durationMs:1500,tracks:[MotionPresetTrack('position.y',[MotionPresetFrame(0,0,mode:MotionPresetValueMode.offset),MotionPresetFrame(0.5,-0.025,mode:MotionPresetValueMode.compositionHeightOffset),MotionPresetFrame(1,0,mode:MotionPresetValueMode.offset)])]),
    MotionPresetDefinition(id:'rubber_band',name:'Rubber Band',category:'Attention',description:'Stretch and compress before returning to normal.',durationMs:920,interpolation:Interpolation.easeInOut,tracks:[MotionPresetTrack('scale.x',[MotionPresetFrame(0,0.8,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(0.28,1.18,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(0.5,0.92,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(0.72,1.06,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(1,1,mode:MotionPresetValueMode.multiplier)]),MotionPresetTrack('scale.y',[MotionPresetFrame(0,1.16,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(0.28,0.86,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(0.5,1.08,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(0.72,0.96,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(1,1,mode:MotionPresetValueMode.multiplier)])]),
    MotionPresetDefinition(id:'tada',name:'Tada',category:'Attention',description:'Celebratory scale and rotation accent.',durationMs:950,interpolation:Interpolation.easeInOut,tracks:[MotionPresetTrack('scale.x',[MotionPresetFrame(0,1,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(0.45,0.92,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(0.72,1.16,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(1,1,mode:MotionPresetValueMode.multiplier)]),MotionPresetTrack('scale.y',[MotionPresetFrame(0,1,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(0.45,0.92,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(0.72,1.16,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(1,1,mode:MotionPresetValueMode.multiplier)]),MotionPresetTrack('rotation.z',[MotionPresetFrame(0,0,mode:MotionPresetValueMode.offset),MotionPresetFrame(0.28,-10,mode:MotionPresetValueMode.offset),MotionPresetFrame(0.55,10,mode:MotionPresetValueMode.offset),MotionPresetFrame(0.8,-5,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,0,mode:MotionPresetValueMode.offset)])]),
    MotionPresetDefinition(id:'bounce_out',name:'Bounce Out',category:'Exit',description:'Shrink away with a bounce and fade.',durationMs:820,tracks:[MotionPresetTrack('scale.x',[MotionPresetFrame(0,1,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(0.7,0.9,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(1,0.2,mode:MotionPresetValueMode.multiplier)]),MotionPresetTrack('scale.y',[MotionPresetFrame(0,1,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(0.7,0.9,mode:MotionPresetValueMode.multiplier),MotionPresetFrame(1,0.2,mode:MotionPresetValueMode.multiplier)]),MotionPresetTrack('opacity',[MotionPresetFrame(0,100),MotionPresetFrame(1,0)])]),
    MotionPresetDefinition(id:'glide_out_left',name:'Glide Out Left',category:'Exit',description:'Glide beyond the left frame edge.',durationMs:700,tracks:[MotionPresetTrack('position.x',[MotionPresetFrame(0,0,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,-1,mode:MotionPresetValueMode.compositionWidthOffset)]),MotionPresetTrack('opacity',[MotionPresetFrame(0,100),MotionPresetFrame(1,0)])]),
    MotionPresetDefinition(id:'glide_out_right',name:'Glide Out Right',category:'Exit',description:'Glide beyond the right frame edge.',durationMs:700,tracks:[MotionPresetTrack('position.x',[MotionPresetFrame(0,0,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,1,mode:MotionPresetValueMode.compositionWidthOffset)]),MotionPresetTrack('opacity',[MotionPresetFrame(0,100),MotionPresetFrame(1,0)])]),
    MotionPresetDefinition(id:'glide_out_up',name:'Glide Out Up',category:'Exit',description:'Glide above the frame edge.',durationMs:700,tracks:[MotionPresetTrack('position.y',[MotionPresetFrame(0,0,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,-1,mode:MotionPresetValueMode.compositionHeightOffset)]),MotionPresetTrack('opacity',[MotionPresetFrame(0,100),MotionPresetFrame(1,0)])]),
    MotionPresetDefinition(id:'glide_out_down',name:'Glide Out Down',category:'Exit',description:'Glide below the frame edge.',durationMs:700,tracks:[MotionPresetTrack('position.y',[MotionPresetFrame(0,0,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,1,mode:MotionPresetValueMode.compositionHeightOffset)]),MotionPresetTrack('opacity',[MotionPresetFrame(0,100),MotionPresetFrame(1,0)])]),
    MotionPresetDefinition(id:'spin_fade_in',name:'Spin Fade In',category:'Entrance',description:'Spin into the composition with opacity ramp.',durationMs:820,tracks:[MotionPresetTrack('rotation.z',[MotionPresetFrame(0,180,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,0,mode:MotionPresetValueMode.offset)]),MotionPresetTrack('opacity',[MotionPresetFrame(0,0),MotionPresetFrame(1,100)])]),
    MotionPresetDefinition(id:'spin_fade_out',name:'Spin Fade Out',category:'Exit',description:'Rotate away while disappearing.',durationMs:760,tracks:[MotionPresetTrack('rotation.z',[MotionPresetFrame(0,0,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,-180,mode:MotionPresetValueMode.offset)]),MotionPresetTrack('opacity',[MotionPresetFrame(0,100),MotionPresetFrame(1,0)])]),
    MotionPresetDefinition(id:'pendulum_reveal',name:'Pendulum Reveal',category:'Attention',description:'Swing from wide angle to centred position.',durationMs:1050,tracks:[MotionPresetTrack('rotation.z',[MotionPresetFrame(0,-34,mode:MotionPresetValueMode.offset),MotionPresetFrame(0.32,20,mode:MotionPresetValueMode.offset),MotionPresetFrame(0.68,-8,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,0,mode:MotionPresetValueMode.offset)])]),
    MotionPresetDefinition(id:'depth_float',name:'Depth Float',category:'3D Motion',description:'Gentle X-axis tilt for dimensional movement.',durationMs:1400,tracks:[MotionPresetTrack('rotation.x',[MotionPresetFrame(0,-5,mode:MotionPresetValueMode.offset),MotionPresetFrame(0.5,5,mode:MotionPresetValueMode.offset),MotionPresetFrame(1,0,mode:MotionPresetValueMode.offset)])]),
    MotionPresetDefinition(id:'soft_spring_up',name:'Soft Spring Up',category:'Entrance',description:'Rise into place with light spring overshoot.',durationMs:900,tracks:[MotionPresetTrack('position.y',[MotionPresetFrame(0,0.16,mode:MotionPresetValueMode.compositionHeightOffset),MotionPresetFrame(0.78,-0.025,mode:MotionPresetValueMode.compositionHeightOffset),MotionPresetFrame(1,0,mode:MotionPresetValueMode.offset)])]),

  ];

  static MotionPresetDefinition? find(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}
