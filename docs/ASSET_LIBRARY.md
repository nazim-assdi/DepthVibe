# DepthVibe Asset Library

## Purpose

The in-app Library is a single browser for original native effect looks, editable motion/keyframe recipes and curated transitions. The bundled catalog is available offline after the application is installed. It is not a mirror of copyrighted paid packs; its contents are independently authored using DepthVibe's own renderer and data models.

## Bundled collection counts

| Library type | Included |
|---|---:|
| Built-in native effects | 68 |
| Original multi-effect looks | 39 |
| Editable motion recipes | 54 |
| Built-in transition engine types | 61 |
| Curated transition recipes | 38 |

## Effect looks

The 39 look recipes are organized into Cinematic, Film & Retro, Creator, Dream & Neon, Distortion, and Utility. Each recipe is an ordered stack of one or more effect IDs and optional parameter values.

When a look is applied, CompositionController.applyEffectPreset resolves each effect against EffectCatalog. It ignores unknown effect IDs and parameters, uses the registered default values for unspecified parameters, clamps values to the effect's declared minimum/maximum, and appends each effect as a normal editable EffectInstance. The result is not a flattened bitmap. Users can disable, tune and keyframe each applied effect independently.

## Motion presets

All 54 motion recipes are defined as ordinary transform/opacity KeyframeTracks. Applying one at the current playhead writes editable keyframes to the selected unlocked layer. The new original recipes cover camera push/pull, spin-pop, broadcast lower thirds, spring entrances, elastic rise/drop, squash-stomp, soft pulse, pendulum swing, hover drift, slide-zoom, rotate-away, shrink-out and snap-zoom.

## Transition recipes

The 38 curated transition recipes map to existing TransitionKind values and specify an intended duration. Applying one inserts the corresponding transition for adjacent enabled visual clips, then applies the recipe duration. The application still uses the normal transition compiler, frame validator and FFmpeg export path. At least two enabled video/image/Photoshop visual clips are required.

## Import and online sources

- .dvmpreset remains the portable single-layer format for editable transforms, effects, keyframes and inert Adobe effect metadata.
- User-owned Motion Bro .mbr archives can be imported into the local pack library. Only compatible preset assets are sent to the Adobe host panels; scripts remain inert.
- The signed Extension Marketplace can download .dvext packages from an HTTPS catalog after the publisher key is explicitly trusted. Package bytes are SHA-256 checked against the signed catalog. Automatic updates are opt-in and only apply to DepthVibe extension packages.
- Adobe UXP/CEP packages are opened through their host-specific installer workflows; DepthVibe does not silently install proprietary Adobe plug-ins.

A publisher feed must be configured by the user/operator. The bundled app does not scrape arbitrary websites or bypass payment, license checks, signatures, host compatibility, or third-party plug-in requirements.

## Preview and rendering limits

Effect/transition thumbnails are generated animated guides, not exact frame-rendered previews of the selected source footage. Final output is produced by the native FFmpeg pipeline. Runtime support depends on the filters actually present in the packaged FFmpeg build and must be verified on each target platform.