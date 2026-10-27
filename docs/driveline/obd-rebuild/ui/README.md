# Native UI comparison

iPhone 17 Pro Max simulator, iOS 27.2, 1320 x 2868. Baseline built from 7a7eedd; rebuild uses the same SwiftUI view hierarchy. See comparison.json; screenshots are synthetic test data only.

Five of seven paired captures match exactly below the top 180 status-bar pixels (a channel difference >10 defines a changed pixel). Vehicle-detail captures differ because the pre-existing fixture generates random vehicle UUIDs: the UUID text differs in dark mode; its variable glyph widths cause an extra wrapped line in the light baseline and shift subsequent cards. Both images were visually inspected; no layout code for that screen changed. This is a fixture nondeterminism limitation, not a claimed pixel-identical seven-screen result.

The five native UI acceptance tests cover navigation, More in dark appearance, Garage/detail in both appearances, largest-accessibility onboarding, and replacement-engine recording/saving through the existing Record screen. New replay screenshot is explicitly SYNTHETIC REPLAY. It verifies sample delivery and Finish/save, not accessory/GPS hardware.

Intentional presentation differences: partial matched economy is labelled “Partial trip economy”; live route preview thins only after 4096 source points while retaining all raw GPS in the durable log. Freshness now uses render time so a newly arrived sample is not incorrectly called future-dated because the one-second display timer has not ticked. No navigation, card layout, typography or color changes.
