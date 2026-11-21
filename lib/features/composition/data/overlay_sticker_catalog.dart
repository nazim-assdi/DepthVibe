/// Native visual overlay recipes and editable typographic sticker layers.
class OverlayStickerDefinition {
  const OverlayStickerDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    this.effectId,
    this.textContent = '',
    this.fontSize = 90,
    this.fontWeight = 800,
    this.textColor = '#FFFFFFFF',
    this.letterSpacing = 0,
    this.positionX = 960,
    this.positionY = 540,
    this.motionPresetId = 'fade_in',
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final String? effectId;
  final String textContent;
  final double fontSize;
  final int fontWeight;
  final String textColor;
  final double letterSpacing;
  final double positionX;
  final double positionY;
  final String motionPresetId;

  bool get isEffectOverlay => effectId != null;
}

class OverlayStickerCatalog {
  OverlayStickerCatalog._();

  static const List<OverlayStickerDefinition> all = [
    // FILM / TEXTURE OVERLAYS (apply a native effect to the selected visual layer)
    OverlayStickerDefinition(id:'overlay_film_grain',name:'Fine Film Grain',category:'Film Overlays',description:'Add a fine organic film texture.',effectId:'film_grain'),
    OverlayStickerDefinition(id:'overlay_old_film',name:'Old Film Texture',category:'Film Overlays',description:'Warm grain and aged film character.',effectId:'old_film'),
    OverlayStickerDefinition(id:'overlay_gate_weave',name:'Film Gate Weave',category:'Film Overlays',description:'Subtle animated gate movement.',effectId:'film_gate_weave'),
    OverlayStickerDefinition(id:'overlay_dust',name:'Dust & Particles',category:'Film Overlays',description:'Procedural floating dust particles.',effectId:'particle_dust'),
    OverlayStickerDefinition(id:'overlay_vignette',name:'Soft Vignette',category:'Film Overlays',description:'Darken frame edges for visual focus.',effectId:'vignette'),
    OverlayStickerDefinition(id:'overlay_letterbox',name:'Cinematic Letterbox',category:'Film Overlays',description:'Add cinematic top and bottom bars.',effectId:'letterbox'),
    OverlayStickerDefinition(id:'overlay_border',name:'Frame Border',category:'Film Overlays',description:'Add a clean frame outline.',effectId:'frame_border'),
    OverlayStickerDefinition(id:'overlay_scanlines',name:'Scanline Texture',category:'Retro Overlays',description:'CRT-style horizontal scanlines.',effectId:'scanlines'),
    OverlayStickerDefinition(id:'overlay_vhs',name:'VHS Tape Warp',category:'Retro Overlays',description:'Analog tape distortion and noise.',effectId:'vhs_warp'),
    OverlayStickerDefinition(id:'overlay_rgb_split',name:'RGB Split',category:'Retro Overlays',description:'Offset the red, green and blue channels.',effectId:'rgb_split'),
    OverlayStickerDefinition(id:'overlay_glitch',name:'Digital Glitch',category:'Retro Overlays',description:'Noisy digital signal corruption.',effectId:'analog_glitch'),
    OverlayStickerDefinition(id:'overlay_film_flicker',name:'Film Flicker',category:'Retro Overlays',description:'Old projector style flashing exposure.',effectId:'deflicker'),
    OverlayStickerDefinition(id:'overlay_flash',name:'Camera Flash',category:'Light & Lens',description:'Flash-frame highlight accent.',effectId:'camera_flash'),
    OverlayStickerDefinition(id:'overlay_glow',name:'Soft Light Bloom',category:'Light & Lens',description:'Glow bright highlights.',effectId:'glow'),
    OverlayStickerDefinition(id:'overlay_edge_glow',name:'Neon Edge Light',category:'Light & Lens',description:'Glowing edge accents.',effectId:'edge_glow'),
    OverlayStickerDefinition(id:'overlay_chromatic',name:'Lens Chromatic Fringe',category:'Light & Lens',description:'Optical RGB fringe around details.',effectId:'chromatic_aberration'),
    OverlayStickerDefinition(id:'overlay_heat',name:'Heat Haze',category:'Light & Lens',description:'Shimmering heat-wave distortion.',effectId:'heat_haze'),
    OverlayStickerDefinition(id:'overlay_wave',name:'Wave Ripple',category:'Light & Lens',description:'Procedural animated wave distortion.',effectId:'wave_distortion'),
    OverlayStickerDefinition(id:'overlay_radial',name:'Radial Motion Blur',category:'Light & Lens',description:'Radial motion streak treatment.',effectId:'radial_blur'),
    OverlayStickerDefinition(id:'overlay_directional',name:'Directional Streak',category:'Light & Lens',description:'Directional blur accents.',effectId:'directional_blur'),
    OverlayStickerDefinition(id:'overlay_fisheye',name:'Fisheye Lens',category:'Light & Lens',description:'Wide-angle barrel lens distortion.',effectId:'fisheye'),
    OverlayStickerDefinition(id:'overlay_pixel',name:'Pixel Mosaic',category:'Graphic Overlays',description:'Pixelated graphic texture.',effectId:'pixelate'),
    OverlayStickerDefinition(id:'overlay_poster',name:'Poster Texture',category:'Graphic Overlays',description:'Posterized color treatment.',effectId:'posterize'),
    OverlayStickerDefinition(id:'overlay_sepia',name:'Sepia Wash',category:'Graphic Overlays',description:'Vintage warm monochrome wash.',effectId:'sepia'),
    OverlayStickerDefinition(id:'overlay_bleach',name:'Bleach Bypass',category:'Graphic Overlays',description:'High contrast desaturated film treatment.',effectId:'bleach_bypass'),
    OverlayStickerDefinition(id:'overlay_invert',name:'Negative Film',category:'Graphic Overlays',description:'Invert image color values.',effectId:'invert'),
    OverlayStickerDefinition(id:'overlay_mirror',name:'Mirror Frame',category:'Graphic Overlays',description:'Mirror the image for a split-screen look.',effectId:'mirror'),
    OverlayStickerDefinition(id:'overlay_displacement',name:'Liquid Displacement',category:'Graphic Overlays',description:'Animated displacement map distortion.',effectId:'displacement'),
    OverlayStickerDefinition(id:'overlay_motion_blur',name:'Motion Blur',category:'Graphic Overlays',description:'Add temporal motion streak blending.',effectId:'motion_blur'),
    OverlayStickerDefinition(id:'overlay_noise_clean',name:'Clean Noise',category:'Graphic Overlays',description:'Reduce visible image noise.',effectId:'noise_reduction'),

    // STICKERS: SYMBOLS / SPARKS
    OverlayStickerDefinition(id:'sticker_star',name:'Star',category:'Symbols & Sparkles',description:'A simple decorative star.',textContent:'★',fontSize:126,textColor:'#FFFFD477',motionPresetId:'pop_bounce',positionX:1480,positionY:260),
    OverlayStickerDefinition(id:'sticker_outline_star',name:'Outline Star',category:'Symbols & Sparkles',description:'Lightweight outline star.',textContent:'☆',fontSize:132,textColor:'#FFFFFFFF',motionPresetId:'spin_pop_in',positionX:1480,positionY:260),
    OverlayStickerDefinition(id:'sticker_sparkle',name:'Sparkle',category:'Symbols & Sparkles',description:'Four-point sparkle ornament.',textContent:'✦',fontSize:116,textColor:'#FFFFE89A',motionPresetId:'pulse_soft',positionX:1450,positionY:300),
    OverlayStickerDefinition(id:'sticker_sparkle_small',name:'Small Sparkle',category:'Symbols & Sparkles',description:'Small clean sparkle glyph.',textContent:'✧',fontSize:100,textColor:'#FFFFFFFF',motionPresetId:'heartbeat',positionX:1450,positionY:300),
    OverlayStickerDefinition(id:'sticker_burst',name:'Starburst',category:'Symbols & Sparkles',description:'Bold starburst accent.',textContent:'✺',fontSize:132,textColor:'#FFFFB56C',motionPresetId:'zoom_bounce'),
    OverlayStickerDefinition(id:'sticker_flower',name:'Flower Ornament',category:'Symbols & Sparkles',description:'Geometric flower ornament.',textContent:'❀',fontSize:120,textColor:'#FFFFB4D2',motionPresetId:'float'),
    OverlayStickerDefinition(id:'sticker_sun',name:'Sunburst',category:'Symbols & Sparkles',description:'Sun-shaped decorative glyph.',textContent:'☼',fontSize:130,textColor:'#FFFFD47C',motionPresetId:'spin_pop_in'),
    OverlayStickerDefinition(id:'sticker_diamond',name:'Diamond',category:'Symbols & Sparkles',description:'Simple diamond accent.',textContent:'◆',fontSize:106,textColor:'#FF91D9FF',motionPresetId:'pop_bounce'),
    OverlayStickerDefinition(id:'sticker_hollow_diamond',name:'Hollow Diamond',category:'Symbols & Sparkles',description:'Minimal diamond outline.',textContent:'◇',fontSize:112,textColor:'#FFFFFFFF',motionPresetId:'fade_in'),
    OverlayStickerDefinition(id:'sticker_circle',name:'Circle Marker',category:'Symbols & Sparkles',description:'Solid circular marker.',textContent:'●',fontSize:100,textColor:'#FF7AD8C4',motionPresetId:'pop_bounce'),
    // ARROWS / POINTERS
    OverlayStickerDefinition(id:'sticker_arrow_right',name:'Arrow Right',category:'Arrows & Pointers',description:'Point toward an on-screen detail.',textContent:'➜',fontSize:124,textColor:'#FFFFFFFF',motionPresetId:'overshoot_left',positionX:1400,positionY:540),
    OverlayStickerDefinition(id:'sticker_arrow_left',name:'Arrow Left',category:'Arrows & Pointers',description:'Point left toward the subject.',textContent:'⬅',fontSize:116,textColor:'#FFFFFFFF',motionPresetId:'overshoot_right',positionX:520,positionY:540),
    OverlayStickerDefinition(id:'sticker_arrow_up',name:'Arrow Up',category:'Arrows & Pointers',description:'Point above the caption.',textContent:'⬆',fontSize:116,textColor:'#FFFFDA8D',motionPresetId:'fade_slide_up',positionX:1450,positionY:340),
    OverlayStickerDefinition(id:'sticker_arrow_down',name:'Arrow Down',category:'Arrows & Pointers',description:'Point down toward a subject.',textContent:'⬇',fontSize:116,textColor:'#FFFFDA8D',motionPresetId:'fade_slide_down',positionX:1450,positionY:700),
    OverlayStickerDefinition(id:'sticker_chevron',name:'Double Chevron',category:'Arrows & Pointers',description:'Minimal navigation chevron.',textContent:'»',fontSize:136,textColor:'#FFFFFFFF',motionPresetId:'fade_in'),
    OverlayStickerDefinition(id:'sticker_pointer',name:'Pointer',category:'Arrows & Pointers',description:'Point at a product or detail.',textContent:'➤',fontSize:116,textColor:'#FFFFD477',motionPresetId:'pop_bounce'),
    OverlayStickerDefinition(id:'sticker_crosshair',name:'Crosshair',category:'Arrows & Pointers',description:'Technical target pointer.',textContent:'⊕',fontSize:110,textColor:'#FF83F0D8',motionPresetId:'pulse_soft'),
    OverlayStickerDefinition(id:'sticker_location',name:'Location Pin',category:'Arrows & Pointers',description:'Map location marker glyph.',textContent:'⌖',fontSize:124,textColor:'#FFFF8B80',motionPresetId:'drop_in'),
    // BADGES / SOCIAL LABELS
    OverlayStickerDefinition(id:'sticker_new',name:'NEW Badge',category:'Badges & Labels',description:'New-content badge.',textContent:'NEW',fontSize:48,textColor:'#FFFFFFFF',letterSpacing:5,motionPresetId:'pop_bounce',positionX:1500,positionY:230),
    OverlayStickerDefinition(id:'sticker_live',name:'LIVE Badge',category:'Badges & Labels',description:'Live indicator label.',textContent:'● LIVE',fontSize:44,textColor:'#FFFF6F74',letterSpacing:2,motionPresetId:'pulse_soft',positionX:1450,positionY:170),
    OverlayStickerDefinition(id:'sticker_sale',name:'SALE Badge',category:'Badges & Labels',description:'Sale price callout.',textContent:'SALE',fontSize:54,textColor:'#FFFFE18A',letterSpacing:4,motionPresetId:'zoom_bounce'),
    OverlayStickerDefinition(id:'sticker_top',name:'TOP Badge',category:'Badges & Labels',description:'Top pick badge.',textContent:'TOP',fontSize:54,textColor:'#FF9CE8FF',letterSpacing:4,motionPresetId:'pop_bounce'),
    OverlayStickerDefinition(id:'sticker_hot',name:'HOT Badge',category:'Badges & Labels',description:'Trending content badge.',textContent:'HOT',fontSize:54,textColor:'#FFFF916B',letterSpacing:4,motionPresetId:'wobble'),
    OverlayStickerDefinition(id:'sticker_100',name:'100 Percent',category:'Badges & Labels',description:'One-hundred percent highlight.',textContent:'100%',fontSize:76,textColor:'#FFFFDA83',motionPresetId:'zoom_bounce'),
    OverlayStickerDefinition(id:'sticker_check',name:'Check Mark',category:'Badges & Labels',description:'Confirm or completed marker.',textContent:'✓',fontSize:120,textColor:'#FF7ED7B3',motionPresetId:'pop_bounce'),
    OverlayStickerDefinition(id:'sticker_verified',name:'Verified',category:'Badges & Labels',description:'Verified creator marker.',textContent:'✔',fontSize:108,textColor:'#FF80BFFF',motionPresetId:'spin_pop_in'),
    OverlayStickerDefinition(id:'sticker_question',name:'Question Mark',category:'Badges & Labels',description:'Large question prompt sticker.',textContent:'?',fontSize:150,textColor:'#FFFFD477',motionPresetId:'wobble'),
    OverlayStickerDefinition(id:'sticker_exclaim',name:'Exclamation',category:'Badges & Labels',description:'Emphasis punctuation sticker.',textContent:'!',fontSize:150,textColor:'#FFFF916B',motionPresetId:'drop_in'),
    // COMIC / SPEECH
    OverlayStickerDefinition(id:'sticker_boom',name:'BOOM',category:'Comic & Speech',description:'Comic-book impact lettering.',textContent:'BOOM!',fontSize:106,textColor:'#FFFFD166',letterSpacing:1,motionPresetId:'squash_stomp'),
    OverlayStickerDefinition(id:'sticker_pow',name:'POW',category:'Comic & Speech',description:'Bold comic impact lettering.',textContent:'POW!',fontSize:112,textColor:'#FFFF8A8A',letterSpacing:2,motionPresetId:'jelly'),
    OverlayStickerDefinition(id:'sticker_wow',name:'WOW',category:'Comic & Speech',description:'Large surprise sticker.',textContent:'WOW!',fontSize:110,textColor:'#FFFFD77F',letterSpacing:2,motionPresetId:'zoom_bounce'),
    OverlayStickerDefinition(id:'sticker_omg',name:'OMG',category:'Comic & Speech',description:'Playful reaction text sticker.',textContent:'OMG!',fontSize:104,textColor:'#FFBFA9FF',letterSpacing:1,motionPresetId:'wobble'),
    OverlayStickerDefinition(id:'sticker_bang',name:'BANG',category:'Comic & Speech',description:'Impact word sticker.',textContent:'BANG!',fontSize:96,textColor:'#FFFFA56E',letterSpacing:2,motionPresetId:'squash_stomp'),
    OverlayStickerDefinition(id:'sticker_question_bubble',name:'Question Prompt',category:'Comic & Speech',description:'Question prompt with a speech-bubble glyph.',textContent:'❖  WHY?',fontSize:80,textColor:'#FFFFFFFF',motionPresetId:'pop_bounce'),
    // DECORATIVE / FRAMES
    OverlayStickerDefinition(id:'sticker_corner_tl',name:'Corner Ornament TL',category:'Decorative Frames',description:'Upper-left corner decoration.',textContent:'⌜',fontSize:150,textColor:'#FFFFFFFF',motionPresetId:'fade_in',positionX:120,positionY:100),
    OverlayStickerDefinition(id:'sticker_corner_tr',name:'Corner Ornament TR',category:'Decorative Frames',description:'Upper-right corner decoration.',textContent:'⌝',fontSize:150,textColor:'#FFFFFFFF',motionPresetId:'fade_in',positionX:1800,positionY:100),
    OverlayStickerDefinition(id:'sticker_corner_bl',name:'Corner Ornament BL',category:'Decorative Frames',description:'Lower-left corner decoration.',textContent:'⌞',fontSize:150,textColor:'#FFFFFFFF',motionPresetId:'fade_in',positionX:120,positionY:960),
    OverlayStickerDefinition(id:'sticker_corner_br',name:'Corner Ornament BR',category:'Decorative Frames',description:'Lower-right corner decoration.',textContent:'⌟',fontSize:150,textColor:'#FFFFFFFF',motionPresetId:'fade_in',positionX:1800,positionY:960),
    OverlayStickerDefinition(id:'sticker_divider',name:'Divider Line',category:'Decorative Frames',description:'Simple graphic divider.',textContent:'━━━━━━━━━━━━',fontSize:52,fontWeight:500,textColor:'#FF9DB8D6',letterSpacing:1,motionPresetId:'fade_slide_up'),
    OverlayStickerDefinition(id:'sticker_dots',name:'Dot Divider',category:'Decorative Frames',description:'Dotted ornamental separator.',textContent:'•  •  •  •  •',fontSize:60,textColor:'#FFFFD477',motionPresetId:'fade_in'),
    OverlayStickerDefinition(id:'sticker_frame_label',name:'Frame Label',category:'Decorative Frames',description:'Small technical frame label.',textContent:'FRAME 01  /  04',fontSize:28,fontWeight:700,textColor:'#FFB7C5DA',letterSpacing:5,motionPresetId:'fade_in'),
    OverlayStickerDefinition(id:'sticker_copyright',name:'Copyright Mark',category:'Decorative Frames',description:'Copyright and creator mark.',textContent:'©  YOUR BRAND',fontSize:24,fontWeight:600,textColor:'#FFB7C5DA',letterSpacing:2,motionPresetId:'fade_in',positionX:1500,positionY:1010),
  ];

  static OverlayStickerDefinition? find(String id) {
    for (final asset in all) {
      if (asset.id == id) return asset;
    }
    return null;
  }

  static List<String> get categories =>
      all.map((asset) => asset.category).toSet().toList()..sort();
}
