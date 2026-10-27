# Decisions

- User explicitly permits loss of app data; no data conversion project is required. Unrelated source/build work remains untouched. No reset is necessary for development.
- Keep the existing Foundation-only shared package and direct-source iOS build convention. New telemetry types live alongside existing contracts.
- Keep the current visual UI and Mac envelope. Raw telemetry logs are local only; no unnegotiated new transfer format.
- Legacy engine remains default until hardware acceptance. Debug launch argument `--obd-rebuild` selects replacement acquisition; selection is immutable during a session. No automatic cross-engine fallback.
- New diagnostics redact all identity/calibration/adapter-information replies at ingress, including malformed/partial replies. User-entered/onboarding VIN metadata retains the existing explicit storage behavior.
- Optional enhanced reads remain deferred by the replacement engine: the six-second engine quiet interval cannot meet a 1.2-second core-gap budget. Existing reviewed implementation remains available to legacy engine; do not remove its safeguards.
- Response-count hints stay disabled until explicit adapter support and unhinted consistency are established. Syntax is not inferred from the handoff example.

Protocol references checked during implementation:
- [ELM327 datasheet](https://elmelectronics.com/wp-content/uploads/2020/05/ELM327DSL.pdf): ATRV returns voltage followed by a prompt; it does not require OK. Content validation belongs after framing. Empty/echo-only prompts remain synchronization noise under the existing bounded deadline.
- [Apple UIBackgroundModes](https://developer.apple.com/documentation/BundleResources/Information-Property-List/UIBackgroundModes): existing external-accessory and location modes remain. Declaration is not proof of phone-lock operation; actual accessory tests are required.

Matched interval results include their own fuel, distance, duration, source and policy. The existing optional trip envelope can carry this metadata while older receivers ignore it. Older Mac software may not display partial-economy coverage; matching endpoint/bytes alone does not establish metric parity. No raw-log upload is enabled.
