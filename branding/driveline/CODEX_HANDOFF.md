# DriveLine icon and Apple app branding — Codex handoff

Prepared 2026-10-24. Repository: `kevin7898/Can-bus-Projects`.

## Start here

Implement the new **DriveLine** public name and the supplied road/CAN-network icon in the existing iPhone app. Prepare a real layered Apple Icon Composer asset with native Liquid Glass appearances, wire it into Xcode, and validate the installed result. Apply the same identity to the Mac app in its own active checkout if available. Preserve the existing app behavior, layouts, data, and connection contracts.

The user selected option 3: the winding road with prominent paired circuit traces and a square-wave signal. The attached image is the subsequent refinement and is the visual reference for implementation. The user requested a Codex handoff so this can be installed in the app on their Mac.

![DriveLine refined icon reference](assets/DriveLine-Icon-Refined.png)

**Artifact status:** this package contains the exact flattened design reference and implementation instructions. It does not contain a layered `.icon` document, production SVGs, generated app-icon catalogs, or an Xcode-tested icon. Do not report native Liquid Glass integration complete merely because the PNG has been added.

## Bring this package into the working app branch

The handoff branch is `codex/driveline-brand-handoff`. It is based on `main` and adds only `branding/driveline/`. The app implementations currently live on other branches.

1. Inspect `git status`, the current branch, worktrees, local instructions, and the Xcode project already in use. Preserve uncommitted work.
2. Fetch the handoff branch. If this package is not already present, cherry-pick its single handoff commit into a suitable implementation branch based on the user's current app work. Do not replace that work with `main` or reset it to the snapshot below.
3. Use separate worktrees or the existing local checkouts for iOS and Mac when necessary. Do not merge unrelated development branches simply to share branding files.

```sh
git fetch origin codex/driveline-brand-handoff
git log -1 --oneline origin/codex/driveline-brand-handoff
# On the appropriate implementation branch, after inspecting the worktree:
git cherry-pick origin/codex/driveline-brand-handoff
```

If the commit is already present, skip the cherry-pick. A newer local app checkout takes precedence over the repository snapshot below.

## Verified repository snapshot

These are observations from GitHub on 2026-10-24, not instructions to discard newer work. No `AGENTS.md` was present in the inspected trees; read any local or newly added instructions before editing.

| Area | Branch and inspected head | Relevant paths |
| --- | --- | --- |
| Handoff base | `main` at `313dd1bbd55c288ff69023ae9f3a3284785d8adf` | Contains Android and locked Mac design; does not contain the iOS implementation |
| iPhone app | `codex/ios-companion` at `7e3ded2fee72ac86c0ebbfc8e214e5cd420fb3e1` | `can-connect-ios/CANConnect.xcodeproj`; scheme `CANConnect` |
| Latest inspected Mac work | `codex/mac-jetta-transfer-signals` at `09acb8c625266fb022ada54e20d316fc154af318` | `mac-app/CANConnect.xcodeproj`; scheme `CANConnect` |
| Earlier Mac implementation | `feature/mac-native-app` at `5437912d5c0059ca3b58cce6618e439f119d4e7f` | Same Mac project location; inspect local progress before choosing a base |

**iOS integration points**

- `can-connect-ios/CANConnect/Info.plist`: `CFBundleDisplayName` is currently `CAN Connect`.
- `can-connect-ios/scripts/make_project.py`: enumerates Swift files and only `.json`/`.txt` resources; does not currently include an icon package or asset catalog. Extend its resource/file-type handling and build settings so regeneration retains the icon.
- App bundle ID is currently `com.canconnect.companion`. The Live Activity extension uses `com.canconnect.companion.recording`.
- `CANConnectLiveActivity/`, `Shared/RecordingActivityAttributes.swift`, `Views/RootView.swift`, and the rest of `Views/` should be inspected for public branding. Keep extension functionality intact.
- Inspected minimum OS is iOS 17.0. Do not raise it merely for icon appearance support.

**Mac integration points**

- `mac-app/Info.plist`: public display name is `CAN / CONNECT`, and `CFBundleName` is `CANConnect`.
- `mac-app/scripts/generate_project.py`: has an empty resources build phase and no icon setup. Extend the generator as well as the checked-in `.pbxproj`.
- Bundle ID is currently `ca.canconnect.mac`; product executable and scheme are `CANConnect`.
- App entry and UI are under `mac-app/Sources/CANConnectMac/`.
- Inspected minimum OS is macOS 14.0. Existing user data lives under `~/Library/Application Support/CANConnect/`.

Neither inspected Apple tree contained an existing app-icon asset catalog or `.icon` package. Recheck before adding one.

## Brand and visual decisions

- Exact public spelling: **DriveLine**, capital D and L.
- The brand covers cars, motorcycles, light trucks, and heavy trucks. Do not use a Jetta silhouette or a single manufacturer's logo.
- Retain the existing dark graphite/navy and electric-blue/cyan design language. This is an icon and name change, not a navigation or dashboard redesign.
- The road must be unmistakable: S bend, widening foreground, clear dashed centerline.
- Circuitry is prominent, not a tiny embellishment: paired blue/cyan traces, five large hollow pads (three left, two right), and the upper-right square-wave motif.
- The square-wave motif is a visual reference to digital vehicle data. It is not an engineering waveform diagram and does not need labels or voltage annotations.
- Preserve the selected silhouette. Minor cleanup for small-size clarity is appropriate: consistent trace widths, smooth road curvature, predictable corner radii, clean joins, equal terminal rings, and useful negative space.
- No DL monogram, wordmark inside the icon, car silhouette, steering wheel, microchip block, carbon-fiber texture, or heavy neon bloom.
- Approximate starting colors: graphite `#10151D`, electric blue `#227DFF`, ice cyan `#72CFFF`. Sample the reference when matching its actual gradients; these values are guidance, not measured exact pixel values.

`assets/DriveLine-Icon-Refined.png` is the exact generated reference, 1254 × 1254, RGB/opaque. It is not a 1024 px store export. Keep it unchanged as provenance. Create new production files under descriptive names.

## Native Liquid Glass implementation

Use the installed Apple toolchain and current Apple documentation. First inspect `xcodebuild -version`, `xcode-select -p`, available SDKs, and Icon Composer. Distinguish build-tool requirements from deployment targets. If the installed toolchain cannot compile native icon documents, document the precise blocker, provide the conventional fallback, and leave the native work explicitly incomplete.

1. Reconstruct/trace the selected mark into clean editable vector geometry. Keep gradients/colors simple and preserve the recognizable design. Do not flatten a screenshot and call it a layered icon. Do not generate unrelated replacement artwork.
2. Use a consistent 1024 × 1024 source canvas for iPhone/iPad/Mac. All foreground exports must use the same canvas and alignment, with transparent space outside their shapes. Keep the background separate. Do not pre-mask rounded corners.
3. Suggested source stack:

   | Layer | Content | Intended treatment |
   | --- | --- | --- |
   | Background | Graphite/navy base | Define color/gradient in Icon Composer; adapt for appearance modes |
   | Circuit network | Both trace colors, terminals, and digital pulse | Restrained glass highlights; preserve separation and readable rings |
   | Road | Blue road body and cyan edge treatment | Strong, saturated focal shape with modest material depth |
   | Markings | Pale centerline dashes | Crisp high-contrast detail; avoid excessive refraction |

   Keep each pair of signal traces together initially; they should not drift into unrelated depth planes. Adjust grouping in Icon Composer if intersections or refraction harm readability.
4. Export flat, simple SVG layers (or transparent PNGs only where required). Let Icon Composer supply dynamic material effects rather than painting permanent shadows and highlights into every source layer.
5. Create a real `DriveLine.icon` document using Icon Composer. Tune Default and Dark for the blue/graphite identity; tune Mono so Clear and Tinted modes retain the road, pulse, and terminal holes. Preview on light, dark, and visually busy wallpapers. Native monochrome/tinted modes will not retain the full blue/cyan palette.
6. Inspect the result at actual Home Screen/Dock sizes and about 32, 48, 60, and 120 px. Tone down highlights/refraction if paired traces merge or the road loses contrast. Avoid over-glassing small details.
7. Check in the `.icon` package and all of its referenced assets, plus the editable vector sources. Use a stable canonical location, such as `branding/driveline/DriveLine.icon`; add appropriate project-relative references in each app. If project-local copies are required, provide a deterministic copy step and one source of truth.
8. Add the icon document with the correct Xcode file type/build handling. Set the app icon build setting (`ASSETCATALOG_COMPILER_APPICON_NAME`) to the document's basename where required by the installed toolchain. Confirm the document is compiled, not just copied as an inert resource. Follow the current Xcode behavior; do not invent a `.icon` JSON schema or rely on an unvalidated renamed PNG.
9. Update both project generators when touching the corresponding app. Treat `.icon` and `.xcassets` directories as packages with proper references; do not accidentally compile their individual internal files as unrelated resources. Run the generator twice and check for unintended changes.
10. Verify the older-OS fallback produced by the current toolchain. Where a conventional catalog is needed, provide appropriately sized opaque iOS PNGs and correct macOS icon assets without duplicate active icon definitions. Preserve the current minimum OS versions. Do not assume a single 1024 px file covers every Mac fallback slot.

Suggested deliverables after implementation:

```text
branding/driveline/
  CODEX_HANDOFF.md
  README.md
  assets/DriveLine-Icon-Refined.png       # unchanged design reference
  source/                              # editable vector source and aligned layers
  DriveLine.icon/                       # native Icon Composer document/package
  previews/                            # exported default/dark/mono previews
  VALIDATION.md                         # toolchain, commands, screenshots, limits
```

## Public rename without breaking existing installs

- Set the iPhone display name to `DriveLine`. Use `DriveLine` for the Mac public brand as well. `DriveLine Hub`, `Link`, and `Dash` were naming suggestions; do not treat those suffixes as a required product rename.
- Update visible headings, About/help copy, recording/Live Activity labels, and relevant accessibility labels where they refer to the product.
- Do not perform a global `CANConnect` replacement. Keep bundle identifiers, signing teams, entitlements, Keychain service/access-group identifiers, storage paths, persisted keys, API routes/schema fields, Bonjour `_canconnect._tcp`, and existing `canconnect:` deep links stable.
- Internal Swift type/module names, directories, project filenames, schemes, and executable names can remain `CANConnect`. Rename them only if there is a demonstrated user-facing need and all build/test references remain correct.
- Preserve tokens, vehicle profiles, trips, pending transfers, scanner setup, and login/background behavior. An icon update must work as an upgrade to the existing install. Do not ask the user to uninstall their real app to refresh its icon.
- Keep Apple-native Liquid Glass icon work separate from any future Android adaptive icon implementation and from a wider in-app Liquid Glass UI redesign.

## Verification and acceptance

Run the relevant installed-toolchain checks; choose an available simulator rather than copying a simulator name blindly.

```sh
xcodebuild -version
xcodebuild -list -project can-connect-ios/CANConnect.xcodeproj
xcodebuild -showdestinations -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect
xcodebuild -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# On the Mac implementation checkout:
xcodebuild -list -project mac-app/CANConnect.xcodeproj
xcodebuild -project mac-app/CANConnect.xcodeproj -scheme CANConnect \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Unsigned builds above are compilation checks, not device-installation or Keychain acceptance. Use the user's existing signing setup for a real upgrade/install. Run the repository's relevant existing tests, especially UI tests affected by changed strings; do not add tests that merely duplicate literal branding strings.

- [ ] Reference art is preserved; production geometry still matches the selected road/circuit concept.
- [ ] A genuine layered `.icon` opens in Icon Composer and compiles with the selected Xcode.
- [ ] Default, Dark, Clear light/dark, and Tinted appearances are inspected where offered by the OS/toolchain; Mono annotation is legible.
- [ ] iPhone Home Screen, Settings, and supported system surfaces show the new icon/name; Mac Dock, Finder, and About/menu surfaces are checked if Mac was implemented.
- [ ] Older supported OS appearance/fallback is actually checked where available, with untested versions listed.
- [ ] Project regeneration retains icon references, asset settings, and public names.
- [ ] Bundle IDs, storage, Keychain, deep links, network discovery, and data contracts remain unchanged.
- [ ] Existing install upgrades without losing vehicles, trips, or pairing; recording and Live Activity launch/tap behavior still work.
- [ ] Screenshots/previews and `VALIDATION.md` distinguish generated artwork, Icon Composer renders, simulator results, and physical-device results.

Finish with the changed files, branch/commit or PR link, build results, icon preview screenshots, and any specific remaining manual step. A flattened fallback alone is not native Liquid Glass completion. Do not publish to the App Store as part of this task.

## Apple references

Reviewed during this handoff; confirm current installed-toolchain behavior when implementing:

- [Icon Composer overview](https://developer.apple.com/icon-composer/) — layered material settings and Default/Dark/Mono annotations.
- [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer) — asset preparation and Xcode integration.
- [App icons — Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/app-icons) — shape, layers, legibility, and appearances.
- [Create icons with Icon Composer — WWDC25](https://developer.apple.com/videos/play/wwdc2025/361/) — flat source artwork, transparent exports, consistent canvases, and native material effects.
- [Icon Composer for Beginners Group Lab — WWDC26](https://developer.apple.com/videos/play/wwdc2026/8012/) — current Mono annotation for clear/tinted appearances.
