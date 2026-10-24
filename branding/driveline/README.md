# DriveLine Apple identity

The reference PNG is preserved unchanged. `source/` holds three editable, aligned 1024 × 1024 SVG layers reconstructed from that reference: winding road, paired circuit network with five hollow pads and pulse, and road markings. No rounded mask is baked into the artwork.

`DriveLine.icon` is the shared native Icon Composer document. It supplies the background, separate material groups, restrained shadows, Default/Dark colors, and Mono fills for Clear/Tinted. Its saved group order is front to back. Open it in Icon Composer bundled with Xcode. Use Xcode 26 or later to compile; deployment remains iOS 17 and macOS 14.

After editing a source SVG, run `python3 branding/driveline/source/sync_icon.py`. Add `--render` on a Mac with Icon Composer to regenerate the checked-in native preview renders. Material/layout edits belong in `DriveLine.icon/icon.json` through Icon Composer. Both project generators reference the document as a package and set `ASSETCATALOG_COMPILER_APPICON_NAME=DriveLine`; do not add its internal files separately or duplicate it with an active asset catalog.

The iOS and Mac implementation branches carry identical branding assets. Copy this directory when updating the other active checkout; do not merge unrelated app changes to share artwork. Xcode compiles native assets and conventional fallback assets from this document.

Public name: **DriveLine**. Internal project/executable names, bundle IDs, storage directories, Keychain services, Bonjour and `canconnect:` links intentionally remain stable so existing installs upgrade in place.

See [validation](VALIDATION.md) for checks and remaining physical/older-system appearance checks. [Apple's Icon Composer guide](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer) describes layering, Mono appearances and Xcode integration.
