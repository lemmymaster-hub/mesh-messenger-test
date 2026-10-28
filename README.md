# NRN Mesh

Flutter Android application for local Nearby Connections messaging, relayed GPS/SOS events and an operational command center. Formerly BSL Mesh Lite. The wire service ID remains `bsl.mesh.test` so existing peers can discover the app.

## Command center

Open the dashboard button in the chat toolbar. The command center switches Android phones to landscape and shows the unified reference layout on one screen: navigation, status cards, map, SOS center, photo wall, teams, dispatch, mission progress, communications and actual direct-link topology. A 1600×900 console scales proportionally to fit the available phone screen, with intentionally small controls; detail dialogs use the physical screen size. On phones, tapping the communications input opens a keyboard-aware composer. Leaving the console restores portrait orientation. Profile editing remains in its dedicated sheet. The main chat restores the large red SOS control.

The map section has a persistent labeled offline download button and saved-area shortcuts, in portrait and landscape. Move the map to the intended area, tap download, name it, and wait for complete coverage. Downloads currently cover an 11×11 tile area at the current and next zoom levels; offline detail is limited to those levels and bounds. Cached OSM tiles are shared with the command-center basemap. Satellite imagery and the optional online topographic layer are separate online layers, not included in these offline downloads.

- GPS uses persistent device IDs, with names as labels. Old positions are grey after two minutes.
- Map controls include zoom, fit all, GPS centering, local user/coordinate search, filters, topography and an optional online Esri imagery layer. OSM uses previously downloaded local tiles when available. Satellite/topographic layers require internet; no 3D or live imagery is claimed.
- Teams and assignments persist locally. Create a team using known device IDs, assign a task with an optional SOS reference, then each member reports acceptance, travel, arrival, completion or rejection on their own device.
- Offline operational edits remain local until explicitly retransmitted using the detail dialog. Sending is reported as submission to direct links, never as a remote receipt. A member's progress is the explicit response.
- Group/private communications use the existing relay transport. Histories are separated by stable peer IDs; sent messages from the main chat also appear in the matching command-center conversation. A private message cannot silently become a broadcast if a peer's HELLO identity is unavailable.
- Photo wall sends a compressed JPEG up to 20 KB. At most 24 photos and 300 operational messages are kept in the local ledger. All participants must run this version for the new `command` protocol messages; older versions cannot relay that message type.
- Resources (repeaters, vehicles, drones and equipment) are a local manual inventory with optional coordinates. They are not measured radio telemetry or hardware controls. Readiness is local to this center.
- SOS events without GPS stay in the list. Cancellation is applied to the matching incident. Accepting through the command center also silences the matching chat alarm.

## Offline planning extension (1.3 pilot)

The **AI planer** sidebar item opens local network/air-relay planning, constrained
team assignment, a draft action plan and manual monitoring. It reads teams and
incidents from this command centre’s operational ledger. Inputs and review records
persist locally; no cloud API or language-model download is used.
See [scope, inputs and limitations](docs/NRN_OFFLINE_PLANNER.md).

## Validation

GitHub Actions runs dependency resolution, static analysis, regression tests, responsive widget interactions and a debug APK build. UI review PNGs and the debug APK are retained as workflow artifacts. Formatting can be checked with `dart format`.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --flavor nrnPilot
```

CI treats analyzer diagnostics as failures, including lint and deprecation notices. Android builds use Java 21 with the repository's AGP 9 / Gradle 9 setup.

## Required field verification

Use three Android devices A → B → C, with A and C outside direct range. Check discovery and reconnect, HELLO identity, UTF-8 broadcast/private messages, GPS update age, SOS with and without GPS, two simultaneous SOS events, matching cancel, team assignment and member acknowledgement, JPEG relay, disconnect and restart persistence. Repeat with location permission denied, Bluetooth disabled and one peer leaving during a send. Compare reported link submission with actual receipt on the other device.

This build has no authenticated organization membership, cryptographic command signatures or end-to-end private-message encryption across relays. Roles and sender IDs are self-reported. Nearby transport links and UI recipient filtering do not provide end-to-end authorization. Do not use the app as the only emergency communications channel. Desktop/web/iOS mesh transport is not implemented by the Android Nearby dependency.

Map coverage and offline availability depend on the downloaded tiles and provider terms; a saved area label alone is not proof of complete coverage. The UI marks incomplete downloads explicitly. Removing an area entry leaves the shared tile cache intact. Public basemap services are not a production offline distribution contract; arrange an appropriate licensed/self-hosted tile source before deployment.
