# Motion Graphics Library

DepthVibe provides 81 original, editable motion-design recipes, 76 built-in native video effects, 59 original multi-effect looks, 51 editable title recipes and 64 curated transition recipes. It does not redistribute commercial Motion Bro packs, third-party plug-in binaries or proprietary preset source files.

## Motion presets

| Group | Included |
|---|---|
| Entrance | Fade In, Slide In Left/Right/Up/Down, Zoom In, Bounce In, Rotate In, Flip In |
| Exit | Fade Out, Slide Out Left/Right/Up/Down, Zoom Out |
| Scale | Pop Bounce, Elastic Pop |
| Attention | Shake, Pulse, Swing |
| Typography | Text Rise |
| Composite entrance/exit | Fade + Slide, Drop In, Tilt In/Out, Vertical Flip, Spring/Elastic entrances, Spin Pop, Headline Drop, Lower Third, Slide + Zoom |
| Cinematic/attention | Cinematic Push/Pull, Squash Stomp, Soft Pulse, Pendulum Swing, Hover Drift, Snap Zoom, Rotate Away |
| Attention/character | Wobble, Heartbeat, Float, Jelly |

Applying a preset adds normal DepthVibe keyframe tracks at the current playhead. The tracks remain editable in the timeline and graph editor.

## Native effect library

The 76-effect built-in library includes the original Color, Blur & Sharpen, Stylize, Compositing, Keying, VFX, Lens, Transform, Tracking, Motion and Noise Reduction groups. The unified Asset Library also ships 59 multi-effect looks across Cinematic, Film & Retro, Creator, Dream & Neon, Distortion and Utility. New native effect entries include Vibrance, Color Contrast, Auto White Balance, RGB Channel Mixer, Adaptive Sharpen, Median/Temporal/Non-Local Means Denoise, Frame Blend, Wave Distortion, Heat Haze, Film Gate Weave, Camera Flash, Cinematic Letterbox, Frame Border, 8mm Old Film, Analog Glitch, Bleach Bypass, Sepia Tone and Edge Glow.

The Effect Library uses generated animated thumbnails for the built-in entries. Hover starts the sample and the Add control applies the effect to the selected layer. Thumbnail rendering is a lightweight visual guide, not a frame-accurate preview of source footage or the final FFmpeg pipeline.

Each built-in entry has a typed parameter definition and a native FFmpeg filter mapping. Effects requiring a filter that is absent from the packaged FFmpeg build may still fail at runtime; actual device/build validation remains required.

## Transition library

The transition picker exposes the full built-in xfade identifier family: fades/dissolves, directional wipes/slides, circle and rectangle crops, distance/radial, smooth, open/close, pixelize, diagonal wipes, slices, blur, squeeze, wind, cover and reveal transitions.

The searchable preview browser groups transitions into Fade, Wipe, Move, Shape and Stylize, and the unified Asset Library provides named timing recipes covering all 61 native transition kinds. Hovering a card runs a generated A/B motion sample and its Apply control inserts that transition for the selected clip. These thumbnails are illustrative previews, not a pixel-identical render of every native xfade implementation; final composition output uses FFmpeg's xfade filter.

## Unified Creative Asset Library

The Library tab is organised into six primary categories plus transitions:

| Category | Built-in entries | Apply behaviour |
|---|---:|---|
| Overlays & Stickers | 72 | 30 native effect overlays and 42 editable text/symbol stickers; user images can be imported as image layers |
| Motion | 81 | Editable transform and opacity keyframes |
| Audio Presets | 41 | Track gain, three-band EQ, pan and fade settings |
| Titles & Lower Thirds | 51 | New editable text layers with typography, position and motion |
| Color Presets | 48 | Native primary color-grade recipes |
| Multi-effect Color Looks | 59 | Independently editable effect stacks |
| Video Effects & Filters | 76 | Native visual effect registry, plus installed declarative extension effects |
| Transitions | 64 recipes / 61 engine kinds | Native clip transitions and curated duration presets |

The 492-entry count across the first eight collections is an entry count, not a count of unique media files. Some underlying effect IDs are intentionally reusable as single effects, overlay recipes and steps in multi-effect looks.

The unified browser searches every category and exposes preview/apply actions. Applying a title or typographic sticker creates a real text layer; an image sticker can be imported as an image layer. Audio presets use the audio controls currently implemented in the project model—gain, low/mid/high EQ, pan and fades. They do not add reverb, de-essing, convolution or a full plugin rack.

The same panel links to image/audio/LUT imports, .dvmpreset, the signed publisher marketplace, the user-supplied Motion Bro pack browser and a curated directory of open asset sources. Online sources are opened at their original websites; downloads are not silently repackaged. Check each item's licence and attribution requirements before import or redistribution.

## Adobe host interoperability

Premiere UXP can enumerate installed video-transition match names and capture active transition track items alongside clip effects. Original native transition identifiers are retained in project metadata.

After Effects export first applies explicit DepthVibe-to-AE mappings, then attempts exact match names for captured native effects. The target system must have the same plug-in installed. Missing effects are reported.

## Original After Effects motion tools

The repository includes a standalone ScriptUI palette at `integrations/adobe/after-effects-cep/scripts/DepthVibe_Motion_Tools.jsx`. It provides original quick actions for Null Controllers, parenting, Adjustment Layers, Camera Rigs, editable shapes/text/lower thirds, a native AE effect/VFX shelf, editable motion entrances, layer staggering and keyframe easing. The Timeline tab can sequence selected layers at the playhead, trim in/out points, split layers and place composition/layer markers. The Align tab centres visible layer bounds and distributes visible centres horizontally or vertically for unparented 2D layers; parented and 3D layers are deliberately skipped rather than transformed incorrectly. Run it in After Effects through **File > Scripts > Run Script File**. It is original utility code; it does not install third-party plugins or execute scripts imported from user packs.

## After Effects helper scripts

The standalone ScriptUI toolkit includes original quick actions for native Adjustment Layers, 3D Null parent controllers, cameras, shape/text layers, built-in effects, editable motion entrances/exits, staggering and keyframe easing. Run the script explicitly inside After Effects. The separate CEP bridge is metadata-oriented and is not a lossless AEP importer/exporter.

## Compatibility boundary

This is not a copy of all Adobe built-in or third-party plug-ins and not a redistribution of Motion Bro preset packs. Native equivalents are added where there is a documented renderer; unmatched proprietary effect descriptors remain metadata and require the original plug-in on the target machine.


## Import/export formats

- `.dvmpreset`: portable single-layer package with DepthVibe editable transforms, effects, scalar keyframes and Adobe native effect descriptors. External assets and plugin binaries are not bundled.
- `.ffx`: native After Effects animation preset import/export through the AE UXP host API (After Effects 27.0+). The host applies the preset to its selected AE layer(s) and DepthVibe captures the result.
- Premiere installed video/audio effects: discoverable via VideoFilterFactory and AudioFilterFactory (Premiere Pro 25.6+), apply to a selected captured clip, then capture typed values and supported animation back to DepthVibe. Component parameters retain effect match-name, index, display-name and path; schema drift is reconciled only on a unique display-name match. The editor exposes numbers, booleans, enumerated choices, points and colours, plus editable keyframe values and interpolation. Supported settings/keyframes synchronize to Premiere through project transactions. MOGRT Source Text is captured from AE.ADBE Capsule as a typed MogrtText control; text, font and faux styles appear only where the template author exposes them as editable. Read-only comments and mixed styling remain retained rather than misrepresented as editable. MogrtText requires Premiere Pro 27.0+.


## Motion Bro pack library

The Compositor can import legacy user-supplied `.MBR` archives into a local pack library. It reads `pack.info`, categories/subcategories, `(Assets)` and `(Preview)` assets, retaining original files. Search by pack, category or preset name. Compatible `.FFX` entries appear in the After Effects host panel; compatible `.MOGRT` entries appear in the Premiere host panel.

After Effects applies the selected `.FFX` to selected layer(s) using the selected Layer's `applyPreset()` API and saves selected layer properties with `savePreset()`. The AE panel also provides **Sync DepthVibe effect values + keyframes**: it matches selected AE layers by persistent source-layer ID, updates or creates installed native effects by matchName, and sends editable values and supported keyframes to the host. Premiere inserts the selected `.MOGRT` at the current sequence playhead. `.JSX/.JSXBIN` files are displayed as inert assets and never automatically executed. Licensed packs retain their original license requirements; DepthVibe does not activate or unlock them.
