# Fuel page hierarchy — build 31

Log a fill-up is now the first control on the Fuel page, above filters and history. The long measured-trip-fuel list is collapsed by default under Trip fuel estimates / Show recent drives. A short explanation distinguishes calculated vehicle fuel use from purchases and notes that gaps can leave totals incomplete. Rows show litres without repeating Measured fuel rate; recorded-summary provenance is still labelled where applicable. No fuel observations, fills or calculation policies were changed.

The native UI check passed: fill-up action is hittable without scrolling, opens Add Fuel, closes normally, and the recent-drive disclosure expands. Existing Today start/save actions also passed in that flow. Signed build 31 succeeded with the rebuilt engine enabled, installed in place, and launched on the physical iPhone. Build inventory and exact launched PID/executable were verified.

Local logs: `/tmp/driveline-car31-ui.log`, `/tmp/driveline-car-build31.log`, and `/tmp/driveline-car-launch31.json`.
