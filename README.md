# DepthVibe

**A lightweight, Android-first 2D video and 3D compositing workspace.**

DepthVibe is being built around a hybrid Easy / Pro editor. The first repository milestone establishes the native Android application shell, video import and preview, editable project/timeline state, and explicit integration contracts for the advanced engines.

> **Current status:** foundation scaffold. AI depth estimation, full-video camera solving, real-time AR tracking, physics simulation, GLB/OBJ rendering, relighting, and final compositing export are not yet implemented. The UI must not represent these engines as working until their implementations and device tests are complete.

## Product direction

- **Easy Mode:** guided actions and effect presets for creators.
- **Pro Mode:** timeline-oriented editing, transform controls, and a node-graph workspace.
- **AI depth:** estimate per-frame depth, provide depth visualisation, and build a layered/parallax scene with disocclusion handling.
- **Camera tracking:** use ARCore pose tracking for live camera sessions; use a separate visual-SLAM / structure-from-motion solve for imported footage.
- **3D and physics:** import GLB/OBJ assets, render with physically based materials, and simulate particles and shatter effects.
- **Performance:** proxy previews, adaptive render resolution, background processing, and memory-aware asset loading.

## Implemented in this foundation

- Native Android application shell using Kotlin and Jetpack Compose.
- Video import through Android's Storage Access Framework.
- In-app video preview using AndroidX Media3.
- Easy / Pro workspace switch and starter timeline / node-workspace UI.
- Explicit engine contracts and feature-readiness messaging.
- GitHub Actions debug-build workflow.

## Build

Requirements:

- Android Studio with Android SDK Platform 37.
- JDK 17.
- Gradle 9.5.0 (the CI workflow installs this version).

From the repository root:

```bash
gradle :app:assembleDebug
gradle :app:testDebugUnitTest
```

Open the repository root in Android Studio to import the Gradle project and run the `app` configuration on an emulator or Android device.

## Roadmap

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/ROADMAP.md](docs/ROADMAP.md) for engine boundaries, technical constraints, and delivery stages.

## Project

- Product: **DepthVibe**
- Developer: **N Tech**
- Platform target for the first milestone: **Android**
