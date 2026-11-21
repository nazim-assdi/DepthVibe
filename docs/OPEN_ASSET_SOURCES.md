# Open Asset Sources

External collections below are optional acquisition sources. DepthVibe's offline pack manager now provides 24 downloadable DAEDAL CC0 packs and two complete CLR audio-library volumes (about 5.21 GB before extraction). The user can install them into DepthVibe's local app storage for offline use; they are not embedded in the APK/installer. AssetPolish has no whole-library ZIP, so download a selected-assets ZIP from its site and import it into DepthVibe, preserving the included source/licence notice. Import only items whose current licence permits the intended use.

## Overlays, textures and stickers

- [AssetPolish](https://www.assetpolish.com/licenses/) — its published license page describes 3,869 downloadable vector assets under CC0 1.0, including original animated icons and sticker collections. Re-check the live catalog and preserve source metadata before importing.
- [DAEDAL](https://daedal.art/terms/) — the published terms say the downloadable LUTs, film assets, grain, light leaks, burns, bokeh, flares, overlays, frames and sound effects are CC0 1.0. The page's terms and individual pack contents should be checked at acquisition.
- [MOTION/LAB Assets](https://motionlab.one/assets) — the current asset page lists a small set of original icon, texture and 3D packs; each file/pack is labeled with its license.

## Audio and sound effects

- [CLR Open Audio](https://clr.fm/openaudio/) — a searchable sound/music library whose page lists CC0, public-domain, CC BY and CC BY-SA items. Keep each sound's own license and required credit line; do not treat the entire catalog as CC0.
- [OpenFilm Library](https://github.com/openfilm/library) — a community repository describing original, independently verified CC0 sounds, music, transitions and CSS overlays. Confirm current item approval/checksum and retain its source record.
- [Lots of Sounds](https://www.lotsofsounds.com/sounds) — a CC0 sound-effects catalog with an API; its API and download terms may differ, so verify access and terms before integrating automated download.

## Color and LUT collections

- [LUTr Open Source LUT Collections](https://github.com/cyberhirsch/LUTr/blob/main/OPEN_SOURCE_LUT_COLLECTIONS.md) — a curated index of LUT collections with individual repositories and license details. Re-check each underlying project before bundling.
- [Open Source Film LUTs](https://huggingface.co/Norton0924/OpenSourceLuts) — the collection page describes 154 LUTs from multiple projects and explicitly retains per-project licenses. Do not assume one license applies to every file.

## Icons and symbol libraries

- [OpenMoji](https://openmoji.org/) — CC BY-SA 4.0; attribution is required and adaptations may be subject to ShareAlike. It is not equivalent to a CC0 pack.
- [Kenney](https://kenney.nl/assets) — many asset packs are CC0; check the license on the individual pack page and do not assume reserved brand marks/logos are included.

## Import workflow in DepthVibe

1. For DAEDAL or CLR content, use the Library's LOCAL OFFLINE ASSET PACKS installer. For AssetPolish and other individual sources, download the selected asset/ZIP from its original source and keep its licence/attribution file.
2. Use the installed-pack browser to Add media directly to the project, or use **IMPORT IMAGE / SVG** for still images and SVG files (SVG imports are rasterized to PNG, so embedded SVG animation is not kept), **IMPORT VIDEO / GIF OVERLAY** for animated/video clips, **IMPORT AUDIO FILE** for sound/music, and **IMPORT 3D .CUBE LUT** for color transforms.
3. For `.dvmpreset` and native extension packs, use their dedicated import/marketplace flows.
4. Use project Save/Export to package media for transfer; independently imported files remain subject to their original license terms.

## Licensing and safety boundary

Free download does not automatically mean open license. This directory intentionally separates CC0, public domain, CC BY, CC BY-SA and item-specific licenses. DepthVibe does not bypass paid access, remove DRM, unlock commercial presets, or redistribute proprietary plugin binaries. The downloader uses HTTPS and ZIP CRC validation, rejects unsafe archive entries, and requires a bundled licence file. CRC is corruption detection, not a cryptographic publisher signature; source trust and item-level attribution remain part of the import process.