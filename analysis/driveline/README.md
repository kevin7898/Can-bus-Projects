# DriveLine capture analysis (MK6 Jetta TDI)

Notes from analysing a batch of DriveLine recordings captured with the DuoCAN on the
drivetrain bus. The captures themselves are not in this repo; see the privacy note in
the root README.

- `dlraw.py` parses `frames.dlraw` and prints a per-ID rate summary.
- `correlate.py` compares polled values in `obd_poll.csv` against every broadcast
  field to find signals that may already be on the bus.

Requires Python 3 with numpy and pandas.

## Findings

### DPF and EGT data is not broadcast
The app polled the regen trigger, regen-active flag, EGT 1–4, DPF differential
pressure and boost. Each was correlated against every u8/u16/12-bit field of every
broadcast ID.

- EGTs, DPF ΔP and boost only reach r ≈ 0.75–0.93, and only against 0x280, 0x288
  and 0x488 (torque, RPM and pedal). Those fields track engine load; they aren't the
  sensors.
- The regen trigger matched 0x62D byte 2 at r = 0.96, but that byte is a **distance
  counter**: it rose by exactly the number of km driven. The match is coincidental.
- **No regen happened in any capture**: regen-active was always 0. Record a full
  regen with start and end markers, then compare broadcasts before and during it to
  look for a regen flag.

### Polling (from the bus)
- The app's polling is SAE Mode 01 on the functional ID 0x7DF: PIDs 6B, 70, 71, 78,
  7A and 8B. The ECU replies in about 6 ms (median), but each PID was read only
  about 1.3 times a second.
- To speed it up, send to the engine's physical ID 0x7E0 instead of 0x7DF; the TCM
  (0x7E1/0x7E9) also answers 0x7DF requests. Also try multi-PID requests
  (`07 01 6B 70 71 78 7A 8B`, up to 6 PIDs each); ECU support is untested.
- Polling gaps came from the ignition being off, or from the app backing off while
  another tester (the MX+) was on the bus.

### The engine ECU speaks TP2.0 / KWP2000 (seen in an MX+ session)
- Channel setup: `0x200: 01 C0 00 10 00 03 01` → `0x201: 00 D0 00 03 40 07 01`.
  The tester then sends on **0x740** and the ECU replies on **0x300**.
- Timing parameters: `A0 0F 8A FF 32 FF` → `A1 0F 8A FF 4A FF`.
- KWP `10 89` (default session) was accepted, and `A8` closes the channel.
  Open-to-close took under 1 s.
- The MX+ session also cleared fault codes (`14 FF 00`) in several modules,
  including the engine.

### Logger and board problems
- **Timestamp scaling:** deltas inside each ~1 s chunk add up to about 2 s. The
  parser treats them as 0.5 µs ticks (`TICK_US`). Fix this in the writer or
  document it there.
- **Error passive while listen-only:** several short captures show the board at
  REC = 128 with 200+ bus errors before it had sent anything, after which it
  (correctly) refused to poll. Check the tap wiring, ground, termination and bit
  timing at that tap point.
- **PCAN UDP transport:** recordings over it contained 0 frames. Only USB GVRET
  captured anything.

## Next steps
1. Capture a full regen (the trigger was over 80% in the last capture) and compare
   broadcasts before and during it.
2. Switch polling to 0x7E0 and test multi-PID Mode 01 requests.
3. Keep one TP2.0 channel open to the ECU (send `A3` keep-alives) for KWP
   measuring blocks or `0x2C` dynamic IDs, instead of opening and closing it.
4. Longer term: bench a spare ECU and map RAM addresses for a broadcast patch.
