# NRN offline planner — first integration

## Scope and status

Integrated into the existing Flutter command centre: the mobile **AI** dock button
and the wide-screen **Offline planer** button open the module. This is an offline
symbolic expert system (rules, radio screening and constrained optimization), not
a bundled language model. It does not call OpenAI, another API or a cloud service.
No API key or model download is needed. Existing application maps/communications
keep their own behavior; this module does not make the entire app offline-ready.

The five functions are present as an initial decision-support implementation:

1. **Network**: select a minimum-relay route between HQ and incident from supplied,
   accessible station candidates, limited by available station inventory.
2. **Air relay**: if no ground route is found, test supplied aerial candidate
   positions and ascending AGL values, with flight-condition confirmation and
   explicitly entered endurance, round-trip transit and reserve time.
3. **Teams**: assign at most one task per available team, enforcing skill matches
   and confirmed task access. A bounded DP maximizes summed task priority, then
   minimizes total straight-line distance. This is not a complete SAR strategy.
4. **Action plan**: produce an explained, templated sequence with unresolved
   dependencies, unassigned tasks, assumptions and a commander review step.
5. **Monitoring**: manually entered reports, per-plan report history, last-report
   timeout, low battery and blocked/help alerts. No live UAV or LoRa telemetry
   adapter is implemented yet. No report means unknown, not confirmed danger.

No commands are sent to teams, stations or aircraft. Approval is a local review
record, not authentication, dispatch, radio validation or flight authorization.

## Commander workflow

- Open command centre → **AI** (mobile) or **Offline planer** (wide screen).
- Fill forms for HQ, incident, radio equipment, drone constraints, stations,
  terrain profiles, teams and tasks. New operational input has **no coordinates
  or radio profile**, preventing accidental use of invented settings.
- Current mesh data can seed the local device location and, only when exactly
  one unresolved SOS is present, the incident. Team positions use a member's
  reported position only as a starting point; availability defaults to false and
  skills remain empty. Confirm positions and their source times manually.
- **DEMO vježba** is synthetic, visibly labelled, and must not be used as terrain
  evidence. Replacing an input requires confirmation and clears its plan/reports.
- Generate a proposal, review all five sections and enter a commander name to
  approve the proposal. Any input edit invalidates approval. Regeneration always
  creates a draft. Network gaps never silently become confirmed coverage.
- Save locally; input, plan, approval and reports survive module/app restart.
  Export copies a JSON envelope to the clipboard. Import can restore its input
  as a draft, never import another person's approval as an active authorization.
- Monitoring reports are manual and scoped to the generated plan version.

## Terrain and radio assumptions

Offline map imagery is not an elevation model. This version takes **explicit
candidate locations and supplied path profiles**; it does not automatically
extract terrain profiles from OSM tiles or generate sites from a DEM.

For each profile specify `from`, `to` (location IDs), `source` and `samples`:
equally spaced terrain/obstacle-top heights in metres AMSL, including endpoints.
The endpoint ground heights must match within 5 m. The entered heights must
include relevant obstacles; vegetation/buildings are not automatically inferred.
Missing endpoint altitude or profile produces **unknown**, never usable.

The radio model screens free-space path loss, entered link margin, 60% first
Fresnel clearance at sampled points, and effective-earth curvature with k=4/3.
It assumes symmetric equipment, frequency, antenna gain and sensitivity at both
ends. A result labelled `estimated` is not an availability guarantee. Sparse
sampling can miss ridges. No diffraction, clutter model, interference, antenna
pattern/orientation, fading statistics, traffic/capacity, LoRa airtime, frequency
coordination or measured propagation calibration is implemented. It is not a
complete implementation of ITU recommendations or a calibrated LoRa predictor.

Reference background:
- [ITU-R P.525 free-space attenuation](https://www.itu.int/rec/R-REC-P.525-5-202411-I/en)
- [ITU-R P.530 terrestrial line-of-sight prediction](https://www.itu.int/rec/R-REC-P.530-19-202509-I/en)

The output is a **route HQ → incident**, not an area coverage raster, terrain-aware
team-routing solution or a guarantee of links to every deployed team. No route
ETA is invented from straight-line distance. Task routes and site accessibility
must be confirmed externally. Ground-station setup times and end-to-end network
capacity are not optimized. The planner handles one incident and one air relay.

AGL = height above local ground. AMSL = elevation above sea level. Aerial output
is the lowest model-feasible **sampled** height among entered candidate sites,
not a globally optimal height. Flight restrictions and weather are not retrieved.
Endurance is user-provided for the actual payload/conditions, not a battery model.

## Data and persistence

`schemaVersion: 1` input is documented by `planner_scenario.dart`; forms cover all
operational fields and advanced JSON remains available for interchange. Values
use degrees, metres, minutes, MHz, dBm, dBi and dB as labelled. IDs must be unique.
Limits: 20 ground sites, 20 aerial sites, 12 teams/tasks, 101 sampled heights;
profiles accept 3–20000 samples each. Planning runs in a worker isolate on native
Flutter targets. The system refuses malformed coordinates, profiles and IDs.

Persistence uses the app's existing SharedPreferences dependency and is not
encrypted storage. One working mission is saved per device. This first version
does not include multi-mission management, signed approval, distributed editing,
mesh plan synchronization, tamper-proof audit or access control. Clipboard export
contains operational data; use controlled test data during evaluation.

## Validation

Run the dependency-free executable:

```sh
dart test/offline_planner/engine_checks.dart
```

It covers 14 cases: incomplete input, ridge obstruction, missing profiles, unknown
altitude, station inventory, aerial height references, endurance/confirmation,
inaccessible sites, capability/availability/route constraints, specialist
allocation, priority, malformed IDs/coordinates/profiles, reciprocal profiles,
latest/stale/missing reports and canonical approval snapshots.

Integration tests for local storage and commander approval invalidation:

```sh
flutter test test/offline_planner/planner_test.dart
flutter analyze lib/modules/offline_planner
```

In this development session the 14 pure-Dart checks and targeted Dart analysis
passed. Full Flutter execution was blocked by automatic review because tool
initialization attempted cloud instance metadata access; widget tests and an
APK build are **not verified**. No attempt was made to bypass that restriction.

## Next engineering work

Before operational evaluation: supply a local DEM/obstacle dataset and generate
profiles; calibrate link models with measured NRN equipment; add route/sector
data and team constraints; connect explicit timestamped telemetry adapters;
validate radio, aircraft and SAR behavior with qualified field personnel.
A local LLM may later help parse commander text or explain results, but must
not replace these calculations or silently manufacture missing inputs.
