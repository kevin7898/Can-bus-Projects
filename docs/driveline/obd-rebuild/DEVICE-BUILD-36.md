# Build 36 — ignition-only manual recording must not auto-stop

## Physical evidence

The user reported a recording ending when switching apps, explicitly not force-quitting. The two newest saved recordings in the private capture began at 16:40:38 and 16:41:37 local time and lasted about 5.41 and 4.76 seconds. Their RPM/speed samples were zero throughout. The same acquisition session continued receiving standard responses through 16:42:05, after both recordings ended. The user subsequently confirmed recording stayed active after starting the engine.

The existing three-second stationary-zero-RPM auto-stop rule was firing without first observing a running engine. App switching coincided with that rule; this capture does not establish a separate background-acquisition failure.

The same physical session also completed two default-session cluster windows: approximately 0.885 and 0.527 seconds including routing/restoration. Both fuel replies were `77E 05 62 22 9A 00 BF` (23.875 L) and coarse-odometer replies `77E 05 62 22 03 66 FF` (experimental 263670 km). These window durations alone are not proof that every core-sample gap meets a target.

## Fix

Require a valid running-engine observation (RPM >= 400) before stationary zero RPM may trigger automatic completion. Resetting the boundary detector clears that evidence. A manually started ignition-only recording therefore stays active; a later observed running-to-stopped transition still uses the existing repeated-zero/fresh-speed rule. Missing replies are never engine-off evidence.

## Validation

- 17 ScannerLifecycleTests passed, including a new manual ignition-only case that posts background/foreground notifications, receives 20 seconds of zero RPM/speed, retains the same draft and GPS session, and saves only on Finish.
- Signed device build 36 succeeded with the rebuilt engine enabled.
- A dedicated simulator UI test passed actual Home Screen departure, eight seconds away, return to the still-active ignition-only synthetic recording, and Finish/save. This is lifecycle evidence, not physical MX+ background acceptance.
- The user confirmed the active recording was finished and saved before authorizing installation. Private state backup remains outside Git.
