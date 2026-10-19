# Version 0.1 validation record

Recorded 18 October 2026. This record describes observed software checks. It does not certify behavior on a Quest 2.

## Passed locally

- Node.js 24.19.0 syntax checks on the application, scene builder, and simulation modules.
- **15 automated Node tests**: rotor/guard/probe start interlocks; guard-open drive removal and recovery; independent emergency-stop release/reset; sensor-fault rehoming; stationary/open-guard correction changes; resonance and deterministic sampling; cancellation and in-phase doubling; stale-result invalidation; aborted sweep rejection; seed reproducibility; numeric validation; new-session reset; restricted static serving; XR permissions and JavaScript MIME types.
- **Complete browser smoke workflow**, twice in headless Microsoft Edge via Playwright. All station mutations use visible page controls and input events. The test verifies baseline acquisition (49 samples), correction at 0.600 g / 300°, a completed passing verification, report units and history, fault/stop recovery, saved-report download and preservation after reload/New session, controls/help, and responsive layouts at 1365, 900, and 390 px widths. No page, console, or failed-network errors were observed.
- Desktop screenshot inspected at 1600 × 1000. A separate flat view of the world-space panels (`?layout=vr`) is an authoring layout inspection, not an XR emulation or a headset result.
- Original scene geometry is about 8,242 triangles before dynamic visibility. Observed idle desktop rendering: 72 draw calls / 6,078 triangles. A flat VR-panel layout rendered 131 draw calls / 6,974 triangles. Actual stereo cost and Quest GPU frame time are unmeasured.
- Runtime scripts, textures, fonts, and geometry load locally. Three.js r180 is vendored with its license. No CDN request, analytics, or app service is needed.
- ADB was downloaded from Google's official Platform-Tools endpoint into the ignored `.tools/platform-tools` folder. `adb devices` returned no attached devices. No physical install or immersive session was attempted.

## Reproduce

```sh
node --check src/app.js
node --check src/simulation.js
node --check src/lab-scene.js
node --test tests/*.test.mjs
node tools/serve.mjs
```

For the browser smoke test, keep the server running in another terminal. Install the optional test runner with `npm install --no-save playwright`, then run:

```sh
node tests/browser-smoke.mjs
```

It defaults to an installed Microsoft Edge browser. Set `PLAYWRIGHT_CHANNEL=chrome` for installed Chrome, or `PLAYWRIGHT_EXECUTABLE_PATH` for a browser executable. Use `PLAYWRIGHT_MODULE` to point to an existing Playwright module instead of installing one. Tests use a software renderer for portability; those FPS results are not a performance benchmark. No XR device is emulated.

To use an existing Playwright installation, replace this example with its module path:

```powershell
$env:PLAYWRIGHT_MODULE = 'C:/Tools/node_modules/playwright/index.mjs'
node tests/browser-smoke.mjs
```

## Still pending on the physical Quest 2

Enter/exit immersive WebXR; left/right controller selection and squeeze; wrist and thumbstick tuning; optional haptic pulses; seated height adjustment; stereo text legibility; guard and rotor depth cues; five-minute frame-time measurement with a 72 Hz target; report retrieval after leaving VR; and comfort. Follow [TEST_PLAN.md](TEST_PLAN.md) and record results in the project's Quest feedback issue.

## Known scope limits

This is a browser-delivered prototype, with no APK or service-worker offline installation. It uses commands and constrained dials rather than free physical pickup. The correction answer is taught explicitly; an influence-coefficient trial-mass solver is planned. The analytical radius and visually enlarged rotor/trim circle are distinct; see [ASSETS.md](ASSETS.md). The ideal model omits two-plane/couple imbalance, realistic sensor phase uncertainty, nonlinear bearings, structural modes, and flight qualification criteria. Python instrument backends, real hardware interfaces, and remote hosting are future work.
