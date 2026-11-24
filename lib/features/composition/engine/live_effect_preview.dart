import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../data/effect_catalog.dart';
import '../domain/composition_models.dart';
import 'color_grade_preview.dart';
import 'cube_lut_validator.dart';

/// GPU-backed, playhead-aware preview for every built-in DepthVibe effect.
///
/// Each effect uses the same EffectInstance and parameter keyframe track as
/// the native export compiler. When the active renderer cannot run Flutter
/// image shaders, a lightweight Flutter fallback is used instead.
class LiveEffectPreview {
  const LiveEffectPreview._();

  static const Map<String, double> _shaderCodes = {
    'brightness': 1,
    'contrast': 2,
    'saturation': 3,
    'gamma': 4,
    'gaussian_blur': 5,
    'box_blur': 6,
    'sharpen': 7,
    'vignette': 8,
    'film_grain': 9,
    'pixelate': 10,
    'threshold': 11,
    'invert': 12,
    'grayscale': 13,
    'chromatic_aberration': 14,
    'edge_detect': 15,
    'mirror': 16,
    'flip': 17,
    'drop_shadow': 18,
    'glow': 19,
    'displacement': 20,
    'particle_dust': 21,
    'motion_blur': 22,
    'lens_distortion': 23,
    'transform': 24,
    'chroma_key': 25,
    'luma_key': 26,
    'stabilize': 27,
    'posterize': 28,
    'color_balance': 29,
    'color_curves': 30,
    'color_lut': 31,
    'color_grade': 32,
    'exposure': 33,
    'hue_rotate': 34,
    'colorize': 35,
    'directional_blur': 36,
    'average_blur': 37,
    'chroma_denoise': 38,
    'deband': 39,
    'deflicker': 40,
    'scanlines': 41,
    'rgb_split': 42,
    'posterize_time': 43,
    'echo_trails': 44,
    'vhs_warp': 45,
    'fisheye': 46,
    'radial_blur': 47,
    'noise_reduction': 48,
    'vibrance': 49,
    'color_contrast': 50,
    'auto_white_balance': 51,
    'rgb_channel_mixer': 52,
    'adaptive_sharpen': 53,
    'median_denoise': 54,
    'temporal_denoise': 55,
    'nlmeans_denoise': 56,
    'frame_blend': 57,
    'wave_distortion': 58,
    'heat_haze': 59,
    'film_gate_weave': 60,
    'camera_flash': 61,
    'letterbox': 62,
    'frame_border': 63,
    'old_film': 64,
    'analog_glitch': 65,
    'bleach_bypass': 66,
    'sepia': 67,
    'edge_glow': 68,
  };

  static bool supports(String effectId) => _shaderCodes.containsKey(effectId);

  static int get builtInEffectCount => _shaderCodes.length;

  static List<double>? colorMatrixFor(EffectInstance effect, int timeMs) {
    double value(String id, double fallback) =>
        effect.parameterAt(id, timeMs, fallback: fallback);
    switch (effect.effectId) {
      case 'brightness':
        final lift = value('value', 0).clamp(-1.0, 1.0).toDouble() * 255;
        return _matrix(1, 0, 0, 0, lift, 0, 1, 0, 0, lift, 0, 0, 1, 0, lift);
      case 'contrast':
        final amount = value('value', 1).clamp(0.0, 3.0).toDouble();
        final offset = 128 * (1 - amount);
        return _matrix(amount, 0, 0, 0, offset, 0, amount, 0, 0, offset, 0, 0, amount, 0, offset);
      case 'saturation':
        return _saturation(value('value', 1).clamp(0.0, 3.0).toDouble());
      case 'grayscale':
        return _saturation(0);
      case 'invert':
        return _matrix(-1, 0, 0, 0, 255, 0, -1, 0, 0, 255, 0, 0, -1, 0, 255);
      case 'sepia':
        return const [
          0.393, 0.769, 0.189, 0, 0,
          0.349, 0.686, 0.168, 0, 0,
          0.272, 0.534, 0.131, 0, 0,
          0, 0, 0, 1, 0,
        ];
      case 'color_balance':
        return _matrix(
          1, 0, 0, 0, value('red', 0) * 96,
          0, 1, 0, 0, value('green', 0) * 96,
          0, 0, 1, 0, value('blue', 0) * 96,
        );
      case 'color_contrast':
        final r = 1 + value('red', 0);
        final g = 1 + value('green', 0);
        final b = 1 + value('blue', 0);
        return _matrix(r, 0, 0, 0, 128 * (1-r), 0, g, 0, 0, 128 * (1-g), 0, 0, b, 0, 128 * (1-b));
      case 'camera_flash':
        final lift = value('brightness', 0.35).clamp(0.0, 2.0).toDouble() * 90;
        return _matrix(1, 0, 0, 0, lift, 0, 1, 0, 0, lift, 0, 0, 1, 0, lift);
      case 'exposure':
        final gain = math.pow(2, value('value', 0).clamp(-3.0, 3.0)).toDouble();
        return _matrix(gain, 0, 0, 0, 0, 0, gain, 0, 0, 0, 0, 0, gain, 0, 0);
      case 'hue_rotate':
        final angle = value('degrees', 0) * math.pi / 180;
        final cs = math.cos(angle);
        final sn = math.sin(angle);
        const lumR = 0.213, lumG = 0.715, lumB = 0.072;
        return _matrix(
          lumR + cs * (1-lumR) + sn * (-lumR),
          lumG + cs * (-lumG) + sn * (-lumG),
          lumB + cs * (-lumB) + sn * (1-lumB), 0, 0,
          lumR + cs * (-lumR) + sn * 0.143,
          lumG + cs * (1-lumG) + sn * 0.140,
          lumB + cs * (-lumB) + sn * (-0.283), 0, 0,
          lumR + cs * (-lumR) + sn * (-(1-lumR)),
          lumG + cs * (-lumG) + sn * lumG,
          lumB + cs * (1-lumB) + sn * lumB, 0, 0,
        );
      case 'vibrance':
        final amount = value('intensity', 0.5).clamp(0.0, 3.0).toDouble();
        return _saturation(1 + amount * 0.35);
      case 'rgb_channel_mixer':
        return _matrix(
          value('rr', 1), value('rg', 0), value('rb', 0), 0, 0,
          value('gr', 0), value('gg', 1), value('gb', 0), 0, 0,
          value('br', 0), value('bg', 0), value('bb', 1), 0, 0,
        );
      case 'bleach_bypass':
        final amount = value('saturation', 0.45).clamp(0.0, 1.0).toDouble();
        final contrast = value('contrast', 1.35).clamp(0.5, 2.5).toDouble();
        return _compose(_saturation(amount), _matrix(
          contrast, 0, 0, 0, 128 * (1-contrast),
          0, contrast, 0, 0, 128 * (1-contrast),
          0, 0, contrast, 0, 128 * (1-contrast),
        ));
      default:
        return null;
    }
  }

  static Widget apply({
    required Widget child,
    required List<EffectInstance> effects,
    required int timeMs,
    required Size canvasSize,
  }) {
    final active = effects.where((item) => item.enabled && supports(item.effectId)).toList();
    if (active.isEmpty) return child;
    return _LiveEffectStack(
      child: child,
      effects: active,
      timeMs: timeMs,
      canvasSize: canvasSize,
    );
  }

  static List<double> _saturation(double amount) {
    const r = 0.213, g = 0.715, b = 0.072;
    final inverse = 1 - amount;
    return _matrix(
      r*inverse+amount, g*inverse, b*inverse, 0, 0,
      r*inverse, g*inverse+amount, b*inverse, 0, 0,
      r*inverse, g*inverse, b*inverse+amount, 0, 0,
    );
  }

  static List<double> _matrix(
    double r0,double r1,double r2,double r3,double r4,
    double g0,double g1,double g2,double g3,double g4,
    double b0,double b1,double b2,double b3,double b4,
  ) => [
    r0,r1,r2,r3,r4, g0,g1,g2,g3,g4,
    b0,b1,b2,b3,b4, 0,0,0,1,0,
  ];

  static List<double> _compose(List<double> first,List<double> second) {
    final result=List<double>.filled(20,0);
    for(var row=0;row<4;row++){
      for(var col=0;col<5;col++){
        var sum=0.0;
        for(var inner=0;inner<4;inner++){
          sum+=second[row*5+inner]*first[inner*5+col];
        }
        if(col==4) sum+=second[row*5+4];
        result[row*5+col]=sum;
      }
    }
    return result;
  }
}

class _LiveEffectStack extends StatefulWidget {
  const _LiveEffectStack({
    required this.child,
    required this.effects,
    required this.timeMs,
    required this.canvasSize,
  });

  final Widget child;
  final List<EffectInstance> effects;
  final int timeMs;
  final Size canvasSize;

  @override
  State<_LiveEffectStack> createState() => _LiveEffectStackState();
}

class _LiveEffectStackState extends State<_LiveEffectStack> {
  static final Future<ui.FragmentProgram> _program =
      ui.FragmentProgram.fromAsset('shaders/live_effect_preview.frag');
  static final Future<ui.FragmentProgram> _lutProgram =
      ui.FragmentProgram.fromAsset('shaders/lut_preview.frag');

  final Map<String, ui.FragmentShader> _shaders = {};
  final Map<String, ui.FragmentShader> _lutShaders = {};
  final Map<String, _LutImageData> _lutImages = {};
  final Map<String, String> _lutRequests = {};

  @override
  void initState() {
    super.initState();
    unawaited(_syncLutImages());
  }

  @override
  void didUpdateWidget(covariant _LiveEffectStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    unawaited(_syncLutImages());
  }

  Future<void> _syncLutImages() async {
    final active = <String, String>{};
    for (final effect in widget.effects.where((item) => item.effectId == 'color_lut')) {
      final path = effect.assetUri;
      if (path == null || path.trim().isEmpty) continue;
      active[effect.id] = path;
      if (_lutRequests[effect.id] == path) continue;
      _lutRequests[effect.id] = path;
      _lutImages.remove(effect.id)?.image.dispose();
      _lutShaders.remove(effect.id)?.dispose();
      try {
        final image = await _loadCubeLut(path);
        if (!mounted || _lutRequests[effect.id] != path) {
          image.image.dispose();
          continue;
        }
        _lutImages[effect.id] = image;
        setState(() {});
      } catch (error) {
        debugPrint('DepthVibe live LUT preview skipped for $path: $error');
      }
    }
    for (final id in _lutRequests.keys.toList()) {
      if (active.containsKey(id)) continue;
      _lutRequests.remove(id);
      _lutImages.remove(id)?.image.dispose();
      _lutShaders.remove(id)?.dispose();
    }
  }

  Future<_LutImageData> _loadCubeLut(String path) async {
    final contents = await File(path).readAsString();
    final info = CubeLutValidator.parse(contents);
    var domainMin = <double>[0, 0, 0];
    var domainMax = <double>[1, 1, 1];
    final values = <List<double>>[];
    for (final raw in contents.split(RegExp(r'\\r?\\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') ||
          line.startsWith('TITLE ') || line.startsWith('LUT_3D_SIZE') ||
          line.startsWith('DOMAIN_MIN') || line.startsWith('DOMAIN_MAX')) {
        if (line.startsWith('DOMAIN_MIN')) {
          domainMin = line.split(RegExp(r'\\s+')).skip(1).map(double.parse).toList();
        } else if (line.startsWith('DOMAIN_MAX')) {
          domainMax = line.split(RegExp(r'\\s+')).skip(1).map(double.parse).toList();
        }
        continue;
      }
      final parts = line.split(RegExp(r'\\s+'));
      if (parts.length == 3) {
        values.add(parts.map(double.parse).toList());
      }
    }
    final n = info.size;
    if (values.length != n * n * n) {
      throw const FormatException('The .cube LUT data rows changed during live preview loading.');
    }
    final width = n * n;
    final bytes = Uint8List(width * n * 4);
    for (var blue = 0; blue < n; blue++) {
      for (var green = 0; green < n; green++) {
        for (var red = 0; red < n; red++) {
          final sample = values[(blue * n * n) + (green * n) + red];
          final target = ((green * width) + (blue * n + red)) * 4;
          bytes[target] = (sample[0].clamp(0.0, 1.0) * 255).round();
          bytes[target + 1] = (sample[1].clamp(0.0, 1.0) * 255).round();
          bytes[target + 2] = (sample[2].clamp(0.0, 1.0) * 255).round();
          bytes[target + 3] = 255;
        }
      }
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: n,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    try {
      final codec = await descriptor.instantiateCodec();
      try {
        final frame = await codec.getNextFrame();
        return _LutImageData(
          image: frame.image,
          size: n,
          domainMin: domainMin,
          domainMax: domainMax,
        );
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }

  @override
  void dispose() {
    for (final shader in _shaders.values) {
      shader.dispose();
    }
    for (final shader in _lutShaders.values) {
      shader.dispose();
    }
    for (final lut in _lutImages.values) {
      lut.image.dispose();
    }
    _shaders.clear();
    _lutShaders.clear();
    _lutImages.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ui.ImageFilter.isShaderFilterSupported) {
      return _fallback(widget.child);
    }
    return FutureBuilder<ui.FragmentProgram>(
      future: _program,
      builder: (context, snapshot) {
        final program = snapshot.data;
        if (program == null || snapshot.hasError) {
          return _fallback(widget.child);
        }
        Widget result = widget.child;
        for (final effect in widget.effects) {
          if (effect.effectId == 'color_lut') {
            result = _applyLut(result, effect);
            continue;
          }
          final code = LiveEffectPreview._shaderCodes[effect.effectId];
          final definition = EffectCatalog.find(effect.effectId);
          if (code == null || definition == null) {
            result = _fallbackEffect(result, effect);
            continue;
          }
          final shader = _shaders.putIfAbsent(
            effect.id,
            () => program.fragmentShader(),
          );
          shader.setFloat(2, code);
          shader.setFloat(3, widget.timeMs / 1000.0);
          final values = <double>[
            for (final parameter in definition.parameters)
              effect.parameterAt(
                parameter.id,
                widget.timeMs,
                fallback: parameter.defaultValue,
              ),
          ];
          for (var index = 0; index < 24; index++) {
            shader.setFloat(4 + index, index < values.length ? values[index] : 0);
          }
          result = ImageFiltered(
            imageFilter: ui.ImageFilter.shader(
              shader,
              filterQuality: ui.FilterQuality.medium,
            ),
            child: result,
          );
        }
        return result;
      },
    );
  }

  Widget _applyLut(Widget child, EffectInstance effect) {
    final texture = _lutImages[effect.id];
    if (texture == null) return child;
    return FutureBuilder<ui.FragmentProgram>(
      future: _lutProgram,
      builder: (context, snapshot) {
        final program = snapshot.data;
        if (program == null || snapshot.hasError) return child;
        final shader = _lutShaders.putIfAbsent(
          effect.id,
          () => program.fragmentShader(),
        );
        shader.setFloat(2, texture.size.toDouble());
        for (var index = 0; index < 3; index++) {
          shader.setFloat(3 + index, texture.domainMin[index]);
          shader.setFloat(6 + index, texture.domainMax[index]);
        }
        shader.setImageSampler(
          1,
          texture.image,
          filterQuality: ui.FilterQuality.none,
        );
        return ImageFiltered(
          imageFilter: ui.ImageFilter.shader(
            shader,
            filterQuality: ui.FilterQuality.medium,
          ),
          child: child,
        );
      },
    );
  }

  Widget _fallback(Widget child) {
    var result = child;
    for (final effect in widget.effects) {
      result = _fallbackEffect(result, effect);
    }
    return result;
  }

  Widget _fallbackEffect(Widget child, EffectInstance effect) {
    double value(String id, double fallback) =>
        effect.parameterAt(id, widget.timeMs, fallback: fallback);
    final matrix = LiveEffectPreview.colorMatrixFor(effect, widget.timeMs);
    if (matrix != null) {
      child = ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: child);
    }
    if (effect.effectId == 'color_grade') {
      final filter = ColorGradePreview.filterFor(effect, widget.timeMs);
      if (filter != null) child = ColorFiltered(colorFilter: filter, child: child);
    }
    if (effect.effectId == 'colorize') {
      final hue = value('hue', 210).clamp(0.0, 360.0).toDouble();
      final saturation = value('saturation', 0.65).clamp(0.0, 1.0).toDouble();
      final lightness = (0.7 + value('lightness', 0)).clamp(0.0, 1.0).toDouble();
      final tint = HSVColor.fromAHSV(1, hue, saturation, lightness).toColor();
      child = ColorFiltered(
        colorFilter: ColorFilter.mode(
          tint.withOpacity(value('mix', 0.5).clamp(0.0, 1.0).toDouble()),
          BlendMode.color,
        ),
        child: child,
      );
    }
    switch (effect.effectId) {
      case 'gaussian_blur':
      case 'box_blur':
      case 'average_blur':
      case 'directional_blur':
      case 'radial_blur':
        final radius = effect.parameters.values.firstOrNull ?? 2;
        final sigma = radius.clamp(0.0, 30.0).toDouble();
        if (sigma > 0) {
          child = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: sigma,
              sigmaY: effect.effectId == 'directional_blur' ? sigma * 0.18 : sigma,
            ),
            child: child,
          );
        }
        break;
      case 'transform':
        child = Transform.rotate(
          angle: value('rotation', 0) * math.pi / 180,
          child: Transform.scale(
            scale: value('scale', 100).clamp(0.0, 400.0).toDouble() / 100,
            child: child,
          ),
        );
        break;
      case 'mirror':
        child = Transform.flip(flipX: true, child: child);
        break;
      case 'flip':
        child = Transform.flip(flipY: true, child: child);
        break;
      case 'letterbox':
        final ratio = value('ratio', 0.1).clamp(0.02, 0.2).toDouble();
        child = Stack(fit: StackFit.passthrough, children: [
          child,
          Positioned(left: 0,right: 0,top: 0,height: widget.canvasSize.height*ratio,
            child: const IgnorePointer(child: ColoredBox(color: Color(0xFF000000)))),
          Positioned(left: 0,right: 0,bottom: 0,height: widget.canvasSize.height*ratio,
            child: const IgnorePointer(child: ColoredBox(color: Color(0xFF000000)))),
        ]);
        break;
      case 'frame_border':
        child = Container(
          foregroundDecoration: BoxDecoration(
            border: Border.all(
              color: Color.fromRGBO(255,255,255,value('opacity',0.8).clamp(0.0,1.0).toDouble()),
              width: value('thickness',6).clamp(1.0,30.0).toDouble(),
            ),
          ),
          child: child,
        );
        break;
      case 'vignette':
        final strength=(value('angle',0.8)/1.5).clamp(0.0,1.0).toDouble();
        child=Stack(fit:StackFit.passthrough,children:[
          child,
          Positioned.fill(child:IgnorePointer(child:DecoratedBox(
            decoration:BoxDecoration(gradient:RadialGradient(
              radius:0.88,
              colors:[const Color(0x00000000),Color.fromRGBO(0,0,0,strength*0.78)],
              stops:const [0.42,1],
            )),
          ))),
        ]);
        break;
      case 'film_grain':
      case 'particle_dust':
      case 'scanlines':
      case 'old_film':
      case 'analog_glitch':
      case 'wave_distortion':
      case 'heat_haze':
        child = CustomPaint(
          foregroundPainter: _FallbackTexturePainter(
            effectId: effect.effectId,
            timeMs: widget.timeMs,
          ),
          child: child,
        );
        break;
    }
    return child;
  }
}

class _FallbackTexturePainter extends CustomPainter {
  const _FallbackTexturePainter({required this.effectId,required this.timeMs});
  final String effectId;
  final int timeMs;

  @override
  void paint(Canvas canvas,Size size) {
    final p=Paint();
    if(effectId=='scanlines'){
      p.color=const Color(0x44000000);
      for(double y=0;y<size.height;y+=4){canvas.drawRect(Rect.fromLTWH(0,y,size.width,1),p);}
    } else if(effectId=='film_grain'||effectId=='old_film'||effectId=='analog_glitch'||effectId=='particle_dust'){
      p.color=const Color(0x66FFFFFF);
      for(var i=0;i<70;i++){
        final x=((i*37+(timeMs~/50))%101)/101*size.width;
        final y=((i*61+(timeMs~/70))%97)/97*size.height;
        canvas.drawCircle(Offset(x,y),i%4==0?1.0:0.45,p);
      }
    } else {
      final path=Path();
      for(double x=0;x<=size.width;x+=3){
        final y=size.height*0.5+math.sin(x/13+timeMs/180)*4;
        if(x==0)path.moveTo(x,y);else path.lineTo(x,y);
      }
      canvas.drawPath(path,p..color=const Color(0x667DD9FF)..style=PaintingStyle.stroke..strokeWidth=1);
    }
  }

  @override
  bool shouldRepaint(covariant _FallbackTexturePainter oldDelegate) =>
      oldDelegate.effectId!=effectId||oldDelegate.timeMs!=timeMs;
}


class _LutImageData {
  const _LutImageData({
    required this.image,
    required this.size,
    required this.domainMin,
    required this.domainMax,
  });

  final ui.Image image;
  final int size;
  final List<double> domainMin;
  final List<double> domainMax;
}
