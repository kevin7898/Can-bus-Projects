# Preview dependencies and data

- **D3 7.9.0** provides geographic projection and chart rendering. Copyright 2010–2023 Mike Bostock. ISC license. Loaded from the pinned jsDelivr distribution. Source and license: https://github.com/d3/d3/tree/v7.9.0
- **Lucide 1.17.0** supplies preview icons through the standalone renderer's pinned unpkg distribution. ISC license, with some icons derived from Feather under MIT. License: https://github.com/lucide-icons/lucide/blob/main/LICENSE
- **Floating UI core 1.7.3 and DOM 1.7.4** are loaded by the standalone preview runtime. MIT license. License: https://github.com/floating-ui/floating-ui/blob/master/LICENSE
- **City of Nanaimo open data** provides embedded road, park, and water GeoJSON reused from the approved CAN / CONNECT iOS design prototype. Map labels retain City of Nanaimo attribution. The exact original dataset endpoint and license record were not preserved in that source; verify those records before redistributing these geographic assets in a production application. Production map-provider selection remains separate from this design reference.
- The standalone export includes its preview shell / styles / runtime. Its shared UI runtime is only preview infrastructure and is not an app architecture dependency.

Highlighted routes, vehicle readings, drive histories, device activity, and service states are illustrative fixtures. They are not exported user recordings.
