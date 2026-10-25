# DriveLine Phase 5 evidence and roadmap reconciliation

Phase 4 intentionally delivered part of the original Fuel Ledger and Signals
roadmap early. This audit compares the accepted Phase 4 tip
`92922b37f549a5337df117a7c6d8a9b215c1fd2a` with the original Drive Ledger
handoff. Statuses describe the merged baseline before Phase 5 completion.

## Original Phase 5 — Fuel Ledger

| Requirement | Baseline status | Evidence and remaining work |
| --- | --- | --- |
| Migration-safe `FuelEntry` with station/location, currency, price per unit, notes, and optional receipt metadata | Partially implemented | Schema-2 and both platform adapters preserve currency, station, notes, and receipt metadata. Price per unit is deterministically calculated. Location is not a distinct field, and actual receipt bytes are not stored. |
| Mac month summary | Not implemented | Phase 4 has selected-vehicle/date totals, but no calendar-month summary. |
| Mac cost/economy chart | Partially implemented | Tank economy and measured-trip-fuel charts exist. Purchased-cost trend and explicit month context remain. |
| Mac fill ledger | Complete and tested | Full/partial fills, cost, currency, odometer, station, sample status, cost per litre, and valid boundary economy are rendered from real library state. |
| Mac selected receipt detail | Implemented but awaiting acceptance evidence | Receipt metadata appears inline, but there is no selected detail surface or actual receipt file inspection. |
| iPhone fuel history | Complete and tested | Vehicle-scoped history and the Phase 4 Fuel Ledger are backed by real state and exclude samples from totals. |
| iPhone compact Add Fuel form | Partially implemented | Litres, total cost, odometer, date, and full/partial state save. Edit, currency, station, notes, corrections, and receipt selection remain. |
| Tank-to-tank economy only across valid full-fill boundaries, including intervening partial fills | Complete and tested | Shared `DriveLineJourneyPolicy.fuelLedger` groups by stable vehicle ID and includes partial fills within consecutive full-fill boundaries. |
| Purchased fuel, measured trip fuel, and OBD-derived economy remain distinct | Complete and tested | Shared policy and both Phase 4 surfaces use separate fields and labels. |
| Receipt files live outside primary JSON state | Not implemented | Only metadata is currently retained. |
| Complete backup/export and restore include receipts | Not implemented | Mac directory backup has no receipt directory yet; iPhone JSON export contains metadata only. |
| A fill added on iPhone transfers to Mac and survives backup/restore without changing trip telemetry | Partially implemented | Fill metadata travels with a recording transfer, but there is no independent post-trip fill update, receipt-byte transfer, or end-to-end restore proof. |
| Validate litres, cost, odometer ordering, and currency without blocking legitimate corrections | Partially implemented | New-fill numeric and chronological odometer validation exists. Editing/correction semantics and normalized currency validation remain. |

## Original Phase 6 — Signals workspace

Phase 5 does not implement the remaining rows below.

| Requirement | Baseline status | Evidence and remaining work |
| --- | --- | --- |
| Mac searchable grouped signal browser | Not implemented | The Mac currently offers a flat picker per card. |
| Mac configurable synchronized lanes | Complete and tested | Six independently configurable cards share one timestamp; duplicate signal choices remain allowed. |
| Shared vertical scrubber linked to route position | Complete and tested | Chart selection updates the shared timestamp and MapKit marker without interpolation. |
| Current/min/max/average inspector where valid | Partially implemented | Current cursor values, units, source, freshness, and coverage exist; min/max/average are not shown. |
| Elapsed-time/distance switching, zoom/reset, and comparison | Not implemented | The current charts use recorded timestamps. The separate Compare surface does not provide the required alignment controls. |
| iPhone grouped Signals overview with sparklines | Not implemented | Signals are presented contextually, not as a grouped overview. |
| iPhone focused signal detail with trace, range, source, and freshness | Partially implemented | Trip Story has gap-aware traces, synchronized cursor, units, source and coverage. A standalone focused detail and range inspector remain. |
| Contextual entry from Trip Story and More | Implemented but awaiting acceptance evidence | Trip Story embeds synchronized Signals and More exposes vehicle data; explicit navigation acceptance remains for the eventual Phase 6 workspace. |
| Missing/stale values stay unavailable and no unsupported sample rate is claimed | Complete and tested | Shared gap/freshness policies leave unavailable observations empty and preserve real timestamps. |

## Phase 5 completion boundary

This phase finishes the incomplete Fuel Ledger rows only. It does not add the
remaining Phase 6 browser, inspectors, alignment modes, Garage/onboarding, or
release-polish work.
