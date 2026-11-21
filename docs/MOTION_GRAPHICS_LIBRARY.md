# Motion Graphics Library

DepthVibe provides 21 original, editable motion-design recipes and native video effects. It does not bundle Motion Bro packs or redistribute commercial source files.

## Motion presets

| Group | Included |
|---|---|
| Entrance | Fade In, Slide In Left/Right/Up/Down, Zoom In, Bounce In, Rotate In, Flip In |
| Exit | Fade Out, Slide Out Left/Right/Up/Down, Zoom Out |
| Scale | Pop Bounce, Elastic Pop |
| Attention | Shake, Pulse, Swing |
| Typography | Text Rise |

Applying a preset adds normal DepthVibe keyframe tracks at the current playhead. The tracks remain editable in the timeline and graph editor.

## Native effect library

The effect library includes Exposure, Hue Rotate, Colorize, Directional Blur, Average Blur, Chroma Denoise, Deband, Deflicker, Scanlines, RGB Split, Posterize Time, Echo Trails, VHS Warp, Fisheye, Radial Blur and Spatial Noise Reduction, in addition to the existing Color, Blur, Stylize, Keying, VFX, Lens, Transform and Tracking effects.

These effects compile to FFmpeg video filters. Availability depends on the FFmpeg build packaged with the application.

## Transition library

The transition picker exposes the full built-in xfade identifier family: fades/dissolves, directional wipes/slides, circle and rectangle crops, distance/radial, smooth, open/close, pixelize, diagonal wipes, slices, blur, squeeze, wind, cover and reveal transitions.

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
