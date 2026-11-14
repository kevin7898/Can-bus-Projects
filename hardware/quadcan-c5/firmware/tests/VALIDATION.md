# Rev 1.1 firmware validation

The complete application, bootloader and partition table compile and link for **ESP32-C5 with ESP-IDF v6.0.3**. No board has been flashed or exercised by this validation.

The SDK is the official `v6.0.3` release archive, commit `76f5dedd9950a3012fee8fb7d5586df21fc67802`. Compiler: `riscv32-esp-elf-gcc (crosstool-NG esp-15.2.0_20251204) 15.2.0`. Python 3.12 was used for the SDK tools.

## Results

| Check | Result |
|---|---|
| Fresh `idf.py set-target esp32c5` and `idf.py build` | Pass; all application and SDK objects built |
| Build after wake API update | Pass; no C compiler warnings/errors in the final build |
| App image | 1,182,496 bytes (`0x120b20`) |
| App partition | 1,536,000 bytes (`0x177000`); 353,504 bytes / 23% free |
| Flash / PSRAM settings | 8 MB flash; PSRAM allocation enabled; hardware presence not tested |
| Backup-policy test | Pass: crank recovery, 30-second timeout, low-cell debounce, ADC failure, timer saturation |
| CAN config-key test | Pass: distinct nominal bitrate, data bitrate and listen-only settings; malformed keys rejected |
| Host AddressSanitizer + UndefinedBehaviorSanitizer | Both tests pass; leak checking disabled because of the execution environment |
| PCB audit | Existing 416 warnings reviewed by category; copper, placement and fabrication outputs unchanged in this firmware follow-up |

SDK Kconfig emits upstream deprecation notices about hex literals without `0x`; these are not application compiler diagnostics. The application initially emitted deprecated sleep API warnings, resolved by using the wake-source bitmap. A timer plus CAN/ignition wake now follows normal boot, instead of taking the timer-only shortcut.

`build-validation.json` records exact firmware source hashes, SDK commit, generated configuration hash and binary hashes. The local image's embedded project version is `960909e-dirty` because the tested changes were not yet committed when built. Rebuilding a committed revision changes version/timestamp metadata and therefore binary hashes. Binary files are local build outputs, not a published or hardware-approved firmware release.

## Reproduce

With ESP-IDF v6.0.3 installed and exported, from `hardware/quadcan-c5/firmware`:

```sh
sh tests/run_host_tests.sh
idf.py set-target esp32c5
idf.py build
```

`set-target` regenerates the ignored `sdkconfig` from `sdkconfig.defaults`. Keep any deliberate local configuration changes separately before using it.

## What this does not establish

Compilation checks API compatibility and linking, not electrical operation or runtime correctness. Still required: real SD flush/recovery and write-stall tests; four-channel capture and controlled transmit tests; SPI contention; Wi-Fi Aware interoperability and stream integrity; GPS resets; CAN/ignition/timer wake; battery switchover, recharge, UVLO and thermal/transient tests. Rev 1.1 sleep current is unmeasured.

This remains a prototype. Use the full hardware release gates in `../../docs/BATTERY_REVISION.md` before ordering or installing it.
