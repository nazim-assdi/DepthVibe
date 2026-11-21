class CreativeAssetPackDefinition {
  const CreativeAssetPackDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.sourceUrl,
    required this.downloadUrl,
    required this.licenseLabel,
    required this.estimatedBytes,
    this.exactBytes,
    this.includesLicenseFile = true,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final String sourceUrl;
  final String downloadUrl;
  final String licenseLabel;
  final int estimatedBytes;
  final int? exactBytes;
  final bool includesLicenseFile;

  String get sizeLabel {
    final bytes = exactBytes ?? estimatedBytes;
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

/// Downloadable upstream packs with source attribution and redistribution
/// terms preserved. DAEDAL archives are CC0. CLR files retain each item's
/// own licence and attribution in the upstream LICENSES.txt.
class CreativeAssetPackCatalog {
  CreativeAssetPackCatalog._();

  static const String _daedalRelease =
      'https://github.com/luciansofronie/daedal-downloads/releases/download/packs-v1/';
  static const String _daedalSource = 'https://daedal.art/film-assets/';
  static const String _clrRelease =
      'https://github.com/dlaneycreative-design/clr-downloads/releases/download/music-library-v1/';

  static const List<CreativeAssetPackDefinition> all = [
    // DAEDAL — CC0 LUT packs.
    CreativeAssetPackDefinition(id:'daedal_wedding_luts',name:'Wedding Looks LUTs',category:'Color Presets',description:'12 skin-friendly Rec.709 creative LUTs.',sourceUrl:'https://daedal.art/resources/wedding-pack/',downloadUrl:_daedalRelease+'DAEDAL_Wedding_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:4300000),
    CreativeAssetPackDefinition(id:'daedal_cinematic_luts',name:'Cinematic Looks LUTs',category:'Color Presets',description:'8 cinematic creative LUTs.',sourceUrl:'https://daedal.art/resources/cinematic-pack/',downloadUrl:_daedalRelease+'DAEDAL_Cinematic_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:2800000),
    CreativeAssetPackDefinition(id:'daedal_clean_luts',name:'Clean Commercial LUTs',category:'Color Presets',description:'8 clean looks for product, fashion, food and tech.',sourceUrl:'https://daedal.art/resources/clean-commercial-pack/',downloadUrl:_daedalRelease+'DAEDAL_Clean_Commercial_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:2400000),
    CreativeAssetPackDefinition(id:'daedal_film_mono_luts',name:'Film & Mono LUTs',category:'Color Presets',description:'8 analog-inspired and two monochrome LUTs.',sourceUrl:'https://daedal.art/resources/film-and-mono-pack/',downloadUrl:_daedalRelease+'DAEDAL_Film_and_Mono_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:2300000),
    CreativeAssetPackDefinition(id:'daedal_travel_luts',name:'Travel & Documentary LUTs',category:'Color Presets',description:'12 natural looks for travel, landscape and documentary footage.',sourceUrl:'https://daedal.art/resources/travel-and-documentary-pack/',downloadUrl:_daedalRelease+'DAEDAL_Travel_and_Documentary_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:3900000),

    // DAEDAL — CC0 overlays and graphic media.
    CreativeAssetPackDefinition(id:'daedal_film_grain',name:'Film Grain 4K + HD',category:'Overlays & Stickers',description:'35mm, 16mm, 8mm and Super 8 film-grain clips.',sourceUrl:'https://daedal.art/resources/film-grain-pack/',downloadUrl:_daedalRelease+'DAEDAL_Film_Grain_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:506600000),
    CreativeAssetPackDefinition(id:'daedal_light_leaks',name:'Light Leaks & Film Burns',category:'Overlays & Stickers',description:'17 light leaks and 4K film-burn overlays.',sourceUrl:'https://daedal.art/resources/light-leaks-and-burns-pack/',downloadUrl:_daedalRelease+'DAEDAL_Light_Leaks_and_Burns_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:262900000),
    CreativeAssetPackDefinition(id:'daedal_analog_vhs',name:'Analog & VHS',category:'Overlays & Stickers',description:'Scanlines, CRT mask, VHS noise and tape-glitch clips.',sourceUrl:'https://daedal.art/resources/analog-distortion-pack/',downloadUrl:_daedalRelease+'DAEDAL_Analog_Distortion_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:104900000),
    CreativeAssetPackDefinition(id:'daedal_bokeh',name:'Bokeh & Particles',category:'Overlays & Stickers',description:'Seamless bokeh, dust, snow and ember loops.',sourceUrl:'https://daedal.art/resources/bokeh-and-particles-pack/',downloadUrl:_daedalRelease+'DAEDAL_Bokeh_and_Particles_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:35500000),
    CreativeAssetPackDefinition(id:'daedal_camera_overlays',name:'Camera Overlays',category:'Overlays & Stickers',description:'REC, running timecode, VHS play and CCTV overlays.',sourceUrl:'https://daedal.art/resources/camera-overlays-pack/',downloadUrl:_daedalRelease+'DAEDAL_Camera_Overlays_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:300000),
    CreativeAssetPackDefinition(id:'daedal_countdown',name:'Countdown & Slates',category:'Titles & Lower Thirds',description:'Classic countdown leader and clean slate cards.',sourceUrl:'https://daedal.art/resources/timecode-tools-pack/',downloadUrl:_daedalRelease+'DAEDAL_Timecode_Tools_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:1300000),
    CreativeAssetPackDefinition(id:'daedal_dust',name:'Dust & Scratches',category:'Overlays & Stickers',description:'Dust, hair, scratches and old-film damage overlays.',sourceUrl:'https://daedal.art/resources/film-damage-pack/',downloadUrl:_daedalRelease+'DAEDAL_Film_Damage_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:1400000),
    CreativeAssetPackDefinition(id:'daedal_film_burns',name:'Film Burns Collection',category:'Transitions',description:'30 edge and corner film-burn transition clips.',sourceUrl:'https://daedal.art/resources/film-burns-collection/',downloadUrl:_daedalRelease+'DAEDAL_Film_Burns_Collection.zip',licenseLabel:'CC0 1.0',estimatedBytes:256100000),
    CreativeAssetPackDefinition(id:'daedal_film_frames',name:'Film Frames',category:'Overlays & Stickers',description:'35mm, 16mm, Super 8 and 8mm frame PNGs.',sourceUrl:'https://daedal.art/resources/film-frames-pack/',downloadUrl:_daedalRelease+'DAEDAL_Film_Frames_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:700000),
    CreativeAssetPackDefinition(id:'daedal_grain_extra',name:'Film Grain Extra',category:'Overlays & Stickers',description:'Extra 4K and HD grain variations.',sourceUrl:'https://daedal.art/resources/film-grain-extra-pack/',downloadUrl:_daedalRelease+'DAEDAL_Film_Grain_Extra_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:417300000),
    CreativeAssetPackDefinition(id:'daedal_letterbox',name:'Letterbox & Safe Guides',category:'Overlays & Stickers',description:'Cinema bars, title-safe and social safe-zone PNGs.',sourceUrl:'https://daedal.art/resources/letterbox-and-safe-guides-pack/',downloadUrl:_daedalRelease+'DAEDAL_Letterbox_and_Safe_Guides_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:100000),
    CreativeAssetPackDefinition(id:'daedal_flares',name:'Optical Flares & Light FX',category:'Overlays & Stickers',description:'Anamorphic flares, streak flashes, camera flashes and lens-dirt textures.',sourceUrl:'https://daedal.art/resources/optical-flares-and-light-fx-pack/',downloadUrl:_daedalRelease+'DAEDAL_Optical_Flares_and_Light_FX_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:29000000),
    CreativeAssetPackDefinition(id:'daedal_split_screen',name:'Split Screen Layouts',category:'Overlays & Stickers',description:'PNG frames and track mattes for 2–6 source layouts.',sourceUrl:'https://daedal.art/resources/split-screen-pack/',downloadUrl:_daedalRelease+'DAEDAL_Split_Screen_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:600000),

    // DAEDAL — CC0 sound-effect packs.
    CreativeAssetPackDefinition(id:'daedal_whoosh',name:'Whoosh Library',category:'Audio Presets',description:'100 whoosh sounds in WAV 48 kHz / 24-bit.',sourceUrl:'https://daedal.art/resources/whoosh-library/',downloadUrl:_daedalRelease+'DAEDAL_Whoosh_Library.zip',licenseLabel:'CC0 1.0',estimatedBytes:45000000),
    CreativeAssetPackDefinition(id:'daedal_impacts',name:'Cinematic Impacts',category:'Audio Presets',description:'50 booms, punches, sub drops, hits and thuds.',sourceUrl:'https://daedal.art/resources/cinematic-impacts/',downloadUrl:_daedalRelease+'DAEDAL_Cinematic_Impacts.zip',licenseLabel:'CC0 1.0',estimatedBytes:36600000),
    CreativeAssetPackDefinition(id:'daedal_risers',name:'Risers & Tension',category:'Audio Presets',description:'60 risers, reverse cymbals and tension drones.',sourceUrl:'https://daedal.art/resources/risers-and-tension/',downloadUrl:_daedalRelease+'DAEDAL_Risers_and_Tension.zip',licenseLabel:'CC0 1.0',estimatedBytes:82900000),
    CreativeAssetPackDefinition(id:'daedal_trailer',name:'Trailer Design SFX',category:'Audio Presets',description:'Braams, rhythmic pulses, reverse swells and stingers.',sourceUrl:'https://daedal.art/resources/trailer-design/',downloadUrl:_daedalRelease+'DAEDAL_Trailer_Design.zip',licenseLabel:'CC0 1.0',estimatedBytes:43900000),
    CreativeAssetPackDefinition(id:'daedal_transition_sfx',name:'Transition SFX',category:'Audio Presets',description:'Whooshes, risers, impacts, UI clicks and glitch sounds.',sourceUrl:'https://daedal.art/resources/transition-sfx-pack/',downloadUrl:_daedalRelease+'DAEDAL_Transition_SFX_Pack.zip',licenseLabel:'CC0 1.0',estimatedBytes:17400000),
    CreativeAssetPackDefinition(id:'daedal_ui_sounds',name:'UI Sounds',category:'Audio Presets',description:'Pops, clicks, swipes, notifications and toggle sounds.',sourceUrl:'https://daedal.art/resources/ui-sounds/',downloadUrl:_daedalRelease+'DAEDAL_UI_Sounds.zip',licenseLabel:'CC0 1.0',estimatedBytes:3900000),

    // CLR Music — public-domain / Creative Commons mix. Keep LICENSES.txt.
    CreativeAssetPackDefinition(id:'clr_audio_volume_1',name:'CLR Audio Library — Volume 1',category:'Audio Presets',description:'2,977 sounds, music, foley and ambience. Contains item-level CC0, CC BY and CC BY-SA licences.',sourceUrl:'https://clr.fm/music/download/',downloadUrl:_clrRelease+'clr-music-volume-1.zip',licenseLabel:'Mixed item licences · LICENSES.txt required',estimatedBytes:1747684172,exactBytes:1747684172),
    CreativeAssetPackDefinition(id:'clr_audio_volume_2',name:'CLR Audio Library — Volume 2',category:'Audio Presets',description:'2,659 sounds and music. Contains item-level CC0, CC BY and CC BY-SA licences.',sourceUrl:'https://clr.fm/music/download/',downloadUrl:_clrRelease+'clr-music-volume-2.zip',licenseLabel:'Mixed item licences · LICENSES.txt required',estimatedBytes:1602149346,exactBytes:1602149346),
  ];

  static CreativeAssetPackDefinition? find(String id) {
    for (final pack in all) {
      if (pack.id == id) return pack;
    }
    return null;
  }

  static int get totalEstimatedBytes =>
      all.fold(0, (total, pack) => total + pack.estimatedBytes);

  static List<String> get categories =>
      all.map((pack) => pack.category).toSet().toList()..sort();
}
