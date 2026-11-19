import '../domain/composition_models.dart';

/// Maps composition blend modes to FFmpeg's built-in blend filter catalog.
class FfmpegBlendModeCompiler {
  const FfmpegBlendModeCompiler();

  String filterMode(LayerBlendMode mode) => switch (mode) {
        LayerBlendMode.normal => 'normal',
        LayerBlendMode.multiply => 'multiply',
        LayerBlendMode.screen => 'screen',
        LayerBlendMode.overlay => 'overlay',
        LayerBlendMode.softLight => 'softlight',
        LayerBlendMode.hardLight => 'hardlight',
        LayerBlendMode.colorDodge => 'dodge',
        LayerBlendMode.colorBurn => 'burn',
        LayerBlendMode.difference => 'difference',
        LayerBlendMode.exclusion => 'exclusion',
        LayerBlendMode.add => 'addition',
        LayerBlendMode.lighten => 'lighten',
        LayerBlendMode.darken => 'darken',
        LayerBlendMode.average => 'average',
        LayerBlendMode.bleach => 'bleach',
        LayerBlendMode.divide => 'divide',
        LayerBlendMode.extremity => 'extremity',
        LayerBlendMode.freeze => 'freeze',
        LayerBlendMode.glow => 'glow',
        LayerBlendMode.grainExtract => 'grainextract',
        LayerBlendMode.grainMerge => 'grainmerge',
        LayerBlendMode.hardMix => 'hardmix',
        LayerBlendMode.hardOverlay => 'hardoverlay',
        LayerBlendMode.heat => 'heat',
        LayerBlendMode.interpolate => 'interpolate',
        LayerBlendMode.linearLight => 'linearlight',
        LayerBlendMode.multiply128 => 'multiply128',
        LayerBlendMode.negation => 'negation',
        LayerBlendMode.bitwiseAnd => 'and',
        LayerBlendMode.bitwiseOr => 'or',
        LayerBlendMode.phoenix => 'phoenix',
        LayerBlendMode.pinLight => 'pinlight',
        LayerBlendMode.reflect => 'reflect',
        LayerBlendMode.softDifference => 'softdifference',
        LayerBlendMode.stain => 'stain',
        LayerBlendMode.subtract => 'subtract',
        LayerBlendMode.vividLight => 'vividlight',
        LayerBlendMode.bitwiseXor => 'xor',
        LayerBlendMode.geometric => 'geometric',
        LayerBlendMode.harmonic => 'harmonic',
      };
}
