/// External open-asset sources. These are discovery links, not bundled files;
/// every imported item must retain its own source and licence metadata.
class OpenAssetSourceDefinition {
  const OpenAssetSourceDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.licenseLabel,
    required this.countLabel,
    required this.url,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final String licenseLabel;
  final String countLabel;
  final String url;
}

class OpenAssetSourceCatalog {
  OpenAssetSourceCatalog._();

  static const List<OpenAssetSourceDefinition> all = [
    OpenAssetSourceDefinition(
      id:'assetpolish',
      name:'AssetPolish Vector & Sticker Library',
      category:'Overlays & Stickers',
      description:'3,869 CC0 vector assets, including 219 animated icons and 119 animated stickers, plus themed SVG/PNG packs.',
      licenseLabel:'CC0 1.0',
      countLabel:'3,869 assets listed',
      url:'https://www.assetpolish.com/assets/',
    ),
    OpenAssetSourceDefinition(
      id:'daedal',
      name:'DAEDAL Film Assets',
      category:'Overlays & Color',
      description:'Procedural LUTs, grain, light leaks, burns, bokeh, flares, frames and sound effects.',
      licenseLabel:'CC0 1.0 (published terms)',
      countLabel:'34 resources · LUTs · 4K overlays · SFX',
      url:'https://daedal.art/film-assets/',
    ),
    OpenAssetSourceDefinition(
      id:'clr_audio',
      name:'CLR Open Audio',
      category:'Audio Presets & Media',
      description:'Sound effects and music; each item identifies whether it is CC0, public domain, CC BY or CC BY-SA.',
      licenseLabel:'Per-item CC0 / PD / BY / BY-SA',
      countLabel:'5,636 sounds · 307 songs',
      url:'https://clr.fm/openaudio/',
    ),
    OpenAssetSourceDefinition(
      id:'openfilm',
      name:'OpenFilm Community Library',
      category:'Audio · Overlays · Transitions',
      description:'Community collection of original CC0 sounds, music, CSS overlays, effects and transitions.',
      licenseLabel:'CC0 community submissions',
      countLabel:'Community packs',
      url:'https://github.com/openfilm/library',
    ),
    OpenAssetSourceDefinition(
      id:'lutr',
      name:'LUTr Open LUT Collections',
      category:'Color Presets',
      description:'Curated index of color grading LUT collections with source repositories and license notes.',
      licenseLabel:'Per-project licence',
      countLabel:'Curated LUT index',
      url:'https://github.com/cyberhirsch/LUTr/blob/main/OPEN_SOURCE_LUT_COLLECTIONS.md',
    ),
    OpenAssetSourceDefinition(
      id:'open_film_luts',
      name:'Open Source Film LUTs',
      category:'Color Presets',
      description:'Collected film emulation LUTs from multiple projects; preserve the licence of every contributing project.',
      licenseLabel:'Mixed licences · see files',
      countLabel:'154 LUTs listed',
      url:'https://huggingface.co/Norton0924/OpenSourceLuts',
    ),
    OpenAssetSourceDefinition(
      id:'openmoji',
      name:'OpenMoji',
      category:'Overlays & Stickers',
      description:'Open emoji and symbol artwork for titles, stickers and overlays.',
      licenseLabel:'CC BY-SA 4.0 · attribution/share-alike',
      countLabel:'Open icon collection',
      url:'https://openmoji.org/',
    ),
    OpenAssetSourceDefinition(
      id:'kenney',
      name:'Kenney Asset Packs',
      category:'Overlays · Audio · Graphics',
      description:'Game-style UI, sprite, texture and sound packs; confirm the license on each pack page.',
      licenseLabel:'Many packs CC0 · check each pack',
      countLabel:'Free asset packs',
      url:'https://kenney.nl/assets',
    ),
    OpenAssetSourceDefinition(
      id:'motionlab',
      name:'MOTION/LAB Assets',
      category:'Overlays · Textures',
      description:'Original icon, texture and 3D asset packs with per-pack licensing labels.',
      licenseLabel:'CC0 / OFL / MIT as marked',
      countLabel:'Icons · textures · 3D',
      url:'https://motionlab.one/assets',
    ),
  ];

  static OpenAssetSourceDefinition? find(String id) {
    for (final source in all) {
      if (source.id == id) return source;
    }
    return null;
  }
}
