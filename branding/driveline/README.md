# DriveLine brand handoff

The CAN / CONNECT project is adopting the public name **DriveLine**.

Start with [the Codex implementation handoff](CODEX_HANDOFF.md). It records the selected road/CAN-network icon, the inspected iOS and Mac branches, native Liquid Glass preparation, Xcode project-generator changes, public-name updates, and validation requirements.

![DriveLine refined icon](assets/DriveLine-Icon-Refined.png)

## Included

- `assets/DriveLine-Icon-Refined.png`: exact flattened refinement of the selected option 3; 1254 × 1254, RGB, opaque. This is the visual reference, not a native layered icon.
- `CODEX_HANDOFF.md`: actionable instructions for Codex working with the app in Xcode.
- `SHA256SUMS`: checksum of the unmodified reference image.

No application code is changed by this handoff. Native `.icon` assets, editable source layers, production fallback exports, and on-device verification remain implementation work.

## Provenance

Created during the 2026-10-24 DriveLine naming and icon-design conversation. The user selected circuit-network option 3 and requested a small refinement and Liquid Glass support. The included image is that subsequent refinement, generated using the built-in image-generation tool. Earlier DL monograms and options 1–2 are not the selected direction.

This folder is intentionally independent of the iOS/Mac implementation branches so its single handoff commit can be cherry-picked into either without bringing unrelated app changes.
