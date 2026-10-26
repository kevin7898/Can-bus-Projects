# DriveLine release checklist

Current Phase 9 classification: **Automated release candidate; physical qualification pending.**

## Before every candidate

- [ ] Confirm the integration branch starts clean and matches its documented remote commit.
- [ ] Back up the Mac library, iPhone state/export, Originals, Receipts and queued transfer payloads. Keep SQLite WAL/SHM sidecars with any SQLite database.
- [ ] Run all shared, Mac, Mac API integration, iPhone unit/UI and compact accessibility tests.
- [ ] Run both Xcode analyzers and complete-concurrency diagnostic builds.
- [ ] Confirm both GitHub Actions workflows pass on the exact applicable code commit. If a documented path filter correctly excludes an unchanged platform, retain the exact latest passing run for that platform and run the changed platform on the candidate commit.
- [ ] Confirm debug/sample fixtures are labelled sample and add zero to real totals.
- [ ] Scan committed changes and evidence for real VINs, routes, scanner serials, addresses, credentials, tokens and receipt content.
- [ ] Review privacy manifests, usage descriptions, entitlements and capabilities against actual APIs.
- [ ] Confirm archive schema 1/2, Mac library schema 3 and iPhone state schema 4 still decode without reset.

## Backup and rollback

1. Quit or pause writers. Copy the complete library/state plus Originals, Receipts and pending transfer payloads to a dated private location.
2. Record the current commit, version/build, stable vehicle and recording counts, and hashes of the backup—not private contents.
3. Validate the copy by restoring into an expendable temporary location and opening it read-only first.
4. If a candidate regresses, quit it, preserve the failing library unchanged, reinstall the previous signed build, and restore the last validated complete backup. Never overwrite the only corrupt source while diagnosing it.
5. Do not change bundle identifiers or storage directories as a rollback shortcut; that creates a parallel empty store rather than restoring data.

## Signed physical qualification

- [ ] Select the local Apple development team for the iPhone app and Live Activity extension without committing credentials/profile data.
- [ ] Archive and validate the signed iPhone candidate; install it on iPhone 17 Pro Max after a private state backup.
- [ ] Run the Phase 7 fictional-2013-to-actual-2014 Jetta review while parked. Never capture the actual VIN in evidence.
- [ ] Test Keep 2013, cancel, accept 2014 and stable UUID continuity.
- [ ] Test MX+ and available Wi-Fi scanner paths, ignition cycles, reconnect inside/after grace, and scanner/GPS independent loss.
- [ ] Leave the vehicle safely stationary long enough for the last GPS observation to become stale; confirm the session stays connected, speed becomes unavailable, and no route point or distance is invented. Resume motion and confirm acquisition continues without flashing unavailable.
- [ ] Run GPS-only and mixed safe-route recordings with a passenger; verify gaps, boost freshness and DPF wording.
- [ ] Verify background/foreground recovery, interrupted draft, duplicate Finish, lock-screen Live Activity and Dynamic Island.
- [ ] Verify offline queue, interrupted retry, authenticated LAN transfer, Mac acknowledgement/processing receipt, hash/UUID continuity and matching metrics.
- [ ] Run VoiceOver, largest Dynamic Type, increased contrast, reduced motion, light/dark and supported rotations physically.

## Mac qualification

- [ ] Verify cold/warm launch, window close/reopen, navigation/selection restoration and quit cleanup using the signed candidate.
- [ ] Verify local-only/LAN modes, port-conflict state, pause/resume queue, interrupted processing and logout/termination.
- [ ] Verify read-only and disconnected-volume behavior against an expendable copy.
- [ ] Check 1080×720 and 1540×1000, light/dark, resize, keyboard-only navigation, full keyboard access and VoiceOver.
- [ ] Enable the intended distribution signing/hardened-runtime configuration, archive, validate and notarize if applicable.

## Release authorization

- [ ] All required physical checks pass and remaining limitations are accepted.
- [ ] Release notes and known limitations match the tested build.
- [ ] Obtain explicit user approval before TestFlight/App Store upload, notarized distribution, public release, or tag creation.
