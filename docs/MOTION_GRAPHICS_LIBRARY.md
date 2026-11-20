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
