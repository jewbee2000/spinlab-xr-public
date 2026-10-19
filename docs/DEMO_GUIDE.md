# SpinLab XR — demonstration and recording guide

This guide provides a repeatable demonstration of the native version 0.5 reaction-wheel balancing lab: its physical console, rear analyzer, four-tab menu, floating guide, measured trial-mass correction, and diagnosis. All instrument data are synthetic. Use [APK_SETUP.md](APK_SETUP.md) for installation and controls, [UX_DESIGN.md](UX_DESIGN.md) for workspace/movement, [TUTORIAL.md](TUTORIAL.md) for lessons, [NATIVE_RESEARCH.md](NATIVE_RESEARCH.md) for analytical assumptions, and [NATIVE_VALIDATION.md](NATIVE_VALIDATION.md) for the current test record.

Earlier headset observations establish the visible lab, controller interactions, and spinning rotor. Feedback informed the new workspace and input changes. Version 0.5 requires its own hardware acceptance for console reach, analyzer sightlines, fingertip contact, menu/controller mode, guide readability, movement, and sustained performance. Identify each capture by its actual installed build.

## Prepare the session

1. Record the application version and APK hash, headset OS/runtime, test date, and scenario. Open the menu with B/Y and choose **Operate → New Session**, then close it.
2. Choose a clear seated or standing position with both Touch controllers tracked. Adjust bench height with the left stick. Right stick walks within the bounded workspace; release to stop. Keep controller rings clear of each other and nearby objects.
3. Confirm the gloves follow the controllers. Release the index trigger to extend the finger for pressing. Touch a physical cap from the front, then withdraw. B/Y opens the pointing menu, replacing gloves with controller models/rays; use trigger selection and close it before manipulating the fixture.
4. Keep units and the active correction plane visible. Use a wide fixture view for orientation and closer instrument views for numerical results.
5. Identify the capture source: **Quest 2 headset recording**, **desktop application capture**, or **standalone geometry preview**. A desktop capture is not evidence of stereo rendering or physical input.

The native app runs without a web server after installation. Browser version 0.1 has different controls and a different known-correction exercise; use [INSTALL_QUEST2.md](INSTALL_QUEST2.md) when demonstrating that version.

## Floating guide demonstration

1. With startup guidance enabled, show the separate card beside the fixture. Capture DO THIS and WHY and explain that A changes the lesson rather than operating the lab.
2. Demonstrate A to continue and X to go back. A practical page remains on its current lesson until the required accepted state exists; capture its NEXT hint.
3. Perform the actual physical Home-cap press, rotor seating, guard motion, and baseline yourself. Keep the menu closed during nearby interaction. Press A deliberately after each objective is met.
4. Follow baseline → known trial → measured response → solve → installed correction → fresh verification. Compare the WHY explanations with the actual analyzer data and report. A page advancing does not mean the rotor passed verification.
5. Open Session to pause the guide and resume at the same page. Show skip lesson and startup OFF, then relaunch. Restart the guide during existing work and show that the lab records remain intact. Close the menu before using A/X or physical grips.
6. Capture tutorial completion separately from lab verification. Optional two-plane and fault practice may be skipped; completion is navigation history, not evidence that every exercise was performed or competence was assessed.

Tutorial navigation does not reset the laboratory. Home, mode/speed/probe changes, a new baseline, and fault practice are explicit lab actions that can discard calibration. Keep a saved report before deliberately demonstrating those changes. The manual scenarios below can run with the guide paused from Session.

## Single-plane demonstration

1. **Prepare:** grip the tray rotor, carry it upright and centered over the spindle, and release to seat it. Press **Home Vibration Probe**. Grip the orange handle, lower the guard fully, and release to latch it.
2. **Baseline:** select single-plane mode and record a baseline at the selected test speed. Keep the setup unchanged and wait for acquisition and coast-down. Capture sensor A amplitude/phase and the waveform or DFT.
3. **Known trial:** lift the guard. Use **Fit Trial** on the console with plane A active. Lower/latch the guard, then **Measure Trial A**. Wait for zero speed. The helper fits a known +0.250 g trial.
4. **Identify:** press **Solve Influence Matrix**. Capture the calculated total correction and condition information. The calculation uses saved baseline and trial responses rather than a displayed scenario answer.
5. **Correct:** open the guard and press **Fit Calculated Correction**. This replaces the trial configuration with the required total installed correction. Close/latch the guard.
6. **Verify:** acquire a fresh verification run at the matching setup. Capture baseline/corrected peak amplitudes, percentage reduction, and result. Near-zero phase can be unobservable; do not describe a noisy residual angle as a precise heavy-spot location.
7. **Repeat:** run three-window repeatability. Show the sample standard deviation and Type A standard error; these describe repeatability rather than total uncertainty.
8. **Save:** export the JSON report and retrieve it using `tools/Pull-Quest-Reports.ps1`. Check its configuration, baseline, trial, solution, verification, and event records.

For a shorter recording, retain these steps as separate clips. Label time cuts; editing does not remove the required settled measurements or coast-down.

## Two-plane demonstration

Start a fresh session in two-plane mode and prepare the fixture as above.

1. Acquire a baseline with both sensor channels visible.
2. Fit and measure the plane A trial.
3. Open the guard, select plane B, and fit its known trial. The helper restores the other plane to its baseline configuration so the influence-matrix columns are independent. Close/latch the guard and measure trial B.
4. Solve, show the condition, open the guard, apply the calculated total correction, then close/latch and acquire fresh verification.
5. Compare both channels and save the report. Single-plane improvement on sensor A alone is not evidence of two-plane correction.

Keep test speed, probe position, and acquisition conditions consistent across baseline and trials. Changing the measurement setup requires a new calibration sequence.

## Additional scenarios

| Scenario | Demonstrate | Evidence to retain |
| --- | --- | --- |
| Guided learning | Read DO THIS/WHY, perform the actual task, observe the readiness hint, use A/X, pause/resume, or skip. | Current page, accepted objective, unchanged lab data during navigation, and startup/restart behavior. |
| Menu mode | B/Y opens four tabs; controller models/rays replace gloves. Point/trigger, change tabs, and close. | Selected tab, clear button labels, physical interaction suspended, fresh approach on return. |
| Movement | Left stick changes height; right stick walks within bounds. Open the menu or hold a mechanism, then return to neutral before retrying. | No movement while blocked, no automatic restart, and separate comfort observations. |
| Readiness/interlock | Try to start before mounting, homing, or guarding; read the readiness message. | Rejected command and unchanged drive state. |
| Guarded operation | Start a run, attempt a prohibited adjustment, and wait for coast-down before access. | Rejection message, speed, and interlock indication. |
| Emergency stop | Latch E-stop during acquisition, wait for zero speed, release deliberately, and rehome before restarting. | Cancelled acquisition, recovery sequence, and event history. |
| Sensor/tach fault | Inject a fault, observe drive removal, clear it at zero speed, and reacquire the required reference/calibration. | Fault text, recovery steps, and new records. |
| Resonance sweep | Sweep speed and show amplification near the illustrative support mode. | Speed/displacement trace with units and recorded peak. |
| Configuration change | After verification, change a correction setting with the guard open. | Cleared current verification and preserved historical record. |
| Tracking/focus recovery | Interrupt a hold or session, return, release grip, and deliberately reacquire. | Cancelled hold, fresh approach, and no unintended command. |
| Assembly inspection | Use the exploded view while stopped; identify rotor, correction planes, probe, and tach pickup. | Labeled geometry, distinct from a physical dynamics result. |

## Recording sequence

| Shot | Content | Explanation |
| --- | --- | --- |
| Station overview | Workbench, rotor tray, guard, probe, physical console, and rear analyzer with menu closed. | A guarded workflow with a defined measurement task. |
| Guide orientation | Separate DO THIS/WHY card, current task, and manual A/X navigation. | Guidance refers to real controls and accepted outcomes without autoplaying the lab. |
| Menu transition | B/Y, controller representations/rays, selected tab, trigger selection, and return to gloves. | Pointing menus and nearby physical operation use distinct input modes. |
| Direct controls | Fingertip press, nearby grip, rotor seating, and dial movement. | Controller-driven gloves and constrained interaction. |
| Baseline | Stable acquisition and trace. | Tach-referenced peak displacement and phase. |
| Trial and solve | Known trial, new measurement, and calculated correction. | Measured influence coefficients connect a known change to correction. |
| Fresh verification | Corrected run and before/after result. | A new measurement tests the installed correction. |
| Diagnostic view | DFT, sweep, or repeatability. | Different analyses answer different questions. |
| Recovery | One fault and orderly reset. | Recovery is part of operation. |
| Report | Matching JSON configuration and records. | Recorded settings support inspection and reproduction. |

Capture actual behavior and retain one uninterrupted reference run before editing clips. Useful stills include the assembled fixture, trial/solution display, corrected verification, annotated inspection view, and fault state. Keep units, speed, active plane, and status visible when discussing measurements.

For desktop workspace/menu/guide renders, run `native/tools/preview_workspace.gd` with the configured Godot executable, `--xr-mode off`, and a rendering display. It uses memory-only preferences and illustrative controller poses; the wide view is a composition for QA, not a measured headset field of view. For an isolated glove comparison use `native/tools/preview_hands.gd`; its four poses do not establish Touch-controller calibration.

## Scientific explanations and boundaries

- Displacement is in **peak micrometres**, not RMS or velocity. Phase is relative to the synthetic tachometer and includes the transfer response; it is not directly the mechanical heavy-spot angle.
- Native acquisition contains 1,024 samples at 1,024 Hz. Least squares separates DC, 1×, and 2×; the DFT covers 0–100 Hz.
- The sweep uses separate quasi-steady windows of a synthetic second-order response, not a measured structural test or transient flexible-rotor simulation.
- The numerical correction radius is 30 mm. Parts, correction markers, probe travel, and visible rotor speed are scaled for legibility; geometry does not determine numerical mass or dynamics.
- Repeatability uses three simulated noise windows. Type A standard error is not an expanded uncertainty or complete calibration budget.
- A successful synthetic exercise does not establish a balance grade, calibrated instrument, flight qualification, training-effectiveness result, or real-machine operating procedure.

## Capture and feedback record

Keep the following with each scenario:

```text
Application version / commit / APK SHA256:
Capture source and date:
Headset OS / runtime, if applicable:
Mode / test speed / probe setting:
Baseline and trial record IDs:
Calculated corrections and fresh verification result:
Report filename:
Hand alignment / contact / reach observations:
Text readability / interruption recovery:
Guide page / A-X navigation / readiness hint / pause-resume / skip-restart:
Physical console / menu rays and selected tab / movement and neutral rearm:
Performance interval and collection method, if measured:
Reproduction steps for unexpected behavior:
```

Use the original capture and report to verify descriptions and annotations. Record unresolved behavior explicitly. A brief clean launch or desktop screenshot does not establish five-minute comfort or headset performance; those observations require a separate timed physical acceptance run.
