# Archived Android-native implementation

This folder preserves the complete Android Kotlin/Jetpack Compose implementation that preceded the Flutter migration (DepthVibe 0.3.0). It is intentionally kept in source control so its Media3 export, MiDaS/LiteRT depth engine, ARCore camera, OpenCV motion solver, Filament/OBJ viewers and particle experiments are not lost.

This directory is not the active Flutter app and is not built by the new root CI pipeline. It can be opened independently in Android Studio by using its Gradle files:

- `build.gradle.kts`
- `settings.gradle.kts`
- `gradle.properties`
- `app/`

The original architecture documents are preserved in `docs/`. Port or redesign these capabilities behind the Flutter renderer interfaces before marking them cross-platform.
