# DepthVibe Adobe Bridge SDK

The protocol contracts are in `depthvibe-bridge.d.ts`, the generic TypeScript client is `depthvibe-bridge-client.ts`, and host adapter interfaces are in `adobe-host-adapter.d.ts`.

## Adapter layers

1. Panel shell: Premiere UXP, legacy After Effects CEP or After Effects Beta UXP.
2. Bridge client: pairing, bearer token, effect catalog and composition transport.
3. Host adapter: Adobe-specific DOM calls that read the active sequence/composition.
4. Capability mapper: maps DepthVibe effect IDs/settings to operations the Adobe host supports.

The first adapters implement the panel and bridge layers. Premiere sequence and After Effects comp/project translation remain host-specific next steps; an adapter must explicitly report lossy mappings and unsupported effects.

## Bridge endpoints

- GET /v1/health
- POST /v1/pair with `{ code, hostApp, hostVersion }`
- GET /v1/session
- GET /v1/effects
- GET /v1/composition
- POST /v1/composition with `{ document }`
- POST /v1/disconnect

The bridge binds only to `127.0.0.1:47653`. The six-digit pairing code rotates after successful use; the panel receives a random bearer token. Sessions are memory-only and are revoked when the app stops or the user disconnects the host panel. Never hard-code codes or tokens inside plugin packages.
