# DepthVibe architecture

## Android editor

The Android application uses Kotlin, Jetpack Compose and AndroidX Media3. ExoPlayer previews source footage. Media3 Transformer exports a selected trim range. The current render path applies trim, rotation and source-audio removal, then publishes the MP4 to Android's shared Movies/DepthVibe collection.

## 3D camera viewport

The 3D workspace uses OpenGL ES 2.0 and a perspective view/projection matrix. It draws a perspective grid, wireframe cube and red/green/blue axes. Dragging changes camera azimuth/elevation; pinching changes orbit distance; the field-of-view slider adjusts the virtual lens.

This is a true virtual 3D scene camera. It is not the device camera and does not currently provide ARCore world tracking or camera-locked 3D placement in captured footage.

## Current edit state

- Source video URI and discovered duration
- Editable trim in/out points
- Split markers (not yet independent clip segments)
- Imported audio and image source references
- Preview playback speed, mute and rotation
- Preview canvas aspect-ratio preset
- Preview title text

Important behavior boundaries:
- Playback speed currently affects preview only.
- Aspect ratio currently changes the editor preview canvas only.
- Title is a preview overlay, not burned into the output MP4.
- Audio and image imports are stored as project references; they are not composited into export yet.
- Split controls add timeline markers; they do not yet create independently rendered clips.
- Export currently applies trim, rotation and source-audio removal to one video source.

## Media export

The export manager constructs a clipped MediaItem, wraps it in an EditedMediaItem, and starts Media3 Transformer asynchronously. Output is written to a temporary app-cache file. After a successful render it is copied to Movies/DepthVibe and exposed as a shareable content URI. Temporary render files are deleted after publish or failure.

## Future engines

- Depth: mobile monocular-depth inference, temporal smoothing, foreground masks and disocclusion fill.
- AR: ARCore live pose tracking, camera background and anchored virtual objects.
- Offline camera solve: feature detection, matching, bundle adjustment and diagnostics for imported footage.
- 3D assets: GLB/glTF and OBJ/MTL loading with a physically based renderer.
- Effects: GPU particles, deterministic shatter and a render graph shared by preview and export.

A depth map estimates relative distance; it cannot recover hidden geometry from one image. Live AR tracking is not a replacement for offline tracking of imported video.

## Performance and reliability

- Keep decode, inference and render work off the UI thread.
- Use lower-resolution preview and full-resolution export separately.
- Bound frame queues and release decoded buffers promptly.
- Keep original media read-only and use cache files for temporary renders.
- Check encoder and graphics capabilities before enabling advanced effects.
- Test URI permissions, camera capture and export on representative physical devices.
