# CAN bus projects

Experiments and applications built around CAN/OBD vehicle data.

## Projects

### [Jetta Recorder Android](jetta-recorder-android/)

An Android-first, local-first driving recorder for the Volkswagen Jetta, initially targeting a OnePlus 6T and OBDLink MX+.

The first hardware milestone establishes a real ELM327/STN connection, records standard OBD-II telemetry, captures raw CAN observations, and exports evidence for decoder development.

> Privacy: raw captures, GPS traces, VINs, and personal vehicle logs are intentionally excluded from this public repository.

### [CAN / CONNECT](telemetry-server/frontend/)

A standalone React + TypeScript automotive telemetry frontend with a customizable dashboard, interactive driving-history map, sample trip replay and engineering workspaces. Uses clearly labeled synthetic data until recorder/server integration is available. Includes self-hosting instructions, tests and a Docker build.
