# Third-party data notices

## OBDb Volkswagen-Jetta signal set

`app/src/main/java/ca/jettatelemetry/app/obd/JettaDiagnosticDiscovery.kt`
contains an adapted, curated subset of candidate diagnostic identifiers and
scaling metadata from:

- Project: OBDb Volkswagen-Jetta
- Source: https://github.com/OBDb/Volkswagen-Jetta
- Reviewed revision: `15e6acad6c58c118b479b8a4cd8a96909a8553d4`
- License: Creative Commons Attribution-ShareAlike 4.0 International
- License text: https://creativecommons.org/licenses/by-sa/4.0/

Changes made for Jetta Recorder: selected a 2014 PQ35/TDI-oriented read-only
probe subset; normalized names and units; represented the declarative scaling
as Kotlin data; added explicit validation notes; and excluded commands that
enter diagnostic sessions or perform anything other than UDS service `0x22`.

That adapted definition subset is offered under CC BY-SA 4.0. The surrounding
application source is not derived from the OBDb dataset.

## OBDb SAEJ1979 standard signals

`app/src/main/java/ca/jettatelemetry/app/obd/StandardObdDiscovery.kt`
adapts the Mode 01 PID `5E`, `70`, `78`, `7A` and `8B` field offsets,
availability flags and scaling from OBDb SAEJ1979:

- Source: https://github.com/OBDb/SAEJ1979/blob/06690177d2d5e11dbf82566297128d673b5a03a7/signalsets/v3/default.json
- Reviewed revision: `06690177d2d5e11dbf82566297128d673b5a03a7`
- License: Creative Commons Attribution-ShareAlike 4.0 International
- License text: https://creativecommons.org/licenses/by-sa/4.0/

Changes: selected five read-only request families, expressed their decoding in
Kotlin, enforced availability bits, and kept their values in discovery snapshots
pending vehicle validation. This adapted definition/decoder file is offered
under CC BY-SA 4.0. The surrounding application is not derived from the dataset.
