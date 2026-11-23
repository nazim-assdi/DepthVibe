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
    this.rendererId,
    this.extensionId,
    this.assetUri,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final List<EffectParameterDefinition> parameters;

  /// Empty means the effect needs a GPU/custom render pass, not that it is absent.
  final String ffmpegFilter;
  final String? rendererId;
  final String? extensionId;
  final String? assetUri;
}

class EffectCatalog {
  EffectCatalog._();

  static final all = <EffectDefinition>[
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
      id: 'color_curves',
      name: 'Primary Curves',
      category: 'Color',
      description: 'Editable master and RGB curves with five control points per channel.',
      parameters: [
        for (final channel in const ['master', 'red', 'green', 'blue'])
          for (var point = 0; point < 5; point++)
            EffectParameterDefinition(
              id: '${channel}_${point}',
              label: '${channel} point ${point + 1}',
              min: 0,
              max: 1,
              defaultValue: point * 0.25,
            ),
      ],
      ffmpegFilter: 'curves',
    ),
    EffectDefinition(
      id: 'color_lut',
      name: '3D LUT',
      category: 'Color',
      description: 'Imported 3D .cube lookup table.',
      parameters: [],
      ffmpegFilter: 'lut3d',
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

    EffectDefinition(
      id: 'exposure', name: 'Exposure', category: 'Color',
      description: 'Adjust exposure in photographic EV stops.',
      parameters: [
        EffectParameterDefinition(id: 'value', label: 'Exposure', min: -3, max: 3, defaultValue: 0, unit: ' EV'),
        EffectParameterDefinition(id: 'black', label: 'Black level', min: -0.1, max: 0.1, defaultValue: 0),
      ],
      ffmpegFilter: 'exposure',
    ),
    EffectDefinition(
      id: 'hue_rotate', name: 'Hue Rotate', category: 'Color',
      description: 'Rotate all hues around the colour wheel.',
      parameters: [EffectParameterDefinition(id: 'degrees', label: 'Hue', min: -180, max: 180, defaultValue: 0, unit: '°')],
      ffmpegFilter: 'hue',
    ),
    EffectDefinition(
      id: 'colorize', name: 'Colorize', category: 'Color',
      description: 'Tint footage with a selectable hue.',
      parameters: [
        EffectParameterDefinition(id: 'hue', label: 'Hue', min: 0, max: 360, defaultValue: 210, unit: '°'),
        EffectParameterDefinition(id: 'saturation', label: 'Saturation', min: 0, max: 1, defaultValue: 0.65),
        EffectParameterDefinition(id: 'lightness', label: 'Lightness', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'mix', label: 'Mix', min: 0, max: 1, defaultValue: 0.5),
      ],
      ffmpegFilter: 'colorize',
    ),
    EffectDefinition(
      id: 'directional_blur', name: 'Directional Blur', category: 'Blur & Sharpen',
      description: 'Create streaking blur along a chosen direction.',
      parameters: [
        EffectParameterDefinition(id: 'angle', label: 'Angle', min: -180, max: 180, defaultValue: 0, unit: '°'),
        EffectParameterDefinition(id: 'radius', label: 'Radius', min: 0, max: 50, defaultValue: 8, unit: 'px'),
      ],
      ffmpegFilter: 'dblur',
    ),
    EffectDefinition(
      id: 'average_blur', name: 'Average Blur', category: 'Blur & Sharpen',
      description: 'Apply a fast averaging blur.',
      parameters: [EffectParameterDefinition(id: 'size', label: 'Kernel size', min: 1, max: 30, defaultValue: 5, unit: 'px')],
      ffmpegFilter: 'avgblur',
    ),
    EffectDefinition(
      id: 'chroma_denoise', name: 'Chroma Denoise', category: 'Noise Reduction',
      description: 'Reduce chroma noise while retaining luminance detail.',
      parameters: [
        EffectParameterDefinition(id: 'threshold', label: 'Threshold', min: 0.01, max: 2, defaultValue: 0.08),
        EffectParameterDefinition(id: 'window', label: 'Window', min: 1, max: 10, defaultValue: 3),
      ],
      ffmpegFilter: 'chromanr',
    ),
    EffectDefinition(
      id: 'deband', name: 'Deband', category: 'Noise Reduction',
      description: 'Reduce visible colour banding in gradients.',
      parameters: [
        EffectParameterDefinition(id: 'threshold', label: 'Threshold', min: 0.00003, max: 0.2, defaultValue: 0.02),
        EffectParameterDefinition(id: 'range', label: 'Range', min: 1, max: 32, defaultValue: 16),
      ],
      ffmpegFilter: 'deband',
    ),
    EffectDefinition(
      id: 'deflicker', name: 'Deflicker', category: 'Cleanup',
      description: 'Smooth unwanted frame-to-frame brightness flicker.',
      parameters: [EffectParameterDefinition(id: 'size', label: 'Window size', min: 2, max: 129, defaultValue: 10)],
      ffmpegFilter: 'deflicker',
    ),
    EffectDefinition(
      id: 'scanlines', name: 'Scanlines', category: 'Stylize',
      description: 'Overlay horizontal CRT-style scanlines.',
      parameters: [
        EffectParameterDefinition(id: 'spacing', label: 'Line spacing', min: 2, max: 32, defaultValue: 4, unit: 'px'),
        EffectParameterDefinition(id: 'thickness', label: 'Thickness', min: 1, max: 8, defaultValue: 1, unit: 'px'),
        EffectParameterDefinition(id: 'opacity', label: 'Opacity', min: 0, max: 1, defaultValue: 0.25),
      ],
      ffmpegFilter: 'drawgrid',
    ),
    EffectDefinition(
      id: 'rgb_split', name: 'RGB Split', category: 'Stylize',
      description: 'Separate colour channels for a chromatic-fringe effect.',
      parameters: [EffectParameterDefinition(id: 'shift', label: 'Channel offset', min: 0, max: 24, defaultValue: 4, unit: 'px')],
      ffmpegFilter: 'chromashift',
    ),
    EffectDefinition(
      id: 'posterize_time', name: 'Posterize Time', category: 'Motion',
      description: 'Reduce the effective frame rate for stepped motion.',
      parameters: [EffectParameterDefinition(id: 'fps', label: 'Posterized FPS', min: 2, max: 60, defaultValue: 12)],
      ffmpegFilter: 'fps',
    ),
    EffectDefinition(
      id: 'echo_trails', name: 'Echo Trails', category: 'Motion',
      description: 'Blend recent frames to create motion trails.',
      parameters: [EffectParameterDefinition(id: 'frames', label: 'Trail samples', min: 2, max: 12, defaultValue: 4)],
      ffmpegFilter: 'tmix',
    ),
    EffectDefinition(
      id: 'vhs_warp', name: 'VHS Warp', category: 'Stylize',
      description: 'Combine chroma separation and analogue noise.',
      parameters: [
        EffectParameterDefinition(id: 'shift', label: 'Chroma shift', min: 0, max: 16, defaultValue: 3, unit: 'px'),
        EffectParameterDefinition(id: 'noise', label: 'Tape noise', min: 0, max: 100, defaultValue: 18),
      ],
      ffmpegFilter: 'chromashift,noise',
    ),
    EffectDefinition(
      id: 'fisheye', name: 'Fisheye', category: 'Lens',
      description: 'Apply radial lens distortion.',
      parameters: [EffectParameterDefinition(id: 'strength', label: 'Distortion', min: -1, max: 1, defaultValue: 0.35)],
      ffmpegFilter: 'lenscorrection',
    ),
    EffectDefinition(
      id: 'radial_blur', name: 'Radial Blur', category: 'Blur & Sharpen',
      description: 'Create radial directional streaking.',
      parameters: [
        EffectParameterDefinition(id: 'angle', label: 'Angle', min: -180, max: 180, defaultValue: 0, unit: '°'),
        EffectParameterDefinition(id: 'radius', label: 'Radius', min: 0, max: 50, defaultValue: 12, unit: 'px'),
      ],
      ffmpegFilter: 'dblur',
    ),
    EffectDefinition(
      id: 'noise_reduction', name: 'Spatial Noise Reduction', category: 'Noise Reduction',
      description: 'Reduce luma and chroma noise using a spatial/temporal denoiser.',
      parameters: [
        EffectParameterDefinition(id: 'luma', label: 'Luma strength', min: 0, max: 12, defaultValue: 1.5),
        EffectParameterDefinition(id: 'chroma', label: 'Chroma strength', min: 0, max: 12, defaultValue: 2),
        EffectParameterDefinition(id: 'temporal', label: 'Temporal strength', min: 0, max: 12, defaultValue: 3),
      ],
      ffmpegFilter: 'hqdn3d',
    ),

    EffectDefinition(
      id: 'vibrance', name: 'Vibrance', category: 'Color',
      description: 'Boost muted colours while keeping already-saturated areas controlled.',
      parameters: [
        EffectParameterDefinition(id: 'intensity', label: 'Intensity', min: -2, max: 2, defaultValue: 0.5),
      ],
      ffmpegFilter: 'vibrance',
    ),
    EffectDefinition(
      id: 'color_contrast', name: 'Color Contrast', category: 'Color',
      description: 'Shape red, green and blue colour contrast independently.',
      parameters: [
        EffectParameterDefinition(id: 'red', label: 'Red contrast', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'green', label: 'Green contrast', min: -1, max: 1, defaultValue: 0),
        EffectParameterDefinition(id: 'blue', label: 'Blue contrast', min: -1, max: 1, defaultValue: 0),
      ],
      ffmpegFilter: 'colorcontrast',
    ),
    EffectDefinition(
      id: 'auto_white_balance', name: 'Auto White Balance', category: 'Color',
      description: 'Estimate neutral balance from the image using the gray-world method.',
      parameters: [],
      ffmpegFilter: 'grayworld',
    ),
    EffectDefinition(
      id: 'rgb_channel_mixer', name: 'RGB Channel Mixer', category: 'Color',
      description: 'Remix RGB channel contributions with an editable 3×3 matrix.',
      parameters: [
        for (final channel in const ['r', 'g', 'b'])
          for (final source in const ['r', 'g', 'b'])
            EffectParameterDefinition(
              id: '$channel$source',
              label: '$channel ← $source',
              min: -2,
              max: 2,
              defaultValue: channel == source ? 1 : 0,
            ),
      ],
      ffmpegFilter: 'colorchannelmixer',
    ),
    EffectDefinition(
      id: 'adaptive_sharpen', name: 'Adaptive Sharpen', category: 'Blur & Sharpen',
      description: 'Apply contrast-adaptive sharpening for crisp detail.',
      parameters: [
        EffectParameterDefinition(id: 'strength', label: 'Strength', min: 0, max: 1, defaultValue: 0.5),
      ],
      ffmpegFilter: 'cas',
    ),
    EffectDefinition(
      id: 'median_denoise', name: 'Median Denoise', category: 'Noise Reduction',
      description: 'Remove isolated speckles while preserving larger edges.',
      parameters: [
        EffectParameterDefinition(id: 'radius', label: 'Radius', min: 1, max: 7, defaultValue: 2),
      ],
      ffmpegFilter: 'median',
    ),
    EffectDefinition(
      id: 'temporal_denoise', name: 'Temporal Median', category: 'Noise Reduction',
      description: 'Reduce transient noise by comparing neighbouring frames.',
      parameters: [
        EffectParameterDefinition(id: 'radius', label: 'Frame radius', min: 1, max: 7, defaultValue: 3),
      ],
      ffmpegFilter: 'tmedian',
    ),
    EffectDefinition(
      id: 'nlmeans_denoise', name: 'Non-Local Means Denoise', category: 'Noise Reduction',
      description: 'Use patch similarity to reduce noise while retaining texture.',
      parameters: [
        EffectParameterDefinition(id: 'strength', label: 'Strength', min: 0.1, max: 12, defaultValue: 1.2),
      ],
      ffmpegFilter: 'nlmeans',
    ),
    EffectDefinition(
      id: 'frame_blend', name: 'Frame Blend', category: 'Motion',
      description: 'Blend consecutive frames for a soft temporal exposure effect.',
      parameters: [],
      ffmpegFilter: 'tblend',
    ),
    EffectDefinition(
      id: 'wave_distortion', name: 'Wave Distortion', category: 'VFX',
      description: 'Displace pixels with an animated horizontal wave field.',
      parameters: [
        EffectParameterDefinition(id: 'amount', label: 'Amplitude', min: 0, max: 30, defaultValue: 8, unit: 'px'),
        EffectParameterDefinition(id: 'wavelength', label: 'Wavelength', min: 8, max: 300, defaultValue: 72, unit: 'px'),
        EffectParameterDefinition(id: 'speed', label: 'Speed', min: 0, max: 8, defaultValue: 1),
      ],
      ffmpegFilter: 'geq',
    ),
    EffectDefinition(
      id: 'heat_haze', name: 'Heat Haze', category: 'VFX',
      description: 'Create a refractive heat shimmer with animated two-axis distortion.',
      parameters: [
        EffectParameterDefinition(id: 'amount', label: 'Distortion', min: 0, max: 24, defaultValue: 5, unit: 'px'),
        EffectParameterDefinition(id: 'scale', label: 'Pattern scale', min: 8, max: 300, defaultValue: 90, unit: 'px'),
        EffectParameterDefinition(id: 'speed', label: 'Speed', min: 0, max: 8, defaultValue: 1.4),
      ],
      ffmpegFilter: 'geq',
    ),
    EffectDefinition(
      id: 'film_gate_weave', name: 'Film Gate Weave', category: 'Stylize',
      description: 'Add subtle animated camera-gate rotation to emulate analogue film movement.',
      parameters: [
        EffectParameterDefinition(id: 'amplitude', label: 'Amplitude', min: 0, max: 3, defaultValue: 0.45, unit: '°'),
        EffectParameterDefinition(id: 'speed', label: 'Speed', min: 0.1, max: 10, defaultValue: 2),
      ],
      ffmpegFilter: 'rotate',
    ),
    EffectDefinition(
      id: 'camera_flash', name: 'Camera Flash', category: 'Lighting',
      description: 'Lift exposure for a bright photographic flash frame.',
      parameters: [
        EffectParameterDefinition(id: 'brightness', label: 'Flash amount', min: 0, max: 2, defaultValue: 0.35),
      ],
      ffmpegFilter: 'eq',
    ),
    EffectDefinition(
      id: 'letterbox', name: 'Cinematic Letterbox', category: 'Compositing',
      description: 'Add adjustable top and bottom mattes for a widescreen finish.',
      parameters: [
        EffectParameterDefinition(id: 'ratio', label: 'Bar height', min: 0.02, max: 0.2, defaultValue: 0.1),
      ],
      ffmpegFilter: 'drawbox',
    ),
    EffectDefinition(
      id: 'frame_border', name: 'Frame Border', category: 'Compositing',
      description: 'Draw a clean, adjustable border around the composition frame.',
      parameters: [
        EffectParameterDefinition(id: 'thickness', label: 'Thickness', min: 1, max: 30, defaultValue: 6, unit: 'px'),
        EffectParameterDefinition(id: 'opacity', label: 'Opacity', min: 0, max: 1, defaultValue: 0.8),
      ],
      ffmpegFilter: 'drawbox',
    ),
    EffectDefinition(
      id: 'old_film', name: '8mm Old Film', category: 'Stylize',
      description: 'Combine moving grain, warm colour bias and a soft vignette.',
      parameters: [
        EffectParameterDefinition(id: 'grain', label: 'Grain', min: 0, max: 100, defaultValue: 22),
        EffectParameterDefinition(id: 'vignette', label: 'Vignette', min: 0.1, max: 1.5, defaultValue: 0.7),
        EffectParameterDefinition(id: 'warmth', label: 'Warmth', min: 0, max: 1, defaultValue: 0.35),
      ],
      ffmpegFilter: 'noise,vignette,colorbalance',
    ),
    EffectDefinition(
      id: 'analog_glitch', name: 'Analog Glitch', category: 'VFX',
      description: 'Combine chroma displacement, moving tape noise and stepped frame rate.',
      parameters: [
        EffectParameterDefinition(id: 'shift', label: 'Chroma shift', min: 0, max: 20, defaultValue: 5, unit: 'px'),
        EffectParameterDefinition(id: 'noise', label: 'Tape noise', min: 0, max: 100, defaultValue: 24),
        EffectParameterDefinition(id: 'fps', label: 'Frame cadence', min: 2, max: 30, defaultValue: 18),
      ],
      ffmpegFilter: 'chromashift,noise,fps',
    ),
    EffectDefinition(
      id: 'bleach_bypass', name: 'Bleach Bypass', category: 'Color',
      description: 'Create a high-contrast, partially desaturated film response.',
      parameters: [
        EffectParameterDefinition(id: 'contrast', label: 'Contrast', min: 0.5, max: 2.5, defaultValue: 1.35),
        EffectParameterDefinition(id: 'saturation', label: 'Saturation', min: 0, max: 1, defaultValue: 0.45),
      ],
      ffmpegFilter: 'hue,eq',
    ),
    EffectDefinition(
      id: 'sepia', name: 'Sepia Tone', category: 'Color',
      description: 'Apply a classic warm photographic monochrome matrix.',
      parameters: [],
      ffmpegFilter: 'colorchannelmixer',
    ),
    EffectDefinition(
      id: 'edge_glow', name: 'Edge Glow', category: 'Stylize',
      description: 'Extract bright contours and soften them into a luminous outline.',
      parameters: [
        EffectParameterDefinition(id: 'radius', label: 'Glow radius', min: 1, max: 40, defaultValue: 8, unit: 'px'),
        EffectParameterDefinition(id: 'brightness', label: 'Glow brightness', min: 0, max: 2, defaultValue: 0.4),
      ],
      ffmpegFilter: 'edgedetect,gblur,eq',
    ),

    EffectDefinition(id:'solarize',name:'Solarize',category:'Stylize',description:'Photographic solarization with adjustable tonal threshold.',parameters:[EffectParameterDefinition(id:'threshold',label:'Threshold',min:0,max:255,defaultValue:128)],ffmpegFilter:'lutrgb'),
    EffectDefinition(id:'color_temperature',name:'Color Temperature',category:'Color',description:'Warm/cool balance with independent tint.',parameters:[EffectParameterDefinition(id:'temperature',label:'Temperature',min:-1,max:1,defaultValue:0),EffectParameterDefinition(id:'tint',label:'Tint',min:-1,max:1,defaultValue:0),EffectParameterDefinition(id:'intensity',label:'Intensity',min:0,max:1,defaultValue:1)],ffmpegFilter:'colorbalance'),
    EffectDefinition(id:'soft_focus',name:'Soft Focus',category:'Blur & Sharpen',description:'Diffusion-style soft focus.',parameters:[EffectParameterDefinition(id:'radius',label:'Diffusion',min:0,max:16,defaultValue:2),EffectParameterDefinition(id:'brightness',label:'Highlight lift',min:0,max:0.25,defaultValue:0.03)],ffmpegFilter:'gblur,eq'),
    EffectDefinition(id:'ripple_warp',name:'Ripple Warp',category:'VFX',description:'Two-axis animated ripple distortion.',parameters:[EffectParameterDefinition(id:'amount',label:'Amplitude',min:0,max:24,defaultValue:5,unit:'px'),EffectParameterDefinition(id:'wavelength',label:'Wavelength',min:8,max:300,defaultValue:84,unit:'px'),EffectParameterDefinition(id:'speed',label:'Speed',min:0,max:8,defaultValue:1.1)],ffmpegFilter:'geq'),
    EffectDefinition(id:'zoom_warp',name:'Zoom Warp',category:'VFX',description:'Centred radial zoom distortion with adjustable focal point.',parameters:[EffectParameterDefinition(id:'amount',label:'Warp amount',min:-0.45,max:0.45,defaultValue:0.08),EffectParameterDefinition(id:'center_x',label:'Center X',min:0,max:1,defaultValue:0.5),EffectParameterDefinition(id:'center_y',label:'Center Y',min:0,max:1,defaultValue:0.5)],ffmpegFilter:'geq'),
    EffectDefinition(id:'color_key',name:'Color Key',category:'Keying',description:'Green-screen colour key with adjustable tolerance and edge blend.',parameters:[EffectParameterDefinition(id:'similarity',label:'Similarity',min:0.01,max:1,defaultValue:0.3),EffectParameterDefinition(id:'blend',label:'Edge blend',min:0,max:1,defaultValue:0.1)],ffmpegFilter:'colorkey'),
    EffectDefinition(id:'high_pass_sharpen',name:'High-Pass Sharpen',category:'Blur & Sharpen',description:'Controlled high-frequency sharpening.',parameters:[EffectParameterDefinition(id:'amount',label:'Amount',min:0,max:5,defaultValue:1.2)],ffmpegFilter:'unsharp'),
    EffectDefinition(id:'chroma_smear',name:'Chroma Smear',category:'Stylize',description:'Offset chroma channels for analogue colour smearing.',parameters:[EffectParameterDefinition(id:'shift',label:'Smear distance',min:0,max:16,defaultValue:3,unit:'px')],ffmpegFilter:'chromashift'),

  ];

  static final Map<String, EffectDefinition> _extensionEffects = {};

  /// Extensions can alias audited host renderers, but cannot provide code or
  /// arbitrary FFmpeg filter strings.
  static const Set<String> extensionSafeRendererIds = {
    'brightness', 'contrast', 'saturation', 'gamma',
    'gaussian_blur', 'box_blur', 'sharpen', 'vignette',
    'film_grain', 'pixelate', 'threshold', 'invert', 'grayscale',
    'chromatic_aberration', 'edge_detect', 'mirror', 'flip',
    'motion_blur', 'lens_distortion', 'chroma_key', 'luma_key',
    'stabilize', 'posterize', 'color_balance', 'color_curves',
    'color_lut', 'color_grade',
    'exposure', 'hue_rotate', 'colorize', 'directional_blur',
    'average_blur', 'chroma_denoise', 'deband', 'deflicker',
    'scanlines', 'rgb_split', 'posterize_time', 'echo_trails',
    'vhs_warp', 'fisheye', 'radial_blur', 'noise_reduction',
    'vibrance', 'color_contrast', 'auto_white_balance', 'rgb_channel_mixer',
    'adaptive_sharpen', 'median_denoise', 'temporal_denoise', 'nlmeans_denoise',
    'frame_blend', 'wave_distortion', 'heat_haze', 'film_gate_weave',
    'camera_flash', 'letterbox', 'frame_border', 'old_film', 'analog_glitch',
    'bleach_bypass', 'sepia', 'edge_glow',
    'solarize', 'color_temperature', 'soft_focus', 'ripple_warp',
    'zoom_warp', 'color_key', 'high_pass_sharpen', 'chroma_smear',
  };

  static List<EffectDefinition> get allEffects =>
      List.unmodifiable([...all, ..._extensionEffects.values]);

  static void setExtensionEffects(Iterable<EffectDefinition> effects) {
    _extensionEffects.clear();
    for (final effect in effects) {
      if (all.any((item) => item.id == effect.id) ||
          _extensionEffects.containsKey(effect.id) ||
          effect.extensionId == null ||
          effect.rendererId == null ||
          !extensionSafeRendererIds.contains(effect.rendererId)) {
        throw ArgumentError('Invalid or duplicate extension effect: ' + effect.id);
      }
      _extensionEffects[effect.id] = effect;
    }
  }

  static EffectDefinition? findBuiltin(String id) {
    for (final effect in all) {
      if (effect.id == id) return effect;
    }
    return null;
  }

  static EffectDefinition? find(String id) =>
      findBuiltin(id) ?? _extensionEffects[id];

  static List<String> get categories =>
      allEffects.map((item) => item.category).toSet().toList()..sort();
}
