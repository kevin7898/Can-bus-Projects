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
