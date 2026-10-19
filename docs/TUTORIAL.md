# Learn: guided operation and engineering methods

Version 0.4 adds a **LEARN** tab with a self-paced, 23-page tutorial. Each page separates **WHAT** to do from **WHY** the action matters. It uses the real laboratory controls and measured simulation results. All instrument data remain synthetic; completing the tour is not a qualification or a demonstration of real-machine safety.

Physical Quest 2 acceptance of the tutorial is pending. The earlier v0.2 launch/button/spin smoke test does not establish this revision's text readability, hand alignment, navigation, reach, or learning effectiveness.

## Using Learn

1. Open **LEARN**, the fifth tab on the control panel. On a fresh installation, the startup preference opens the tutorial there. It does not start a measurement or operate a mechanism.
2. Read the current WHAT and WHY sections. **Practice** opens the relevant Operate, Balance, Analyze, or Session menu. The compact coach display keeps the current instruction visible while the real controls are in use.
3. Complete the action yourself. For a practical objective, **Next** remains disabled until the tutorial observes its required state or accepted outcome. Read-only reference pages can continue immediately. Progress never advances automatically.
4. Use **OPEN LESSON** to return from a practice menu while its objective is unmet, or **LESSON / NEXT** to continue once ready. **Back**, **Skip lesson**, and **Skip for now** let you review or leave without operating the lab. Back is unavailable on the first page because there is no previous page.
5. Use **Restart** in Learn for a refresher. Restart returns to the first tutorial page; it preserves the current fixture, measurements, and reports.

**STARTUP: ON / OFF** is a persistent preference. Turning it off keeps future launches in the ordinary lab, and Learn remains available manually. **Skip for now** closes the current tour without changing that preference. Completing the final page records completion and turns startup off. Turning startup on again explicitly reopens the tutorial on a later launch, even after completion. The current page and temporary practice flags are not a saved lab session; reopening the app starts a fresh laboratory as before.

With Touch controllers, extend the virtual index finger and approach buttons from their front. Withdraw before another press. Grip the nearby rotor, orange guard handle, or dial when its hint appears. Short B/Y cycles all five tabs; holding B/Y toggles menu reach assist. Assist can select menu controls with an aim ray and trigger; mechanical handles still need nearby grips. Optical hand tracking is not required. On desktop, use the world controls and the dedicated touch-practice button.

While a lesson is active, its compact task coach remains visible. The ordinary Guided Coach setting applies to the general lab guidance; use Skip for now to leave lesson guidance.

The tutorial is optional while work is in progress. Opening it, changing pages, choosing Practice, skipping, or changing its startup preference does not reset the model, select a balancing mode, inject a fault, fit a mass, or start a run. Some **actions the learner deliberately performs** do discard calibration: Home, a probe/speed/mode change, a new baseline, E-stop, or an injected fault. New Session clears lab data. Save the work you need before practicing those actions.

## Lesson coverage

| Page | WHAT the learner does | WHY / engineering concept |
| --- | --- | --- |
| 1. Welcome | Locate the tutorial, Practice, and navigation controls. | Separate instructions from machine operation and synthetic evidence from physical validation. |
| 2. Comfortable bench | Try height, distance, recenter, or menu reach assist in Session. | Reach and recovery after focus/tracking interruption; no required artificial locomotion. |
| 3. Fingertip press | Use the safe touch-practice control, then withdraw. | Front approach, stroke, debounce, and rearming prevent repeated or accidental presses. |
| 4. Load rotor | Grip the tray rotor, carry it upright, and release above the spindle. | Exclusive ownership and constrained assembly; the model does not simulate contact forces. |
| 5. Home probe | Home at zero speed with a loaded rotor and clear faults. | Establish the 6.00 mm reference before influence-coefficient calibration. |
| 6. Wrist dials | Move the probe dial, release it, and restore Home. | Rotation about the dial shaft, active correction plane, and setup-dependent calibration. |
| 7. Guard | Lower the orange handle fully, release, and confirm the latch. | The closed interlock and released handles are distinct run prerequisites. |
| 8. Baseline | Capture the unchanged rotor response and wait through analysis/coast. | Preserve a reference configuration; an interrupted run is not an accepted measurement. |
| 9. Amplitude and phase | Read both channels, units, and phase observability. | Peak versus RMS, tach reference, mass-radius unbalance, speed-squared forcing, and support phase. |
| 10. Analyzer | Open Time and Order chart views. | Tach-referenced least squares separates DC/1×/2×; the displayed DFT has leakage and is not the solver's phasor. |
| 11. Known trial | Open the guard and fit a plane A trial relative to baseline. | A known complex mass-radius change measures sensitivity; the other plane returns to baseline. |
| 12. Trial capture | Close the guard and acquire the plane A response. | Use matching speed/setup and an independent trial to isolate its effect. |
| 13. Solve | Solve and inspect correction and matrix condition. | Single-plane `alpha = (Vt - V0)/Ut`, `C = -V0/alpha`; use measured complex data. |
| 14. Apply and verify | Fit total calculated masses and acquire fresh verification. | Replace trial masses, then test the prediction with a new measurement. Inspect and retry if reduction is poor. |
| 15. Repeatability | Acquire the three-window repeatability result. | Sample scatter `s` differs from `s/sqrt(n)`; Type A SEM is not total or expanded uncertainty. |
| 16. Resonance sweep | Acquire and inspect the speed-response trace. | Separate speed-dependent forcing from support amplification; quasi-steady windows are not transient integration or a damping fit. |
| 17. Two-plane reference | Optionally select two-plane mode and review its full sequence. | Two sensors respond to both planes; independent A/B trials populate direct and cross coefficients. Poor conditioning amplifies error. |
| 18. E-stop recovery | At zero speed, latch E-stop, release deliberately, and rehome. | Calibration becomes invalid and release never restarts the drive. |
| 19. Sensor/tach recovery | Practice each fault, reset, and rehome. | Missing measurement/reference signals invalidate calibration; future balancing requires fresh captures. |
| 20. Tools and test speed | Optionally explore the exploded view, sonification, ordinary coach, and 900/1,200/1,500 rpm speed control. | Geometry/audio aid inspection; changing test speed invalidates calibration, and baseline/trials must use the same speed. |
| 21. Report | Save and confirm a JSON output path. | Connect configuration, accepted captures, solver results, events, references, and limitations. |
| 22. Session controls | Review New Session and Exit without needing to activate them. | Explicit data lifecycle; lesson navigation is separate from laboratory reset. |
| 23. Finish | Finish manually, or keep practicing and return later. | Tour completion includes any skipped pages and does not certify competence or headset performance. |

The two-plane page is an optional advanced reference, not a second enforced complete balancing exercise. Selecting its mode is its practice gate. The learner can then repeat the documented baseline → independent A/B trials → solve → apply → verify workflow. It is safe to skip that page to retain current single-plane calibration. The fault and E-stop practices are also skippable.

## Reading results correctly

Native capture uses 1,024 samples at 1,024 Hz; the waveform displays the last 256 samples and the spectrum covers 0–100 Hz. Vibration is **displacement in micrometres peak**. For a sinusoid, RMS is peak divided by the square root of two. Measured tach phase includes the support and sensor response; it is not directly the physical heavy-spot angle. Near the simulated noise floor, phase is unavailable.

The solver identifies complex influence coefficients from captured baseline and trial data. The trial helper restores both planes to their baseline mass configuration before adding the selected trial. Applying a solution installs the **total** masses, including any baseline masses, and removes the temporary trial configuration. One-plane balancing minimizes sensor A at one speed; it does not guarantee zero motion on B. Two-plane balancing requires independent trials and verification of both channels. The model rejects singular/poorly conditioned matrices and inadequate trial sensitivity.

The verification lesson requires a fresh accepted verification of the installed correction, not merely pressing Verify or seeing an earlier green result. A low reduction still provides a measurement to inspect; tutorial progress is not awarded based on an invented pass. The ordinary lab's verification status remains authoritative. Probe/speed/mode or correction changes invalidate the corresponding current calibration/verification.

The sweep is a sequence of quasi-steady synthetic windows around an illustrative 22 Hz support mode. Its force varies with speed squared, so the unnormalized response peak cannot supply a simple half-power damping estimate. Repeatability uses three independent synthetic-noise windows; it omits a full calibration, covariance, and expanded-uncertainty budget. Detailed equations, assumptions, and primary references are in [NATIVE_RESEARCH.md](NATIVE_RESEARCH.md).

## Implementation and review contract

`native/scripts/lab_tutorial.gd` is a separate `RefCounted` controller. It reads a lab snapshot and accepted action outcomes; it has no laboratory-model reference and never operates the station. Main supplies current configuration, readiness, capture/solver records, chart state, handle ownership, and save outcomes. Existing compatible data can satisfy state-based objectives; entering Learn does not force a reset or new copy of every experiment. Temporary flags track interactions such as comfort controls, touch practice, chart visits, recovery practice, and successful save.

The public interface is:

```gdscript
LabTutorial.new(settings_path = "user://tutorial.cfg")
start(snapshot)
observe(snapshot, event = {})
view(snapshot)
next(snapshot)      # { ok, message, finished }
back()
skip_step()
skip()
set_startup(enabled)
should_autostart()
```

`view()` supplies the page `id`, `chapter`, `title`, `body`/`what`, `theory`/`why`, `practice_tab`, `target`, `index`, `total`, progress, `ready`, and a short unmet-objective `hint`. The UI shows WHAT and WHY from this view, disables only gated Next, and sends navigation back through the tutorial controller. `next()` checks readiness again; a disabled visual button is not the only protection. Practical steps inspect accepted outcomes and current state, including completion of capture/analysis and zero-speed conditions where required. Rejected commands do not satisfy practice events.

`ConfigFile` stores only the startup preference and completion history in `user://tutorial.cfg`. An empty settings path provides a memory-only instance for deterministic tests. Missing settings use defaults; malformed/unwritable settings return an error that can be shown without blocking the laboratory. Explicit `load_settings()` and `save_settings()` methods support this boundary. Tutorial completion is navigation history, not a log claiming that every skipped exercise was performed.

Changing tutorial pages or returning from a practice menu rebuilds controls through the ordinary contact-reset path. A control appearing under an already embedded fingertip must not actuate. Tracking/focus recovery requires released grips and a fresh approach; it must not synthesize a successful action or advance the page. App/XR focus loss stops an active acquisition through the existing lab recovery path. Individual controller tracking loss releases its interaction; it does not by itself claim a completed measurement or a completed exercise.

The pending acceptance matrix is in [NATIVE_VALIDATION.md](NATIVE_VALIDATION.md). Installation and direct-hand controls remain documented in [APK_SETUP.md](APK_SETUP.md) and [DIRECT_INTERACTION_DESIGN.md](DIRECT_INTERACTION_DESIGN.md).
