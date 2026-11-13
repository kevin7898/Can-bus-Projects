# QuadCAN-C5 rev 1.1 — battery-backed prototype

Engineering revision dated 2026-11-13, based on commit `9938883ec0b1e249e960172527008df2e0b648c7`. This is a reviewable design, not an electrically validated or automotive-qualified product. Do not order boards from it until the remaining release gates below are resolved.

## What changed

The 0.47 F memory-backup supercapacitor and its charge/discharge resistor/diode are removed. A BQ24074 charger and power path supplies VSYS from isolated vehicle/optional USB input or a protected one-cell battery. TPS61023 boosts VSYS to nominal 4.95 V, supplying both the CAN transceivers and existing 3.3 V regulator. The LTE header remains on vehicle VIN and is not backed up.

| Function | Revision |
|---|---|
| Pack target | Protected 1S, 4.2 V charge, at least 500 mAh, at least 2 A discharge capability; exact pack not selected |
| Pack connector J7 | Pin 1 positive, pin 2 pack-mounted NTC, pin 3 negative; verify mating cable polarity |
| Cell protection | Pack protection plus F2 1.5 A fuse; UVLO is an operating cutoff, not cell protection |
| Charge current | R90 8.87 kΩ: approximately 100 mA nominal; verify limits against actual cell |
| Charger input budget | R91 1.62 kΩ: approximately 0.99 A total, shared between system and charging |
| Temperature | Requires actual 10 kΩ 103AT-2-compatible pack NTC; nominal charger window 0–50°C |
| USB power | JP9 open by default; close only with a suitable ≥1 A 5 V source; no USB current negotiation implemented |
| Boost | TPS61023, 1 µH SRP7028A, 732 kΩ / 100 kΩ feedback, nominal 4.9504 V |
| Hardware cutoff | TLV3012B reference/comparator; nominal VSYS off 3.16 V, restart 3.66 V |
| Monitoring | TCA9535 at 0x21 reads charger status; ADS1115 at 0x48 reads cell voltage |
| Board | 140 × 85 mm, four layers; rev 1.0 was 110 × 85 mm |

**Cell selection is a release gate.** Many ordinary pouch cells permit charging only to 45°C; those are not compatible with this unmodified 0–50°C NTC window. Match the exact cell's charge, discharge, storage and peak-current specifications or redesign the TS network/charger. No permanent resistor may substitute for the pack temperature sensor in the installed product. No LiFePO4 or unprotected-cell substitution. This fixed 4.2 V charger does not implement an 80% state-of-charge ceiling. Mount and restrain the cell away from the regulators; the enclosure source has been widened but does not yet include a pack cradle.

The small pack is for the CAN logger, SD and optional GPS. It is not sized for a future SBC, display, NVMe or LTE modem. As an illustrative energy calculation, 2 W for 30 seconds needs about 5.3 mAh at 3.7 V and 85% conversion efficiency; peak current, temperature, aging and voltage sag are more important than that ideal energy figure. This is not a measured runtime.

## Board errors addressed

- U9/U10 interrupt outputs now have separate nets and pull-ups, feeding an AND gate. Either active-low interrupt asserts the processor input without reset-time output contention.
- MCP2518FD IOCON writes now use single-byte transfers, including error propagation, instead of a 32-bit write.
- GPS UART RX moves off GPIO27, a boot strap. GPIO27 becomes TX through a disabled-at-reset buffer and pull-up; GPIO26 receives GPS TX and GPIO23 receives the MCP interrupt.
- The charger footprint uses 0.30 mm thermal-via drills in the original 0.50 mm copper rings, matching the project's hole rule.
- Charger and boost pin maps use custom symbols matched to their manufacturer pin tables. The charger exposed pad is ground.
- Reviewed unused pins receive explicit no-connect markers. MCP SDO is represented as tri-state, matching deselected SPI behavior. The inherited pin-compatible MCP2517FD library symbol is used with the MCP2518FD value/MPN; SDO type is corrected in the embedded symbol. No global output-conflict rule is disabled.
- D3 placement moves closer to U1's switch node. This is a placement improvement, not a completed switching-loop sign-off.
- Shutdown waits for the SD queue to drain and the writer to acknowledge closure before unmounting; the old 1.5-second timeout could cut power during a write. The no-file logger path no longer fills an unflushed RAM buffer. CAN transmit and MCP receive/sleep operations share a mutex to avoid shutdown racing an active SPI transaction. These target-side changes still require firmware compilation and hardware testing.
- IO-expander output updates now use a mutex and retain the previous shadow state on a failed write.

## Power-loss behavior

Firmware allows 30 seconds of continuous absent external power before shutdown. Recovery clears the timer. A valid cell reading below 3.45 V for one second triggers earlier shutdown. Wi-Fi and CAN/GPS producers stop before the log flush. The network server is asked to stop and release GET/LIST file handles before SD unmount. Backup sleep ignores bus wake, periodically checks vehicle VIN, and resumes when approximately 8 V returns. USB-only recovery from this sleep currently needs RESET.

The low-cell software threshold leaves margin above hardware UVLO but cannot guarantee an SD flush with an aged, cold or disconnected cell. Deep sleep does not disconnect the battery. Hardware UVLO eventually disconnects the 5 V load; comparator, divider, charger and protection leakage remain. The ADS1115 monitors voltage, not state-of-charge percentage. System-voltage AIN1 is wired for future diagnostics but firmware presently samples AIN0 only.

## Calculations and component assumptions

- Boost set point: 0.595 × (1 + 732/100) = 4.9504 V; verify tolerance, transient response and ripple on the assembled board.
- UVLO ideal thresholds: rising = 1.242 × (1 + 1000/560 + 1000/6340) = 3.656 V; falling divides that value by (1 + 1000/6340) = 3.158 V. Actual comparator output swing, reference tolerance and resistor tolerances shift these values.
- ADC divider: 100 kΩ / 33 kΩ, ratio 133/33. ADS1115 runs at ±4.096 V full scale, 125 µV/LSB, 128 samples/s. Validate conversion and input leakage/partial-power behavior with the boost off.
- L3 manufacturer's 25°C ratings are 11 A RMS and 22 A saturation. These are inductor ratings, not the board's available output current.
- Charger total input current is limited. Load may consume available charging power or supplement it from the battery; verify simultaneous worst-case Wi-Fi, SD, GPS and CAN operation.
- 22 µF output capacitors need selected MPNs with adequate effective capacitance at 5 V and temperature. Generic value/footprint BOM entries are not final procurement specifications.

## Validation and release gates

The KiCad 9 placement checker now builds courtyard caches, and the build fails on actual courtyard overlap or electrical DRC errors. The router no longer lets reserved escape lanes override clearance to real copper; its finishing pass uses a local 0.025 mm grid.

Automated results are recorded in `fab/STATUS.md`; the host policy test is `firmware/tests/power_policy_test.c`. Matching source, schematic and PCB connectivity checks establish consistency, not analog correctness. An autorouted prototype does not establish impedance control, transient immunity or thermal performance.

Before a fabrication release:

1. Select the actual protected pack, NTC curve, cable and retention method; verify allowed temperature window and F2 time-current behavior.
2. Manually review and optimize both switching loops, decoupling, feedback return and thermal-via geometry. Verify the tiny SOT-563 boost pad fanout can carry the required current without unacceptable voltage drop or heating.
3. Route and validate USB as a controlled 90 Ω differential pair, and GPS RF as a controlled 50 Ω path using the chosen fabricator stack-up. Existing automatic routing is not an impedance-controlled design.
4. Check 3.3 V LDO heating, charger thermal regulation, peak load, capacitor DC bias, minimum battery voltage startup, battery-absent operation and return-to-charge behavior.
5. Resolve all electrical DRC errors and remaining actionable ERC warnings. Check component orientation, footprint pad numbering and assembly rotations against actual ordered MPNs.
6. Build the complete firmware with the intended ESP-IDF v6 toolchain, then test real SD flush/recovery, SPI concurrency, hot GPS reset, independent CAN interrupts and wake behavior. Only the pure backup policy has a host compile/test here.
7. Bench-test vehicle power interruption and slow/fast crank profiles with a programmable supply, oscilloscope and real load. Verify no 5 V/3.3 V brownout, no input backfeed and no corrupt log. Test NTC open/short, cold/hot charge inhibit, depleted pack and repeated dips.
8. Test input transients/reverse polarity for the target vehicle environment. The existing TVS/fuse/buck circuit is not certified load-dump protection.

All four CAN transceivers remain high-speed ISO 11898-2 parts. A 100 kbit/s setting does not make them compatible with the Jetta fault-tolerant comfort bus.

## Manufacturer references

- [TI BQ24074 data sheet](https://www.ti.com/lit/ds/symlink/bq24074.pdf): pins, power path, ISET/ILIM, TS and timers.
- [TI TPS61023 data sheet](https://www.ti.com/lit/ds/symlink/tps61023.pdf): pinout, feedback and output disconnect.
- [TI TLV3012 data sheet](https://www.ti.com/lit/ds/symlink/tlv3012.pdf): B-device comparator/reference pinout and tolerances.
- [TI ADS1115 data sheet](https://www.ti.com/lit/ds/symlink/ads1115.pdf): pinout, PGA, configuration and conversion scaling.
- [Bourns SRP7028A](https://bourns.com/docs/product-datasheets/srp7028a.pdf): 1R0M land pattern/current ratings.
- [u-blox NEO-M9N integration manual](https://content.u-blox.com/sites/default/files/NEO-M9N_Integrationmanual_UBX-19014286.pdf): UART selection and intentionally unused pins.
- [Espressif ESP32-C5-WROOM-1](https://documentation.espressif.com/esp32-c5-wroom-1_wroom-1u_datasheet_en.pdf): module pin numbering and boot straps.
