# Build 35 — expose startup failures

## Evidence

The private build-34 capture taken after the 16:32 screenshots contains repeated telemetry sessions with only a header and finalized `disconnected` event. No rebuilt-engine exchanges or cluster windows were reached. This places the failure inside platform transport opening / its existing identification handshake, not inside periodic cluster polling. The older legacy scanner journal predates these attempts and must not be treated as current evidence. Build 34 discarded the underlying opening error from its user-facing generic failure message, so the exact Bluetooth/adapter/vehicle failure is not recoverable from that capture.

## Change

Preserve actionable AppFailure text in the rebuilt scanner UI. Distinguish an explicit storage failure from scanner connection/acquisition failure. Record a fixed opening-stage enum and fixed failure category in the existing local telemetry log; do not persist arbitrary error descriptions. The MX+ reports accessory selection, stream opening, adapter identification, configuration, VIN, capability and protocol stages. Polling, VIN checks, reserve calculation and cluster routing are unchanged.

## Validation

35 targeted iOS tests passed: 17 TelemetryRebuildTests, 8 MXPlusTransportTests, 10 FuelRangeTests. New cases verify a startup ATI timeout reaches the UI without a storage diagnosis or any cluster requests, log-category redaction, and precise handshake-stage reporting. Signed device build succeeded; build 35 was installed and normal launch matched the running executable / process 16969. Physical connection recovery remains unverified until a new on-car connection attempt.
