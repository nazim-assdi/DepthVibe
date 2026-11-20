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
- Read the current DepthVibe composition document.
- Query the DepthVibe effect catalog.
- Send a DepthVibe-compatible composition JSON document to the open Compositor.

This sample does not translate arbitrary Premiere timelines or third-party Premiere effects into the DepthVibe project model. Add a host-specific translator using the official Premiere DOM APIs where required. Document import is an explicit panel action.

## Distribution

Use UXP Developer Tool to package a CCX installer. Adobe recommends UDT for packaging; it creates a host-specific package. The user installs the CCX with Creative Cloud Desktop/UPIA and confirms permissions. DepthVibe does not bypass Adobe's installer or licensing.

Official documentation:
- https://developer.adobe.com/premiere-pro/uxp/
- https://developer.adobe.com/premiere-pro/uxp/plugins/distribution/package/
