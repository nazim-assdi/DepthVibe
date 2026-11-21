# Motion Graphics Library

DepthVibe provides 34 original, editable motion-design recipes and 68 built-in native video effects. It does not bundle Motion Bro packs or redistribute commercial source files. It does not bundle Motion Bro packs or redistribute commercial source files.

## Motion presets

| Group | Included |
|---|---|
| Entrance | Fade In, Slide In Left/Right/Up/Down, Zoom In, Bounce In, Rotate In, Flip In |
| Exit | Fade Out, Slide Out Left/Right/Up/Down, Zoom Out |
| Scale | Pop Bounce, Elastic Pop |
| Attention | Shake, Pulse, Swing |
| Typography | Text Rise |
| Composite entrance/exit | Fade + Slide Up/Down, Drop In, Tilt In/Out, Vertical Flip In, Overshoot Slide Left/Right |
| Attention/character | Wobble, Heartbeat, Float, Jelly |

Applying a preset adds normal DepthVibe keyframe tracks at the current playhead. The tracks remain editable in the timeline and graph editor.

## Native effect library

The 68-effect built-in library includes the original Color, Blur & Sharpen, Stylize, Compositing, Keying, VFX, Lens, Transform, Tracking, Motion and Noise Reduction groups. New native entries include Vibrance, Color Contrast, Auto White Balance, RGB Channel Mixer, Adaptive Sharpen, Median/Temporal/Non-Local Means Denoise, Frame Blend, Wave Distortion, Heat Haze, Film Gate Weave, Camera Flash, Cinematic Letterbox, Frame Border, 8mm Old Film, Analog Glitch, Bleach Bypass, Sepia Tone and Edge Glow.

Each built-in entry has a typed parameter definition and a native FFmpeg filter mapping. Effects requiring a filter that is absent from the packaged FFmpeg build may still fail at runtime; actual device/build validation remains required.

## Transition library

The transition picker exposes the full built-in xfade identifier family: fades/dissolves, directional wipes/slides, circle and rectangle crops, distance/radial, smooth, open/close, pixelize, diagonal wipes, slices, blur, squeeze, wind, cover and reveal transitions.

The searchable preview browser groups transitions into Fade, Wipe, Move, Shape and Stylize. Hovering a card runs a generated A/B motion sample and its Apply control inserts that transition for the selected clip. These thumbnails are illustrative previews, not a pixel-identical render of every native xfade implementation; final composition output uses FFmpeg's xfade filter.

## Adobe host interoperability

Premiere UXP can enumerate installed video-transition match names and capture active transition track items alongside clip effects. Original native transition identifiers are retained in project metadata.

After Effects export first applies explicit DepthVibe-to-AE mappings, then attempts exact match names for captured native effects. The target system must have the same plug-in installed. Missing effects are reported.

## Compatibility boundary

This is not a copy of all Adobe built-in or third-party plug-ins and not a redistribution of Motion Bro preset packs. Native equivalents are added where there is a documented renderer; unmatched proprietary effect descriptors remain metadata and require the original plug-in on the target machine.


## Import/export formats

- `.dvmpreset`: portable single-layer package with DepthVibe editable transforms, effects, scalar keyframes and Adobe native effect descriptors. External assets and plugin binaries are not bundled.
- `.ffx`: native After Effects animation preset import/export through the AE UXP host API (After Effects 27.0+). The host applies the preset to its selected AE layer(s) and DepthVibe captures the result.
- Premiere installed video/audio effects: discoverable via VideoFilterFactory and AudioFilterFactory (Premiere Pro 25.6+), apply to a selected captured clip, then capture typed values and supported animation back to DepthVibe. Component parameters retain effect match-name, index, display-name and path; schema drift is reconciled only on a unique display-name match. The editor exposes numbers, booleans, enumerated choices, points and colours, plus editable keyframe values and interpolation. Supported settings/keyframes synchronize to Premiere through project transactions. MOGRT Source Text is captured from AE.ADBE Capsule as a typed MogrtText control; text, font and faux styles appear only where the template author exposes them as editable. Read-only comments and mixed styling remain retained rather than misrepresented as editable. MogrtText requires Premiere Pro 27.0+.


## Motion Bro pack library

The Compositor can import legacy user-supplied `.MBR` archives into a local pack library. It reads `pack.info`, categories/subcategories, `(Assets)` and `(Preview)` assets, retaining original files. Search by pack, category or preset name. Compatible `.FFX` entries appear in the After Effects host panel; compatible `.MOGRT` entries appear in the Premiere host panel.

After Effects applies the selected `.FFX` to selected layer(s) using the selected Layer's `applyPreset()` API and saves selected layer properties with `savePreset()`. The AE panel also provides **Sync DepthVibe effect values + keyframes**: it matches selected AE layers by persistent source-layer ID, updates or creates installed native effects by matchName, and sends editable values and supported keyframes to the host. Premiere inserts the selected `.MOGRT` at the current sequence playhead. `.JSX/.JSXBIN` files are displayed as inert assets and never automatically executed. Licensed packs retain their original license requirements; DepthVibe does not activate or unlock them.
