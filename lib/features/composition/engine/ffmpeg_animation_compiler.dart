import '../domain/composition_models.dart';

/// Translates native timeline curves into per-frame FFmpeg expressions.
class FfmpegAnimationCompiler {
  const FfmpegAnimationCompiler();

  String scalarExpression({
    required CompositionLayer layer,
    required String property,
    required double fallback,
    String timeVariable = 't',
  }) {
    final tracks = layer.keyframeTracks.where((item) => item.property == property);
    return keyframeExpression(
      tracks.isEmpty ? null : tracks.first,
      fallback: fallback,
      timeVariable: timeVariable,
    );
  }

  String keyframeExpression(
    KeyframeTrack? track, {
    required double fallback,
    String timeVariable = 't',
  }) {
    if (track == null || !track.enabled || track.keyframes.isEmpty) {
      return _n(fallback);
    }
    final frames = [...track.keyframes]
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    if (frames.length == 1) return _n(frames.first.value);

    var expression = _n(frames.last.value);
    for (var i = frames.length - 2; i >= 0; i--) {
      final left = frames[i];
      final right = frames[i + 1];
      final start = left.timeMs / 1000;
      final end = right.timeMs / 1000;
      final span = end - start;
      if (span <= 0) continue;
      final p = '(($timeVariable-' + _n(start) + ')/' + _n(span) + ')';
      final eased = switch (left.interpolation) {
        Interpolation.hold => '0',
        Interpolation.linear => p,
        Interpolation.easeIn => 'pow($p,2)',
        Interpolation.easeOut => '(1-pow(1-$p,2))',
        Interpolation.easeInOut =>
          'if(lt($p,0.5),2*pow($p,2),1-pow(-2*$p+2,2)/2)',
      };
      final value = left.value == right.value
          ? _n(left.value)
          : '(' + _n(left.value) + '+(' + _n(right.value - left.value) + ')*(' + eased + '))';
      expression = 'if(lt($timeVariable,' + _n(end) + '),' + value + ',' + expression + ')';
    }
    return 'if(lt($timeVariable,' + _n(frames.first.timeMs / 1000) + '),' +
        _n(frames.first.value) + ',' + expression + ')';
  }

  String maskAlphaExpression(List<MaskModel> masks) {
    final active = masks.where((item) => item.enabled).toList();
    if (active.isEmpty) return '1';
    var result = '0';
    var first = true;
    for (final mask in active) {
      var shape = _maskShape(mask);
      if (mask.inverted) shape = '(1-(' + shape + '))';
      shape = '((' + shape + ')*' + _n((mask.opacity / 100).clamp(0, 1)) + ')';
      if (first) {
        result = mask.operation == MaskOperation.subtract
            ? '(1-(' + shape + '))'
            : shape;
        first = false;
      } else {
        result = switch (mask.operation) {
          MaskOperation.add => 'max((' + result + '),(' + shape + '))',
          MaskOperation.subtract => '((' + result + ')*(1-(' + shape + ')))',
          MaskOperation.intersect => '((' + result + ')*(' + shape + '))',
          MaskOperation.difference => 'abs((' + result + ')-(' + shape + '))',
        };
      }
    }
    return 'min(1,max(0,' + result + '))';
  }

  String _maskShape(MaskModel mask) {
    final l = _n(mask.left);
    final t = _n(mask.top);
    final r = _n(mask.left + mask.width);
    final b = _n(mask.top + mask.height);
    final e = _n(mask.expansion);
    late final String distance;
    if (mask.shape == MaskShape.ellipse) {
      final cx = '(W*((' + l + '+' + r + ')/2))';
      final cy = '(H*((' + t + '+' + b + ')/2))';
      final rx = 'max(1,W*((' + r + '-' + l + ')/2)+' + e + ')';
      final ry = 'max(1,H*((' + b + '-' + t + ')/2)+' + e + ')';
      distance = '(1-sqrt(pow((X-' + cx + ')/(' + rx + '),2)+pow((Y-' +
          cy + ')/(' + ry + '),2)))*min((' + rx + '),(' + ry + '))';
    } else if ((mask.shape == MaskShape.polygon || mask.shape == MaskShape.bezier) &&
        mask.vertices.length >= 3) {
      final crossings = <String>[];
      final edgeDistances = <String>[];
      for (var i = 0; i < mask.vertices.length; i++) {
        final a = mask.vertices[i].anchor;
        final bPoint = mask.vertices[(i + 1) % mask.vertices.length].anchor;
        final ax = '(W*' + _n(a.x) + ')';
        final ay = '(H*' + _n(a.y) + ')';
        final bx = '(W*' + _n(bPoint.x) + ')';
        final by = '(H*' + _n(bPoint.y) + ')';
        final dx = '(' + bx + '-' + ax + ')';
        final dy = '(' + by + '-' + ay + ')';
        final lengthSquared = '(pow(' + dx + ',2)+pow(' + dy + ',2))';
        final projection = 'clip(((X-' + ax + ')*' + dx + '+(Y-' +
            ay + ')*' + dy + ')/max(0.0001,' + lengthSquared + '),0,1)';
        final closestX = '(' + ax + '+' + projection + '*' + dx + ')';
        final closestY = '(' + ay + '+' + projection + '*' + dy + ')';
        edgeDistances.add('hypot(X-' + closestX + ',Y-' + closestY + ')');
        final xAtY = '(' + ax + '+(Y-' + ay + ')*' + dx +
            '/if(eq(' + dy + ',0),0.0001,' + dy + '))';
        crossings.add('if(lt(' + ay + ',Y),if(gte(' + by + ',Y),if(lt(X,' +
            xAtY + '),1,0),0),if(lt(' + by + ',Y),if(gte(' + ay +
            ',Y),if(lt(X,' + xAtY + '),1,0),0),0))');
      }
      final parity = 'mod(' + crossings.join('+') + ',2)';
      var edgeDistance = edgeDistances.first;
      for (final candidate in edgeDistances.skip(1)) {
        edgeDistance = 'min(' + edgeDistance + ',' + candidate + ')';
      }
      final expandedDistance = '(' + edgeDistance + '+' + _n(mask.expansion) + ')';
      distance = 'if(gt(' + parity + ',0.5),' + expandedDistance +
          ',-(' + expandedDistance + '))';
    } else {
      final x1 = '(W*' + l + '-' + e + ')';
      final x2 = '(W*' + r + '+' + e + ')';
      final y1 = '(H*' + t + '-' + e + ')';
      final y2 = '(H*' + b + '+' + e + ')';
      distance = 'min(min(X-' + x1 + ',' + x2 + '-X),min(Y-' + y1 + ',' + y2 + '-Y))';
    }
    if (mask.feather <= 0) return 'if(gte(' + distance + ',0),1,0)';
    return 'min(1,max(0,0.5+(' + distance + ')/' + _n(mask.feather) + '))';
  }

  String transitionScaleExpression({
    required CompositionLayer layer,
    required List<CompositionTransition> transitions,
    required String baseExpression,
  }) {
    var result = baseExpression;
    for (final item in transitions) {
      if (item.kind == TransitionKind.zoomIn && item.toLayerId == layer.id) {
        result = '(' + result + ')*max(0.01,' + _progress(item, 't') + ')';
      }
      if (item.kind == TransitionKind.zoomOut && item.fromLayerId == layer.id) {
        result = '(' + result + ')*max(0.01,(1-' + _progress(item, 't') + '))';
      }
    }
    return result;
  }

  String transitionPositionExpression({
    required CompositionLayer layer,
    required List<CompositionTransition> transitions,
    required String baseExpression,
    required String axis,
    required int compositionWidth,
    required int compositionHeight,
  }) {
    var result = baseExpression;
    for (final item in transitions) {
      final incoming = item.toLayerId == layer.id;
      final outgoing = item.fromLayerId == layer.id;
      if (!incoming && !outgoing) continue;
      final progress = _progress(item, 't');
      final magnitude = axis == 'x' ? compositionWidth : compositionHeight;
      String? offset;
      switch (item.kind) {
        case TransitionKind.slideLeft:
          if (axis == 'x') {
            offset = incoming
                ? '(' + magnitude.toString() + '*(1-' + progress + '))'
                : '(-' + magnitude.toString() + '*' + progress + ')';
          }
          break;
        case TransitionKind.slideRight:
          if (axis == 'x') {
            offset = incoming
                ? '(-' + magnitude.toString() + '*(1-' + progress + '))'
                : '(' + magnitude.toString() + '*' + progress + ')';
          }
          break;
        default:
          break;
      }
      if (offset != null) result = '(' + result + '+(' + offset + '))';
    }
    return result;
  }

  String transitionAlphaExpression({
    required CompositionLayer layer,
    required List<CompositionTransition> transitions,
  }) {
    var result = '1';
    for (final item in transitions) {
      if (item.durationMs <= 0) continue;
      if (item.toLayerId == layer.id) {
        result = '((' + result + ')*(' + _incoming(item) + '))';
      }
      if (item.fromLayerId == layer.id) {
        result = '((' + result + ')*(' + _outgoing(item) + '))';
      }
    }
    return result;
  }

  String _incoming(CompositionTransition item) {
    final start = item.startMs / 1000;
    final end = (item.startMs + item.durationMs) / 1000;
    final p = _progress(item, 'T');
    if (item.kind == TransitionKind.fadeThroughColor) {
      final half = item.durationMs / 2000;
      return 'if(lt(T,' + _n(start + half) + '),0,min(1,max(0,(T-' +
          _n(start + half) + ')/' + _n(half) + ')))';
    }
    return switch (item.kind) {
      TransitionKind.slideLeft || TransitionKind.slideRight ||
      TransitionKind.zoomIn || TransitionKind.zoomOut => '1',
      TransitionKind.wipeLeft =>
        'if(lt(T,' + _n(start) + '),0,if(gt(T,' + _n(end) + '),1,if(lt(X,W*' + p + '),1,0)))',
      TransitionKind.wipeRight =>
        'if(lt(T,' + _n(start) + '),0,if(gt(T,' + _n(end) + '),1,if(gt(X,W*(1-' + p + ')),1,0)))',
      TransitionKind.wipeUp =>
        'if(lt(T,' + _n(start) + '),0,if(gt(T,' + _n(end) + '),1,if(lt(Y,H*' + p + '),1,0)))',
      TransitionKind.wipeDown =>
        'if(lt(T,' + _n(start) + '),0,if(gt(T,' + _n(end) + '),1,if(gt(Y,H*(1-' + p + ')),1,0)))',
      TransitionKind.luma =>
        'if(lt(T,' + _n(start) + '),0,if(gt(T,' + _n(end) + '),1,if(lt(hypot(X-W/2,Y-H/2),max(W,H)*' + p + '),1,0)))',
      _ => 'if(lt(T,' + _n(start) + '),0,if(gt(T,' + _n(end) + '),1,' + p + '))',
    };
  }

  String _outgoing(CompositionTransition item) {
    final start = item.startMs / 1000;
    final end = (item.startMs + item.durationMs) / 1000;
    final p = _progress(item, 'T');
    if (item.kind == TransitionKind.fadeThroughColor) {
      final half = item.durationMs / 2000;
      return 'if(lt(T,' + _n(start) + '),1,if(gt(T,' + _n(start + half) +
          '),0,1-min(1,max(0,(T-' + _n(start) + ')/' + _n(half) + '))))';
    }
    return switch (item.kind) {
      TransitionKind.slideLeft || TransitionKind.slideRight ||
      TransitionKind.zoomIn || TransitionKind.zoomOut => '1',
      TransitionKind.wipeLeft =>
        'if(lt(T,' + _n(start) + '),1,if(gt(T,' + _n(end) + '),0,if(lt(X,W*' + p + '),0,1)))',
      TransitionKind.wipeRight =>
        'if(lt(T,' + _n(start) + '),1,if(gt(T,' + _n(end) + '),0,if(gt(X,W*(1-' + p + ')),0,1)))',
      TransitionKind.wipeUp =>
        'if(lt(T,' + _n(start) + '),1,if(gt(T,' + _n(end) + '),0,if(lt(Y,H*' + p + '),0,1)))',
      TransitionKind.wipeDown =>
        'if(lt(T,' + _n(start) + '),1,if(gt(T,' + _n(end) + '),0,if(gt(Y,H*(1-' + p + ')),0,1)))',
      TransitionKind.luma =>
        'if(lt(T,' + _n(start) + '),1,if(gt(T,' + _n(end) + '),0,if(lt(hypot(X-W/2,Y-H/2),max(W,H)*' + p + '),0,1)))',
      _ => 'if(lt(T,' + _n(start) + '),1,if(gt(T,' + _n(end) + '),0,1-' + p + '))',
    };
  }

  String _progress(CompositionTransition item, String timeVariable) =>
      'min(1,max(0,(' + timeVariable + '-' + _n(item.startMs / 1000) +
      ')/' + _n(item.durationMs / 1000) + '))';

  String _n(num value) => value.toStringAsFixed(5);
}
