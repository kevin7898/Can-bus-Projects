# Third-party signal definitions

The declarative PID formulas in `Core/ScannerReadings.swift` adapt OBDb/SAEJ1979 revision `06690177d2d5e11dbf82566297128d673b5a03a7` (https://github.com/OBDb/SAEJ1979). They were cross-checked against the existing Android Pocket Recorder `ObservedJettaProfile.kt` on branch `feature/jetta-pocket-recorder`.

The hardware investigation also used OBDb/Volkswagen-Jetta revision `15e6acad6c58c118b479b8a4cd8a96909a8553d4` (https://github.com/OBDb/Volkswagen-Jetta), used by Android `JettaDiagnosticDiscovery.kt`, and the user-supplied https://github.com/jverkoey/Volkswagen-Jetta fork. Their curated 2014 TDI candidate DIDs and the DSG temperature candidate returned NO DATA on this car; none are polled or displayed by the final application. The generic transmission temperature/gear definitions restricted to 2015 and newer were excluded.

Both OBDb datasets are licensed under Creative Commons Attribution-ShareAlike 4.0 International: https://creativecommons.org/licenses/by-sa/4.0/. Those adapted declarative definitions are offered under the same license. The full license is bundled in `CANConnect/Resources/OBDb-CC-BY-SA-4.0.txt`. The surrounding application code is not derived from the datasets. No endorsement or warranty is implied.

Changes: curated standard Mode 01 boost, EGT, DPF pressure/regeneration and airflow formulas; normalized signal names and units; retained per-field support bits, signed pressure, ECU attribution and ISO-TP boundaries; restricted engine ECU selection to the user's real 2014 Jetta TDI DSG profile. The hardware acceptance document records the rejected VW candidates; uncertain soot/pressure units are not presented as dashboard signals. No commands write vehicle data, clear faults, start regeneration, or enter security/actuator sessions.


Build 11 consulted factual signal identification in seishuku/teensycanbusdisplay revision `e6df5a54c18a8ede47ad4dcdc2f86aab48bff339` (https://github.com/seishuku/teensycanbusdisplay): block 0x72, zero-based field 5, type 0x7E, grams. The CAN Connect decoder and transport are independently implemented; no source implementation or asset was copied from that project. Units and block layout were checked against responses from the supported ECU calibration.
