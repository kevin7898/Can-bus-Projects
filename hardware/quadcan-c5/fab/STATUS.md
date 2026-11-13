# Rev 1.1 battery prototype — engineering draft

**Not released for manufacture.** Generated with KiCad 9.0.2; no assembled board has been powered. Firmware target compilation and hardware tests are still outstanding. See [the revision and release gates](../docs/BATTERY_REVISION.md).

| Check | Result |
|---|---|
| Schematic vs design source | 123 nets, 0 mismatches |
| PCB vs design source | 185 footprints, all assigned pad nets and values match |
| Schematic ERC | 0 errors; 18 warnings retained for review |
| Courtyards | 0 overlaps, using KiCad 9 courtyard caches |
| Electrical/clearance/hole/short DRC errors | 0 |
| Unrouted connections | 0 |
| Signal tracks on In1 ground plane | 0 |
| DRC warnings | 416; breakdown below |
| Backup policy host test | Pass with `-Wall -Wextra -Werror`; address/undefined sanitizers also pass with leak checking disabled for this environment |
| ESP-IDF target build | Not run; toolchain unavailable |
| Bench, temperature, transient, battery, RF/USB and thermal testing | Not run |

The remaining PCB warnings are 199 silkscreen-over-copper, 199 silkscreen overlaps, 14 silkscreen-edge clearances, one short dangling track stub, one back-layer text mirroring warning, and two footprint/library mismatch warnings (U3 ESP32 module and J4 u.FL connector). Inspect them rather than treating a zero-error count as a manufacturing approval.

ERC retains 14 warnings for U17 spare bidirectional pins tied to ground (firmware must keep all of U17 as inputs) and four symbol/library mismatches: the two MCP symbols have a deliberately corrected tri-state SDO type; the USB and GPS symbols are flattened library derivatives.

The BOM, pick-and-place, Gerbers, drill, schematic PDF and assembly PDF are **prototype review outputs**, generated from this same revision. They are not an assembler-approved order package. The exact protected pack, NTC temperature compatibility, passive MPNs/DC bias, connector polarity, assembly rotation, power loops, impedance-controlled USB/GPS paths and enclosure battery restraint remain release gates.

Rebuild the checked placement and routes with:

```sh
SKIP_ROUTE=1 bash hardware/quadcan-c5/gen/build.sh
```

The route cache carries a geometry SHA-256 and cannot be reused after a placement change. A new routing run must pass the checks again; minimum clearance is never lowered to make a failing layout pass.
