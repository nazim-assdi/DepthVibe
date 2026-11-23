/// Original multi-effect looks inspired by common professional grading and
/// motion-graphics workflows. Every step uses a native, reviewed DepthVibe
/// effect definition; no third-party preset code or assets are bundled.
class EffectPresetStep {
  const EffectPresetStep(this.effectId, {this.parameters = const {}});

  final String effectId;
  final Map<String, double> parameters;
}

class EffectPresetDefinition {
  const EffectPresetDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.steps,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final List<EffectPresetStep> steps;
}

class EffectPresetCatalog {
  EffectPresetCatalog._();

  static const List<EffectPresetDefinition> all = [
    // CINEMATIC COLLECTION
    EffectPresetDefinition(id: 'cinema_teal_amber', name: 'Teal & Amber', category: 'Cinematic', description: 'Cool shadows, warm highlights and controlled saturation.', steps: [
      EffectPresetStep('color_grade', parameters: {'temperature': 0.18, 'tint': 0.02, 'contrast': 1.16, 'saturation': 1.12}),
      EffectPresetStep('vibrance', parameters: {'intensity': 0.32}),
      EffectPresetStep('vignette', parameters: {'angle': 0.78}),
    ]),
    EffectPresetDefinition(id: 'cinema_noir', name: 'Neo Noir', category: 'Cinematic', description: 'Deep blacks, crisp contrast and restrained color.', steps: [
      EffectPresetStep('color_grade', parameters: {'contrast': 1.42, 'saturation': 0.62, 'master_gamma': 0.94}),
      EffectPresetStep('vignette', parameters: {'angle': 0.92}),
      EffectPresetStep('film_grain', parameters: {'amount': 9}),
    ]),
    EffectPresetDefinition(id: 'cinema_bleach', name: 'Bleach Bypass', category: 'Cinematic', description: 'Dense contrast with a desaturated print-film character.', steps: [
      EffectPresetStep('bleach_bypass', parameters: {'contrast': 1.55, 'saturation': 0.38}),
      EffectPresetStep('film_grain', parameters: {'amount': 10}),
    ]),
    EffectPresetDefinition(id: 'cinema_golden_hour', name: 'Golden Hour', category: 'Cinematic', description: 'Warm sunlight, soft highlight bloom and gentle depth.', steps: [
      EffectPresetStep('color_grade', parameters: {'temperature': 0.32, 'tint': 0.04, 'contrast': 1.04, 'saturation': 1.12}),
      EffectPresetStep('glow', parameters: {'threshold': 0.82, 'radius': 16, 'intensity': 0.42}),
      EffectPresetStep('vignette', parameters: {'angle': 0.62}),
    ]),
    EffectPresetDefinition(id: 'cinema_arctic', name: 'Arctic Blue', category: 'Cinematic', description: 'Cool steel-blue tonality with sharp modern contrast.', steps: [
      EffectPresetStep('color_grade', parameters: {'temperature': -0.28, 'tint': -0.02, 'contrast': 1.18, 'saturation': 0.9}),
      EffectPresetStep('color_balance', parameters: {'red': -0.06, 'green': 0.01, 'blue': 0.13}),
    ]),
    EffectPresetDefinition(id: 'cinema_muted_drama', name: 'Muted Drama', category: 'Cinematic', description: 'Low saturation, lifted shadows and subtle film texture.', steps: [
      EffectPresetStep('color_grade', parameters: {'contrast': 1.12, 'brightness': 0.025, 'master_gamma': 1.08, 'saturation': 0.72}),
      EffectPresetStep('film_grain', parameters: {'amount': 13}),
      EffectPresetStep('vignette', parameters: {'angle': 0.72}),
    ]),
    EffectPresetDefinition(id: 'cinema_silver', name: 'Silver Screen', category: 'Cinematic', description: 'Monochrome cinema with luminous highlights.', steps: [
      EffectPresetStep('grayscale'),
      EffectPresetStep('contrast', parameters: {'value': 1.28}),
      EffectPresetStep('glow', parameters: {'threshold': 0.9, 'radius': 10, 'intensity': 0.24}),
      EffectPresetStep('film_grain', parameters: {'amount': 8}),
    ]),
    EffectPresetDefinition(id: 'cinema_night_city', name: 'Night City', category: 'Cinematic', description: 'Cool night color, neon highlights and atmospheric depth.', steps: [
      EffectPresetStep('color_grade', parameters: {'temperature': -0.2, 'contrast': 1.25, 'saturation': 1.22}),
      EffectPresetStep('glow', parameters: {'threshold': 0.68, 'radius': 20, 'intensity': 0.62}),
      EffectPresetStep('vignette', parameters: {'angle': 0.96}),
    ]),

    // FILM & ANALOG COLLECTION
    EffectPresetDefinition(id: 'film_super8', name: 'Super 8 Home Movie', category: 'Film & Retro', description: 'Warm home-movie color, gate weave, grain and dust.', steps: [
      EffectPresetStep('old_film', parameters: {'grain': 25, 'vignette': 0.78, 'warmth': 0.46}),
      EffectPresetStep('film_gate_weave', parameters: {'amplitude': 0.5, 'speed': 2.2}),
      EffectPresetStep('particle_dust', parameters: {'spacing': 86, 'size': 2.2, 'intensity': 0.28, 'speed': 0.7}),
    ]),
    EffectPresetDefinition(id: 'film_vhs_90s', name: '90s VHS Tape', category: 'Film & Retro', description: 'Tape wobble, chroma separation and analog noise.', steps: [
      EffectPresetStep('vhs_warp', parameters: {'shift': 4.5, 'noise': 28}),
      EffectPresetStep('rgb_split', parameters: {'shift': 3.5}),
      EffectPresetStep('scanlines', parameters: {'spacing': 4, 'thickness': 1, 'opacity': 0.24}),
    ]),
    EffectPresetDefinition(id: 'film_crt', name: 'CRT Monitor', category: 'Film & Retro', description: 'Screen scanlines with a punchy display response.', steps: [
      EffectPresetStep('scanlines', parameters: {'spacing': 3, 'thickness': 1, 'opacity': 0.38}),
      EffectPresetStep('chromatic_aberration', parameters: {'shift': 1.8}),
      EffectPresetStep('contrast', parameters: {'value': 1.18}),
    ]),
    EffectPresetDefinition(id: 'film_instant_photo', name: 'Instant Photo', category: 'Film & Retro', description: 'Soft contrast, warm paper tone and gentle vignette.', steps: [
      EffectPresetStep('color_grade', parameters: {'temperature': 0.16, 'contrast': 0.94, 'saturation': 0.88, 'brightness': 0.025}),
      EffectPresetStep('old_film', parameters: {'grain': 8, 'vignette': 0.66, 'warmth': 0.3}),
    ]),
    EffectPresetDefinition(id: 'film_faded_print', name: 'Faded Print', category: 'Film & Retro', description: 'Aged print tones with gentle lifted mids.', steps: [
      EffectPresetStep('color_grade', parameters: {'temperature': 0.12, 'contrast': 0.86, 'master_gamma': 1.12, 'saturation': 0.78}),
      EffectPresetStep('film_grain', parameters: {'amount': 16}),
    ]),
    EffectPresetDefinition(id: 'film_mono_grain', name: 'Grainy Monochrome', category: 'Film & Retro', description: 'Classic black-and-white texture with strong tonal separation.', steps: [
      EffectPresetStep('grayscale'),
      EffectPresetStep('contrast', parameters: {'value': 1.36}),
      EffectPresetStep('film_grain', parameters: {'amount': 28}),
      EffectPresetStep('vignette', parameters: {'angle': 0.82}),
    ]),
    EffectPresetDefinition(id: 'film_polaroid', name: 'Polaroid Warmth', category: 'Film & Retro', description: 'Warm instant-film palette with softened highlights.', steps: [
      EffectPresetStep('sepia'),
      EffectPresetStep('colorize', parameters: {'hue': 34, 'saturation': 0.18, 'lightness': 0.02, 'mix': 0.22}),
      EffectPresetStep('vignette', parameters: {'angle': 0.68}),
    ]),
    EffectPresetDefinition(id: 'film_datamosh', name: 'Analog Signal Break', category: 'Film & Retro', description: 'Glitch streaks, frame echoes and chromatic tearing.', steps: [
      EffectPresetStep('analog_glitch', parameters: {'shift': 7, 'noise': 34, 'fps': 15}),
      EffectPresetStep('echo_trails', parameters: {'frames': 4}),
      EffectPresetStep('rgb_split', parameters: {'shift': 5}),
    ]),

    // CREATOR / SOCIAL COLLECTION
    EffectPresetDefinition(id: 'creator_clean', name: 'Clean Creator', category: 'Creator', description: 'Balanced skin-friendly color, clear contrast and detail.', steps: [
      EffectPresetStep('auto_white_balance'),
      EffectPresetStep('color_grade', parameters: {'contrast': 1.06, 'saturation': 1.04}),
      EffectPresetStep('adaptive_sharpen', parameters: {'strength': 0.32}),
    ]),
    EffectPresetDefinition(id: 'creator_vibrant', name: 'Vibrant Pop', category: 'Creator', description: 'Punchy social color with controlled saturation boost.', steps: [
      EffectPresetStep('vibrance', parameters: {'intensity': 0.72}),
      EffectPresetStep('color_grade', parameters: {'contrast': 1.14, 'saturation': 1.12}),
      EffectPresetStep('sharpen', parameters: {'amount': 0.7}),
    ]),
    EffectPresetDefinition(id: 'creator_product', name: 'Product Detail', category: 'Creator', description: 'Crisp product presentation with clean highlights.', steps: [
      EffectPresetStep('auto_white_balance'),
      EffectPresetStep('color_grade', parameters: {'contrast': 1.12, 'saturation': 1.04}),
      EffectPresetStep('adaptive_sharpen', parameters: {'strength': 0.48}),
    ]),
    EffectPresetDefinition(id: 'creator_food', name: 'Food Warmth', category: 'Creator', description: 'Warm appetizing color and a subtle highlight lift.', steps: [
      EffectPresetStep('color_grade', parameters: {'temperature': 0.2, 'tint': 0.04, 'contrast': 1.08, 'saturation': 1.2}),
      EffectPresetStep('vibrance', parameters: {'intensity': 0.38}),
    ]),
    EffectPresetDefinition(id: 'creator_travel', name: 'Travel Aqua', category: 'Creator', description: 'Bright travel colors with lively cyan and blue tones.', steps: [
      EffectPresetStep('color_grade', parameters: {'temperature': -0.08, 'contrast': 1.1, 'saturation': 1.18}),
      EffectPresetStep('vibrance', parameters: {'intensity': 0.52}),
    ]),
    EffectPresetDefinition(id: 'creator_thumbnail', name: 'Thumbnail Impact', category: 'Creator', description: 'Bold, bright and high-contrast thumbnail treatment.', steps: [
      EffectPresetStep('color_grade', parameters: {'contrast': 1.28, 'saturation': 1.28, 'brightness': 0.035}),
      EffectPresetStep('sharpen', parameters: {'amount': 1.25}),
      EffectPresetStep('vignette', parameters: {'angle': 0.58}),
    ]),
    EffectPresetDefinition(id: 'creator_soft_pastel', name: 'Soft Pastel', category: 'Creator', description: 'Airy highlights, pastel color and gentle contrast.', steps: [
      EffectPresetStep('color_grade', parameters: {'contrast': 0.9, 'brightness': 0.045, 'master_gamma': 1.12, 'saturation': 0.86}),
      EffectPresetStep('glow', parameters: {'threshold': 0.9, 'radius': 12, 'intensity': 0.18}),
    ]),
    EffectPresetDefinition(id: 'creator_studio', name: 'Studio Neutral', category: 'Creator', description: 'Neutral white balance with sharp, accurate detail.', steps: [
      EffectPresetStep('auto_white_balance'),
      EffectPresetStep('color_grade', parameters: {'contrast': 1.04, 'saturation': 0.96}),
      EffectPresetStep('adaptive_sharpen', parameters: {'strength': 0.38}),
    ]),

    // DREAM / LIGHT COLLECTION
    EffectPresetDefinition(id: 'dream_bloom', name: 'Dream Bloom', category: 'Dream & Neon', description: 'Soft highlight bloom with a dreamy pastel finish.', steps: [
      EffectPresetStep('glow', parameters: {'threshold': 0.76, 'radius': 26, 'intensity': 0.72}),
      EffectPresetStep('color_grade', parameters: {'contrast': 0.94, 'saturation': 1.06}),
    ]),
    EffectPresetDefinition(id: 'dream_neon', name: 'Neon After Dark', category: 'Dream & Neon', description: 'Neon edge light, rich color and a darkened frame.', steps: [
      EffectPresetStep('edge_glow', parameters: {'radius': 14, 'brightness': 0.8}),
      EffectPresetStep('color_grade', parameters: {'contrast': 1.32, 'saturation': 1.42}),
      EffectPresetStep('vignette', parameters: {'angle': 1.02}),
    ]),
    EffectPresetDefinition(id: 'dream_halo', name: 'Soft Halo', category: 'Dream & Neon', description: 'Gentle luminous halo for atmospheric portraits and titles.', steps: [
      EffectPresetStep('glow', parameters: {'threshold': 0.86, 'radius': 20, 'intensity': 0.38}),
      EffectPresetStep('gaussian_blur', parameters: {'sigma': 0.35}),
      EffectPresetStep('color_grade', parameters: {'contrast': 0.96, 'saturation': 1.02}),
    ]),
    EffectPresetDefinition(id: 'dream_heatwave', name: 'Heatwave Mirage', category: 'Dream & Neon', description: 'Animated thermal shimmer with subtle color shift.', steps: [
      EffectPresetStep('heat_haze', parameters: {'amount': 4.8, 'scale': 92, 'speed': 1.2}),
      EffectPresetStep('chromatic_aberration', parameters: {'shift': 0.8}),
    ]),
    EffectPresetDefinition(id: 'dream_prism', name: 'Prism Split', category: 'Dream & Neon', description: 'Prismatic color separation with a luminous center.', steps: [
      EffectPresetStep('chromatic_aberration', parameters: {'shift': 4}),
      EffectPresetStep('glow', parameters: {'threshold': 0.86, 'radius': 18, 'intensity': 0.46}),
    ]),
    EffectPresetDefinition(id: 'dream_flash', name: 'Flash Frame', category: 'Dream & Neon', description: 'Quick camera flash accent for a highlight beat.', steps: [
      EffectPresetStep('camera_flash', parameters: {'brightness': 0.72}),
      EffectPresetStep('color_grade', parameters: {'contrast': 1.05, 'saturation': 1.08}),
    ]),

    // DISTORTION / MOTION COLLECTION
    EffectPresetDefinition(id: 'motion_glitch_burst', name: 'Glitch Burst', category: 'Distortion', description: 'Digital tearing, RGB offset and noisy signal breakup.', steps: [
      EffectPresetStep('analog_glitch', parameters: {'shift': 9, 'noise': 42, 'fps': 16}),
      EffectPresetStep('rgb_split', parameters: {'shift': 7}),
      EffectPresetStep('displacement', parameters: {'amount': 14, 'wavelength': 68, 'speed': 2}),
    ]),
    EffectPresetDefinition(id: 'motion_speed_lines', name: 'Speed Lines', category: 'Distortion', description: 'Directional smear and frame echo for fast movement.', steps: [
      EffectPresetStep('directional_blur', parameters: {'angle': 0, 'radius': 14}),
      EffectPresetStep('echo_trails', parameters: {'frames': 3}),
    ]),
    EffectPresetDefinition(id: 'motion_wave', name: 'Wave Warp', category: 'Distortion', description: 'Animated wave distortion for stylized transitions and shots.', steps: [
      EffectPresetStep('wave_distortion', parameters: {'amount': 7, 'wavelength': 74, 'speed': 1.6}),
    ]),
    EffectPresetDefinition(id: 'motion_pixel_art', name: 'Pixel Art', category: 'Distortion', description: 'Chunky digital pixels with reduced color palette.', steps: [
      EffectPresetStep('pixelate', parameters: {'size': 9}),
      EffectPresetStep('posterize', parameters: {'levels': 8}),
    ]),
    EffectPresetDefinition(id: 'motion_fisheye', name: 'Action Fisheye', category: 'Distortion', description: 'Wide action-camera lens character with energetic contrast.', steps: [
      EffectPresetStep('fisheye', parameters: {'strength': 0.46}),
      EffectPresetStep('color_grade', parameters: {'contrast': 1.14, 'saturation': 1.12}),
    ]),

    // CLEANUP & TEXTURE COLLECTION
    EffectPresetDefinition(id: 'utility_lowlight', name: 'Low-light Cleanup', category: 'Utility', description: 'Reduce noise and preserve important detail in dark footage.', steps: [
      EffectPresetStep('nlmeans_denoise', parameters: {'strength': 1.35}),
      EffectPresetStep('chroma_denoise', parameters: {'threshold': 0.09, 'window': 3}),
      EffectPresetStep('adaptive_sharpen', parameters: {'strength': 0.22}),
    ]),
    EffectPresetDefinition(id: 'utility_detail', name: 'Detail Recovery', category: 'Utility', description: 'Light denoise followed by controlled sharpening.', steps: [
      EffectPresetStep('median_denoise', parameters: {'radius': 1}),
      EffectPresetStep('adaptive_sharpen', parameters: {'strength': 0.56}),
      EffectPresetStep('color_grade', parameters: {'contrast': 1.04}),
    ]),
    EffectPresetDefinition(id: 'utility_deband', name: 'Gradient Repair', category: 'Utility', description: 'Reduce visible banding in skies and smooth gradients.', steps: [
      EffectPresetStep('deband', parameters: {'threshold': 0.025, 'range': 18}),
      EffectPresetStep('noise_reduction', parameters: {'luma': 0.6, 'chroma': 1.2, 'temporal': 1}),
    ]),
    EffectPresetDefinition(id: 'utility_edge', name: 'Edge Accent', category: 'Utility', description: 'Bright edge tracing for graphic and poster-style footage.', steps: [
      EffectPresetStep('edge_detect'),
      EffectPresetStep('edge_glow', parameters: {'radius': 10, 'brightness': 0.56}),
    ]),

    EffectPresetDefinition(id:'cinema_amber_halo',name:'Amber Halo',category:'Cinematic',description:'Warm bloom, restrained contrast and soft edge falloff.',steps:[EffectPresetStep('color_temperature',parameters:{'temperature':0.3,'tint':0.02,'intensity':0.85}),EffectPresetStep('glow',parameters:{'threshold':0.84,'radius':19,'intensity':0.52}),EffectPresetStep('vignette',parameters:{'angle':0.78})]),
    EffectPresetDefinition(id:'cinema_blue_hour',name:'Blue Hour',category:'Cinematic',description:'Cool twilight shadows and blue separation.',steps:[EffectPresetStep('color_temperature',parameters:{'temperature':-0.32,'tint':-0.04,'intensity':0.9}),EffectPresetStep('color_grade',parameters:{'contrast':1.22,'saturation':0.92}),EffectPresetStep('vignette',parameters:{'angle':0.86})]),
    EffectPresetDefinition(id:'cinema_crimson',name:'Crimson Drama',category:'Cinematic',description:'Rich red bias and dense cinematic contrast.',steps:[EffectPresetStep('color_grade',parameters:{'temperature':0.12,'tint':0.12,'contrast':1.26,'saturation':1.14}),EffectPresetStep('color_balance',parameters:{'red':0.1,'green':-0.02,'blue':-0.04}),EffectPresetStep('film_grain',parameters:{'amount':8})]),
    EffectPresetDefinition(id:'cinema_soft_haze',name:'Soft Haze',category:'Cinematic',description:'Gentle diffusion and lifted highlight atmosphere.',steps:[EffectPresetStep('soft_focus',parameters:{'radius':1.6,'brightness':0.04}),EffectPresetStep('color_grade',parameters:{'contrast':0.94,'saturation':1.04}),EffectPresetStep('glow',parameters:{'threshold':0.9,'radius':16,'intensity':0.2})]),
    EffectPresetDefinition(id:'cinema_steel_noir',name:'Steel Noir',category:'Cinematic',description:'Cold contrast and crisp monochrome-leaning edges.',steps:[EffectPresetStep('color_grade',parameters:{'temperature':-0.18,'contrast':1.44,'saturation':0.72}),EffectPresetStep('high_pass_sharpen',parameters:{'amount':0.8}),EffectPresetStep('vignette',parameters:{'angle':0.96})]),
    EffectPresetDefinition(id:'film_solarized_print',name:'Solarized Print',category:'Film & Retro',description:'Experimental solarization and film texture.',steps:[EffectPresetStep('solarize',parameters:{'threshold':174}),EffectPresetStep('film_grain',parameters:{'amount':16}),EffectPresetStep('vignette',parameters:{'angle':0.72})]),
    EffectPresetDefinition(id:'film_cold_reel',name:'Cold Reel',category:'Film & Retro',description:'Cool print stock with a subdued vintage finish.',steps:[EffectPresetStep('color_temperature',parameters:{'temperature':-0.24,'tint':-0.02,'intensity':0.8}),EffectPresetStep('old_film',parameters:{'grain':14,'vignette':0.78,'warmth':0.12})]),
    EffectPresetDefinition(id:'film_matte_amber',name:'Matte Amber',category:'Film & Retro',description:'Lifted matte shadows with soft amber colour.',steps:[EffectPresetStep('color_temperature',parameters:{'temperature':0.24,'tint':0.06,'intensity':0.75}),EffectPresetStep('color_grade',parameters:{'contrast':0.88,'brightness':0.03,'master_gamma':1.1,'saturation':0.82}),EffectPresetStep('film_grain',parameters:{'amount':10})]),
    EffectPresetDefinition(id:'creator_crisp_detail',name:'Crisp Detail',category:'Creator',description:'Neutral white balance and sharp tutorial/product footage.',steps:[EffectPresetStep('auto_white_balance'),EffectPresetStep('high_pass_sharpen',parameters:{'amount':1.1}),EffectPresetStep('color_grade',parameters:{'contrast':1.1,'saturation':1.04})]),
    EffectPresetDefinition(id:'creator_natural_skin',name:'Natural Skin',category:'Creator',description:'Subtle warmth, restrained colour and gentle diffusion.',steps:[EffectPresetStep('color_temperature',parameters:{'temperature':0.12,'tint':0.03,'intensity':0.65}),EffectPresetStep('soft_focus',parameters:{'radius':0.8,'brightness':0.02}),EffectPresetStep('vibrance',parameters:{'intensity':0.22})]),
    EffectPresetDefinition(id:'creator_color_pop',name:'Colour Pop',category:'Creator',description:'Lift muted tones and strengthen colour separation.',steps:[EffectPresetStep('vibrance',parameters:{'intensity':0.82}),EffectPresetStep('color_grade',parameters:{'contrast':1.14,'saturation':1.16}),EffectPresetStep('high_pass_sharpen',parameters:{'amount':0.6})]),
    EffectPresetDefinition(id:'creator_soft_product',name:'Soft Product Light',category:'Creator',description:'Bright soft product footage with clean neutral colour.',steps:[EffectPresetStep('auto_white_balance'),EffectPresetStep('soft_focus',parameters:{'radius':1.1,'brightness':0.035}),EffectPresetStep('color_grade',parameters:{'contrast':1.02,'saturation':1.02})]),
    EffectPresetDefinition(id:'creator_green_screen',name:'Green Screen Key',category:'Creator',description:'Start an adjustable green-screen removal workflow.',steps:[EffectPresetStep('color_key',parameters:{'similarity':0.32,'blend':0.12})]),
    EffectPresetDefinition(id:'dream_prism_haze',name:'Prism Haze',category:'Dream & Neon',description:'Chromatic fringe, diffusion and luminous bloom.',steps:[EffectPresetStep('chroma_smear',parameters:{'shift':3.5}),EffectPresetStep('soft_focus',parameters:{'radius':1.4,'brightness':0.025}),EffectPresetStep('glow',parameters:{'threshold':0.88,'radius':22,'intensity':0.34})]),
    EffectPresetDefinition(id:'dream_rose_glow',name:'Rose Glow',category:'Dream & Neon',description:'Warm rosy tint and smooth highlight halo.',steps:[EffectPresetStep('color_temperature',parameters:{'temperature':0.16,'tint':0.16,'intensity':0.6}),EffectPresetStep('glow',parameters:{'threshold':0.86,'radius':24,'intensity':0.4}),EffectPresetStep('soft_focus',parameters:{'radius':0.9,'brightness':0.03})]),
    EffectPresetDefinition(id:'distortion_ripple_pool',name:'Ripple Pool',category:'Distortion',description:'Animated water-like ripple field for abstract shots.',steps:[EffectPresetStep('ripple_warp',parameters:{'amount':7,'wavelength':96,'speed':1.5}),EffectPresetStep('color_grade',parameters:{'temperature':-0.08,'saturation':1.12})]),
    EffectPresetDefinition(id:'distortion_zoom_pull',name:'Zoom Pull',category:'Distortion',description:'Centred radial stretch with subtle chromatic offset.',steps:[EffectPresetStep('zoom_warp',parameters:{'amount':0.16,'center_x':0.5,'center_y':0.5}),EffectPresetStep('chroma_smear',parameters:{'shift':1.4})]),
    EffectPresetDefinition(id:'distortion_split_signal',name:'Split Signal',category:'Distortion',description:'Chromatic tearing and analogue signal breakup.',steps:[EffectPresetStep('chroma_smear',parameters:{'shift':6}),EffectPresetStep('analog_glitch',parameters:{'shift':5,'noise':26,'fps':18}),EffectPresetStep('scanlines',parameters:{'spacing':4,'thickness':1,'opacity':0.2})]),
    EffectPresetDefinition(id:'utility_soft_cleanup',name:'Soft Cleanup',category:'Utility',description:'Light noise reduction with detail preservation.',steps:[EffectPresetStep('chroma_denoise',parameters:{'threshold':0.08,'window':3}),EffectPresetStep('soft_focus',parameters:{'radius':0.35,'brightness':0.01})]),
    EffectPresetDefinition(id:'utility_sharpen_edges',name:'Edge Definition',category:'Utility',description:'Controlled high-frequency sharpening for crisp footage.',steps:[EffectPresetStep('high_pass_sharpen',parameters:{'amount':1.45}),EffectPresetStep('color_grade',parameters:{'contrast':1.06})]),

  ];

  static EffectPresetDefinition? find(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  static List<String> get categories =>
      all.map((preset) => preset.category).toSet().toList()..sort();
}
