# SpinLab XR

An interactive reaction-wheel balancing and commissioning laboratory for **Meta Quest 2**, built by Walter Teitelbaum. Practice fixture setup, vibration measurement, trial-mass calibration, correction, and verification using synthetic training data.

**Version 0.8.0 (Android version code 10) teaches a complete two-plane balancing experiment in 38 interactive steps.** A clear introduction explains why an off-center mass makes a rotor shake. The learner then operates the actual probe micrometer, Mass and Angle dials, interlocked guard, and physical console, reads measured graphs, identifies both correction planes, and verifies the result.

Small prompts appear beside each target while bundled offline speech explains the action and its purpose. Correct work advances immediately, replacing the previous speech; listen before acting to hear the full explanation. Pause, restart, skip, disable startup, mute voice, or replay from Session. Right-stick click also replays. Setup changes or faults that invalidate calibration return the guide to fresh baseline/trial work without erasing historical records or operating equipment automatically.

The default workspace shows controller-driven gloves and four small circular A/B/X/Y markers at the physical Touch button positions. Use nearby grips for the rotor, guard, actual micrometer drum, Mass, and Angle; wrist rotation turns the adjustments. There are no duplicate front-panel probe dial or ± controls. Release a held adjustment before pressing another setup control. Use the physical console for all ordinary operating commands, including HOME, SPEED, CHART, and SAVE REPORT.

B/Y opens the separate **Tools / Session** pointer menu and replaces gloves with controller models and rays. Tools contains fault injection, assembly inspection, and motor sound; Session manages guidance, voice, movement, recentering, and reset. Operating commands are not duplicated in menu tabs. Menu controllers prefer headset-provided models, with pinned Touch v3 assets as fallback; controller-derived Capsense visuals appear when supported. See [controller visuals](docs/CONTROLLER_VISUALS.md).

The lower side analyzer presents thick, distinct A/B traces with numerical axes. Captures select TIME; sweeps select the speed-response plot. CHART also exposes an ORDER spectrum normalized by the captured shaft speed, with 1× and 2× references. An explicit instruction appears before data exist. See [analyzer behavior](docs/ANALYZER.md), [installation](docs/APK_SETUP.md), [workspace design](docs/UX_DESIGN.md), [tutorial](docs/TUTORIAL.md), [voice transcript/provenance](docs/NARRATION.md), [scientific methodology](docs/NATIVE_RESEARCH.md), and [validation](docs/NATIVE_VALIDATION.md).

The numerical lab measures a baseline and independent known trials, solves single- or two-plane complex influence coefficients, then tests the installed correction with a new capture. It synthesizes sampled tach-referenced vibration, fits DC/1×/2× by least squares, computes a 0–100 Hz DFT, explores quasi-steady resonance response, estimates three-window Type A repeatability, and exports JSON evidence. Analysis runs in isolated workers. The Quest app needs no web server or network after installation.

The left stick adjusts bench height. The right stick walks at up to 0.65 m/s relative to head direction; it pauses during menus, active holds, focus/tracking loss, and requires neutral rearming. Keep holding both Touch controllers; optical hand tracking is unnecessary. Source is in `native/`, built with Godot 4.7.2/OpenXR.

```powershell
# Once the local native toolchain is prepared:
.\tools\Build-APK.ps1
.\tools\Install-APK.ps1
# After saving reports in the headset:
.\tools\Pull-Quest-Reports.ps1
```

`tools/Setup-NativeToolchain.ps1` prepares pinned Godot/plugin/Android versions and JDK 17. Keep `.local/spinlab-debug.keystore` for compatible updates; it is excluded from Git. The signed development build target is `artifacts/SpinLabXR-v0.8.0.apk`. [Releases](https://github.com/jewbee2000/spinlab-xr-public/releases) supply packaged builds; the validation record identifies exact exported/installed hashes and test evidence.

The operator described v0.7.0's minimal prompts, speech, and small button markers as substantially better, then reported obscuring dial labels, missing beginner/micrometer instruction, and an empty graph. Version 0.8.0 addresses those findings. Its expanded lesson, readout clearance, chart readability, physical reach, and sustained performance require a fresh headset run; earlier observations do not establish these results.

![Operator workspace in a wide desktop QA perspective from an earlier revision](docs/images/operator-workspace.png)

## Browser version 0.1

![SpinLab desktop preview during a vibration sweep](docs/images/desktop.png)

Mount a rotor, home the probe, close the guard, run a vibration sweep, fit a correction mass, and verify the result. Practice sensor faults, guard trips, and emergency-stop recovery. Save traceable JSON measurements and event history.

## Run the browser preview

Use Node.js 22 or 24 LTS. The app has no npm runtime installation step and no CDN dependencies.

```sh
node tools/serve.mjs
```

Open **http://localhost:8080** on the computer for the desktop preview. For the physical Quest 2, follow [the installation guide](docs/INSTALL_QUEST2.md): enable developer USB debugging, connect a data cable, run `adb reverse tcp:8080 tcp:8080`, open **http://localhost:8080 in Quest Browser**, then select **Enter VR**. Rendering runs on the headset; the computer serves files. Keep the cable and server connected for reloads.

These browser instructions apply to version 0.1. For the standalone version 0.8.0 APK, use the native guide above. Physical acceptance is recorded in the native validation document.

## Browser guided exercise

1. Load rotor, home probe, close guard.
2. Run the 12-second sweep and wait through coast-down to zero speed.
3. Open guard. Set trim mass **0.600 g**, angle **300°**. Close guard.
4. Run again. The modeled initial 18 g·mm imbalance cancels at the fixed 30 mm correction radius. The training pass limit is 2 g·mm.
5. Save report. In VR, leave immersive mode and select **Saved report** to download it. A saved report survives reload; the live station starts fresh after reload.

Phase is an ideally compensated imbalance position, not a raw accelerometer phase. The damped support model and all limits are illustrative. This is not a qualified balancing instrument or a real machine controller.

## Browser controls

- **Quest:** point and trigger; hold a dial with trigger and rotate wrist or use horizontal thumbstick; squeeze over fixture targets; left stick vertically adjusts station height when no dial is held.
- **Desktop:** buttons/sliders; scene drag to orbit; scroll to zoom; Tab/Enter for UI controls.
- **Fault recovery:** wait for zero speed; close guard after a guard trip; release E-stop and reset in separate actions; rehome after sensor fault.

## Engineering documents

- [Floating guide, lesson coverage, and navigation](docs/TUTORIAL.md)
- [Workspace, menu, guide, and movement design](docs/UX_DESIGN.md)
- [Analyzer plots, data, and axes](docs/ANALYZER.md)
- [Project architecture and development roadmap](docs/PROJECT_PLAN.md)
- [Primary-source research and model assumptions](docs/RESEARCH.md)
- [Quest 2 setup, testing, and troubleshooting](docs/INSTALL_QUEST2.md)
- [Verification and hardware acceptance](docs/TEST_PLAN.md)
- [Asset inventory and scale conventions](docs/ASSETS.md)
- [Demo scenarios and recording guide](docs/DEMO_GUIDE.md)
- [Version 0.1 validation record](docs/VALIDATION.md)

## Verify and package

```sh
node --check src/app.js
node --check src/simulation.js
node --check src/lab-scene.js
node --test tests/*.test.mjs
node tools/package.mjs
```

The portable directory is `artifacts/spinlab-xr`. Serve it with `node tools/serve.mjs`. Browser smoke testing additionally uses Playwright; see [validation](docs/VALIDATION.md). GitHub Actions verifies the model/server and creates the portable artifact.

The fixture geometry, signal models, UI, and teaching scenarios are original project assets. The [asset inventory](docs/ASSETS.md) records their scale and provenance. All measurements are synthetic and intended for training.

Original project: all rights reserved by Walter Teitelbaum. Three.js retains its MIT license; see [notices](THIRD_PARTY_NOTICES.md).
