# Native validation record

Recorded 18 October 2026. This distinguishes software evidence from physical-headset acceptance.

## Version 0.2 software checks passed

- Godot 4.7.2 Compatibility renderer imports and runs the native project on Windows, including the procedural scene, world-space controls, sampled-signal plots, and report export.
- **129 numerical checks:** deterministic tach-referenced least-squares extraction of DC/1×/2×, noninteger-revolution windows, single- and two-plane measured influence coefficients, trial independence, nonzero baseline masses, low sensitivity and near-singular matrix rejection, speed/probe calibration invalidation, resonance sweep, repeatability, latched faults, and pending-analysis cancellation.
- Threaded and synchronous acquisitions produce equivalent captured phasors, waveforms, spectra, three-window statistics, and sweep points. A worker owns its own model/configuration/RNG; results are copied only after it is joined. Stop and E-stop discard pending results. This tests concurrency logic, not Quest frame pacing.
- **581 native UI integration assertions** pass through the actual command handlers and button metadata for both balancing modes, all menus, charts, correction invalidation, repeatability, and JSON report export. The rendered integration run adds two image checks (583 assertions). Screenshots were visually reviewed. Both Touch action bindings are present in the generated OpenXR action map; physical input has not yet been established by these tests.
- In deterministic model tests, single-plane response fell from 8.25610 µm to 0.00517 µm. Two-plane residuals were 0.0120 and 0.0102 µm, with matrix condition 3.008. These are synthetic results under the chosen linear model, not measurements of physical equipment.
- The APK exports successfully through Godot/Gradle and Android's `apksigner verify` accepts its v2 development signature. Its manifest identifies `us.teitelbaum.spinlabxr` v0.2.0, minimum SDK29, target35, compile36, the Meta VR and OpenXR immersive launch categories, Quest2 support, runtime-discovery permissions, and the Meta OpenXR plugin. Both `.GodotApp` and its launcher alias `com.godot.game.GodotAppLauncher` are exported; the install helper uses the alias with the VR category. The lab is not configured as an Android home launcher.
- App runtime requires no network, microphone, camera, API key, or web server. Scientific reports persist in the app's `user://reports` directory with unique filenames; live station state starts fresh after relaunch.

## Reproduce

With the local pinned toolchain configured:

```powershell
.\tools\Build-APK.ps1
```

Or run checks separately:

```powershell
.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --xr-mode off --path native --script res://tests/test_science.gd
.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --xr-mode off --path native --script res://tests/test_app.gd
```

`--xr-mode off` applies only to desktop QA/export tooling. The actual Android APK enables native OpenXR. CI runs the numerical and command/UI checks on Linux in addition to the existing browser model/server tests. The APK build itself is a local Windows Gradle build; a passing headless CI job does not imply a headset render test.

## Compatibility warning and runtime metrics

The latest launch no longer reports the missing `xr/openxr/extensions/hand_tracking` property. One upstream renderer warning remains: **“Foveation with subsampled images was enabled, but rendering features are in use that have forced it to be disabled.”** Godot 4.7.2's Compatibility texture storage always reports subsampled images unavailable. Its OpenXR render state starts with `use_subsampled_images=true`, and the first fallback emits this warning without checking whether the feature was requested. Consequently this message alone does not establish an MSAA defect or a failure to initialize XR. It is retained as an observed fallback warning; no engine patch or renderer change was made to hide it. [OpenXR initial state](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/openxr/openxr_api.h), [fallback/warning logic](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/openxr/openxr_api.cpp), [Compatibility texture-storage implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/texture_storage.h).

Capture timestamped runtime statistics during a deliberate foreground test, then stop collection with Ctrl+C:

```powershell
& .\.tools\platform-tools\adb.exe logcat -v threadtime 'VrApi:V' 'crcs:V' 'godot:I' '*:S' > .\artifacts\quest-runtime-metrics.txt
```

Correlate each interval with the SpinLab process, resumed activity, and headset session state; `adb shell pidof us.teitelbaum.spinlabxr` and `adb shell dumpsys activity activities` provide useful snapshots. Exclude startup/transition, paused/off-head, and Meta Home intervals. Avoid filtering the whole capture by the app PID because runtime statistics may originate in another process. Meta defines `FPS` as rendered frames/display refresh and reports stale-frame counts and app/timewarp GPU timing. `App=` can overlap compositor work; it is not the complete CPU+GPU frame interval. A short clean interval establishes only that interval, and does not establish five-minute performance or comfort. [Meta logcat statistic definitions](https://developers.meta.com/vr/documentation/spatial-sdk/ts-logcat-stats/), [Meta GPU-cost interpretation](https://developers.meta.com/horizon/documentation/unity/po-per-frame-gpu/).

## Version 0.2 physical evidence

The signed v0.2 APK installed successfully on the physical Quest 2 (Android API32) after restoring its Windows ADB interface registration and authorizing USB debugging. The device reports Godot 4.7.2, OpenXR 1.1.54 on Oculus runtime74.759.0, the Adreno650 OpenGL ES3.2 renderer, and `SPINLAB_NATIVE_READY ... xr=true`. Both `left_hand` and `right_hand` aim trackers report ready. A physical-headset smoke test confirmed **the 3D lab and controller pointers are visible, menu buttons respond, and the rotor spins**.

An app-process VrApi snapshot from16:01:14–16:01:23 local time contains ten one-second samples, all at72/72 rendered/display FPS. The first sample reports one stale frame; the remaining nine report zero. `App=` ranges6.96–8.30ms. This is a short smoke-test interval, with no claim about five-minute stability or comfort. The engine's own five-second samples are supplementary diagnostics and are included in saved reports.

A complete balancing exercise, report retrieval, text readability, seating/recenter ergonomics, suspend/resume, and sustained comfort/performance remain unconfirmed. No saved report files were available during the retrieval check; the source-confirmed storage path is not proof of a successful hardware export. Local device logs and reports are excluded from Git.

Installed APK SHA256: `641a22a9ec0943e81b329d45143af054fed45de8b7baf7d09feae5416e9cb313` (89,900,036 bytes). Retain this hash with feedback; the debug signing key remains private outside Git.

## Version 0.3 direct-interaction validation

Windows software verification passes: **129 scientific**, **603 command/UI**, **68 contact state-machine**, **475 hand geometry/button travel**, and **85 direct-hand application** assertions. A rendered command/UI run adds two screenshot checks. The new application suite drives the actual input polling loop with simulated controller APIs and verifies grip rearming, app/OpenXR focus conjunction, nearby/exclusive ownership, rotor orientation/seating, continuous guard travel, correct X/Z dial axes, held-control setup protection, and report interaction history. These are software checks, not physical hand tracking measurements.

The signed v0.3.0/code3 APK installed successfully on the connected Quest 2 using the retained development key. APK signing verification passes. Current APK SHA256: `500bea5382e975379ddf0cb4b4d574f6a950d05db66a6a107f996e58c6532f1f`. Physical alignment/contact feedback is pending.

Version 0.3 replaces the default ray workflow with Touch-driven visible gloves, fingertip button travel, nearby rotor/guard/dial grips, wrist adjustments, and menu-only reach assist. The scientific methods are unchanged. These new interactions require their own physical acceptance; the v0.2 button/spin smoke test and short VrApi sample do not establish their hand alignment, contact reliability, comfort, report retrieval, or sustained frame pacing. Follow the current [APK setup and physical test](APK_SETUP.md) and [direct-interaction design](DIRECT_INTERACTION_DESIGN.md). Record the installed v0.3 APK hash and observed results separately after installation.

## Version 0.4 tutorial software and package evidence

Windows verification passes **2,474 assertions** across eight native suites: 129 scientific, 823 command/UI, 68 contact, 475 hand geometry/button travel, 85 direct-hand application, 256 tutorial state/content, 546 tutorial panel/layout, and 92 tutorial/application workflow checks. The panel suite checks every actual lesson for untruncated body/theory text and font-based spacing, all five tab captions, and hidden/disabled input. The application suite completes the real single-plane tutorial workflow, saves/inspects a JSON report, exercises fingertip practice, rejects premature Next, and verifies startup preferences across actual scene relaunches. Its corrupt-settings case intentionally emits a ConfigFile parse diagnostic and asserts recovery with a visible status message. A rendered panel run adds two actual-app capture checks (548); the welcome and measured-influence views were visually reviewed. The browser syntax checks, 15 tests, and portable packaging also pass.

The v0.4.0/code4 ARM64 APK exported through Godot/Gradle, passed Android v2 signature verification, and installed successfully on the connected Quest 2 using the retained development key. Package-manager inspection confirms code4/name0.4.0, minimum SDK29 and target35. The APK is **89,955,357 bytes**, SHA256 `80944512787b318719860709ba72f4578438299dfa4c1480530a12550173ae86`. Its 157 ZIP entries include the tutorial scripts and exclude tests and nested Android build assets. Setup excludes the Gradle directory from Godot imports to prevent generated `.import` files from becoming Android resources.

Installation is confirmed; v0.4 foreground rendering, tutorial readability/reach, completed physical exercises, report retrieval, and sustained performance remain pending. The desktop screenshot is layout QA, not a headset capture. Keep the APK hash with physical feedback.

## Learn tutorial acceptance plan — hardware pending

The 23-page Learn feature needs physical acceptance in addition to the software/package evidence above. This matrix defines the complete expected exercise and does not extend the earlier v0.2/v0.3 physical evidence. Retain the installed build version, commit, APK SHA256, and device observations with each executed check. See [TUTORIAL.md](TUTORIAL.md) for the lesson inventory and state-controller contract.

| ID | Check | Required evidence / acceptance condition |
| --- | --- | --- |
| T-01 | First launch and discovery | LEARN is the fifth readable/reachable tab. Startup opens instruction when enabled, without a modal obstruction, simulated run, mass change, fault, mode change, or lab reset. B/Y and desktop tab navigation include Learn. |
| T-02 | WHAT / WHY layout | Inspect every page, longest hint, and settings error. Chapter, progress, WHAT, WHY, controls, and unmet-objective text remain legible without clipping or overlap. Test inside the headset, including both eye views. |
| T-03 | Practice and return | Practice opens the indicated real menu only. The compact coach retains the current task. Learn/Next and Skip remain reachable from ordinary practice menus; changing tabs does not lose the selected page. |
| T-04 | Manual gated Next | An unmet practical objective disables Next and explains what is missing. Calling the handler directly also rejects advancement. Satisfying an objective enables Next but never advances automatically or runs the next action. |
| T-05 | Escape and review | Back after the first page, Skip lesson, Skip for now, and manual Restart work with an unmet objective, during a run, and after a fault. They do not alter model configuration, records, pending acquisition, or saved reports. |
| T-06 | Startup persistence | Test default ON, explicit OFF across relaunch, manual start while OFF, skip without preference change, completion turning startup OFF, and explicit ON after completion. Corrupt/missing settings and save failure produce recoverable behavior. |
| T-07 | Mid-session tutorial entry | Open/restart Learn with valid baseline, trials, solution, and records, including while processing. Preserve all lab state. Reuse compatible state where intended; require accepted evidence rather than treating a rejected command as completion. |
| T-08 | Contact exercise | Dedicated practice press and accepted physical fingertip actions satisfy the contact exercise. Holding, partial/back/side entry, duplicate cross-hand contact, and a menu appearing around an embedded tip do not dispatch repeated commands. |
| T-09 | Physical preparation | Rotor instructions match nearby grip/upright seating; Home requires the actual accepted homed state. Guard readiness requires closed latch, zero speed, and released handles. Load/Guard instructional buttons in XR cannot substitute for physical gestures. |
| T-10 | Dials and restored reference | Accepted probe motion followed by released Home to 6.00 mm satisfies the exercise. Mere translation, a rejected adjustment, or leaving the probe displaced does not. Active-plane mass/angle instructions match the physical controls. |
| T-11 | Baseline lifecycle | A completed accepted baseline and zero speed satisfy the page; initial press, partial capture, running, analysis, Stop, E-stop, focus loss, and discarded worker output do not invent completion. |
| T-12 | Analyzer and units | Visit Time and Order; verify peak µm, tach phase/observability, 1× = rpm/60, 1,024 Hz/1,024 samples, and DFT leakage explanations. Do not imply variable-speed angular resampling or a full order waterfall is implemented. |
| T-13 | Known trial and solve | Gate fitting against current baseline configuration and independent plane A change. Reject no baseline, no trial, mismatched setup, retained other-plane trial, insufficient sensitivity, and poor matrix conditioning without a fabricated success. |
| T-14 | Apply and fresh verification | Test nonzero baseline masses, total installed solution, removed trials, new accepted verification after Apply, and completed coast. Earlier verification, edited/mismatched masses, configuration invalidation, cancelled runs, and faulted state cannot stand in for the required result. Low measured reduction is explained without calling it a pass. |
| T-15 | Repeatability | Require a completed accepted three-window result and zero speed. Explain mean, sample standard deviation, and SEM separately; no full/expanded uncertainty or calibration accuracy claim. |
| T-16 | Resonance and advanced reference | Complete sweep with recorded speed points; explain quasi-steady response and force varying with speed squared. Two-plane reference requires deliberate mode selection or explicit skip, with no automatic mode/data reset and no claim that the entire advanced exercise has been completed. |
| T-17 | Recovery | Exercise E-stop/release/Home and sensor/tach reset/Home. Rejected release while coasting cannot advance. Fault clearing never restarts a run; invalidated calibration requires fresh measurements. Optional practice remains skippable to preserve work. |
| T-18 | Calibration changes and out-of-order use | Change probe/speed/mode, rehome, acquire a new baseline, or edit corrections while revisiting related pages. Live readiness must reflect applicable invalidation; old green status cannot represent current verification. Skip/Back must not bypass the lab's own interlocks. |
| T-19 | Tracking, focus, and relocation | Lose either controller, remove/return the headset, invoke the system menu, recenter, move the bench, and switch tutorial pages with fingertip/grip held. Cancel contacts/holds, require released grip and a fresh approach, and avoid unintended commands or page advancement. App/XR focus loss stops acquisition; no automatic restart. |
| T-20 | Save and session lifecycle | Successful file creation enables the report objective; permission/path/write failure does not. Inspect JSON configuration, captures, solution, events, and limits. New Session/Exit remain explicit lab actions; merely reading their lesson or restarting Learn preserves data. |
| T-21 | First-time physical usability | Have a learner follow the tutorial using Touch gloves, with optional assist, seated and standing, and both hands. Record ambiguous instructions, missed/accidental presses, excess reach, page-return friction, text readability, and whether an external verbal explanation was needed. |
| T-22 | Sustained physical operation | Run at least five deliberate foreground minutes covering lesson changes, diagrams/text, acquisition, and direct controls. Correlate app/runtime metrics with foreground state and collect comfort observations. Desktop tests or the earlier short 72/72 interval do not satisfy this check. |

Keep all rows pending until their execution evidence is recorded. Automated model/UI tests can establish state and command behavior; the headset rows require observations on the installed tutorial APK. Tutorial completion itself is not acceptance evidence or a competency score.
