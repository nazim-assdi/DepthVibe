
# DepthVibe Extension Packages

DepthVibe extensions use the .dvext file extension. A .dvext file is a ZIP archive with manifest.json at its root and optional LUT assets under assets/.

## Version 1 package capabilities

A package can contribute named effect presets that use DepthVibe's audited renderer operations. A package can also bundle a .cube LUT and register it as a named LUT effect.

External packages are declarative data only. They cannot load Dart, JavaScript, native libraries, scripts, arbitrary FFmpeg expressions, shaders, or commands. This restriction keeps one package format usable across Android, iOS, Windows, macOS and Linux and prevents a package from executing arbitrary code.

## Minimal manifest

manifest.json:

~~~json
{
  "format": "DepthVibe.Extension",
  "schemaVersion": 1,
  "id": "com.example.cinematic-pack",
  "name": "Cinematic Pack",
  "version": "1.0.0",
  "author": "Example Studio",
  "description": "A small pack of cinematic looks.",
  "effects": [
    {
      "id": "warm-film",
      "name": "Warm Film",
      "category": "Creative Looks",
      "description": "A warm, restrained film-like color balance.",
      "operation": "color_balance",
      "defaults": {
        "red": 0.12,
        "green": 0.02,
        "blue": -0.08
      }
    }
  ]
}
~~~

The operation must be one of the renderer operations explicitly allowed by DepthVibe. The extension inherits the selected operation's parameter schema and may override only known default values within their declared ranges. This prevents manifest data from injecting filter text.

## Bundled LUT example

Place the LUT at assets/film-look.cube and add this effect to the manifest:

~~~json
{
  "id": "film-look",
  "name": "Film Look LUT",
  "category": "Creative Looks",
  "description": "A bundled 3D lookup table.",
  "operation": "color_lut",
  "asset": "assets/film-look.cube"
}
~~~

Only .cube assets under assets/ are accepted. The package must not contain any other file type. The LUT is copied into the installed extension folder and is embedded in .dvproj packages when the project is saved.

## Packaging and installation

1. Put manifest.json at the root of a folder.
2. Add any referenced .cube files under assets/.
3. ZIP the contents of that folder—not the containing folder.
4. Rename the ZIP file to .dvext (or keep .zip).
5. In DepthVibe, open Extensions and choose Install .dvext.

The package limits are 64 MiB compressed, 128 MiB expanded, 100 archive entries, and 512 KiB for the manifest. ZIP traversal paths, symbolic/hard links, duplicate entries, unknown files, executable content and unsupported render operations are rejected.

## Effect identity and projects

Extension effect IDs are namespaced as extension.<extension-id>.<effect-id>. Composition projects persist these IDs and the selected parameter values/keyframes. A project opened on another device needs the same extension installed and enabled to render its extension effects. Bundled LUT files are embedded by .dvproj Save, but the extension definition itself is not embedded.

## Compatibility and support boundary

The extension manifest schema is versioned. The host app controls the renderer operations and parameter constraints. Extension packages cannot add arbitrary new algorithms; new rendering capabilities require a reviewed host-app update that registers a safe renderer operation. This is an intentional security and cross-platform compatibility boundary.
