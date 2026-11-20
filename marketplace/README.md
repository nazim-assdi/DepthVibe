# DepthVibe Extension Marketplace publishing

DepthVibe does not ship with a live marketplace server or a pre-trusted publisher. An operator hosts a signed HTTPS catalog. Users import the publisher's public `.dvpub` key, verify its fingerprint through a separate trusted channel and explicitly trust that key before refreshing the feed.

## 1. Generate a publisher key

```sh
dart run tool/generate_publisher_key.dart \
  com.example.publisher \
  "Example Publisher" \
  publisher-2026 \
  marketplace/keys/public/example.dvpub \
  marketplace/keys/private/example.dvpublisher-private.json
```

The `.dvpub` public key can be distributed to users. The private JSON contains an Ed25519 private seed. Store it offline, use a secure backup and never commit it. The repository `.gitignore` excludes the default private-key filename and private key folder.

## 2. Build and hash each package

Create a `.dvext` package and calculate SHA-256 over its exact bytes, for example:

```sh
sha256sum releases/my-effects-1.0.0.dvext
```

Adobe entries may point to HTTPS-hosted CCX or CEP archives. Marketplace signatures do not replace Adobe's own code-signing, permission or installation rules.

## 3. Draft the catalog

Copy `marketplace/index.template.json` to a draft file. Fill the top-level `publisherId`, `keyId` and UTC `generatedAt`. Each entry requires a unique ID, semantic version, matching publisher/key IDs, package type, target hosts, HTTPS download URL and SHA-256 hash.

Package types: `dvext`, `premiere-uxp`, `after-effects-cep`, `after-effects-uxp-beta`.

A catalog is signed by one publisher key. For multiple publishers, host separate feeds.

## 4. Sign and publish

```sh
dart run tool/sign_marketplace_catalog.dart \
  marketplace/catalog-draft.json \
  marketplace/keys/private/example.dvpublisher-private.json \
  marketplace/index.json
```

Host `index.json` and package files over HTTPS. Users enter the catalog URL in Extension Marketplace, import the matching `.dvpub` file, compare its SHA-256 fingerprint out-of-band, then explicitly trust it.

The app verifies the catalog Ed25519 signature before showing entries and checks the exact downloaded package bytes against the SHA-256 value protected by that signature.

## 5. Automatic updates

After opt-in, DepthVibe checks the configured feed on startup and every 24 hours while the app remains open. Automatic updates apply only to DepthVibe `.dvext` packages. Update installation verifies the package ID/version against the signed catalog, validates package contents and transactionally replaces the folder while preserving the previous version if installation fails. A disabled extension remains disabled after an update.

Adobe packages are never silently installed or updated. Premiere CCX packages are opened through the Adobe installer workflow; CEP/After Effects UXP packages are saved for a host-specific install workflow and still require user action in Adobe.
