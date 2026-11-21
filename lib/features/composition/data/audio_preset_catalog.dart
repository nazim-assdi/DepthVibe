import '../domain/composition_models.dart';

/// Original, non-destructive audio starting points using DepthVibe's native
/// track gain, three-band EQ, pan and fade controls.
class AudioPresetDefinition {
  const AudioPresetDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    this.gainDb = 0,
    this.lowEqDb = 0,
    this.midEqDb = 0,
    this.highEqDb = 0,
    this.pan = 0,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final double gainDb;
  final double lowEqDb;
  final double midEqDb;
  final double highEqDb;
  final double pan;
  final int fadeInMs;
  final int fadeOutMs;

  AudioSettings applyTo(AudioSettings base) => base.copyWith(
    gainDb: gainDb.clamp(-24, 24).toDouble(),
    lowEqDb: lowEqDb.clamp(-18, 18).toDouble(),
    midEqDb: midEqDb.clamp(-18, 18).toDouble(),
    highEqDb: highEqDb.clamp(-18, 18).toDouble(),
    pan: pan.clamp(-1, 1).toDouble(),
    fadeInMs: fadeInMs.clamp(0, 30000).toInt(),
    fadeOutMs: fadeOutMs.clamp(0, 30000).toInt(),
  );
}

class AudioPresetCatalog {
  AudioPresetCatalog._();

  static const List<AudioPresetDefinition> all = [
    // VOICE / PODCAST
    AudioPresetDefinition(id:'voice_clean',name:'Clean Voice',category:'Voice & Podcast',description:'Neutral speech EQ with gentle presence.',gainDb:1,lowEqDb:-1.5,midEqDb:1.5,highEqDb:1.8),
    AudioPresetDefinition(id:'voice_warm',name:'Warm Narration',category:'Voice & Podcast',description:'Warmth in the lows and smooth top end.',gainDb:1.5,lowEqDb:2.5,midEqDb:1.2,highEqDb:-0.8),
    AudioPresetDefinition(id:'voice_broadcast',name:'Broadcast Voice',category:'Voice & Podcast',description:'Forward mids and controlled low-end weight.',gainDb:2,lowEqDb:1.5,midEqDb:3,highEqDb:1.4),
    AudioPresetDefinition(id:'voice_radio',name:'Radio Presenter',category:'Voice & Podcast',description:'Compact mid-forward radio tone.',gainDb:1,lowEqDb:-2,midEqDb:3.5,highEqDb:1.2),
    AudioPresetDefinition(id:'voice_deep',name:'Deep Voice',category:'Voice & Podcast',description:'Add low body while keeping speech clear.',gainDb:1,lowEqDb:3.5,midEqDb:1.2,highEqDb:-0.6),
    AudioPresetDefinition(id:'voice_bright',name:'Bright Voice',category:'Voice & Podcast',description:'Lift intelligibility and upper presence.',gainDb:1,lowEqDb:-1,midEqDb:2,highEqDb:3.5),
    AudioPresetDefinition(id:'voice_soft',name:'Soft Spoken',category:'Voice & Podcast',description:'Gentle low-mid warmth without sharp highs.',gainDb:1,lowEqDb:1.5,midEqDb:0.8,highEqDb:-2),
    AudioPresetDefinition(id:'voice_telephone',name:'Telephone',category:'Voice & Podcast',description:'Narrow-band telephone-style voice color.',lowEqDb:-8,midEqDb:4,highEqDb:-8),
    AudioPresetDefinition(id:'voice_asr',name:'Speech Clarity',category:'Voice & Podcast',description:'Reduce rumble and emphasize speech intelligibility.',gainDb:1,lowEqDb:-3,midEqDb:2.5,highEqDb:2),
    AudioPresetDefinition(id:'voice_story',name:'Storytelling',category:'Voice & Podcast',description:'Natural warm narration with a gentle top.',gainDb:1,lowEqDb:1.8,midEqDb:1.3,highEqDb:0.5),
    AudioPresetDefinition(id:'voice_stream',name:'Streamer Mic',category:'Voice & Podcast',description:'Presence-forward streaming voice tone.',gainDb:1.5,lowEqDb:0.5,midEqDb:2.5,highEqDb:2.2),
    AudioPresetDefinition(id:'voice_mobile',name:'Mobile Voice Note',category:'Voice & Podcast',description:'Bring thin mobile speech into a clearer range.',gainDb:2,lowEqDb:1,midEqDb:2,highEqDb:1.5),
    // MUSIC
    AudioPresetDefinition(id:'music_warm',name:'Warm Music',category:'Music',description:'Warm low end and a smooth high range.',gainDb:-1,lowEqDb:2.5,midEqDb:0.5,highEqDb:-0.8),
    AudioPresetDefinition(id:'music_bright',name:'Bright Music',category:'Music',description:'Open up the upper range and presence.',gainDb:-1,lowEqDb:-0.5,midEqDb:0.8,highEqDb:2.6),
    AudioPresetDefinition(id:'music_bass',name:'Bass Weight',category:'Music',description:'Emphasize bass while easing the high mids.',gainDb:-2,lowEqDb:4,midEqDb:-0.8,highEqDb:0.5),
    AudioPresetDefinition(id:'music_vocal',name:'Vocal Focus',category:'Music',description:'Push the vocal range ahead of the backing.',gainDb:-1,lowEqDb:-1.2,midEqDb:2.8,highEqDb:1.2),
    AudioPresetDefinition(id:'music_lofi',name:'Lo-fi Warmth',category:'Music',description:'Soft top end with gentle low-mid character.',gainDb:-1.5,lowEqDb:1.5,midEqDb:0.8,highEqDb:-3),
    AudioPresetDefinition(id:'music_acoustic',name:'Acoustic Detail',category:'Music',description:'Natural acoustic body and string detail.',gainDb:-1,lowEqDb:1.4,midEqDb:1.1,highEqDb:1.8),
    AudioPresetDefinition(id:'music_piano',name:'Piano Warmth',category:'Music',description:'Full piano body and gentle brilliance.',gainDb:-1,lowEqDb:1.8,midEqDb:1.3,highEqDb:1.5),
    AudioPresetDefinition(id:'music_cinematic',name:'Cinematic Score',category:'Music',description:'Broad low foundation and smooth highs.',gainDb:-2,lowEqDb:2.5,midEqDb:0.8,highEqDb:-0.4,fadeInMs:900,fadeOutMs:1300),
    AudioPresetDefinition(id:'music_edm',name:'Electronic Punch',category:'Music',description:'Tight low frequency and bright upper energy.',gainDb:-2,lowEqDb:3,midEqDb:0.3,highEqDb:2.2),
    AudioPresetDefinition(id:'music_ambient',name:'Ambient Space',category:'Music',description:'Soft warm ambience with smooth highs.',gainDb:-3,lowEqDb:1.2,midEqDb:0.4,highEqDb:-1.2,fadeInMs:1400,fadeOutMs:1800),
    AudioPresetDefinition(id:'music_hiphop',name:'Hip-hop Beat',category:'Music',description:'Solid low-end and crisp high percussion.',gainDb:-2,lowEqDb:3.8,midEqDb:0.5,highEqDb:2.4),
    AudioPresetDefinition(id:'music_rock',name:'Rock Energy',category:'Music',description:'Punchy mids with energetic highs.',gainDb:-2,lowEqDb:1.5,midEqDb:2.4,highEqDb:1.8),
    AudioPresetDefinition(id:'music_classical',name:'Classical Balance',category:'Music',description:'Balanced orchestral tonal starting point.',gainDb:-2,lowEqDb:0.8,midEqDb:0.5,highEqDb:0.8,fadeInMs:650,fadeOutMs:1100),
    // CINEMATIC / ENVIRONMENT
    AudioPresetDefinition(id:'sfx_impact',name:'Impact',category:'Cinematic & SFX',description:'Give a hit more low-end weight.',gainDb:0,lowEqDb:4,midEqDb:1,highEqDb:1),
    AudioPresetDefinition(id:'sfx_whoosh',name:'Whoosh Sweep',category:'Cinematic & SFX',description:'Brighten the transient sweep.',gainDb:-1,lowEqDb:-1,midEqDb:1,highEqDb:3),
    AudioPresetDefinition(id:'sfx_rumble',name:'Deep Rumble',category:'Cinematic & SFX',description:'Emphasize low-frequency atmosphere.',gainDb:-3,lowEqDb:5,midEqDb:-3,highEqDb:-6),
    AudioPresetDefinition(id:'sfx_foley',name:'Foley Detail',category:'Cinematic & SFX',description:'Bring out tactile midrange detail.',gainDb:-1,lowEqDb:0.5,midEqDb:2.2,highEqDb:1.8),
    AudioPresetDefinition(id:'sfx_room',name:'Room Ambience',category:'Cinematic & SFX',description:'Smooth atmospheric bed with long fades.',gainDb:-4,lowEqDb:0.5,midEqDb:-0.5,highEqDb:-1,fadeInMs:1800,fadeOutMs:2200),
    AudioPresetDefinition(id:'sfx_wind',name:'Wind / Air',category:'Cinematic & SFX',description:'Reduce low rumble and emphasize air movement.',gainDb:-2,lowEqDb:-4,midEqDb:0.5,highEqDb:1.5),
    AudioPresetDefinition(id:'sfx_water',name:'Water Texture',category:'Cinematic & SFX',description:'A balanced, smooth environmental texture.',gainDb:-2,lowEqDb:0.5,midEqDb:0.5,highEqDb:1),
    AudioPresetDefinition(id:'sfx_transition',name:'Transition Accent',category:'Cinematic & SFX',description:'A clean transition accent with fast fades.',gainDb:-1,lowEqDb:0,midEqDb:1,highEqDb:2,fadeInMs:100,fadeOutMs:180),
    // MIX / OUTPUT
    AudioPresetDefinition(id:'mix_background',name:'Background Bed',category:'Mix & Output',description:'Set music lower with a soft top end.',gainDb:-8,lowEqDb:0.8,midEqDb:-0.8,highEqDb:-1.2,fadeInMs:900,fadeOutMs:1400),
    AudioPresetDefinition(id:'mix_under_voice',name:'Under Dialogue',category:'Mix & Output',description:'Keep a music bed tucked under dialogue.',gainDb:-11,lowEqDb:-1,midEqDb:-1.5,highEqDb:-1,fadeInMs:400,fadeOutMs:600),
    AudioPresetDefinition(id:'mix_transition',name:'Smooth In / Out',category:'Mix & Output',description:'Soft fade handles for a clean music edit.',gainDb:-1,fadeInMs:1200,fadeOutMs:1500),
    AudioPresetDefinition(id:'mix_mono_center',name:'Mono Centre',category:'Mix & Output',description:'Place the track in the centre.',pan:0),
    AudioPresetDefinition(id:'mix_left',name:'Left Accent',category:'Mix & Output',description:'Pan a sound toward the left channel.',pan:-0.65),
    AudioPresetDefinition(id:'mix_right',name:'Right Accent',category:'Mix & Output',description:'Pan a sound toward the right channel.',pan:0.65),
    AudioPresetDefinition(id:'mix_low_cut',name:'Reduce Low Rumble',category:'Mix & Output',description:'Reduce low-frequency energy using the low EQ band.',lowEqDb:-6,midEqDb:0.5,highEqDb:0.5),
    AudioPresetDefinition(id:'mix_air',name:'Air & Presence',category:'Mix & Output',description:'Add upper presence and clarity.',lowEqDb:-0.5,midEqDb:1.2,highEqDb:3),
  ];

  static AudioPresetDefinition? find(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  static List<String> get categories =>
      all.map((preset) => preset.category).toSet().toList()..sort();
}
