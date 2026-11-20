class EffectParameterDefinition {
  const EffectParameterDefinition({
    required this.id,
    required this.label,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.unit = '',
  });

  final String id;
  final String label;
  final double min;
  final double max;
  final double defaultValue;
  final String unit;
}

class EffectDefinition {
  const EffectDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.parameters,
    required this.ffmpegFilter,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final List<EffectParameterDefinition> parameters;

  /// Empty means the effect needs a GPU/custom render pass, not that it is absent.
  final String ffmpegFilter;
}

class EffectCatalog {
  EffectCatalog._();

  static const all = <EffectDefinition>[
    EffectDefinition(
      id: 'brightness',
      name: 'Brightness',
      category: 'Color',
      description: 'Lift or lower the overall image luminance.',
      parameters: [EffectParameterDefinition(id: 'value', label: 'Brightness', min: -1, max: 1, defaultValue: 0)],
      ffmpegFilter: 'eq',
    ),
    EffectDefinition(
      id: 'contrast',
      name: 'Contrast',
      category: 'Color',
      description: 'Control the difference between highlights and shadows.',
      parameters: [EffectParameterDefinition(id: 'value', label: 'Contrast', min: 0, max: 3, defaultValue: 1)],
      ffmpegFilter: 'eq',
    ),
    EffectDefinition(
      id: 'saturation',
      name: 'Saturation',
      category: 'Color',
      description: 'Control color intensity.',
      parameters: [EffectParameterDefinition(id: 'value', label: 'Saturation', min: 0, max: 3, defaultValue: 1)],
      ffmpegFilter: 'hue',
    ),
    EffectDefinition(
      id: 'gamma',
      name: 'Gamma',
      category: 'Color',
      description: 'Adjust midtone response.',
      parameters: [EffectParameterDefinition(id: 'value', label: 'Gamma', min: 0.2, max: 3, defaultValue: 1)],
      ffmpegFilter: 'eq',
    ),
    EffectDefinition(
      id: 'gaussian_blur',
      name: 'Gaussian Blur',
      category: 'Blur & Sharpen',
      description: 'Soften the image with a Gaussian kernel.',
      parameters: [EffectParameterDefinition(id: 'sigma', label: 'Blur', min: 0, max: 30, defaultValue: 2, unit: 'px')],
      ffmpegFilter: 'gblur',
    ),
    EffectDefinition(
      id: 'box_blur',
      name: 'Box Blur',
      category: 'Blur & Sharpen',
      description: 'Fast uniform blur.',
      parameters: [EffectParameterDefinition(id: 'radius', label: 'Radius', min: 0, max: 20, defaultValue: 2, unit: 'px')],
      ffmpegFilter: 'boxblur',
    ),
    EffectDefinition(
      id: 'sharpen',
      name: 'Sharpen',
      category: 'Blur & Sharpen',
      description: 'Enhance local edge contrast.',
      parameters: [EffectParameterDefinition(id: 'amount', label: 'Amount', min: 0, max: 5, defaultValue: 1)],
      ffmpegFilter: 'unsharp',
    ),
    EffectDefinition(
      id: 'vignette',
      name: 'Vignette',
      category: 'Stylize',
      description: 'Darken or shape the frame edges.',
      parameters: [EffectParameterDefinition(id: 'angle', label: 'Strength', min: 0.1, max: 1.5, defaultValue: 0.8)],
      ffmpegFilter: 'vignette',
    ),
    EffectDefinition(
      id: 'film_grain',
      name: 'Film Grain',
      category: 'Stylize',
      description: 'Add animated film texture.',
      parameters: [EffectParameterDefinition(id: 'amount', label: 'Amount', min: 0, max: 100, defaultValue: 12)],
      ffmpegFilter: 'noise',
    ),
    EffectDefinition(
      id: 'pixelate',
      name: 'Pixelate',
      category: 'Stylize',
      description: 'Create a block-pixel mosaic.',
      parameters: [EffectParameterDefinition(id: 'size', label: 'Pixel Size', min: 2, max: 80, defaultValue: 12, unit: 'px')],
      ffmpegFilter: 'pixelize',
    ),
    EffectDefinition(
      id: 'threshold',
      name: 'Threshold',
      category: 'Color',
      description: 'Convert pixel intensity into hard black and white regions.',
      parameters: [
        EffectParameterDefinition(
          id: 'value',
          label: 'Threshold',
          min: 0,
          max: 255,
          defaultValue: 128,
        ),
      ],
      ffmpegFilter: 'lutrgb',
    ),
    EffectDefinition(
      id: 'invert',
      name: 'Invert',
      category: 'Stylize',
      description: 'Invert the image colors.',
      parameters: [],
      ffmpegFilter: 'negate',
    ),
    EffectDefinition(
      id: 'grayscale',
      name: 'Black & White',
      category: 'Color',
      description: 'Remove color information.',
      parameters: [],
      ffmpegFilter: 'hue',
    ),
    EffectDefinition(
      id: 'chromatic_aberration',
      name: 'Chromatic Aberration',
      category: 'Stylize',
      description: 'Shift chroma channels for a lens-fringe look.',
      parameters: [EffectParameterDefinition(id: 'shift', label: 'Shift', min: 0, max: 12, defaultValue: 2, unit: 'px')],
      ffmpegFilter: 'chromashift',
    ),
    EffectDefinition(
      id: 'edge_detect',
      name: 'Edge Detect',
      category: 'Stylize',
      description: 'Reveal image contours.',
      parameters: [],
      ffmpegFilter: 'edgedetect',
    ),
    EffectDefinition(
      id: 'mirror',
      name: 'Mirror',
      category: 'Transform',
      description: 'Mirror the image horizontally.',
      parameters: [],
      ffmpegFilter: 'hflip',
    ),
    EffectDefinition(
      id: 'flip',
      name: 'Flip',
      category: 'Transform',
      description: 'Flip the image vertically.',
      parameters: [],
      ffmpegFilter: 'vflip',
    ),
    EffectDefinition(
      id: 'color_curves',
      name: 'Color Curves',
      category: 'Color',
      description: 'Advanced tone curves using a GPU render pass.',
      parameters: [EffectParameterDefinition(id: 'lift', label: 'Lift', min: -1, max: 1, defaultValue: 0), EffectParameterDefinition(id: 'gamma', label: 'Gamma', min: 0.2, max: 3, defaultValue: 1), EffectParameterDefinition(id: 'gain', label: 'Gain', min: 0, max: 3, defaultValue: 1)],
      ffmpegFilter: 'curves',
    ),
    EffectDefinition(
      id: 'drop_shadow',
      name: 'Drop Shadow',
      category: 'Compositing',
      description: 'Generate a soft shadow behind alpha content.',
      parameters: [EffectParameterDefinition(id: 'opacity', label: 'Opacity', min: 0, max: 1, defaultValue: 0.6), EffectParameterDefinition(id: 'blur', label: 'Blur', min: 0, max: 40, defaultValue: 8), EffectParameterDefinition(id: 'offset', label: 'Offset', min: -100, max: 100, defaultValue: 8)],
      ffmpegFilter: 'shadow',
    ),
    EffectDefinition(
      id: 'glow',
      name: 'Glow',
      category: 'Compositing',
      description: 'Bloom bright pixels with a soft halo.',
      parameters: [EffectParameterDefinition(id: 'threshold', label: 'Threshold', min: 0, max: 1, defaultValue: 0.75), EffectParameterDefinition(id: 'radius', label: 'Radius', min: 1, max: 50, defaultValue: 12), EffectParameterDefinition(id: 'intensity', label: 'Intensity', min: 0, max: 3, defaultValue: 1)],
      ffmpegFilter: 'split',
    ),
    EffectDefinition(
      id: 'displacement',
      name: 'Displacement',
      category: 'VFX',
      description: 'Warp pixels with animated procedural X/Y displacement fields.',
      parameters: [
        EffectParameterDefinition(id: 'amount', label: 'Amount', min: 0, max: 64, defaultValue: 12, unit: 'px'),
        EffectParameterDefinition(id: 'wavelength', label: 'Wavelength', min: 20, max: 500, defaultValue: 80, unit: 'px'),
        EffectParameterDefinition(id: 'speed', label: 'Animation speed', min: 0, max: 8, defaultValue: 1),
      ],
      ffmpegFilter: '',
    ),
    EffectDefinition(
      id: 'particle_dust',
      name: 'Particle Dust',
      category: 'VFX',
      description: 'Add an animated procedural dust-particle field with adjustable spacing and drift.',
      parameters: [
        EffectParameterDefinition(id: 'spacing', label: 'Particle spacing', min: 16, max: 160, defaultValue: 72, unit: 'px'),
        EffectParameterDefinition(id: 'size', label: 'Particle size', min: 1, max: 12, defaultValue: 2, unit: 'px'),
        EffectParameterDefinition(id: 'intensity', label: 'Intensity', min: 0, max: 1, defaultValue: 0.55),
        EffectParameterDefinition(id: 'speed', label: 'Drift speed', min: 0, max: 8, defaultValue: 1),
      ],
      ffmpegFilter: '',
    ),
    EffectDefinition(
      id: 'motion_blur',
      name: 'Motion Blur',
      category: 'Motion',
      description: 'Blend adjacent frames to simulate shutter motion.',
      parameters: [EffectParameterDefinition(id: 'frames', label: 'Samples', min: 2, max: 16, defaultValue: 5)],
      ffmpegFilter: 'tmix',
    ),
    EffectDefinition(
      id: 'lens_distortion',
      name: 'Lens Distortion',
      category: 'Lens',
      description: 'Barrel or pincushion lens deformation.',
      parameters: [EffectParameterDefinition(id: 'strength', label: 'Strength', min: -1, max: 1, defaultValue: 0.1)],
      ffmpegFilter: 'lenscorrection',
    ),
    EffectDefinition(
      id: 'transform',
      name: 'Transform',
      category: 'Transform',
      description: '2D position, scale, rotation and anchor transform.',
      parameters: [EffectParameterDefinition(id: 'scale', label: 'Scale', min: 0, max: 400, defaultValue: 100, unit: '%'), EffectParameterDefinition(id: 'rotation', label: 'Rotation', min: -360, max: 360, defaultValue: 0, unit: '°')],
      ffmpegFilter: 'rotate',
    ),
    EffectDefinition(
      id: 'chroma_key',
      name: 'Chroma Key',
      category: 'Keying',
      description: 'Remove a selected background color.',
      parameters: [EffectParameterDefinition(id: 'similarity', label: 'Similarity', min: 0.01, max: 1, defaultValue: 0.3), EffectParameterDefinition(id: 'blend', label: 'Blend', min: 0, max: 1, defaultValue: 0.1)],
      ffmpegFilter: 'chromakey',
    ),
    EffectDefinition(
      id: 'luma_key',
      name: 'Luma Key',
      category: 'Keying',
      description: 'Create transparency from luminance.',
      parameters: [EffectParameterDefinition(id: 'threshold', label: 'Threshold', min: 0, max: 1, defaultValue: 0.5), EffectParameterDefinition(id: 'tolerance', label: 'Tolerance', min: 0, max: 1, defaultValue: 0.1)],
      ffmpegFilter: 'lumakey',
    ),
    EffectDefinition(
      id: 'stabilize',
      name: 'Stabilize',
      category: 'Tracking',
      description: 'Motion stabilization pass using FFmpeg deshake.',
      parameters: [EffectParameterDefinition(id: 'strength', label: 'Strength', min: 1, max: 64, defaultValue: 4)],
      ffmpegFilter: 'deshake',
    ),
    EffectDefinition(
      id: 'posterize',
      name: 'Posterize',
      category: 'Stylize',
      description: 'Reduce the number of color levels.',
      parameters: [EffectParameterDefinition(id: 'levels', label: 'Levels', min: 2, max: 32, defaultValue: 6)],
      ffmpegFilter: 'posterize',
    ),
    EffectDefinition(
      id: 'color_balance',
      name: 'Color Balance',
      category: 'Color',
      description: 'Grade shadows, midtones and highlights.',
      parameters: [EffectParameterDefinition(id: 'red', label: 'Red', min: -1, max: 1, defaultValue: 0), EffectParameterDefinition(id: 'green', label: 'Green', min: -1, max: 1, defaultValue: 0), EffectParameterDefinition(id: 'blue', label: 'Blue', min: -1, max: 1, defaultValue: 0)],
      ffmpegFilter: 'colorbalance',
    ),

    EffectDefinition(
      id: 'color_grade',
      name: 'Primary Color Grade',
      category: 'Color',
      description: 'Lift, Gamma, Gain and Offset wheels with temperature, tint, contrast and saturation controls.',
      parameters: [
        EffectParameterDefinition(id: 'lift_r', label: 'Lift Red', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'lift_g', label: 'Lift Green', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'lift_b', label: 'Lift Blue', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'gamma_r', label: 'Gamma Red', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'gamma_g', label: 'Gamma Green', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'gamma_b', label: 'Gamma Blue', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'gain_r', label: 'Gain Red', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'gain_g', label: 'Gain Green', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'gain_b', label: 'Gain Blue', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'offset_r', label: 'Offset Red', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'offset_g', label: 'Offset Green', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'offset_b', label: 'Offset Blue', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'temperature', label: 'Temperature', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'tint', label: 'Tint', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'contrast', label: 'Contrast', min: 0, max: 3, defaultValue: 1),
        EffectParameterDefinition(id: 'brightness', label: 'Exposure / Brightness', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'master_gamma', label: 'Master Gamma', min: 0.1, max: 3, defaultValue: 1),
        EffectParameterDefinition(id: 'saturation', label: 'Saturation', min: 0, max: 3, defaultValue: 1),
      ],
      ffmpegFilter: 'colorbalance,eq',
    ),
  ];

  static List<EffectDefinition> get allEffects => List.unmodifiable(all);

  static EffectDefinition? find(String id) {
    for (final effect in all) {
      if (effect.id == id) return effect;
    }
    return null;
  }

  static List<String> get categories =>
      all.map((item) => item.category).toSet().toList()..sort();
}
