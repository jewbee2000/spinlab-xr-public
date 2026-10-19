# SpinLab XR — architecture and implementation plan

Updated 18 October 2026. SpinLab XR is an educational reaction-wheel balancing and commissioning simulation. The active application is a **Godot 4.7.2 / OpenXR standalone ARM64 APK for Quest 2**, version 0.7.0. A separate Three.js/WebXR version 0.1 remains available as a browser demonstrator. The two applications have different interaction and numerical capabilities; identify their setup and results by version.

Use [APK_SETUP.md](APK_SETUP.md) for installation and controls, [UX_DESIGN.md](UX_DESIGN.md) for workspace and movement, [TUTORIAL.md](TUTORIAL.md) for guided learning, [DIRECT_INTERACTION_DESIGN.md](DIRECT_INTERACTION_DESIGN.md) for contact and grip behavior, [NATIVE_RESEARCH.md](NATIVE_RESEARCH.md) for scientific methods, and [NATIVE_VALIDATION.md](NATIVE_VALIDATION.md) for recorded evidence. [DEMO_GUIDE.md](DEMO_GUIDE.md) provides a repeatable demonstration and capture procedure.

## Implemented application

The learner installs a rotor, references a vibration probe, closes an interlocked enclosure, records a baseline and known trial response, calculates correction masses, and verifies the corrected rotor with a fresh acquisition. An advanced exercise uses two correction planes and two coupled sensor channels.

Version 0.7.0 includes:

- An original procedural laboratory, workbench, spindle, rotor cassette, two correction planes, probe stage, and counterbalanced lift guard.
- Controller-tracked articulated gloves, fingertip button presses with visible cap travel, nearby rotor pickup and seating, continuous guard movement, and wrist-operated dials.
- Guided and expert operation, single- and two-plane balancing, waveform/DFT/sweep views, repeatability, fault injection and recovery, an exploded teaching view, and optional synthesized motor audio.
- An 18-button physical operating console, lower, angled side analyzer, default-hidden three-tab menu, runtime controller models with Quest 2 asset fallback, controller-derived Capsense finger visuals, and menu rays, haptics, and a desktop review interface.
- Two small circular letter markers above each glove, aligned with authored Quest 2 face-button positions through the full grip transform; hidden in menu mode or tracking/focus loss.
- Left-stick bench height and bounded, head-relative right-stick walking with focus/tracking/ownership restrictions and neutral rearming; Session provides recenter and walking enable/disable.
- Isolated worker-thread signal analysis, deterministic scenarios, command/interaction history, and persistent JSON reports.
- Fifteen automatically advancing balancing stages with minimal target-adjacent callouts and offline neural voice instructions/scientific explanations. Whole-card collision and stereo occlusion checks hide obstructed prompts. Voice can be replayed or muted; Session retains pause/resume, skip, restart, and startup preference.

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
| `native/scripts/panel_chart.gd` | Bounded world-space traces and graph grids. Instrument labels declare signal type and units. |
| `native/scripts/lab_tutorial.gd` | Balancing work instructions with fresh accepted-action/capture gates, automatic completion dwell, review, and preference persistence. It never operates or resets the laboratory model. |
| `native/scripts/tutorial_narrator.gd` | Offline step audio, interruption, replay/mute, preference and progression gating. |
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
| Spectrum | One-sided peak-amplitude DFT from 0–100 Hz. Frequency labels identify the expected 1× location at the selected speed. |
| Resonance sweep | Separate quasi-steady windows over speed using an illustrative second-order response with 22 Hz natural frequency and damping ratio 0.11. |
| Repeatability | Three independent deterministic-noise windows, sample standard deviation, and Type A standard error of the mean. |

A sweep is not a transient flexible-rotor integration. Repeatability is not a complete uncertainty budget. Near-zero synchronous phase is marked unobservable at the simulated noise floor. Single-plane correction minimizes sensor A at one speed and can leave sensor B motion. The model does not establish an ISO balance grade, instrument calibration, structural qualification, bearing life, vacuum/thermal behavior, or flight performance. Assumptions and references are maintained in [NATIVE_RESEARCH.md](NATIVE_RESEARCH.md).

JSON reports retain configuration and units, baseline/trial/verification records, calculated corrections, sweep data, methodology/references, event history, interaction history, application diagnostics, and a tutorial progress snapshot. Tutorial completion is separate from measurement verification or competence. Reports persist in `user://reports` with unique filenames. Relaunching starts a fresh live station rather than resuming a rotating acquisition. Tutorial startup/completion preferences persist separately in `user://tutorial.cfg`.

## Interaction and state requirements

The default input uses two Touch controllers. Separate grip and aim nodes supply nearby interaction and menu pointing. Finger articulation is estimated from controller inputs; this is not optical finger tracking. Handed orientation follows the documented OpenXR grip convention and remains adjustable for physical fit testing.

Direct buttons actuate 6 mm behind the resting cap surface, show up to 8 mm travel, and require front approach plus withdrawal before another press. Contact history resets after tracking gaps, target relocation, recentering, and focus interruption. Mesh position and mathematical fingertip position share the same marker.

Nearby rotor, guard, and dial grips have exclusive ownership. Shared controls for the same probe adjustment share a resource lock. Starting an acquisition while a mechanism is held is rejected. Manipulation requires zero speed and no pending acquisition/analysis; correction changes also require a mounted rotor and open guard. Opening a closed lift guard removes its interlock; lowering fully and releasing latches it. Tracking/focus loss cancels holds without seating an uncommitted rotor.

Left-stick height adjustment supports seated/standing reach. Right-stick movement is limited to 0.65 m/s within floor bounds and follows head yaw without vertical movement or artificial turning. It is blocked while menus are open, mechanisms are held, required tracking is unavailable, or focus is lost; neutral rearming prevents motion when control returns. Session recenter restores the starting arrangement. These safeguards do not establish comfort; validate movement, text legibility, controller clearance, and reach on physical hardware.

B/Y toggles the menu, which has Balance, Analyze, and Session tabs with selected-state highlighting. The open menu replaces gloves with controller models, available controller-derived Capsense hands, and trigger-operated rays; it suspends physical interaction. The 15-stage work instructions advance after actual accepted work and a 1.5-second success dwell; A/X remain optional review controls while the menu is closed. Session contains New Session; app exit uses the Quest system menu. The physical console exposes the ordinary balancing workflow. Contact resets on menu changes and target relocation prevent an embedded fingertip from actuating a newly appearing control.

## Assets and rendering

Fixture geometry, original physical-work gloves, labels, graphs, and synthesized audio are generated locally. Menu controllers use headset-supplied models when available and pinned MIT Quest 2 Touch assets as fallback. Capsense uses a runtime hand mesh and controller-derived joint poses; Meta runtime assets are not extracted into the repository. The fixture hierarchy follows its moving parts. Repeated details use shared geometry and instancing. Metal appearance and transparent guard panels are illustrative rather than a dimensional or optical simulation.

Visual speed, part size, and probe travel are exaggerated for legibility; numerical readouts and reports use the engineering values. Geometry volume does not determine correction mass. Glove previews and geometry tests check pose correspondence and structural budgets; submitted stereo draw calls and frame timing require runtime measurement.

Any added model, texture, font, sound, or dependency must have a recorded source, version, license, redistribution terms, and attribution. Prefer metre-scale glTF/GLB assets with explicit origins, moving-part names, material slots, and bounded geometry/texture budgets. Preserve dependency notices in distributable builds.

## Build and verification workflow

1. Prepare the pinned Windows toolchain with `tools/Setup-NativeToolchain.ps1`. It installs the matching Android Gradle source template and delegates the final test/export gate to `tools/Build-APK.ps1`.
2. Build with `tools/Build-APK.ps1`. Numerical, contact, geometry, application, tutorial, and navigation checks must pass before exporting the signed ARM64 APK to `artifacts/SpinLabXR-v0.7.0.apk`. Signing and immersive launch metadata require their own checks.
3. Install using `tools/Install-APK.ps1` after authorizing USB debugging. Keep the development signing key for compatible updates; do not commit it.
4. Run the physical acceptance procedure in [APK_SETUP.md](APK_SETUP.md), then retrieve reports with `tools/Pull-Quest-Reports.ps1`.
5. Record the APK version/hash, device OS/runtime, scenario, observed behavior, and relevant report/capture with each issue. Rebuild and repeat affected checks after changes.

The separate browser demonstrator uses its Node.js model/server tests and packaging workflow. Its WebXR transport and known-correction exercise do not substitute for native APK or measured-trial validation.

## Milestones and current status

| Milestone | Status and evidence |
| --- | --- |
| Native scientific model | Implemented with deterministic numerical tests, including synchronous/threaded equivalence and cancellation. |
| Direct interaction | Implemented with contact, geometry, ownership, and actual command-handler checks; standalone hand renders have been reviewed. |
| APK packaging | Build/install tooling targets v0.7.0 ARM64. Exact export/signature/install evidence and hashes are recorded in [NATIVE_VALIDATION.md](NATIVE_VALIDATION.md); older install evidence does not establish v0.7.0 behavior. |
| Physical launch foundation | Version 0.2 hardware observations confirm the 3D lab, controller interaction, and spinning rotor. A short recorded runtime interval does not establish sustained performance. |
| Physical workflow feedback | Prior feedback found hands, guard, and dials useful and identified obstructive instruction cards and unintended curled-finger presses. Version 0.5.1 feedback confirmed upright lettering and acceptable guide/analyzer appearance but found the controller button/stick layout incorrect. Version 0.7.0 replaces controller graphics and adds controller-derived finger visuals; those changes need a fresh headset run. |
| Version 0.7.0 workspace and movement | Implemented physical console, side analyzer, separate menu/controller mode, floating guide, and bounded stick movement. Desktop geometry/application/navigation tests and preview renders support software checks. Physical reach, monitor visibility, glove contact, menu use, locomotion comfort, report retrieval, and sustained frame pacing remain pending. |
| Demonstration records | Capture repeatable scenarios and supporting reports using [DEMO_GUIDE.md](DEMO_GUIDE.md), identifying desktop versus headset evidence. |

## Next implementation and test priorities

1. Complete the version 0.7.0 headset exercise with both hands. Check physical console visibility, analyzer sightlines with the guard open/closed, B/Y menu/controller transition, ray-trigger selection, automatic guide progression and its success dwell, optional A/X review, pause/resume, skip, startup OFF, and restart. Confirm the three tabs are Balance/Analyze/Session and New Session is in Session. Tune placement, offsets, contact thresholds, or text size from reproducible feedback.
2. Verify complete single-plane and two-plane sequences, deliberate failures, report persistence/retrieval, standby/re-entry, and recentering. Check that tutorial gates reflect accepted outcomes, cancelled acquisitions, and calibration invalidation without altering scientific state.
3. Check left-stick height, right-stick walking, floor bounds, and neutral rearming after menus, holds, tracking interruptions, and focus changes. Profile at least five minutes of reaching, carrying, adjustment, movement, and analysis. Correlate foreground intervals with runtime statistics; exclude startup, paused/off-head, and unrelated application intervals.
4. Address measured CPU/GPU or interaction issues, then repeat relevant checks. Retain original captures and the tested APK hash.

Possible research extensions include angular resampling during changing-speed records, a full order waterfall, identified modal/damping fitting, Type B uncertainty, Monte Carlo correction intervals, and optional optical hands. These require separate implementation and validation; they are not current capabilities.
