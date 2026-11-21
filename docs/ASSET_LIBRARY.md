# DepthVibe Creative Asset Library

## Overview

The Compositor Library has six primary categories: Overlays & Stickers, Motion, Audio Presets, Titles & Lower Thirds, Color Presets, and Video Effects & Filters. A Transitions collection remains available alongside them. Built-in recipes are data-driven and available offline after installation; user-imported media remains editable project content.

## Bundled catalogue

| Collection | Entries | What Apply does |
|---|---:|---|
| Overlays & Stickers | 72 | 30 native effect overlays apply a registered visual effect; 42 typographic stickers create editable text layers with optional motion |
| Motion | 54 | Adds ordinary editable transform/opacity keyframe tracks to the selected unlocked layer |
| Audio Presets | 41 | Applies track gain, three-band EQ, pan and fade-in/out settings to an audio or video layer |
| Titles & Lower Thirds | 39 | Creates an editable text layer with styling, position and a registered motion recipe |
| Color Presets | 48 | Applies an editable native primary color-grade effect |
| Multi-effect Color Looks | 39 | Adds a stack of independently editable native effects to a selected visual layer |
| Video Effects & Filters | 68 | Adds one registered native visual effect with its parameter controls |
| Curated Transitions | 38 | Adds a native transition recipe with its configured duration |
| Transition Engine | 61 | Exposes the underlying built-in transition types |

The first eight collections total 399 built-in catalogue entries. This is an entry count, not a count of unique media files; an effect may also appear as an overlay recipe or as a step in a multi-effect look.

## Applying the collections

### Overlays & Stickers

Native film, texture, lens and graphic overlays apply existing DepthVibe effect IDs to the selected visual layer. Typographic stickers create regular text layers and may add motion keyframes. Import PNG/JPG/WebP to add a raster overlay as an image layer. SVG files are rendered to a bounded 4096-pixel PNG and imported as raster image layers; their embedded CSS/SMIL animation is not retained, but the resulting image layer can receive DepthVibe motion keyframes. MP4/MOV/M4V/WebM/MKV/GIF clips can be imported as video overlay layers. The editor does not claim the built-in 42 symbol/word stickers are a complete vector-art collection; their visual output depends on installed font glyph coverage.

### Motion

All 54 recipes are ordinary transform/opacity KeyframeTracks. Applying one at the current playhead writes editable keyframes to the selected unlocked layer; the timeline and graph editor remain available.

### Audio Presets

The 41 starting points use the audio controls currently supported by the project model: gain, low/mid/high EQ, pan and fade-in/out. They apply to audio layers and video layers that contain audio. They do not pretend to add reverb, de-esser, convolution, noise-gate or a full plugin rack. Import WAV, MP3, M4A, AAC, FLAC or OGG as a new audio layer.

### Titles & Lower Thirds

Applying one creates a new editable text layer with sample copy, font size, weight, colour, tracking, alignment, text-box width, composition-relative position and a registered motion recipe. Replace the sample copy in the Typography panel and choose any installed font.

### Color Presets

The 48 primary-grade recipes use the registered Color Grade parameter schema. Applying a color preset replaces the selected layer's current primary/curves/LUT grade group with that recipe. The 39 multi-effect looks add a stack of normal, separately editable effect instances. Import `.cube` LUTs through the LUT importer; a LUT is not embedded in a primary-grade-only recipe.

### Video Effects & Filters

The 68 built-in native effects keep typed parameters and use the current FFmpeg/custom render pipeline. Preview tiles are generated visual guides rather than pixel-exact rendering of the source footage. Runtime support depends on the filters present in the packaged FFmpeg build and must be verified on each target platform.

### Transitions

The 38 curated recipes map to existing TransitionKind values and specify intended durations. Applying a recipe requires at least two enabled visual clips. The editor uses the regular frame validator and FFmpeg export path; preview animation is illustrative.

## Local import and online sources

- PNG/JPG/WebP images can be imported as overlay/image layers.
- WAV/MP3/M4A/AAC/FLAC/OGG files can be imported as audio layers.
- `.cube` LUT files, `.dvmpreset` layer presets, and user-supplied Motion Bro `.mbr` packs retain their dedicated import workflows.
- The signed Extension Marketplace downloads `.dvext` packages from an HTTPS catalog after the publisher signing key is explicitly trusted; package bytes are checked against the signed SHA-256 catalogue entry.
- See [OPEN_ASSET_SOURCES.md](OPEN_ASSET_SOURCES.md) for optional public-domain and Creative Commons source libraries, including each source's licence boundary and import workflow.

DepthVibe does not scrape arbitrary websites, bypass payment, unlock proprietary packs or silently install Adobe plug-ins. An online publisher feed must be configured by its operator; a live universal marketplace is not bundled by default.

## Preview and rendering limits

Effect and transition thumbnails are generated animated guides, not exact frame-rendered previews of the selected source footage. Audio presets are EQ/gain/fade starting points, not replacements for unavailable DSP effects. Final video output is produced by the native FFmpeg pipeline. Target-device validation is required before a feature should be described as complete.