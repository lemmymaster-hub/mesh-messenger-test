# NRN Mesh

Flutter Android application for local Nearby Connections messaging, relayed GPS/SOS events and an operational command center. Formerly BSL Mesh Lite. The wire service ID remains `bsl.mesh.test` so existing peers can discover the app.

## Command center

Open the dashboard button in the chat toolbar. On large screens the layout follows the supplied reference: navigation, status cards, map, SOS center, photo wall, teams, dispatch, mission progress, communications and actual direct-link topology. Phones use a drawer and stacked panels.

- GPS uses persistent device IDs, with names as labels. Old positions are grey after two minutes.
- Map controls include zoom, fit all, GPS centering, local user/coordinate search, filters, topography and an optional online Esri imagery layer. OSM uses previously downloaded local tiles when available. Satellite/topographic layers require internet; no 3D or live imagery is claimed.
- Teams and assignments persist locally. Create a team using known device IDs, assign a task with an optional SOS reference, then each member reports acceptance, travel, arrival, completion or rejection on their own device.
- Offline operational edits remain local until explicitly retransmitted using the detail dialog. Sending is reported as submission to direct links, never as a remote receipt. A member's progress is the explicit response.
- Group/private communications use the existing relay transport. A private message cannot silently become a broadcast if a peer's HELLO identity is unavailable.
- Photo wall sends a compressed JPEG up to 36 KB. At most 24 photos and 300 operational messages are kept in the local ledger. All participants must run this version for the new `command` protocol messages; older versions cannot relay that message type.
- Resources (repeaters, vehicles, drones and equipment) are a local manual inventory with optional coordinates. They are not measured radio telemetry or hardware controls. Readiness is local to this center.
- SOS events without GPS stay in the list. Cancellation is applied to the matching incident. Accepting through the command center also silences the matching chat alarm.

## Validation

GitHub Actions runs dependency resolution, static analysis, regression tests, responsive widget interactions and a debug APK build. UI review PNGs and the debug APK are retained as workflow artifacts. Formatting can be checked with `dart format`.

```sh
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --debug
```

Some legacy lint/deprecation notices remain in the chat/map implementation. CI treats compiler errors as failures. Android builds use Java 21 with the repository's AGP 9 / Gradle 9 setup.

## Required field verification

Use three Android devices A → B → C, with A and C outside direct range. Check discovery and reconnect, HELLO identity, UTF-8 broadcast/private messages, GPS update age, SOS with and without GPS, two simultaneous SOS events, matching cancel, team assignment and member acknowledgement, JPEG relay, disconnect and restart persistence. Repeat with location permission denied, Bluetooth disabled and one peer leaving during a send. Compare reported link submission with actual receipt on the other device.

This build has no authenticated organization membership, cryptographic command signatures or end-to-end private-message encryption across relays. Roles and sender IDs are self-reported. Nearby transport links and UI recipient filtering do not provide end-to-end authorization. Do not use the app as the only emergency communications channel. Desktop/web/iOS mesh transport is not implemented by the Android Nearby dependency.

Map coverage and offline availability depend on the downloaded tiles and provider terms; a saved area label alone is not proof of complete coverage. The UI marks incomplete downloads explicitly. Removing an area entry leaves the shared tile cache intact. Public basemap services are not a production offline distribution contract; arrange an appropriate licensed/self-hosted tile source before deployment.
