# VW odometer discovery — 2026-10-26

Pelican returned no discoveries for engine 7E0 DID 1160 and transmission 7E1 DID 3841 on the user's Jetta. Ordinary RPM works. Those results do not establish that the diagnostic port cannot provide mileage.

## Research

Primary public definitions inspected on 2026-10-26:
- https://github.com/OBDb/Volkswagen-Jetta/blob/main/signalsets/v3/default.json
- https://github.com/OBDb/.schemas/blob/main/signals.json
- https://pelican.clutch.engineering/cars/volkswagen/jetta/parameters#m-odometer
- https://www.ross-tech.com/vcds/tour/m-blocks.php
- https://www.ross-tech.com/vcds/tour/EDC-15-Mileage.php

The useful new lead is cluster 714 -> 77E, DID 2203, with `din:03`. The schema defines `din` as the diagnostic level needed by the ECU. The source limits this definition to model years through 2018, but Pelican's detailed support results include failures for 2014. It remains a candidate, not verified support. Cluster DID 22B8 has a documented 32-bit /1000 km value; confirmation on newer cars does not establish 2014 compatibility. A decoded metre unit is not proof of actual metre-level update resolution.

Ross-Tech distinguishes KWP measuring blocks from UDS advanced measuring values. Its EDC15/16 mileage utility explicitly excludes newer common-rail engines; it is not proof of support for this Jetta. Existing DriveLine TP2.0 code is a separate possible avenue, but no reviewed odometer block was established, so this change does not extend its allowlist or send guessed raw frames.

## Bounded probe

| Request / response | Read DIDs | Candidate scale |
|---|---|---|
| 7E0 / 7E8 | 108C, 10E0, 1160 | uint32 km, uint32 km, uint32 /1000 km |
| 7E1 / 7E9 | 103D, 3841, 3887 | uint24 km, uint32 /10 km, little-endian uint32 /10 km |
| 714 / 77E | F187, F189 | Part / software identification, raw only |
| 714 / 77E | 2203, 22B8 | uint24 km, uint32 /1000 km |

Cluster candidates are tried in the existing default session, then after a positively acknowledged 1003 extended diagnostic session. 1001 returns to default even after cancellation; absent restoration acknowledgement is reported as a failure. Explicit ELM flow-control headers support nonstandard cluster address pairs. No programming session, security access, coding, DTC clearing, EEPROM operation, or actuator command exists in the probe allowlist.

A saved Volkswagen VIN must match the identity handshake; protocol must be 11-bit 500 kbit CAN; a fresh targeted speed response must be zero. The user must keep the car parked. Recording/finalization must finish before probing. AppStore blocks concurrent recording, auto-reconnect, and profile changes; ScannerRecorder awaits normal-engine teardown and holds exclusive probe ownership. Reconnect explicitly afterwards. Closing the sheet cancels the probe.

Reports preserve request/response headers, commands, raw replies, negative-response codes, and unverified decoded candidates under Application Support/CANConnect/OdometerProbes. The identity handshake itself is not included. Reports are local and only shared by the user. Candidate values never enter OBDSample, trip data, trusted odometer storage, or fuel prefill.

## Vehicle acceptance still required

Run from More -> OBD scanner -> Check VW odometer with Pelican closed, ignition on, car parked, and recording finished. Compare results with the dashboard and retain the report, including failures. Repeat after a known distance before accepting scale, freshness, and resolution. This build does not establish an accessible or high-resolution odometer on the user's vehicle.

## Follow-up: older VW diagnostics, cluster fuel, and trip meter

The user's build-32 report reached cluster 5C6 920 853 A / software 0809. DID 2203 positively returned two bytes, 66 FF, in both default and extended sessions. The dashboard photograph showed 263,671 km; unsigned 26,367 times ten is 263,670 km. This suggests a coarse 10 km counter but is not a verified scale until another boundary is observed. DID 22B8 returned NRC 31 in both sessions. Session 1001 acknowledged restoration. No reinterpretation of those two bytes has been added to authoritative odometer storage.

Research for the older diagnostic path:
- https://forums.ross-tech.com/index.php?threads/31596/ — owner-posted 02E VCDS measurement map includes group 109 with a mileage value, alongside percentage fields. Its controller is a different 02E software revision; this establishes a family-level lead, not exact-controller support or fine resolution.
- https://forums.ross-tech.com/index.php?threads/19787/ — discussion points to DSG group 109 but provides no confirmed high-resolution decoder for this car.
- https://forums.ross-tech.com/index.php?threads/26683/ — posted 2014 Jetta scan includes 03L 997 030 M / 9983 and 02E 300 062 B / 9430, matching the software fingerprints already reviewed by DriveLine.
- https://forums.ross-tech.com/index.php?threads/48323/ — exact engine software scan includes mileage in fault freeze frames. Historical fault mileage is not a live distance counter and is not used as odometer data.

Build 33 adds one read of measuring block 109 (KWP service 21, local identifier 6D) through the existing negotiated TP2.0 path. A current targeted Mode 09 calibration reply must match 02E300062B9430 before any raw TP2.0 setup. The complete assembled payload and raw exchange trace are retained without guessing field scaling. No periodic scheduler or engine measuring-block list is expanded. Cleanup disables custom ISO-TP flow control, closes the VW channel, and restores ordinary OBD settings.

The public OBDb Jetta definition also provides cluster DID 229A in diagnostic session 03, uint16 /8 litres, for vehicles through 2018. It is probed in default and acknowledged extended sessions; decoded candidates are explicitly litres, never kilometres or percent. Wrong ECU, wrong DID, unexpected length, all-FF, conflicts and values over 200 L are not displayed as candidates. Physical scale and gauge/fill-up agreement remain unverified.

The user's trip display shows 340.0 km. This establishes displayed tenth-kilometre resolution for resettable trip distance, not a known diagnostic identifier or the fractional part of lifetime mileage. No sufficiently supported trip-meter identifier was found in this research pass. Neither inferred trip distance nor reset commands are added.
