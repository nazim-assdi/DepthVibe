/// Typography and broadcast-style title recipes. Applying a recipe creates
/// a normal editable text layer and optionally applies native motion keyframes.
class TitlePresetDefinition {
  const TitlePresetDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.sampleText,
    this.fontSize = 84,
    this.fontWeight = 800,
    this.textColor = '#FFFFFFFF',
    this.letterSpacing = 0,
    this.lineHeight = 1.05,
    this.textAlign = 'center',
    this.positionX = 960,
    this.positionY = 540,
    this.motionPresetId = 'fade_in',
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final String sampleText;
  final double fontSize;
  final int fontWeight;
  final String textColor;
  final double letterSpacing;
  final double lineHeight;
  final String textAlign;
  final double positionX;
  final double positionY;
  final String motionPresetId;
}

class TitlePresetCatalog {
  TitlePresetCatalog._();

  static const List<TitlePresetDefinition> all = [
    // CINEMATIC TITLE CARDS
    TitlePresetDefinition(id:'title_epic',name:'Epic Feature Title',category:'Cinematic Titles',description:'Large centred feature title with a cinematic entrance.',sampleText:'THE JOURNEY',fontSize:112,letterSpacing:5,motionPresetId:'zoom_bounce'),
    TitlePresetDefinition(id:'title_minimal',name:'Minimal Cinema',category:'Cinematic Titles',description:'Restrained modern title with generous tracking.',sampleText:'A NEW STORY',fontSize:66,fontWeight:500,letterSpacing:12,motionPresetId:'fade_in'),
    TitlePresetDefinition(id:'title_thriller',name:'Thriller',category:'Cinematic Titles',description:'Compact bold title for dramatic edits.',sampleText:'NO TURNING BACK',fontSize:88,letterSpacing:3,motionPresetId:'drop_in'),
    TitlePresetDefinition(id:'title_documentary',name:'Documentary',category:'Cinematic Titles',description:'Clean editorial documentary title.',sampleText:'THE UNTOLD STORY',fontSize:76,fontWeight:700,letterSpacing:2,motionPresetId:'fade_slide_up'),
    TitlePresetDefinition(id:'title_scifi',name:'Sci-Fi Display',category:'Cinematic Titles',description:'Wide-spaced futuristic heading.',sampleText:'BEYOND THE GRID',fontSize:70,fontWeight:600,textColor:'#FF9CEBFF',letterSpacing:8,motionPresetId:'spin_pop_in'),
    TitlePresetDefinition(id:'title_chapter',name:'Chapter Card',category:'Cinematic Titles',description:'Elegant chapter number and heading.',sampleText:'CHAPTER 01',fontSize:64,fontWeight:600,letterSpacing:7,motionPresetId:'fade_in'),
    TitlePresetDefinition(id:'title_endcard',name:'End Card',category:'Cinematic Titles',description:'A clear closing message with a soft fade.',sampleText:'THANK YOU FOR WATCHING',fontSize:56,fontWeight:700,letterSpacing:2,motionPresetId:'fade_in'),
    TitlePresetDefinition(id:'title_premium',name:'Premium Editorial',category:'Cinematic Titles',description:'Elegant restrained editorial heading.',sampleText:'THE ART OF DETAIL',fontSize:72,fontWeight:500,letterSpacing:5,motionPresetId:'fade_slide_up'),
    // SOCIAL / CREATOR
    TitlePresetDefinition(id:'title_viral',name:'Viral Hook',category:'Creator Titles',description:'Bold first-frame hook for short-form video.',sampleText:'WAIT FOR IT!',fontSize:116,letterSpacing:-1,motionPresetId:'snap_zoom'),
    TitlePresetDefinition(id:'title_big_claim',name:'Big Statement',category:'Creator Titles',description:'Large bold statement for a thumbnail or reel.',sampleText:'THIS CHANGES EVERYTHING',fontSize:84,letterSpacing:-1,motionPresetId:'zoom_bounce'),
    TitlePresetDefinition(id:'title_question',name:'Question Hook',category:'Creator Titles',description:'Question-led title to open a story.',sampleText:'DID YOU KNOW?',fontSize:98,textColor:'#FFFFE08A',motionPresetId:'pop_bounce'),
    TitlePresetDefinition(id:'title_list',name:'Listicle Heading',category:'Creator Titles',description:'Punchy list heading.',sampleText:'5 THINGS TO TRY',fontSize:86,textColor:'#FFB8E2FF',motionPresetId:'drop_in'),
    TitlePresetDefinition(id:'title_reaction',name:'Reaction Caption',category:'Creator Titles',description:'Short energetic reaction caption.',sampleText:'NO WAY!',fontSize:116,textColor:'#FFFFD16A',motionPresetId:'wobble'),
    TitlePresetDefinition(id:'title_tutorial',name:'Tutorial Heading',category:'Creator Titles',description:'Friendly clear lesson heading.',sampleText:'LET\'S GET STARTED',fontSize:72,textColor:'#FF9EE5D2',motionPresetId:'fade_slide_up'),
    TitlePresetDefinition(id:'title_step',name:'Step Marker',category:'Creator Titles',description:'Simple numbered lesson step.',sampleText:'STEP 01',fontSize:88,textColor:'#FFBBAAFF',letterSpacing:3,motionPresetId:'drop_in'),
    TitlePresetDefinition(id:'title_subscribe',name:'Call to Action',category:'Creator Titles',description:'High-visibility subscribe and follow callout.',sampleText:'LIKE • SHARE • FOLLOW',fontSize:58,textColor:'#FFFFD77A',letterSpacing:2,motionPresetId:'zoom_bounce'),
    TitlePresetDefinition(id:'title_new_episode',name:'New Episode',category:'Creator Titles',description:'Series or channel episode launch title.',sampleText:'NEW EPISODE',fontSize:86,letterSpacing:3,motionPresetId:'spin_pop_in'),
    // LOWER THIRDS / BROADCAST
    TitlePresetDefinition(id:'lower_news',name:'News Presenter',category:'Lower Thirds',description:'Broadcast anchor name and role layout.',sampleText:'ALEX MORGAN\nNEWS PRESENTER',fontSize:46,fontWeight:700,textAlign:'left',positionX:600,positionY:850,motionPresetId:'lower_third_rise'),
    TitlePresetDefinition(id:'lower_name',name:'Name & Role',category:'Lower Thirds',description:'Simple speaker identification.',sampleText:'YOUR NAME\nCREATOR / DESIGNER',fontSize:44,fontWeight:700,textAlign:'left',positionX:560,positionY:850,motionPresetId:'lower_third_rise'),
    TitlePresetDefinition(id:'lower_interview',name:'Interview Guest',category:'Lower Thirds',description:'Interview guest and organisation tag.',sampleText:'GUEST NAME\nGUEST / ORGANISATION',fontSize:42,fontWeight:700,textAlign:'left',positionX:600,positionY:860,motionPresetId:'fade_slide_up'),
    TitlePresetDefinition(id:'lower_location',name:'Location Tag',category:'Lower Thirds',description:'Location and date identifier.',sampleText:'DHAKA, BANGLADESH\n21 NOVEMBER 2026',fontSize:40,fontWeight:600,textAlign:'left',positionX:520,positionY:865,motionPresetId:'lower_third_rise'),
    TitlePresetDefinition(id:'lower_topic',name:'Topic Strap',category:'Lower Thirds',description:'Programme or segment topic strap.',sampleText:'SPECIAL REPORT',fontSize:48,fontWeight:800,textAlign:'left',positionX:560,positionY:870,motionPresetId:'lower_third_rise'),
    TitlePresetDefinition(id:'lower_quote',name:'Quote Attribution',category:'Lower Thirds',description:'Quote author and designation.',sampleText:'“A GREAT IDEA”\n— YOUR NAME',fontSize:48,fontWeight:600,textAlign:'left',positionX:560,positionY:860,motionPresetId:'fade_slide_up'),
    TitlePresetDefinition(id:'lower_social',name:'Social Handle',category:'Lower Thirds',description:'Social handle for a creator or guest.',sampleText:'@YOURCHANNEL',fontSize:52,fontWeight:700,textColor:'#FFBCE7FF',textAlign:'left',positionX:460,positionY:890,motionPresetId:'lower_third_rise'),
    TitlePresetDefinition(id:'lower_score',name:'Score Update',category:'Lower Thirds',description:'Compact score or live update lower third.',sampleText:'TEAM A  2 — 1  TEAM B',fontSize:54,fontWeight:800,textAlign:'left',positionX:560,positionY:860,motionPresetId:'drop_in'),
    // TYPE TREATMENTS
    TitlePresetDefinition(id:'type_outline',name:'Outline Style',category:'Typography',description:'Wide tracking and crisp title layout.',sampleText:'OUTLINE',fontSize:108,fontWeight:900,letterSpacing:8,motionPresetId:'fade_in'),
    TitlePresetDefinition(id:'type_serif',name:'Elegant Editorial',category:'Typography',description:'Lightweight high-end editorial title.',sampleText:'The Collection',fontSize:94,fontWeight:400,letterSpacing:1,motionPresetId:'fade_slide_up'),
    TitlePresetDefinition(id:'type_mono',name:'Mono Label',category:'Typography',description:'Compact technical monospace-style label.',sampleText:'[ SYSTEM READY ]',fontSize:42,fontWeight:700,textColor:'#FF93F0D2',letterSpacing:4,motionPresetId:'type_in'),
    TitlePresetDefinition(id:'type_vertical',name:'Vertical Caption',category:'Typography',description:'Narrow title stack suitable for side labels.',sampleText:'CREATIVE\nSTUDIO',fontSize:64,fontWeight:800,letterSpacing:5,motionPresetId:'tilt_in'),
    TitlePresetDefinition(id:'type_kicker',name:'Small Kicker',category:'Typography',description:'Small section label above a headline.',sampleText:'INTRODUCING',fontSize:32,fontWeight:700,letterSpacing:8,motionPresetId:'fade_in'),
    TitlePresetDefinition(id:'type_big_number',name:'Big Number',category:'Typography',description:'Large numeric hero title.',sampleText:'2026',fontSize:180,fontWeight:900,letterSpacing:-4,motionPresetId:'zoom_bounce'),
    // NEWS / EVENTS
    TitlePresetDefinition(id:'event_live',name:'LIVE NOW',category:'Broadcast & Events',description:'Live broadcast marker.',sampleText:'LIVE NOW',fontSize:54,fontWeight:900,textColor:'#FFFF6969',letterSpacing:3,motionPresetId:'pulse_soft'),
    TitlePresetDefinition(id:'event_breaking',name:'Breaking News',category:'Broadcast & Events',description:'High-impact news alert title.',sampleText:'BREAKING NEWS',fontSize:88,fontWeight:900,textColor:'#FFFFD16A',letterSpacing:2,motionPresetId:'snap_zoom'),
    TitlePresetDefinition(id:'event_countdown',name:'Countdown',category:'Broadcast & Events',description:'Event countdown or launch marker.',sampleText:'COMING SOON',fontSize:86,fontWeight:800,textColor:'#FFB8C9FF',motionPresetId:'heartbeat'),
    TitlePresetDefinition(id:'event_podcast',name:'Podcast Header',category:'Broadcast & Events',description:'Podcast episode title.',sampleText:'THE CREATOR PODCAST',fontSize:62,fontWeight:800,textColor:'#FFC2A7FF',letterSpacing:2,motionPresetId:'fade_slide_up'),
    TitlePresetDefinition(id:'event_webinar',name:'Webinar Speaker',category:'Broadcast & Events',description:'Online event speaker identifier.',sampleText:'TODAY  •  8:00 PM',fontSize:52,fontWeight:700,textColor:'#FF9EE5D2',letterSpacing:2,motionPresetId:'lower_third_rise'),
    // OUTRO / CREDITS
    TitlePresetDefinition(id:'outro_follow',name:'Follow for More',category:'Outro & CTA',description:'Closing follow callout.',sampleText:'FOLLOW FOR MORE',fontSize:84,fontWeight:800,textColor:'#FFFFD77A',motionPresetId:'pop_bounce'),
    TitlePresetDefinition(id:'outro_next',name:'Next Episode',category:'Outro & CTA',description:'End card teasing the next episode.',sampleText:'NEXT EPISODE',fontSize:88,fontWeight:800,letterSpacing:4,motionPresetId:'fade_slide_up'),
    TitlePresetDefinition(id:'outro_credits',name:'Credits Heading',category:'Outro & CTA',description:'Simple clean credit title.',sampleText:'CREDITS',fontSize:76,fontWeight:700,letterSpacing:8,motionPresetId:'fade_in'),
  ];

  static TitlePresetDefinition? find(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  static List<String> get categories =>
      all.map((preset) => preset.category).toSet().toList()..sort();
}
