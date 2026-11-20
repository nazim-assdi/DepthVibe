# DepthVibe Bridge — Adobe CEP compatibility panel

This folder contains the legacy CEP panel adapter. It is a compatibility route for After Effects releases where CEP remains enabled and older Premiere workflows.

## Manual development install

1. Copy the complete after-effects-cep folder to the CEP extension directory.
   - Windows per-user: %APPDATA%/Adobe/CEP/extensions/
   - macOS per-user: ~/Library/Application Support/Adobe/CEP/extensions/
2. Enable CEP debug mode only for local unsigned development. Restart the Adobe application.
3. Open Window > Extensions (Legacy) > DepthVibe Bridge (Legacy CEP).
4. Open DepthVibe > Extension Manager > Adobe Integration, then enter the one-time pairing code.

For signed production ZXP distribution, a publisher must use an Adobe-compatible certificate and signing process. This repository does not contain a publisher private key or signed ZXP installer.

## Migration direction

CEP is a compatibility route only. Premiere's modern plugin API is UXP. After Effects has a public UXP beta; new integrations should migrate to that host's UXP quick starter as its beta APIs stabilise. Keep CEP for existing projects and older releases only.

The CEP panel does not load AEX or PRM native effects into DepthVibe.


## Active composition capture

Choose **Capture active After Effects composition** in the panel. The host-side ExtendScript adapter reads the active CompItem and layer metadata (dimensions, duration, frame rate, layer timing, visibility/solo/lock flags, 3D/adjustment/null state and parent links) through the Adobe CEP host. The snapshot is sent through the authenticated DepthVibe localhost bridge and shown in Extension Manager > Adobe Integration.

Only a metadata snapshot is sent. The project path is not transmitted (only the project filename is included); footage bytes, third-party effect binaries, expressions and complete animated effect property graphs are not copied. This snapshot is read-only and is not a lossless AEP converter or automatic editable-layer import.
