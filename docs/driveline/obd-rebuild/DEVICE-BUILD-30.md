# History navigation responsiveness — build 30

## Cause and change

Drives computed complete journey metrics repeatedly in row badge rendering and in quality filtering. Even source badges converted all samples to the shared recording model. Fuel converted and recalculated every trip's metrics during SwiftUI rendering, including repeated computed-property accesses. These synchronous operations stalled the main thread and could delay navigation away to Garage. Garage's own existing observation/receipt counts were already lightweight; no serialization bug was found there.

History row quality and measured trip fuel now use a shared bounded actor cache. Observation conversion and metric work execute off the main actor. SwiftUI reads small prepared values, showing Checking/Preparing until ready. Source badges inspect only observation presence. Quality filtering prepares results asynchronously. Cancelled/obsolete vehicle or filter requests cannot publish stale results. Full immutable Trip equality on the cache actor invalidates changes even when the ID and sample counts stay the same; the 128-entry cache shares copy-on-write arrays with the library rather than copying raw samples. Summaries use the existing evidence policies and preserve unavailable/sample semantics. No trip data or stored metrics were rewritten.

## Validation

- Eight performance/cache tests passed: existing snapshot bounds and synthetic corpus, history policy parity, same-ID/content edit invalidation, bounded cache eviction, cancellation, 30,000-sample main-actor responsiveness, and warm-cache reuse.
- Two simulator UI tests passed for primary destinations and Today/Fuel recording controls.
- The first physical test activated the already installed build 29. Independent device inventory confirmed 29. It measured Drives 2.810 s and Fuel 3.656 s and failed the 3-second threshold. This is baseline evidence, not a build 30 failure. The test was corrected to launch the intended build, and build 30 was explicitly installed before rerunning.
- Physical build 30 test against the existing private library passed two full navigation rounds, with no fixture/reset arguments. Times include XCTest tap, idle wait and selected-tab accessibility verification; these are not frame-rendering measurements.

| Tab | First pass | Second pass |
| --- | ---: | ---: |
| Drives | 0.513 s | 0.532 s |
| Fuel | 0.483 s | 0.517 s |
| Garage | 0.454 s | 0.481 s |
| Today | 0.515 s | 0.502 s |

Build 30 retains DEBUG DRIVELINE_OBD_REBUILD. In-place installation and post-test normal launch succeeded; device inventory confirms build 30 and the exact launched PID/executable was independently verified. Automatic recording and acquisition behavior were not changed. Heavy historical derivations can still take time to populate asynchronously; opening the tab no longer waits for them.

Local evidence: `/tmp/driveline-car30-tests.log`, `/tmp/driveline-car30-device.log` (baseline), `/tmp/driveline-car30-device-final.log`, and `/tmp/DriveLineOBDCarTest30`. Device test screenshots/logs remain local; no private library contents were committed.
