# DepthVibe

**A mobile video-editing studio with a real-time 3D perspective camera workspace.**

DepthVibe is an Android application by **N Tech**. Version 0.2.0 adds media import, trim controls, timeline split markers, preview playback controls, a Media3 MP4 export path and an interactive OpenGL ES 3D viewport.

## Current capabilities

- Import video, audio and image references through Android's document picker.
- Capture a new source video using the device's camera app.
- Preview source video with playback-speed, mute and rotation controls.
- Set trim in/out points and export the selected range to MP4.
- Apply rotation and remove source audio during export.
- Save rendered MP4 files to Movies/DepthVibe and share the result.
- Preview 16:9, 9:16, 1:1 and 4:5 canvas presets.
- Add a title overlay to the editor preview.
- Use an interactive perspective 3D camera: drag to orbit, pinch to dolly and adjust field of view.

## Current limitations

Animated titles, keyframed text and multi-style captions are not yet included. Audio and image imports are currently project references and are not mixed into the exported video. Split markers are visible on the timeline but do not yet produce independent clips. ARCore tracking, AI depth reconstruction, GLB/OBJ rendering, GPU particles, multi-clip composition and advanced colour grading remain future engine work.

## Build

Requirements: Android SDK Platform 36, JDK 17 and Gradle 8.13.

From the repository root:

```
gradle :app:assembleDebug
gradle :app:testDebugUnitTest
```

Open the repository root in Android Studio to import the Gradle project and run the app on an Android device or emulator.

## Technology

- Kotlin and Jetpack Compose
- AndroidX Media3 ExoPlayer
- AndroidX Media3 Transformer
- OpenGL ES 2.0
- GitHub Actions build and APK artifacts

See docs/ARCHITECTURE.md and docs/ROADMAP.md.

## Project

- Product: DepthVibe
- Developer: N Tech
- Package: com.ntech.depthvibe
- Version: 0.2.0
