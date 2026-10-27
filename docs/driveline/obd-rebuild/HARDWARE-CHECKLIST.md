# Hardware acceptance — all pending

The rebuild remains a debug development engine. The installed on-car build 26 uses `DEBUG DRIVELINE_OBD_REBUILD` compilation conditions, so the rebuilt engine stays enabled on ordinary Home Screen launches. To roll back that build, rebuild/install without `DRIVELINE_OBD_REBUILD`. Ordinary Debug builds still accept `--obd-rebuild`; removing that argument restores their legacy default. Never switch engines while recording. No automatic engine fallback exists.

1. On the intended iPhone/MX+/vehicle, record OS, device, accessory firmware and engine build SHA privately. Do ten cold/warm connection cycles without resetting Bluetooth. Verify saved VIN match, conflicting VIN block, missing VIN policy, and no mixed ECU data.
2. Parked first: validate speed/RPM/fuel against known adapter readings. Capture raw logs and diagnostics. New engine currently supports verified 11-bit CAN routing; 29-bit routing and non-CAN are explicitly unsupported, not silently configured as 11-bit.
3. Passenger-operated 20-minute drives: assess 1 Hz, then adaptive 2/3 Hz, separately. Stable-window reference target: >=1 Hz, >=99% valid per supported core PID, max gap <=1.2 seconds. Report whole-trip outages too.
4. Lock phone/app switch for >=5 minutes; ignition cycle; controlled disconnect; within-grace reconnect; reconnect to another VIN. Verify recording state, identity, saved boundaries and raw log recovery.
5. Wi-Fi gets its own connect/cancel/late-prompt/background evidence; MX+ results do not validate Wi-Fi.
6. Optional enhanced reads stay disabled in the replacement engine. Do not enable the six-second engine quiet window until the core-gap tradeoff is measured and explicitly accepted. Legacy controller fingerprint, exact KWP groups and checked restoration remain unchanged.
7. Test real Mac transfer with the current receiver, verify hash/length, identity, processed receipt and no duplicate imports. Partial matched economy is omitted from the old unlabeled economy field while optional coverage metadata remains in the envelope. Raw logs are not sent.
8. Preserve fuel-prefill semantics: last measured odometer is independent of integrated distance. Test manual/automatic stop, sample exclusion, GPS route, fuel entries and navigation on-device.
9. Compare complete coverage drives with multiple full-to-full fills. +/-5% is an investigation target, not a calibration claim.

Build 26 was installed and launched on the physical iPhone on 2026-10-26. Live vehicle, accessory, second vehicle, GPS, actual phone-lock, ignition and on-road acceptance remain pending.
