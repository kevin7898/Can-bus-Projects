# Device build 38 — selectable display and entry units

Gauge boost already subtracts measured ambient pressure. The recording screen now labels it Gauge boost, defaults to psi, and offers a saved psi/kPa/bar selector. More > Units and Settings expose independent distance/speed (km or mi), temperature (C/F), volume (L, US gal, Imp gal), and economy (L/100 km, US mpg, Imperial mpg) choices.

Conversions apply to live readings, Today totals, trip lists and story metrics/charts, signal detail values/charts, fuel history, rolling range/reserve, and fuel/vehicle entry forms. Input forms freeze their units while open, convert quantities back to metric on save, and retain odometer provenance. Raw evidence, exports, and diagnostic provenance retain canonical units; this is not a storage migration. The rolling window remains 500 km regardless of display units. Static sample illustrations and explicitly labelled raw evidence are not rewritten.

Validation: 20 contract and fuel-prefill tests passed, including gauge subtraction, unit conversions, missing ambient, negative gauge values, persistence defaults, input round trips, and US/Imperial distinctions. Signed Debug device build with DRIVELINE_OBD_REBUILD succeeded. 17 shared telemetry tests passed, including the new five-minute ambient-temperature schedule. The simulator UI selection test passed (1 test); validation is recorded in /tmp/driveline-units-segments38.log. Live and Settings unit controls use direct segmented choices.

After the user confirmed recording finished, the full app data was backed up to /tmp/driveline-before38. Build 38 was installed and launched; devicectl verified PID 17147 and the exact app executable. Artifact: /tmp/DriveLineOBDCarTest38/Build/Products/Debug-iphoneos/CANConnect.app.

Odometer: user observed the coarse cluster reading advancing to 263680 km. This supports 10 km resolution; no high-resolution cluster trip signal has been decoded. No decimal reconstruction added. Trip increments require an independent anchor and reset/gap uncertainty handling; unseen travel around resets cannot be recovered exactly from the coarse counter alone.

Ambient temperature (PID 46) is now separate from the frequent coolant/barometer/voltage group: initial read on connection, then 300-second cadence. Failed ambient reads do not accelerate polling; display validity is 315 seconds. Fast-changing signals retain their existing cadence. Vehicle timing remains physical acceptance, separate from scheduler tests.
