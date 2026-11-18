# DepthVibe roadmap

## Stage 0 — Flutter core migration (0.4.x)
- [x] Establish a single Flutter/Dart application root.
- [x] Preserve the prior Android Kotlin/Compose code in legacy storage.
- [x] Add responsive editor shell, media import and playback.
- [x] Add camera recording adapters for mobile and desktop.
- [x] Add core trim, speed, rotate, mute, aspect, fit/fill and title/caption editing state.
- [x] Add shared FFmpeg MP4 export path and progress callbacks.
- [x] Add multi-platform CI build jobs and controller tests.
- [ ] Run CI on all runners and repair platform-specific dependency issues.
- [ ] Validate output files and real device camera recording on physical hardware.

## Stage 1 — Non-linear editing
- [ ] Turn split markers into real clip segments.
- [ ] Multiple clips, reorder, ripple/roll edits, proxy media and thumbnails.
- [ ] Audio tracks, music replacement, volume/keyframes and ducking.
- [ ] Image, text, logo and subtitle overlays in preview and export.
- [ ] Transitions, speed ramps and audio waveforms.
- [ ] Autosave, project files, undo/redo and crash recovery.

## Stage 2 — Professional finishing
- [ ] Color wheels, curves, scopes, LUT import and masks.
- [ ] HDR / 10-bit pipeline and export presets.
- [ ] Proxy/background render queue and cache manager.
- [ ] Render graph shared by preview and export.

## Stage 3 — AI depth and 3D
- [ ] Port MiDaS / relative depth inference behind a platform-aware engine.
- [ ] Temporal depth smoothing, segmentation and disocclusion filling.
- [ ] GLB/OBJ asset library and real-time 3D viewport.
- [ ] AR camera support on eligible phones, with graceful desktop fallback.
- [ ] Recorded-video camera tracking and calibrated camera solve.
- [ ] 3D layer compositing, camera-matched shadows and relighting.
- [ ] Physics, mesh shatter and particle baking into final output.

## Stage 4 — Pro node and animation tools
- [ ] Typed node canvas with ports, validation and live graph execution.
- [ ] Keyframe tracks, bezier handles, motion paths and graph curves.
- [ ] Export-linked transforms, camera animation and effect parameters.

## Release gate

A capability is complete only after it is available in the shared project model, visible in preview, present in final export, tested on supported platform targets and covered by automated or reproducible tests. A UI control or preview-only prototype does not count as a finished editor feature.
