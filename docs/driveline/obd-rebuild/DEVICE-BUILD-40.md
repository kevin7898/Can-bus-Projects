# Build 40 — second bounded cluster trip discovery batch

Batch 2 checks 2210–221F and 22A0–22AF, 32 previously untested identifiers near the first batch. These are exploratory neighbors, not known trip-counter identifiers. The scanner screen defaults to Batch 2 and retains Batch 1 through a segmented picker. Reports label the selected batch and exact ranges. Each batch performs at most 64 discovery reads across default and accepted extended sessions.

Existing VIN, stationary-speed, CAN-protocol and cluster-fingerprint gates remain. Recording and connection ownership remain exclusive; session restore and disconnect behavior are unchanged. No inferred trip value or decimal odometer is saved.

The user's first batch reset comparison had 22 unique positive identifiers, identical within each default/extended pair. Between the original and post-reset reports only 220C, 2294, 2297 and 229A changed; none transitioned from nonzero to zero. This does not exclude other encodings or identifiers, and does not prove the trip counter is inaccessible.

Validation: 12 VWOdometerProbeTests passed. New test checks disjoint 32-identifier ranges, exact request sequence/count in both accepted and rejected extended sessions, labelled reports, no numeric promotion and default-session cleanup.

For physical validation: remain parked with ignition on and recording stopped; select Batch 2, photograph dashboard trip/odometer and share the report. After a short drive, repeat Batch 2 while parked without resetting trip.

Signed Debug build with rebuilt engine succeeded; full app data backed up to /tmp/driveline-before40. No draft or unfinalized trip logs were present. Installed and exact launch executable/PID 17365 verified. Physical Batch 2 results remain pending.
