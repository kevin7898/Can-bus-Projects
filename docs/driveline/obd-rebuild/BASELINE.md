# Verified baseline — 2026-10-26

Baseline: `7a7eedd`, `codex/obd-workflow-reliability`. The original checkout is `0876a16` (`codex/ios-companion`); its untracked Mac build outputs were left untouched. Rebuild uses a separate managed worktree and `codex/driveline-obd-rebuild`. No applicable AGENTS.md was found in the workspace or ancestor directories.

Existing UI: native SwiftUI DriveLine, minimum iOS 17. Shared Foundation sources in `shared/DriveLineShared` are compiled by SwiftPM and directly by the generated iOS project. Keep that established integration rather than introduce duplicate packages/metrics. Xcode project generator: `can-connect-ios/scripts/make_project.py`.

Commands:
- `swift test --package-path shared/DriveLineShared`
- `xcodebuild build-for-testing -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect -destination 'platform=iOS Simulator,id=C975E238-AE3A-4B13-9FE8-477B69F94928' -derivedDataPath /tmp/driveline-obd-baseline CODE_SIGNING_ALLOWED=NO`

Available booted simulators include DriveLine iPhone 17 Pro Max, iPhone 18 Pro and compact layout check, iOS 27.2. Actual Xcode version and test results are recorded in STATUS.md. Hardware acceptance is pending.

Boundary inventory:
- Platform: `MXPlusTransport.swift`, `VehicleIdentification.swift` (Wi-Fi).
- Ownership/polling: `ScannerRecorder.swift`, `OBDPollScheduler.swift`, `VWMeasuringBlocks.swift`.
- Parsing: `ELMResponses.swift`, `ScannerReadings.swift`, `VWDiagnostics.swift`.
- Persistence: `LocalStore.swift`, `RecordingCheckpoint.swift`, `ScannerJournal` in `Jetta2014Profile.swift`.
- Presentation/lifecycle: `AppStore.swift`, `DriveLinePresentation.swift`, `Models.swift`.
- Analysis: shared `DriveLineMetrics.swift`, `DriveLineDistanceCandidate.swift`.
- Transfer: `MacServer.swift`, frozen legacy envelope and receipt queue.

Observed defects: identity parser flattens ECU headers; transport performs AT content validation before completing prompt; generic capability discovery merges responders; journal accepts raw identity replies; published draft retains full sample arrays; integral accumulator retains all points; economy requires complete start/end coverage. Existing independent parser/transport tests are retained.

UI references: baseline screenshot suite pending. Historical screenshots in `docs/driveline/obd-workflow-reliability/screenshots` are references, not fresh rebuild verification.

Reported 99-minute and other capture rates are unverified. No private raw capture is copied into fixtures. Synthetic test vectors are identified as synthetic.

Completed baseline results: shared suite 44/44; Xcode test build succeeded; selected native UI tests 3/3. Fresh baseline captures are committed in `ui/baseline-*.png`. Two vehicle-detail comparisons have random UUID fixture differences; see ui/README.md.
