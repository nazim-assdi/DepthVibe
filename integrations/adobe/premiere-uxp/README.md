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
- Capture each clip component's parameter schema, current value, time-varying state, keyframe times/values and symbolic interpolation when the Premiere API exposes them.
- Recognize the `AE.ADBE Capsule` MOGRT component and serialize `MogrtText` Source Text values as typed controls, including the author-exposed font family/size/faux-style editability flags.
- Apply captured native values and supported keyframes back to Premiere through ComponentParam actions. The parameter index is verified against the captured display name; a unique name match may be used when component parameter ordering changes. Ambiguous duplicates are skipped rather than guessed.
- Insert imported MOGRT templates and capture the newly added clip's exposed control summary where the host returns a matchable track item.
- Send an explicit metadata-only snapshot to DepthVibe. The latest snapshot appears in Extension Manager > Adobe Integration.
- Read the current DepthVibe composition document and effect catalog.
- Send a DepthVibe-compatible composition JSON document to the open Compositor.

The active sequence snapshot is a metadata handoff, not a lossless Premiere project conversion. Media bytes, plugin binaries, multicam/nested sequence internals and Premiere-only effects are not copied. ComponentParam animation is round-tripped only when the host exposes the relevant keyframe actions/interpolation API; unsupported parameter types remain preserved as metadata and are listed as skipped. MOGRT Source Text is editable only when the template exposes a uniform/author-editable control. Mixed styling and read-only comments are retained but not forced into editable fields. Premiere 27.0+ is required for the MogrtText value API; keyframe component APIs start in 25.6. The current snapshot is a read-only interchange record; it is not automatically converted into editable DepthVibe layers.

## Distribution

Use UXP Developer Tool to package a CCX installer. Adobe recommends UDT for packaging; it creates a host-specific package. The user installs the CCX with Creative Cloud Desktop/UPIA and confirms permissions. DepthVibe does not bypass Adobe's installer or licensing.

Official documentation:
- https://developer.adobe.com/premiere-pro/uxp/
- https://developer.adobe.com/premiere-pro/uxp/plugins/distribution/package/
