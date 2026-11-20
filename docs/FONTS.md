# Global Font Manager

DepthVibe's font system is designed around Unicode text, local font ownership and portable composition files.

## Application-wide fonts

Open **Font Manager** from either the Video Studio or Compositor toolbar. The manager scans readable system font folders and reads each font's actual family/subfamily names from its SFNT name table, so the picker can show entries such as `Arial · Bold` instead of only `arialbd.ttf`. It can import one `.ttf` or `.otf` file or bulk-import a folder (up to 2,000 candidate files and 1 GiB per operation), preview the faces, set a default family for the full app, and configure an ordered glyph fallback chain. Installed `.ttc` collections are enumerated face-by-face from the operating system; they are selected by their real system family name rather than copied into DepthVibe. System font scanning runs after the first app frame so it does not block the initial window.

System-folder discovery is currently implemented for:

- Windows: `%WINDIR%\\Fonts` and `%LOCALAPPDATA%\\Microsoft\\Windows\\Fonts` (machine-wide and per-user installs)
- macOS: `/System/Library/Fonts`, `/Library/Fonts` and the user's `~/Library/Fonts`
- Linux: `/usr/share/fonts`, `/usr/local/share/fonts`, `~/.local/share/fonts` and `~/.fonts`
- Android: `/system/fonts` where the platform allows file access
- iOS: system typography is reached through Flutter's normal platform font fallback; private iOS font directories are not scanned.

## Text layer typography

Each Composition Text layer stores its own content, font family, optional local font file, fallback family names, point size, weight, italic, ARGB/RGB colour, letter spacing, line height, text alignment and text-box width. A layer-specific family overrides the application default. A missing glyph searches the ordered fallback families and then the operating system's font fallback.

Text content is edited as a multiline Unicode field and committed with **Save Text**, avoiding an undo entry for every typed character. The same global font and ordered fallback chain also apply to Video Studio title/caption preview and MP4 overlay export.

## Project portability and export

When a `.dvproj` is saved, the project service embeds an imported text layer's selected font file. Where a text layer uses an imported global app font without a local override, the selected font is embedded too. System-installed fonts are saved by real family name, not copied, so the same family must be installed on the other computer for exact rendering. The codec retains typography metadata and remains able to open earlier project documents that do not contain font fields.

The final composition renderer uses Flutter `TextPainter` for line breaking, glyph shaping and bidirectional paragraph layout. It rasterizes the resulting text with a transparent background to a temporary PNG, then passes that PNG through the regular FFmpeg layer graph. This avoids relying on different FFmpeg `drawtext`/FreeType/FriBidi builds on each platform.

## Format, platform and licensing limits

Flutter's runtime `FontLoader` accepts OpenType `.otf` and TrueType `.ttf` byte streams. Direct import of `.ttc` collections is intentionally disabled because `FontLoader.addFont` currently accepts OTF/TTF bytes only; installed TTC faces are still discovered and resolved by the operating system. `.woff` and `.woff2` are not supported by Flutter on all platforms. It does not extract hidden fonts from documents, bypass font licensing restrictions, download every font from the internet, or guarantee every font contains every Unicode script.

The fallback list names families; it does not install them. Folder import batches settings writes and limits a single folder operation to 2,000 candidate font files and 1 GiB total. A fallback is usable only when its font exists on the current device or is installed/embedded separately. Different OS releases ship different fonts. To achieve consistent cross-device typography, use a licensed `.ttf` or `.otf` file and save the project as `.dvproj` so the font asset is included.

Variable-font axes beyond the standard weight/style interface, multi-file family face grouping, OpenType feature controls, font subsetting, colour-font parity and commercial font activation services remain future work.
