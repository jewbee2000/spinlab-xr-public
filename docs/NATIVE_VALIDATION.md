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
