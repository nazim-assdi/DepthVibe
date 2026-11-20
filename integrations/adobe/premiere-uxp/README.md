# DepthVibe Bridge — Premiere Pro UXP

This panel runs inside Premiere Pro 25.6 or later, not inside the Flutter application.

## Development install

1. Install Premiere Pro 25.6+ and UXP Developer Tool (UDT).
2. Enable Developer Mode in Premiere Pro Plugins preferences.
3. In UDT, choose Add Plugin and select this folder.
4. Load the plugin. It appears under Window > UXP Plugins > DepthVibe Bridge.
5. Run DepthVibe on the same desktop. Open Extension Manager > Adobe Integration.
6. Enter the one-time pairing code in this panel and connect.

The sample requests network access only to http://127.0.0.1:47653. The app bridge binds only to the IPv4 loopback interface.

## Panel capabilities

- Pair with a one-time code and receive a scoped session token.
- Capture the active Premiere Pro project/sequence using the official Premiere UXP DOM API (25.6+).
- Capture sequence frame size, timebase/duration, video/audio track names, clip names, source in/out, sequence start/end and speed.
- Send an explicit metadata-only snapshot to DepthVibe. The latest snapshot appears in Extension Manager > Adobe Integration.
- Read the current DepthVibe composition document and effect catalog.
- Send a DepthVibe-compatible composition JSON document to the open Compositor.

The active sequence snapshot is a metadata handoff, not a lossless Premiere project conversion. Media bytes, plugin binaries, effect parameter graphs, multicam/nested sequence internals and Premiere-only effects are not copied. The current snapshot is a read-only interchange record; it is not automatically converted into editable DepthVibe layers.

## Distribution

Use UXP Developer Tool to package a CCX installer. Adobe recommends UDT for packaging; it creates a host-specific package. The user installs the CCX with Creative Cloud Desktop/UPIA and confirms permissions. DepthVibe does not bypass Adobe's installer or licensing.

Official documentation:
- https://developer.adobe.com/premiere-pro/uxp/
- https://developer.adobe.com/premiere-pro/uxp/plugins/distribution/package/
