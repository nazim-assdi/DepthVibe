import '../domain/composition_models.dart';

/// Curated transition recipes built from DepthVibe's native transition engine.
/// Presets only select a transition type and timing; no third-party binary
/// transition packages are required.
class TransitionPresetDefinition {
  const TransitionPresetDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.kind,
    this.durationMs = 550,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final TransitionKind kind;
  final int durationMs;
}

class TransitionPresetCatalog {
  TransitionPresetCatalog._();

  static const List<TransitionPresetDefinition> all = [
    // CINEMATIC
    TransitionPresetDefinition(id: 'cinema_soft_dissolve', name: 'Soft Cinema Dissolve', category: 'Cinematic', description: 'A gentle, film-style blend between shots.', kind: TransitionKind.dissolve, durationMs: 850),
    TransitionPresetDefinition(id: 'cinema_blackout', name: 'Blackout Cut', category: 'Cinematic', description: 'Dip cleanly through black for a dramatic scene change.', kind: TransitionKind.fadeBlack, durationMs: 620),
    TransitionPresetDefinition(id: 'cinema_white_flash', name: 'White Flash Cut', category: 'Cinematic', description: 'A bright flash between energetic shots.', kind: TransitionKind.fadeWhite, durationMs: 360),
    TransitionPresetDefinition(id: 'cinema_blur_pass', name: 'Cinematic Blur Pass', category: 'Cinematic', description: 'A horizontal blur sweep that blends the new scene.', kind: TransitionKind.horizontalBlur, durationMs: 620),
    TransitionPresetDefinition(id: 'cinema_luma_reveal', name: 'Luma Reveal', category: 'Cinematic', description: 'A soft tonal reveal from one shot to the next.', kind: TransitionKind.luma, durationMs: 700),
    TransitionPresetDefinition(id: 'cinema_smooth_pan', name: 'Smooth Pan Left', category: 'Cinematic', description: 'A flowing directional reveal for travel and montage edits.', kind: TransitionKind.smoothLeft, durationMs: 740),
    TransitionPresetDefinition(id: 'cinema_depth_zoom', name: 'Depth Zoom', category: 'Cinematic', description: 'A centered zoom reveal with a steady visual landing.', kind: TransitionKind.zoomIn, durationMs: 680),
    TransitionPresetDefinition(id: 'cinema_radial', name: 'Radial Cinema', category: 'Cinematic', description: 'Expand the next shot outward from the centre.', kind: TransitionKind.radial, durationMs: 760),

    // SOCIAL / CREATOR
    TransitionPresetDefinition(id: 'social_whip_left', name: 'Whip Left', category: 'Creator', description: 'Fast left-moving transition for short-form edits.', kind: TransitionKind.slideLeft, durationMs: 280),
    TransitionPresetDefinition(id: 'social_whip_right', name: 'Whip Right', category: 'Creator', description: 'Fast right-moving transition for short-form edits.', kind: TransitionKind.slideRight, durationMs: 280),
    TransitionPresetDefinition(id: 'social_pop_zoom', name: 'Pop Zoom', category: 'Creator', description: 'Punch into the next clip with a quick zoom.', kind: TransitionKind.zoomIn, durationMs: 320),
    TransitionPresetDefinition(id: 'social_snap_black', name: 'Snap Through Black', category: 'Creator', description: 'Short black dip timed for a beat cut.', kind: TransitionKind.fadeBlack, durationMs: 220),
    TransitionPresetDefinition(id: 'social_flash_white', name: 'Snap Flash', category: 'Creator', description: 'Quick white-frame flash for a rhythmic cut.', kind: TransitionKind.fadeWhite, durationMs: 180),
    TransitionPresetDefinition(id: 'social_pixel_burst', name: 'Pixel Burst', category: 'Creator', description: 'Break into the next scene with a digital pixel reveal.', kind: TransitionKind.pixelize, durationMs: 460),
    TransitionPresetDefinition(id: 'social_fast_dissolve', name: 'Fast Dissolve', category: 'Creator', description: 'Rapid clean dissolve for punchy montage sequences.', kind: TransitionKind.fadeFast, durationMs: 240),
    TransitionPresetDefinition(id: 'social_vertical_swipe', name: 'Vertical Swipe', category: 'Creator', description: 'Swipe upward into the next clip.', kind: TransitionKind.wipeUp, durationMs: 340),

    // GEOMETRIC / SHAPE
    TransitionPresetDefinition(id: 'shape_iris_open', name: 'Iris Open', category: 'Shape', description: 'Open the new scene through a circular aperture.', kind: TransitionKind.circleOpen, durationMs: 680),
    TransitionPresetDefinition(id: 'shape_iris_close', name: 'Iris Close', category: 'Shape', description: 'Close down to a circular point before revealing the next shot.', kind: TransitionKind.circleClose, durationMs: 680),
    TransitionPresetDefinition(id: 'shape_circle_crop', name: 'Circle Crop Reveal', category: 'Shape', description: 'A bold circular crop across the frame.', kind: TransitionKind.circleCrop, durationMs: 620),
    TransitionPresetDefinition(id: 'shape_rect_crop', name: 'Rectangle Crop', category: 'Shape', description: 'A geometric rectangular opening transition.', kind: TransitionKind.rectangleCrop, durationMs: 620),
    TransitionPresetDefinition(id: 'shape_vertical_split', name: 'Vertical Split Open', category: 'Shape', description: 'Split open from the centre on the vertical axis.', kind: TransitionKind.verticalOpen, durationMs: 620),
    TransitionPresetDefinition(id: 'shape_horizontal_split', name: 'Horizontal Split Open', category: 'Shape', description: 'Split open from the centre on the horizontal axis.', kind: TransitionKind.horizontalOpen, durationMs: 620),
    TransitionPresetDefinition(id: 'shape_diagonal_tl', name: 'Diagonal Top Left', category: 'Shape', description: 'A diagonal wipe entering from the top-left corner.', kind: TransitionKind.diagonalTopLeft, durationMs: 560),
    TransitionPresetDefinition(id: 'shape_diagonal_br', name: 'Diagonal Bottom Right', category: 'Shape', description: 'A diagonal wipe entering from the bottom-right corner.', kind: TransitionKind.diagonalBottomRight, durationMs: 560),

    // DIRECTIONAL / SLICE
    TransitionPresetDefinition(id: 'move_cover_left', name: 'Cover Left', category: 'Directional', description: 'The incoming shot covers the frame from the left.', kind: TransitionKind.coverLeft, durationMs: 520),
    TransitionPresetDefinition(id: 'move_cover_up', name: 'Cover Up', category: 'Directional', description: 'The incoming shot rises to cover the previous shot.', kind: TransitionKind.coverUp, durationMs: 520),
    TransitionPresetDefinition(id: 'move_reveal_right', name: 'Reveal Right', category: 'Directional', description: 'Reveal the next shot while moving toward the right.', kind: TransitionKind.revealRight, durationMs: 520),
    TransitionPresetDefinition(id: 'move_reveal_down', name: 'Reveal Down', category: 'Directional', description: 'Reveal the next shot from the top toward the bottom.', kind: TransitionKind.revealDown, durationMs: 520),
    TransitionPresetDefinition(id: 'move_slice_left', name: 'Horizontal Slice Left', category: 'Directional', description: 'A segmented horizontal wipe for energetic edits.', kind: TransitionKind.horizontalLeftSlice, durationMs: 500),
    TransitionPresetDefinition(id: 'move_slice_up', name: 'Vertical Slice Up', category: 'Directional', description: 'A segmented vertical wipe moving upward.', kind: TransitionKind.verticalUpSlice, durationMs: 500),
    TransitionPresetDefinition(id: 'move_wind_right', name: 'Wind Right', category: 'Directional', description: 'A wind-like segmented sweep toward the right.', kind: TransitionKind.horizontalRightWind, durationMs: 460),
    TransitionPresetDefinition(id: 'move_squeeze', name: 'Squeeze Reveal', category: 'Directional', description: 'Compress one scene and stretch the next into view.', kind: TransitionKind.squeezeHorizontal, durationMs: 540),

    // STYLIZED / EXPERIMENTAL
    TransitionPresetDefinition(id: 'style_fade_grays', name: 'Fade Through Gray', category: 'Stylized', description: 'A desaturated bridge between contrasting scenes.', kind: TransitionKind.fadeGrays, durationMs: 720),
    TransitionPresetDefinition(id: 'style_distance', name: 'Distance Warp', category: 'Stylized', description: 'A warped transition based on distance from the reveal centre.', kind: TransitionKind.distance, durationMs: 650),
    TransitionPresetDefinition(id: 'style_smooth_down', name: 'Smooth Down', category: 'Stylized', description: 'A soft downward motion reveal.', kind: TransitionKind.smoothDown, durationMs: 660),
    TransitionPresetDefinition(id: 'style_fast_wipe', name: 'Fast Wipe', category: 'Stylized', description: 'A fast directional wipe for high-energy cuts.', kind: TransitionKind.wipeRight, durationMs: 260),
    TransitionPresetDefinition(id: 'style_slow_fade', name: 'Slow Atmosphere Fade', category: 'Stylized', description: 'A long, gentle blend for calm transitions.', kind: TransitionKind.fadeSlow, durationMs: 1150),
    TransitionPresetDefinition(id: 'style_vertical_wind', name: 'Vertical Wind', category: 'Stylized', description: 'Layered strips of image sweep vertically.', kind: TransitionKind.verticalDownWind, durationMs: 480),
    TransitionPresetDefinition(id:'native_fadeThroughColor_recipe',name:'Fade Through Colour',category:'Cinematic',description:'DepthVibe native fade through colour transition recipe.',kind:TransitionKind.fadeThroughColor,durationMs:560),
    TransitionPresetDefinition(id:'native_wipeLeft_recipe',name:'Wipe Left',category:'Directional',description:'DepthVibe native wipe left transition recipe.',kind:TransitionKind.wipeLeft,durationMs:340),
    TransitionPresetDefinition(id:'native_wipeDown_recipe',name:'Wipe Down',category:'Directional',description:'DepthVibe native wipe down transition recipe.',kind:TransitionKind.wipeDown,durationMs:340),
    TransitionPresetDefinition(id:'native_slideUp_recipe',name:'Slide Up',category:'Directional',description:'DepthVibe native slide up transition recipe.',kind:TransitionKind.slideUp,durationMs:340),
    TransitionPresetDefinition(id:'native_slideDown_recipe',name:'Slide Down',category:'Directional',description:'DepthVibe native slide down transition recipe.',kind:TransitionKind.slideDown,durationMs:340),
    TransitionPresetDefinition(id:'native_zoomOut_recipe',name:'Zoom Out',category:'Stylized',description:'DepthVibe native zoom out transition recipe.',kind:TransitionKind.zoomOut,durationMs:560),
    TransitionPresetDefinition(id:'native_blur_recipe',name:'Blur',category:'Stylized',description:'DepthVibe native blur transition recipe.',kind:TransitionKind.blur,durationMs:560),
    TransitionPresetDefinition(id:'native_smoothRight_recipe',name:'Smooth Right',category:'Creator',description:'DepthVibe native smooth right transition recipe.',kind:TransitionKind.smoothRight,durationMs:900),
    TransitionPresetDefinition(id:'native_smoothUp_recipe',name:'Smooth Up',category:'Creator',description:'DepthVibe native smooth up transition recipe.',kind:TransitionKind.smoothUp,durationMs:900),
    TransitionPresetDefinition(id:'native_verticalClose_recipe',name:'Vertical Close',category:'Shape',description:'DepthVibe native vertical close transition recipe.',kind:TransitionKind.verticalClose,durationMs:560),
    TransitionPresetDefinition(id:'native_horizontalClose_recipe',name:'Horizontal Close',category:'Shape',description:'DepthVibe native horizontal close transition recipe.',kind:TransitionKind.horizontalClose,durationMs:560),
    TransitionPresetDefinition(id:'native_diagonalTopRight_recipe',name:'Diagonal Top Right',category:'Shape',description:'DepthVibe native diagonal top right transition recipe.',kind:TransitionKind.diagonalTopRight,durationMs:560),
    TransitionPresetDefinition(id:'native_diagonalBottomLeft_recipe',name:'Diagonal Bottom Left',category:'Shape',description:'DepthVibe native diagonal bottom left transition recipe.',kind:TransitionKind.diagonalBottomLeft,durationMs:560),
    TransitionPresetDefinition(id:'native_horizontalRightSlice_recipe',name:'Horizontal Right Slice',category:'Creator',description:'DepthVibe native horizontal right slice transition recipe.',kind:TransitionKind.horizontalRightSlice,durationMs:560),
    TransitionPresetDefinition(id:'native_verticalDownSlice_recipe',name:'Vertical Down Slice',category:'Creator',description:'DepthVibe native vertical down slice transition recipe.',kind:TransitionKind.verticalDownSlice,durationMs:560),
    TransitionPresetDefinition(id:'native_wipeTopLeft_recipe',name:'Wipe Top Left',category:'Directional',description:'DepthVibe native wipe top left transition recipe.',kind:TransitionKind.wipeTopLeft,durationMs:340),
    TransitionPresetDefinition(id:'native_wipeTopRight_recipe',name:'Wipe Top Right',category:'Directional',description:'DepthVibe native wipe top right transition recipe.',kind:TransitionKind.wipeTopRight,durationMs:340),
    TransitionPresetDefinition(id:'native_wipeBottomLeft_recipe',name:'Wipe Bottom Left',category:'Directional',description:'DepthVibe native wipe bottom left transition recipe.',kind:TransitionKind.wipeBottomLeft,durationMs:340),
    TransitionPresetDefinition(id:'native_wipeBottomRight_recipe',name:'Wipe Bottom Right',category:'Directional',description:'DepthVibe native wipe bottom right transition recipe.',kind:TransitionKind.wipeBottomRight,durationMs:340),
    TransitionPresetDefinition(id:'native_squeezeVertical_recipe',name:'Vertical Squeeze',category:'Directional',description:'DepthVibe native vertical squeeze transition recipe.',kind:TransitionKind.squeezeVertical,durationMs:560),
    TransitionPresetDefinition(id:'native_horizontalLeftWind_recipe',name:'Horizontal Left Wind',category:'Creator',description:'DepthVibe native horizontal left wind transition recipe.',kind:TransitionKind.horizontalLeftWind,durationMs:560),
    TransitionPresetDefinition(id:'native_verticalUpWind_recipe',name:'Vertical Up Wind',category:'Creator',description:'DepthVibe native vertical up wind transition recipe.',kind:TransitionKind.verticalUpWind,durationMs:560),
    TransitionPresetDefinition(id:'native_coverRight_recipe',name:'Cover Right',category:'Directional',description:'DepthVibe native cover right transition recipe.',kind:TransitionKind.coverRight,durationMs:560),
    TransitionPresetDefinition(id:'native_coverDown_recipe',name:'Cover Down',category:'Directional',description:'DepthVibe native cover down transition recipe.',kind:TransitionKind.coverDown,durationMs:560),
    TransitionPresetDefinition(id:'native_revealLeft_recipe',name:'Reveal Left',category:'Directional',description:'DepthVibe native reveal left transition recipe.',kind:TransitionKind.revealLeft,durationMs:560),
    TransitionPresetDefinition(id:'native_revealUp_recipe',name:'Reveal Up',category:'Directional',description:'DepthVibe native reveal up transition recipe.',kind:TransitionKind.revealUp,durationMs:560),
  ];

  static TransitionPresetDefinition? find(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  static List<String> get categories =>
      all.map((preset) => preset.category).toSet().toList()..sort();
}
