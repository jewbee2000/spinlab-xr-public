# SpinLab XR — verification and physical acceptance

Version baseline: 0.1.0, 18 October 2026. This plan defines evidence to collect; unchecked items are not completed tests. The repository's automated test output and release record determine the actual passing counts. **Physical Quest 2 acceptance is pending.** No connected headset was found in the development ADB check.

## Test layers and commands

| Layer | Purpose | Location / command | What it cannot establish |
| --- | --- | --- | --- |
| Model and machine state | Check deterministic physics response, permissive conditions, coast-down, faults, results, and report integrity | `tests/simulation.test.mjs`; `node --test tests/*.test.mjs` | Whether actual controllers, reach, or text work in the headset |
| Serving boundary | Verify asset MIME/XR headers and blocking repository files/path traversal | `tests/server.test.mjs`; same test command | Remote hosting configuration or all browser security behavior |
| Syntax | Parse the app/model/scene modules | `npm.cmd run check` on Windows, or `npm run check` elsewhere | Runtime interaction correctness |
| Desktop browser smoke | Exercise visible buttons/sliders, baseline and correction runs, fault recovery, exports, and layout | `tests/browser-smoke.mjs`, with the app server running | Stereoscopic comfort, controller pose/axes, or Quest GPU performance |
| Physical Quest 2 | Verify entry, interaction, recovery, readability, comfort, lifecycle, and performance | The unfilled record below; setup in [INSTALL_QUEST2.md](INSTALL_QUEST2.md) | Calibrated hardware behavior or training transfer to a real station |

No `npm install` is needed to run the app or its Node tests. The optional desktop automation script requires Playwright or an existing installed Playwright module; it is a development tool, not an app runtime dependency. Its header describes `PLAYWRIGHT_MODULE`, browser channel/executable overrides, and the local server URL. Software rendering is used in that smoke test and its frame rates must not be presented as Quest performance results.

For a clean verification pass, run from the project root:

```powershell
node --test tests/*.test.mjs
npm.cmd run check
```

Start `node tools/serve.mjs` in another terminal for the desktop smoke script. If Playwright is already available:

```powershell
node tests/browser-smoke.mjs
```

Use the maintained Playwright installation available on the development machine or set `PLAYWRIGHT_MODULE` to its module path. Playwright is optional when testing only the Quest app.

## Requirements traceability

IDs correspond to [PROJECT_PLAN.md](PROJECT_PLAN.md). "Existing coverage" means a test/check is present; record its execution result separately.

| ID | Requirement | Existing coverage / verification route | Remaining evidence |
| --- | --- | --- | --- |
| R-01 | Start requires mounted rotor, valid homed probe, closed guard, and no active fault/E-stop/coast | Model test `start requires rotor, guard, homing, valid probe, and zero-speed interlocks`; desktop negative actions | Repeat interlocks through physical controller targets |
| R-02 | Stop, E-stop, fault reset, and zero-speed edits are deterministic | Model tests for manual coast, guard fault, E-stop release/reset, sensor rehome, correction restrictions, and New session; browser smoke repeats main recovery paths | In-headset labels, inadvertent repeat activation, and recovery comprehension |
| R-03 | Correct vector arithmetic and physically motivated speed response | Model tests for cancellation, in-phase doubling, resonance crossing, seed consistency; units/formulas reviewed in [RESEARCH.md](RESEARCH.md) | Independent numeric spot-check against the closed-form SDOF equation; force speed-squared is an analytical property, while vibration includes a speed-dependent transfer response |
| R-04 | Complete prepare/run/correct/verify using controllers | Desktop smoke covers shared commands; VR rays/dials/squeeze are implemented | Physical Quest workflow, both hands, thumbstick/wrist fine control |
| R-05 | XR unavailable/denied has a useful desktop/retry path | App support/secure-context checks; desktop preview smoke | Physical permission denial, re-entry, interruption, and error-message checks |
| R-06 | Runtime has no CDN dependency | Vendored Three.js and local assets; desktop request failures captured | Network inspection of full load and VR entry; no service-worker/offline restart claim |
| R-07 | Target comfortable operation at 72 Hz | App requests 72 Hz when the session advertises support; read-only render statistics available | Physical performance HUD/profiler evidence and subjective comfort |
| R-08 | Readable/reachable seated and standing | Responsive desktop layout checks; VR bench-height control | Physical eye-level, panel distance, reach, glare/contrast, handedness |
| R-09 | Export contains units, settings, outcomes, and events | Model report detachment/JSON tests; browser smoke validates downloaded/persisted reports, completed runs, aborted results, and saved snapshot | Headset download/storage behavior; browser storage unavailable case |
| R-10 | Original or appropriately licensed assets | Procedural geometry and UI; asset manifest; dependency notices | Review asset provenance, license attribution, documentation, and capture quality |
| R-11 | Documented clean launch and recovery | Static server tests, portable package recipe, installation guide | Clean-machine rehearsal and actual USB/Quest setup |
| R-12 | Peak/RMS/phase/threshold semantics are clear | Units and compensated-phase comments in model/report; research explains analytic samples and RMS summary | User comprehension review; instrument labels should remain consistent in future UI changes |

## Deterministic numerical and state expectations

- Nominal probe is `6.0 mm`; range `5.5–6.5 mm` permits a sweep after homing.
- The initial modeled vector is `18 g·mm` at `120°`.
- A correction of `0.600 g` at `300°`, radius `30 mm`, cancels that vector. The same correction at `120°` doubles it to `36 g·mm`.
- Run acceleration is `360 rpm/s` to `1,800 rpm`. Acquisition lasts 12 simulated seconds, including its ramp. Samples are recorded at `t=0` and each `0.25 s` through `t=12`, totaling 49.
- On successful acquisition completion the drive target becomes zero. Deceleration is `900 rpm/s`; a run becomes complete only after zero speed, about two more simulated seconds at full target speed.
- A manual stop, guard trip, E-stop, or sensor fault invalidates the interrupted result. It must not become a passing completed run or overwrite an earlier historical result with an invented completion.
- Changing probe or correction settings invalidates the current acceptance result. A fresh completed sweep is required even when the calculated residual is already zero.
- E-stop release and fault reset are separate actions. Neither restarts the drive. A guard fault additionally requires a closed guard before reset; a sensor fault clears probe homing and requires home after reset.
- New session and a page reload create a fresh station. Only an explicitly saved report snapshot is persisted; its survival depends on browser storage permission/data retention.
- Rotor mesh rotation is slowed for visibility and probe travel is visually exaggerated. Do not use animation speed or mesh dimensions to validate instrument RPM or correction radius; inspect the numerical model/report instead.

Values above are fictional simulation constants, not a real machine recipe or acceptance specification. Exact cancellation has no independent sensor noise floor. The displayed phase at exact cancellation is defined as zero for numerical/UI convenience and has no useful physical direction.

## Desktop smoke procedure

The optional browser script exercises the same rendered commands and input events used by the desktop page. It reads telemetry through `window.spinlab` for assertions; it does not bypass commands to manipulate the station.

1. Load the page without fatal/module/request errors; attempt premature run and correction.
2. Load/home, move probe out of range, confirm rejection, restore position, run the baseline.
3. Confirm closed/running guard conditions reject mass edits, then apply the correction through sliders with the guard open.
4. Complete verification, export JSON, and validate two historical completed runs and the saved snapshot.
5. Inject sensor fault; reset/rehome; E-stop and release/reset; guard trip with a failed reset until closure.
6. Verify aborted/current results do not inherit an earlier PASS; preserve historical completed runs.
7. Inspect exploded/assembled views, controls dialog, and representative desktop/narrow layouts.
8. Reload and verify a fresh station plus access to the previously saved report.

A screenshot verifies a frame of visual layout, not the complete training workflow. A passing browser script does not establish physical controller or headset performance acceptance.

## Physical Quest 2 record — unfilled

Copy this section for each physical run. Record failures as well as passes and attach the downloaded session JSON when available. Keep a test pending when the necessary device/tool was unavailable.

```text
Tester:
Test date/time and timezone:
App version and commit:
Quest model: Quest 2
Horizon OS version:
Meta Quest Browser version:
Controller type / handedness:
Connection: USB localhost / HTTPS / other:
Node version and server port:
Seated / standing:
Session duration:
Performance tool/version and settings:
Observed refresh rate:
Recording / screenshots / report JSON references:
Open defects and reproduction steps:
Overall decision: PENDING / PASS / FAIL / PASS WITH DOCUMENTED LIMITATIONS
```

### Launch and input

- [ ] `adb devices` lists the authorized Quest 2; correct port reversal is present.
- [ ] Headset Browser loads `http://localhost:8080`; app assets finish loading.
- [ ] Enter VR succeeds after a user action; permission denial provides a useful retry/error path.
- [ ] Local-floor height places the bench and panels usefully without moving the user's viewpoint.
- [ ] Left and right rays have clear target feedback; a trigger press activates once.
- [ ] Holding the trigger on a toggle does not repeatedly change its state.
- [ ] Squeeze works on the rotor, probe, and guard targets as documented.
- [ ] Each dial changes with wrist roll while held, and stops changing on release.
- [ ] Horizontal thumbstick makes continuous fine adjustments that accumulate below the displayed rounding step; no stuck value or large unexpected jump.
- [ ] Left thumbstick vertical changes bench height only when no dial is held; endpoint limits are usable.
- [ ] Releasing/reconnecting a controller does not issue an accidental command or leave a dial stuck.
- [ ] NEW SESSION and SENSOR FAULT controls are reachable at the lower right.

### Engineering workflow and recovery

- [ ] Premature start names the missing permissive condition.
- [ ] Load → Home probe → Close guard → Run completes a baseline and coasts to zero.
- [ ] Nominal readouts and 49 recorded samples match the model expectations.
- [ ] Running/guarded correction edits are rejected clearly.
- [ ] Correcting to `0.600 g` at `300°`, then completing a new sweep, reports verification.
- [ ] Manual stop coasts and does not create a completed result.
- [ ] Guard trip removes drive; zero speed, guard closure, and reset are required.
- [ ] Sensor fault removes drive; zero speed, reset, and probe rehome are required.
- [ ] E-stop removes drive; release and fault reset remain distinct; no automatic restart occurs.
- [ ] Configuration changes invalidate PASS until another completed sweep.
- [ ] The next-move instructions explain recovery without verbal assistance.
- [ ] SAVE REPORT captures; exiting VR and using Saved report downloads that snapshot.
- [ ] Downloaded JSON contains the intended session and historical completed runs.
- [ ] Reload creates a fresh station while Saved report still retrieves the prior snapshot when browser storage permits.
- [ ] A new explicit save replaces the earlier stored snapshot predictably.

### Comfort, rendering, and lifecycle

- [ ] Text, units, angles, and fault messages are readable at a comfortable distance.
- [ ] Seated and standing bench heights work without repeated reaching outside the comfortable forward arc.
- [ ] Critical states use words as well as color; sound/haptics are not required to understand them.
- [ ] No required artificial locomotion or camera shake.
- [ ] At least five continuous minutes include running rotor, panel updates, and interaction; no persistent stutter or progressive degradation is observed.
- [ ] Performance HUD/profiler records the actual refresh rate and CPU/GPU/compositor behavior. Target: 72 Hz (~13.9 ms/interval), with no sustained missed-frame pattern. Record measurements and misses rather than inferring this from desktop FPS.
- [ ] Headset removal/system-menu interruption/visibility loss and return do not fire unintended commands; record whether simulation pauses, slows, or continues.
- [ ] Exit/re-enter VR restores usable viewpoint, controller state, and panels.
- [ ] A serving-connection interruption has an understandable reload/reconnect recovery.
- [ ] Learner comfort/readability ratings and any nausea/eye strain/arm fatigue are recorded.

## Defect triage and release decision

Prioritize failure to enter VR, unintended control activation, incorrect interlock/recovery outcomes, and data loss above visual polish. Treat persistent stutter or unusable reach/text as release blockers for a headset demo. Cosmetic differences may be accepted with a recorded limitation. Every reported issue should include exact steps, expected/actual behavior, versions, and evidence.

Before calling the app headset-validated, complete the physical record and resolve or explicitly accept each material defect. Release preparation also includes asset provenance, license attribution, documentation accuracy, and final capture review. Keep the initial feedback release label until those checks are satisfied.
