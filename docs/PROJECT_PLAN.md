# SpinLab XR — architecture and implementation plan

Updated 18 October 2026. SpinLab XR is an educational reaction-wheel balancing and commissioning simulation. The active application is a **Godot 4.7.2 / OpenXR standalone ARM64 APK for Quest 2**, version 0.8.0. A separate Three.js/WebXR version 0.1 remains available as a browser demonstrator. The two applications have different interaction and numerical capabilities; identify their setup and results by version.

Use [APK_SETUP.md](APK_SETUP.md) for installation and controls, [UX_DESIGN.md](UX_DESIGN.md) for workspace and movement, [TUTORIAL.md](TUTORIAL.md) for guided learning, [DIRECT_INTERACTION_DESIGN.md](DIRECT_INTERACTION_DESIGN.md) for contact and grip behavior, [NATIVE_RESEARCH.md](NATIVE_RESEARCH.md) for scientific methods, and [NATIVE_VALIDATION.md](NATIVE_VALIDATION.md) for recorded evidence. [DEMO_GUIDE.md](DEMO_GUIDE.md) provides a repeatable demonstration and capture procedure.

## Implemented application

The learner installs a rotor, references a vibration probe, closes an interlocked enclosure, records a baseline and known trial response, calculates correction masses, and verifies the corrected rotor with a fresh acquisition. The beginner course teaches both correction planes and two coupled sensor channels as one coherent experiment; single-plane operation remains available independently.

Version 0.8.0 (Android version code 10) includes:

- An original procedural laboratory, workbench, spindle, rotor cassette, two correction planes, probe stage, and counterbalanced lift guard.
- Controller-tracked articulated gloves, fingertip button presses with visible cap travel, nearby rotor pickup and seating, continuous guard movement, and wrist-operated dials.
- Guided and expert operation, single- and two-plane balancing, waveform/DFT/sweep views, repeatability, fault injection and recovery, an exploded teaching view, and optional synthesized motor audio.
- An 18-button physical operating console, lower, angled side analyzer, default-hidden Tools/Session menu, runtime controller models with Quest 2 asset fallback, controller-derived Capsense finger visuals, and menu rays, haptics, and a desktop review interface.
- Two small circular letter markers above each glove, aligned with authored Quest 2 face-button positions through the full grip transform; hidden in menu mode or tracking/focus loss.
- Left-stick bench height and bounded, head-relative right-stick walking with focus/tracking/ownership restrictions and neutral rearming; Session provides recenter and walking enable/disable.
- Isolated worker-thread signal analysis, deterministic scenarios, command/interaction history, and persistent JSON reports.
- Thirty-eight automatically advancing balancing stages with minimal target-adjacent callouts and offline neural voice instructions/scientific explanations. Whole-card collision and stereo occlusion checks hide obstructed prompts. Voice can be replayed or muted; Session retains pause/resume, skip, restart, and startup preference.

The normal workspace has the menu closed. Startup guidance appears beside the fixture when enabled. Pause/resume preserves the current lesson; the startup preference controls later launches and completion turns it off. Instruction navigation never starts a run or changes the fixture. Deliberate laboratory actions can invalidate calibration; save reports before changing setup or starting a new live session.

The virtual hardware and measurements are synthetic. The application does not control laboratory equipment or use headset tracking, cameras, or microphones as vibration sensors.

## Software architecture

| Component | Responsibility and boundary |
| --- | --- |
| `native/scripts/rotor_lab.gd` | Deterministic engineering state, acquisition configuration, sampled signals, interlocks, complex influence coefficients, verification, statistics, and report data. Numerical state is separate from rendering and input. |
| `native/scripts/main.gd` | Godot/OpenXR setup, command dispatch, tracked input, ownership, station placement, instrument displays, report persistence, and runtime diagnostics. Desktop and XR operations use the same command handlers. |
| `native/scripts/direct_interaction.gd` | Pure fingertip contact state machine with front approach, swept crossing, actuation depth, debounce, withdrawal, and tracking-gap reset. |
| `native/scripts/virtual_hand.gd` | Original articulated glove geometry and controller-input pose estimation. The visible fingertip marker supplies the contact coordinate; calibration offsets affect both together. |
| `native/scripts/virtual_controller.gd` | Runtime-supplied controller model, pinned MIT Quest 2 Touch v3 fallback assets, and authored fallback control animation for the menu. It does not supply input/aim calibration. |
| `native/scripts/controller_capsense_hand.gd` | Menu-only runtime hand mesh and controller-derived joint poses. Requires valid controller-source data; owns no gestures, input targets, or asset export. |
| `native/scripts/operator_navigation.gd` | Pure bounded floor translation, dead zone, and head-relative direction. Main owns station height and movement permission/rearming rules. |
| `native/scripts/lab_geometry.gd` | Procedural fixture/environment, moving assemblies, interaction targets, and visual engineering state. Shared meshes and MultiMesh instances reduce repeated draw work. |
| `native/scripts/lab_button.gd` | World-space button geometry, captions, metadata, and cap depression. Input ownership and command dispatch remain in the application. |
| `native/scripts/analyzer_view.gd` | Captured-data selection, time/order/sweep axes and empty-state instructions. |
| `native/scripts/panel_chart.gd` | Bounded thick A/B traces, numeric ticks, zero/grid references, and explicit signal units. |
| `native/scripts/lab_tutorial.gd` | Balancing work instructions with fresh accepted-action/capture gates, immediate action-driven progression, calibration recovery, review, and preference persistence. It never operates or resets the laboratory model. |
| `native/scripts/tutorial_narrator.gd` | Offline step audio, interruption, replay/mute, preference and immediate replacement on task transition; audio never gates progression. |
| `native/scripts/target_callout_placement.gd` | Whole-card collision/stereo occlusion checks and cached live geometry. |
| `native/scripts/tutorial_panel.gd` | Minimal target-adjacent imperative/arrow, progress and short state. No paragraphs or touch targets. |
| `native/tests/` | Numerical, contact, hand geometry, command/UI, direct-hand, and tutorial model/panel/application verification without a headset. |
| `tools/` | Toolchain preparation, APK build/install, and device report retrieval. Downloaded tools, generated Android templates, signing keys, and device captures stay outside source control. |

Analysis workers receive isolated configuration, arrays, and random-number state. The main thread accepts results after joining a worker. Stop, E-stop, and interruption paths discard cancelled results. Rendering continues during analysis; software concurrency checks do not establish headset frame pacing.

## Scientific model and data contract

The native model uses mass in grams, radius in millimetres, speed in rpm, phase in degrees relative to the tachometer, and displacement in **peak micrometres**. Correction is a complex mass-radius vector. The numerical correction radius is 30 mm; the rendered rotor and correction markers are enlarged for visibility.

| Method | Implemented behavior |
| --- | --- |
| Acquisition | 1,024 synthetic samples at 1,024 Hz, including DC offset, synchronous 1× response, 2× content, and deterministic noise. The displayed waveform retains the last 256 samples. |
| Tach-referenced analysis | Least-squares DC, cosine/sine 1×, and cosine/sine 2× terms separate synchronous response from bias and second-harmonic motion, including noninteger-revolution records. |
| Single-plane balancing | Measure baseline and a known complex trial vector at a matching setup; estimate the influence coefficient and solve the required correction from saved measurements. |
| Two-plane balancing | Measure independent trials in each plane and both channels; solve the measured 2×2 complex influence matrix. Trial independence, sensitivity, setup consistency, and conditioning checks reject unsuitable calibration. |
| Verification | Remove trial masses, fit the calculated total correction, and acquire a new record. Configuration changes invalidate current verification while preserving historical records. |
| Spectrum / order | One-sided peak-amplitude DFT from 0–100 Hz. ORDER displays frequency divided by the captured shaft frequency, from 0–5× with 1×/2× references; it does not use a later speed setting. |
| Resonance sweep | Separate quasi-steady windows over speed using an illustrative second-order response with 22 Hz natural frequency and damping ratio 0.11. |
| Repeatability | Three independent deterministic-noise windows, sample standard deviation, and Type A standard error of the mean. |

A sweep is not a transient flexible-rotor integration. Repeatability is not a complete uncertainty budget. Near-zero synchronous phase is marked unobservable at the simulated noise floor. Single-plane correction minimizes sensor A at one speed and can leave sensor B motion. The model does not establish an ISO balance grade, instrument calibration, structural qualification, bearing life, vacuum/thermal behavior, or flight performance. Assumptions and references are maintained in [NATIVE_RESEARCH.md](NATIVE_RESEARCH.md).

JSON reports retain configuration and units, baseline/trial/verification records, calculated corrections, sweep data, methodology/references, event history, interaction history, application diagnostics, and a tutorial progress snapshot. Tutorial completion is separate from measurement verification or competence. Reports persist in `user://reports` with unique filenames. Relaunching starts a fresh live station rather than resuming a rotating acquisition. Tutorial startup/completion preferences persist separately in `user://tutorial.cfg`.

## Interaction and state requirements

The default input uses two Touch controllers. Separate grip and aim nodes supply nearby interaction and menu pointing. Finger articulation is estimated from controller inputs; this is not optical finger tracking. Handed orientation follows the documented OpenXR grip convention and remains adjustable for physical fit testing.

Direct buttons actuate 6 mm behind the resting cap surface, show up to 8 mm travel, and require front approach plus withdrawal before another press. Contact history resets after tracking gaps, target relocation, recentering, and focus interruption. Mesh position and mathematical fingertip position share the same marker.

Nearby rotor, guard, and dial grips have exclusive ownership. The sole probe control is the actual carriage micrometer; front Probe and ± duplicates have been removed. Starting an acquisition while a mechanism is held is rejected. Manipulation requires zero speed and no pending acquisition/analysis; correction changes also require a mounted rotor and open guard. Opening a closed lift guard removes its interlock; lowering fully and releasing latches it. Tracking/focus loss cancels holds without seating an uncommitted rotor.

Left-stick height adjustment supports seated/standing reach. Right-stick movement is limited to 0.65 m/s within floor bounds and follows head yaw without vertical movement or artificial turning. It is blocked while menus are open, mechanisms are held, required tracking is unavailable, or focus is lost; neutral rearming prevents motion when control returns. Session recenter restores the starting arrangement. These safeguards do not establish comfort; validate movement, text legibility, controller clearance, and reach on physical hardware.

B/Y toggles the two-tab Tools/Session menu with selected-state highlighting. It replaces gloves with controller models, supported controller-derived Capsense visuals, and trigger-operated rays while suspending physical input. All ordinary operating commands, including HOME, SPEED, CHART, and SAVE REPORT, have one canonical physical console cap and no menu duplicate. Tools holds only faults, assembly inspection, and motor sound. Session holds guide/voice preferences, recenter, movement, and reset.

The 38-step course observes accepted actions and completed measurements, advancing immediately without waiting for audio. It teaches the activity before the first action and introduces theory while using real controls and graphs. When post-baseline calibration is invalidated, the guide directs stopped recovery/HOME and requires a new baseline plus independent trials, preserving records. A/X provide optional review. Read-only guidance and playback cannot operate equipment. See [TUTORIAL.md](TUTORIAL.md), [NARRATION.md](NARRATION.md), and [ANALYZER.md](ANALYZER.md).

## Assets and rendering

Fixture geometry, original physical-work gloves, labels, graphs, and synthesized audio are generated locally. Menu controllers use headset-supplied models when available and pinned MIT Quest 2 Touch assets as fallback. Capsense uses a runtime hand mesh and controller-derived joint poses; Meta runtime assets are not extracted into the repository. The fixture hierarchy follows its moving parts. Repeated details use shared geometry and instancing. Metal appearance and transparent guard panels are illustrative rather than a dimensional or optical simulation.

Visual speed, part size, and probe travel are exaggerated for legibility; numerical readouts and reports use the engineering values. Geometry volume does not determine correction mass. Glove previews and geometry tests check pose correspondence and structural budgets; submitted stereo draw calls and frame timing require runtime measurement.

Any added model, texture, font, sound, or dependency must have a recorded source, version, license, redistribution terms, and attribution. Prefer metre-scale glTF/GLB assets with explicit origins, moving-part names, material slots, and bounded geometry/texture budgets. Preserve dependency notices in distributable builds.

## Build and verification workflow

1. Prepare the pinned Windows toolchain with `tools/Setup-NativeToolchain.ps1`. It installs the matching Android Gradle source template and delegates the final test/export gate to `tools/Build-APK.ps1`.
2. Build with `tools/Build-APK.ps1`. Numerical, contact, geometry, application, tutorial, and navigation checks must pass before exporting the signed ARM64 APK to `artifacts/SpinLabXR-v0.8.0.apk`. Signing and immersive launch metadata require their own checks.
3. Install using `tools/Install-APK.ps1` after authorizing USB debugging. Keep the development signing key for compatible updates; do not commit it.
4. Run the physical acceptance procedure in [APK_SETUP.md](APK_SETUP.md), then retrieve reports with `tools/Pull-Quest-Reports.ps1`.
5. Record the APK version/hash, device OS/runtime, scenario, observed behavior, and relevant report/capture with each issue. Rebuild and repeat affected checks after changes.

The separate browser demonstrator uses its Node.js model/server tests and packaging workflow. Its WebXR transport and known-correction exercise do not substitute for native APK or measured-trial validation.

## Milestones and remaining validation

| Area | Current state and evidence boundary |
| --- | --- |
| Scientific model | Measured single/two-plane influence coefficients, independent trials, fresh verification, repeatability, and quasi-steady sweep are implemented. Exact test results remain in [NATIVE_VALIDATION.md](NATIVE_VALIDATION.md). |
| Direct interaction | Controller-driven gloves, nearby pickup, constrained guard, wrist dials, and physical console share accepted command routing. No redundant front Probe or ± controls remain. |
| Beginner learning | The 38-step course includes conceptual introduction, actual micrometer and vector practice, safe abort/recovery, plots, independent two-plane calibration, correction, verification, repeats, and reporting. |
| Analyzer | Acquired-data TIME/ORDER/SWEEP views have distinct A/B traces, numerical axes, captured-speed normalization, and explicit missing-data instructions. |
| Packaging | Tooling targets `SpinLabXR-v0.8.0.apk`, version code 10. Export, signing, installed version, device/runtime evidence, and hashes must be recorded for the actual release. |
| Prior headset feedback | v0.6 automatic progression worked. The operator described v0.7.0's minimal prompts, narration, and button markers as substantially better, then reported label obstruction, missing concepts/micrometer, and an empty graph. |
| Current physical acceptance | v0.8.0 needs a full two-plane course run, dial/readout clearance, right-side micrometer reach, plot reading, immediate speech interruption, calibration recovery, report retrieval, comfort, and sustained frame pacing. Software checks do not establish those results. |

## Execution and test priorities

1. Build and verify source behavior, audio coverage, actual-fixture placement, analyzer data/axes, packaging, and signed manifest. Install only the intended APK and record its hash/version.
2. Run the complete physical lesson with both hands. Listen before some actions, act during others, and confirm that accepted work immediately replaces speech. Check micrometer reach using right-stick walking, release-before-HOME, wrist regripping, independent A/B trials, fresh verification, and the saved report.
3. Deliberately invalidate calibration after baseline, verify stopped recovery/HOME guidance and a return to fresh baseline/trials, and check that historic evidence remains. Reject aborted, stale, processing, coasting, and incompatible records.
4. Check both Tools/Session tabs, selected state, guide preferences/review/skip, standby/re-entry, movement neutral rearming, recenter, report retrieval, and at least five minutes of representative foreground activity. Retain actual device captures separately from desktop previews.
5. Fix reproducible hardware issues and repeat affected checks. Preserve the original report, logs, and tested APK hash with feedback.

Possible research extensions include changing-speed angular resampling, a full order waterfall, identified damping/modal fits, Type B uncertainty, Monte Carlo correction intervals, and optical-hand operation. They require separate implementation and validation; they are not current capabilities.
