# DepthVibe

**Android video studio with AI depth, AR, 3D assets and procedural VFX experiments.**

DepthVibe is an Android app by **N Tech**. The 0.3.0 development branch adds an advanced 3D/VFX lab alongside the video studio and virtual 3D camera.

## Development features

### Video Studio
- Import a source video and add sequential video clips.
- Import a separate music track; the export compositor can loop the background audio under the video sequence.
- Trim the first source clip, apply rotation and constant playback speed.
- Export aspect-ratio fit/crop, static title burn-in, brightness and grayscale.
- Save MP4 files to Movies/DepthVibe and share the result.
- Preview 16:9, 9:16, 1:1 and 4:5 canvases, title overlays, speed and color controls.

### AI Depth / 2.5D
- First-use MiDaS Small model download (approximately 33 MB).
- LiteRT GPU inference with CPU fallback.
- Grayscale estimated depth map and an interactive mesh-displacement parallax preview.
- The depth output is relative depth. It does not reconstruct invisible geometry or create a complete watertight 3D human/object model.

### Live AR
- ARCore live camera background and plane detection.
- Tap a tracked plane to place an anchored 3D marker.
- Requires camera permission, Google Play Services for AR and a supported Android device.

### Recorded video motion solve
- OpenCV ORB feature detection/matching.
- Essential-matrix and relative pose recovery on sampled frames.
- This is a first-pass monocular visual-odometry solver. It does not yet provide metric scale, loop closure, global bundle adjustment, lens calibration or production-grade full SLAM.

### 3D Assets and VFX
- GLB loading using Filament glTF renderer.
- Static OBJ geometry import with orbit/zoom preview.
- Filament key-light intensity control and real-time 3D scene preview.
- Fire, smoke and shatter-style particle simulation preview with gravity and particle lifetime.
- Typed node-graph model, editable graph links, keyframe interpolation and curve preview.

## Important limitations

This is an actively developing mobile editor, not yet a complete After Effects replacement. The following are not complete: MTL texture/material import for OBJ, IBL/HDR environment relighting controls, mesh-fragment shatter, particle baking into final video, image/overlay compositing in export, overlapping multi-track video layers, audio mixing/ducking, cross-fade transitions, LUT import, masks, full graph execution, and export-linked keyframe animation. Split markers are still timeline markers, not independently editable clip segments.

ARCore and GPU behavior must be checked on physical phones. AI depth needs a first-use network model download. Lower-end devices may need reduced preview resolution/particle counts.

## Build

Requirements: Android SDK Platform 36, JDK 17 and Gradle 8.13.

```bash
gradle :app:assembleDebug
gradle :app:testDebugUnitTest
```

Open the root folder in Android Studio and run the `app` configuration on an Android device or emulator.

## Stack

- Kotlin 2.4.0, Jetpack Compose and AndroidX Media3
- LiteRT 2.3.0 and MiDaS Small model
- ARCore 1.56.0
- Filament 1.70.1
- OpenCV 4.11.0
- OpenGL ES 2.0
- GitHub Actions APK artifacts

## Project
- Product: DepthVibe
- Developer: N Tech
- Package: `com.ntech.depthvibe`
- Version: 0.3.0
