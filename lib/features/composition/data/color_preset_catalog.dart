/// Original color-grading recipes expressed as validated native primary
/// correction values. No third-party LUT files are bundled in this catalog.
class ColorPresetDefinition {
  const ColorPresetDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    this.temperature = 0,
    this.tint = 0,
    this.contrast = 1,
    this.brightness = 0,
    this.masterGamma = 1,
    this.saturation = 1,
    this.liftR = 0,
    this.liftG = 0,
    this.liftB = 0,
    this.gainR = 0,
    this.gainG = 0,
    this.gainB = 0,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final double temperature;
  final double tint;
  final double contrast;
  final double brightness;
  final double masterGamma;
  final double saturation;
  final double liftR;
  final double liftG;
  final double liftB;
  final double gainR;
  final double gainG;
  final double gainB;

  Map<String, double> get parameters => {
    'temperature': temperature,
    'tint': tint,
    'contrast': contrast,
    'brightness': brightness,
    'master_gamma': masterGamma,
    'saturation': saturation,
    'lift_r': liftR,
    'lift_g': liftG,
    'lift_b': liftB,
    'gain_r': gainR,
    'gain_g': gainG,
    'gain_b': gainB,
  };
}

class ColorPresetCatalog {
  ColorPresetCatalog._();

  static const List<ColorPresetDefinition> all = [
    // CINEMATIC
    ColorPresetDefinition(id:'cine_teal_orange',name:'Teal & Orange',category:'Cinematic',description:'Cool shadow bias and warm highlight separation.',temperature:0.18,tint:0.02,contrast:1.16,saturation:1.12,liftG:0.025,gainR:0.045,gainB:0.025),
    ColorPresetDefinition(id:'cine_noir',name:'Neo Noir',category:'Cinematic',description:'Deep contrast with restrained color.',contrast:1.42,masterGamma:0.94,saturation:0.62,liftB:0.018),
    ColorPresetDefinition(id:'cine_bleach',name:'Bleach Bypass',category:'Cinematic',description:'High contrast, low saturation film-print character.',contrast:1.55,saturation:0.38,masterGamma:0.96),
    ColorPresetDefinition(id:'cine_golden_hour',name:'Golden Hour',category:'Cinematic',description:'Warm late-afternoon highlights.',temperature:0.32,tint:0.04,contrast:1.04,saturation:1.12,gainR:0.06,gainB:-0.035),
    ColorPresetDefinition(id:'cine_arctic',name:'Arctic Blue',category:'Cinematic',description:'Cool steel-blue palette.',temperature:-0.28,tint:-0.02,contrast:1.18,saturation:0.9,liftB:0.04,gainB:0.05),
    ColorPresetDefinition(id:'cine_muted_drama',name:'Muted Drama',category:'Cinematic',description:'Muted hues with lifted midtones.',contrast:1.12,brightness:0.025,masterGamma:1.08,saturation:0.72,liftB:0.018),
    ColorPresetDefinition(id:'cine_silver',name:'Silver Screen',category:'Cinematic',description:'Near-monochrome silver-grey cinema.',contrast:1.28,saturation:0.08,masterGamma:0.98),
    ColorPresetDefinition(id:'cine_night',name:'Night City',category:'Cinematic',description:'Cool night contrast with saturated highlights.',temperature:-0.2,contrast:1.25,saturation:1.22,liftB:0.04,gainB:0.055),
    ColorPresetDefinition(id:'cine_copper',name:'Copper Sunset',category:'Cinematic',description:'Copper warmth and rich shadow density.',temperature:0.4,tint:0.08,contrast:1.14,saturation:1.08,liftR:0.025,gainR:0.07,gainB:-0.045),
    ColorPresetDefinition(id:'cine_emerald',name:'Emerald Cinema',category:'Cinematic',description:'Subtle green-cyan cinematic separation.',temperature:-0.08,tint:-0.12,contrast:1.18,saturation:0.96,liftG:0.04,gainG:0.025),
    // FILM
    ColorPresetDefinition(id:'film_kodak_warm',name:'Warm Negative',category:'Film',description:'Warm, gentle contrast with rich skin tones.',temperature:0.22,tint:0.035,contrast:1.04,saturation:1.08,masterGamma:1.04),
    ColorPresetDefinition(id:'film_portra_soft',name:'Soft Portrait Film',category:'Film',description:'Soft pastel portrait color and smooth mids.',temperature:0.12,contrast:0.94,brightness:0.018,masterGamma:1.08,saturation:0.92),
    ColorPresetDefinition(id:'film_ektar_pop',name:'Color Negative Pop',category:'Film',description:'Vivid color negative with clean contrast.',temperature:0.04,contrast:1.18,saturation:1.3,masterGamma:0.98),
    ColorPresetDefinition(id:'film_faded',name:'Faded Print',category:'Film',description:'Lifted shadows and mellow vintage saturation.',temperature:0.12,contrast:0.86,brightness:0.035,masterGamma:1.12,saturation:0.78,liftR:0.025,liftB:0.02),
    ColorPresetDefinition(id:'film_super8',name:'Super 8 Warmth',category:'Film',description:'Warm home-movie inspired grade.',temperature:0.3,contrast:1.06,saturation:1.16,masterGamma:1.04,gainR:0.04),
    ColorPresetDefinition(id:'film_mono',name:'Classic Monochrome',category:'Film',description:'Black and white tonal separation.',contrast:1.32,saturation:0,masterGamma:0.98),
    ColorPresetDefinition(id:'film_sepia',name:'Sepia Memory',category:'Film',description:'Soft amber monochrome finish.',temperature:0.36,tint:0.05,contrast:0.98,saturation:0.42,masterGamma:1.06),
    ColorPresetDefinition(id:'film_cool_fade',name:'Cool Fade',category:'Film',description:'Faded cool analogue print look.',temperature:-0.18,contrast:0.88,brightness:0.025,masterGamma:1.14,saturation:0.72,liftB:0.045),
    ColorPresetDefinition(id:'film_cross_process',name:'Cross Process',category:'Film',description:'Punchy contrast and unusual channel bias.',temperature:0.12,tint:-0.08,contrast:1.28,saturation:1.25,liftG:-0.025,gainB:0.06,gainR:0.04),
    ColorPresetDefinition(id:'film_slide',name:'Slide Film',category:'Film',description:'Deep saturated slide-film-inspired look.',contrast:1.24,saturation:1.18,masterGamma:0.94,liftB:-0.02),
    // PORTRAIT
    ColorPresetDefinition(id:'portrait_clean',name:'Clean Skin',category:'Portrait',description:'Neutral color with a small exposure lift.',temperature:0.03,tint:0.015,contrast:1.02,brightness:0.025,saturation:1.02),
    ColorPresetDefinition(id:'portrait_warm',name:'Warm Portrait',category:'Portrait',description:'Soft warmth and gentle skin-friendly contrast.',temperature:0.18,tint:0.035,contrast:0.96,brightness:0.025,saturation:1.04,masterGamma:1.05),
    ColorPresetDefinition(id:'portrait_matte',name:'Matte Portrait',category:'Portrait',description:'Matte blacks with subdued highlights.',contrast:0.9,brightness:0.025,masterGamma:1.12,saturation:0.88,liftR:0.018,liftB:0.018),
    ColorPresetDefinition(id:'portrait_editorial',name:'Editorial Skin',category:'Portrait',description:'Crisp editorial finish with neutral whites.',temperature:0.04,contrast:1.12,saturation:0.94,masterGamma:0.98),
    ColorPresetDefinition(id:'portrait_peach',name:'Peach Glow',category:'Portrait',description:'Peach warmth and soft highlight lift.',temperature:0.22,tint:0.05,contrast:0.94,brightness:0.03,saturation:1.06,gainR:0.045),
    ColorPresetDefinition(id:'portrait_cool',name:'Cool Studio',category:'Portrait',description:'Cool-neutral studio skin and crisp detail.',temperature:-0.08,contrast:1.08,saturation:0.92,masterGamma:0.98,gainB:0.025),
    // CREATOR / SOCIAL
    ColorPresetDefinition(id:'creator_vibrant',name:'Vibrant Pop',category:'Creator',description:'Bold saturated look for social content.',contrast:1.14,saturation:1.35,brightness:0.02),
    ColorPresetDefinition(id:'creator_thumbnail',name:'Thumbnail Impact',category:'Creator',description:'Punchy contrast and strong color separation.',contrast:1.32,saturation:1.42,brightness:0.045,masterGamma:0.94),
    ColorPresetDefinition(id:'creator_pastel',name:'Soft Pastel',category:'Creator',description:'Airy highlights and gentle pastel color.',contrast:0.9,brightness:0.045,masterGamma:1.12,saturation:0.86),
    ColorPresetDefinition(id:'creator_food',name:'Food Warmth',category:'Creator',description:'Warm appetizing food color.',temperature:0.2,tint:0.04,contrast:1.08,saturation:1.2),
    ColorPresetDefinition(id:'creator_travel',name:'Travel Aqua',category:'Creator',description:'Bright lively cyan and blue travel color.',temperature:-0.08,contrast:1.1,saturation:1.18,gainB:0.025),
    ColorPresetDefinition(id:'creator_summer',name:'Summer Bright',category:'Creator',description:'Bright, happy warm daylight finish.',temperature:0.12,contrast:1.04,brightness:0.05,saturation:1.22),
    ColorPresetDefinition(id:'creator_autumn',name:'Autumn Leaves',category:'Creator',description:'Golden earth tones with rich reds.',temperature:0.28,tint:0.045,contrast:1.08,saturation:1.18,gainR:0.06,gainB:-0.04),
    ColorPresetDefinition(id:'creator_mint',name:'Mint Fresh',category:'Creator',description:'Fresh bright greens and cool whites.',temperature:-0.08,tint:-0.03,contrast:1.02,saturation:1.14,gainG:0.04),
    // MOOD
    ColorPresetDefinition(id:'mood_moody',name:'Moody Shadows',category:'Mood',description:'Dark cinematic mood with dense shadows.',contrast:1.3,brightness:-0.035,masterGamma:0.9,saturation:0.9,liftB:0.02),
    ColorPresetDefinition(id:'mood_dream',name:'Dreamy',category:'Mood',description:'Soft low-contrast dreamy pastel grade.',contrast:0.86,brightness:0.045,masterGamma:1.18,saturation:0.92),
    ColorPresetDefinition(id:'mood_romantic',name:'Romantic Rose',category:'Mood',description:'Soft rose warmth for intimate scenes.',temperature:0.12,tint:0.12,contrast:0.94,saturation:1.04,gainR:0.04),
    ColorPresetDefinition(id:'mood_mystic',name:'Mystic Violet',category:'Mood',description:'Cool violet shadow bias.',temperature:-0.08,tint:0.18,contrast:1.12,saturation:1.08,liftB:0.055,gainR:0.02),
    ColorPresetDefinition(id:'mood_forest',name:'Forest Green',category:'Mood',description:'Natural deep green and subdued skin tones.',temperature:-0.04,tint:-0.08,contrast:1.12,saturation:0.94,liftG:0.035),
    ColorPresetDefinition(id:'mood_desert',name:'Desert Sand',category:'Mood',description:'Dusty golden light and muted blue.',temperature:0.32,tint:0.04,contrast:0.98,saturation:0.88,gainR:0.055,gainB:-0.045),
    ColorPresetDefinition(id:'mood_storm',name:'Storm Blue',category:'Mood',description:'Steel-blue atmospheric cool grade.',temperature:-0.25,tint:-0.02,contrast:1.18,saturation:0.86,liftB:0.05),
    ColorPresetDefinition(id:'mood_crimson',name:'Crimson Night',category:'Mood',description:'Deep reds with cinematic contrast.',temperature:0.12,tint:0.1,contrast:1.26,saturation:1.14,liftR:0.025,gainR:0.06),
    // CLEAN / ACCESSIBILITY
    ColorPresetDefinition(id:'clean_neutral',name:'Neutral Balance',category:'Clean',description:'A restrained neutral correction starting point.',contrast:1,saturation:1),
    ColorPresetDefinition(id:'clean_bright',name:'Bright Daylight',category:'Clean',description:'Lift exposure and keep colors realistic.',brightness:0.065,contrast:1.02,saturation:1.02),
    ColorPresetDefinition(id:'clean_soft',name:'Soft Contrast',category:'Clean',description:'Gentle contrast for bright everyday footage.',contrast:0.94,masterGamma:1.04,saturation:0.98),
    ColorPresetDefinition(id:'clean_crisp',name:'Crisp Detail',category:'Clean',description:'Clean whites and stronger tonal separation.',contrast:1.18,saturation:1.04,masterGamma:0.98),
    ColorPresetDefinition(id:'clean_low_sat',name:'Low Saturation',category:'Clean',description:'Subdued natural color for documentary edits.',contrast:1.04,saturation:0.68),
    ColorPresetDefinition(id:'clean_hc_bw',name:'High Contrast B&W',category:'Clean',description:'Graphic high-contrast monochrome.',contrast:1.5,saturation:0,masterGamma:0.92),
  ];

  static ColorPresetDefinition? find(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  static List<String> get categories =>
      all.map((preset) => preset.category).toSet().toList()..sort();
}
