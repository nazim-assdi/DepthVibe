import '../domain/composition_models.dart';

/// Maps DepthVibe's editor transition catalog to FFmpeg xfade identifiers.
class TransitionCatalog {
  TransitionCatalog._();

  static const Map<TransitionKind, String> xfadeNames = {
    TransitionKind.dissolve: 'fade',
    TransitionKind.fadeThroughColor: 'fade',
    TransitionKind.wipeLeft: 'wipeleft',
    TransitionKind.wipeRight: 'wiperight',
    TransitionKind.wipeUp: 'wipeup',
    TransitionKind.wipeDown: 'wipedown',
    TransitionKind.slideLeft: 'slideleft',
    TransitionKind.slideRight: 'slideright',
    TransitionKind.slideUp: 'slideup',
    TransitionKind.slideDown: 'slidedown',
    TransitionKind.zoomIn: 'zoomin',
    TransitionKind.zoomOut: 'smoothright',
    TransitionKind.blur: 'hblur',
    TransitionKind.luma: 'circleopen',
    TransitionKind.circleCrop: 'circlecrop',
    TransitionKind.rectangleCrop: 'rectcrop',
    TransitionKind.distance: 'distance',
    TransitionKind.fadeBlack: 'fadeblack',
    TransitionKind.fadeWhite: 'fadewhite',
    TransitionKind.radial: 'radial',
    TransitionKind.smoothLeft: 'smoothleft',
    TransitionKind.smoothRight: 'smoothright',
    TransitionKind.smoothUp: 'smoothup',
    TransitionKind.smoothDown: 'smoothdown',
    TransitionKind.circleOpen: 'circleopen',
    TransitionKind.circleClose: 'circleclose',
    TransitionKind.verticalOpen: 'vertopen',
    TransitionKind.verticalClose: 'vertclose',
    TransitionKind.horizontalOpen: 'horzopen',
    TransitionKind.horizontalClose: 'horzclose',
    TransitionKind.pixelize: 'pixelize',
    TransitionKind.diagonalTopLeft: 'diagtl',
    TransitionKind.diagonalTopRight: 'diagtr',
    TransitionKind.diagonalBottomLeft: 'diagbl',
    TransitionKind.diagonalBottomRight: 'diagbr',
    TransitionKind.horizontalLeftSlice: 'hlslice',
    TransitionKind.horizontalRightSlice: 'hrslice',
    TransitionKind.verticalUpSlice: 'vuslice',
    TransitionKind.verticalDownSlice: 'vdslice',
    TransitionKind.horizontalBlur: 'hblur',
    TransitionKind.fadeGrays: 'fadegrays',
    TransitionKind.wipeTopLeft: 'wipetl',
    TransitionKind.wipeTopRight: 'wipetr',
    TransitionKind.wipeBottomLeft: 'wipebl',
    TransitionKind.wipeBottomRight: 'wipebr',
    TransitionKind.squeezeHorizontal: 'squeezeh',
    TransitionKind.squeezeVertical: 'squeezev',
    TransitionKind.fadeFast: 'fadefast',
    TransitionKind.fadeSlow: 'fadeslow',
    TransitionKind.horizontalLeftWind: 'hlwind',
    TransitionKind.horizontalRightWind: 'hrwind',
    TransitionKind.verticalUpWind: 'vuwind',
    TransitionKind.verticalDownWind: 'vdwind',
    TransitionKind.coverLeft: 'coverleft',
    TransitionKind.coverRight: 'coverright',
    TransitionKind.coverUp: 'coverup',
    TransitionKind.coverDown: 'coverdown',
    TransitionKind.revealLeft: 'revealleft',
    TransitionKind.revealRight: 'revealright',
    TransitionKind.revealUp: 'revealup',
    TransitionKind.revealDown: 'revealdown',
  };

  static String xfadeName(TransitionKind kind) => xfadeNames[kind] ?? 'fade';

  static String displayName(TransitionKind kind) {
    const labels = <TransitionKind, String>{
      TransitionKind.dissolve: 'Cross Dissolve',
      TransitionKind.fadeThroughColor: 'Fade Through Color',
      TransitionKind.circleCrop: 'Circle Crop',
      TransitionKind.rectangleCrop: 'Rectangle Crop',
      TransitionKind.fadeBlack: 'Fade to Black',
      TransitionKind.fadeWhite: 'Fade to White',
      TransitionKind.fadeGrays: 'Fade Grays',
      TransitionKind.slideLeft: 'Slide Left',
      TransitionKind.slideRight: 'Slide Right',
      TransitionKind.slideUp: 'Slide Up',
      TransitionKind.slideDown: 'Slide Down',
      TransitionKind.wipeTopLeft: 'Wipe Top Left',
      TransitionKind.wipeTopRight: 'Wipe Top Right',
      TransitionKind.wipeBottomLeft: 'Wipe Bottom Left',
      TransitionKind.wipeBottomRight: 'Wipe Bottom Right',
      TransitionKind.horizontalLeftSlice: 'Horizontal Left Slice',
      TransitionKind.horizontalRightSlice: 'Horizontal Right Slice',
      TransitionKind.verticalUpSlice: 'Vertical Up Slice',
      TransitionKind.verticalDownSlice: 'Vertical Down Slice',
      TransitionKind.horizontalLeftWind: 'Horizontal Left Wind',
      TransitionKind.horizontalRightWind: 'Horizontal Right Wind',
      TransitionKind.verticalUpWind: 'Vertical Up Wind',
      TransitionKind.verticalDownWind: 'Vertical Down Wind',
      TransitionKind.squeezeHorizontal: 'Squeeze Horizontal',
      TransitionKind.squeezeVertical: 'Squeeze Vertical',
    };
    return labels[kind] ?? kind.name
        .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ' + match.group(1)!)
        .split(' ')
        .map((part) => part.isEmpty
            ? part
            : part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  static List<TransitionKind> get all => List.unmodifiable(TransitionKind.values);
}
