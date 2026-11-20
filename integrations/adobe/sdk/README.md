# DepthVibe Adobe Bridge SDK

The protocol contracts are in `depthvibe-bridge.d.ts`, the generic TypeScript client is `depthvibe-bridge-client.ts`, and host adapter interfaces are in `adobe-host-adapter.d.ts`.

## Adapter layers

1. Panel shell: Premiere UXP, legacy After Effects CEP or After Effects Beta UXP.
2. Bridge client: pairing, bearer token, effect catalog and composition transport.
3. Host adapter: Adobe-specific DOM calls that read the active sequence/composition.
4. Capability mapper: maps DepthVibe effect IDs/settings to operations the Adobe host supports.

Premiere Pro UXP 25.6+ and After Effects UXP Beta 27.1+ now include host-side read adapters. Premiere captures the active project/sequence, video/audio tracks, clips, source in/out and timing; After Effects captures the active composition and layer timing/flags. The stable After Effects CEP panel captures the same composition/layer metadata through its ExtendScript host script. All snapshots are explicit, metadata-only and read-only.

## Bridge endpoints

- GET /v1/health
- POST /v1/pair with `{ code, hostApp, hostVersion }`
- GET /v1/session
- GET /v1/effects
- GET /v1/composition
- POST /v1/composition with `{ document }`
- GET /v1/adobe/metadata
- POST /v1/adobe/metadata with `{ snapshot }`
- POST /v1/disconnect

The bridge binds only to `127.0.0.1:47653`. The six-digit pairing code rotates after successful use; the panel receives a random bearer token. Sessions are memory-only and are revoked when the app stops or the user disconnects the host panel. Never hard-code codes or tokens inside plugin packages.

## Host snapshot schema

Every snapshot uses `schemaVersion: 1`, `hostApp`, `hostVersion`, `capturedAt` and a host-specific `payload`. The bridge checks the paired host identity and retains the latest snapshot in app memory. It displays the snapshot in the Adobe Integration screen, and host panels can retrieve it using GET /v1/adobe/metadata.

Snapshots contain project/sequence/composition metadata only. They do not include source media bytes, Adobe effect binaries, third-party plugins, or complete host-native effect/keyframe graphs. They are not currently auto-converted to editable DepthVibe layers.
