# Floating guide: operation and engineering methods

Version 0.5.2 presents a **read-only floating guide**, separate from the four-tab menu and the physical station console. Its 23 short lessons pair one task with relevant theory. All instrument data remain synthetic; guide completion is navigation history, not operator qualification.

Quest 2 feedback on version 0.5 found the guide too small and difficult to read. The readability revision increases the text itself, gives instruction and theory equal bright contrast, and removes the small decorative footer. Physical acceptance of the enlarged guide remains pending; earlier launch/button/spin checks do not establish its placement, readability, or comfort.

## Controls and input modes

On a fresh installation, the guide appears with the menu hidden. It contains no touch buttons or ray targets. **Use menu pointers and index triggers for command buttons. No lesson requires pressing a button with a virtual hand.** Hands are used for carrying the rotor, lifting the guard, and turning dials.

| Control | Behavior |
| --- | --- |
| **A**, right controller | Continue the current guide lesson when its objective is met; finish on the last page. |
| **X**, left controller | Return to the previous guide lesson. |
| **B/Y** | Open or close the menu. Opening shows controller pointers; closing restores virtual hands. |
| Index trigger while menu is open | Select a highlighted menu control using its controller ray. |
| Index fingertip while menu is closed, optional | Physical fixture/console caps are an alternative to menu commands. Approach from the front and withdraw; other fingers can remain curled. |
| Grip near a mechanism | Carry the rotor, move the orange guard handle, or hold a dial while twisting the wrist. |
| Right stick | Walk relative to the headset viewing direction when walking is enabled. |
| Left stick | Adjust workbench height. |

In glove mode, look beside each hand for the physical button map: **left Y Menu / X Guide back**, **right B Menu / A Guide next**. The legends follow the hands and remain facing the viewer; they disappear when the controller-pointer menu is open. Off/wait/first-page cues explain when guide navigation is unavailable.

The menu has **Operate, Balance, Analyze, and Session** tabs; its current tab is highlighted. Guide content is not a fifth tab. The guide hides while the menu is open and returns when it closes. Opening the menu alone does not stop an existing acquisition; keep the guard closed until zero speed.

Movement and height adjustments require focused, tracked input, neutral-stick rearming, a closed menu, and released mechanical grips. Walking can be disabled from Session. Keep physical movement within the clear play area; a virtual movement limit does not replace headset boundary awareness. After tracking, focus, or input-mode changes, release grips/triggers and center the sticks before acting again.

On desktop, **Space** continues, **Backspace** goes back, and **M** opens/closes the same menu. Mouse clicks operate visible world controls. Desktop checks do not reproduce headset tracking or comfort.

## Following or pausing the guide

Read **DO THIS**, perform the action yourself, then press A. Relevant theory appears under **WHY**. The action hint explains an unmet objective. The guide never advances automatically or operates the station. An accepted measurement must finish analysis and coast below 0.1 rpm before a measurement lesson can continue.

Use **B/Y > Session** for:

- **Pause/Resume Floating Guide**: retain the current page and temporary practice evidence during the current app session.
- **Restart Floating Guide**: return to the first lesson without resetting the fixture, calibration, measurements, or reports.
- **Skip Current Guide Lesson**: move past an optional or inconvenient exercise without performing it.
- **Guide at Startup: ON/OFF**: persist whether the guide appears on a later launch.

Completing the last page records completion and turns startup off. Explicitly turning startup on again enables the next-launch guide even after completion. Pausing or skipping does not alter that preference. Current page and temporary practice evidence are not persisted across app launches.

The third lesson practices **B/Y → point at the Operate tab → index trigger → B/Y close**. It requires a real accepted menu selection and a closed menu before A continues. A raw pointer event before validation does not count. A valid optional physical-cap contact can also supply input-practice evidence; it does not imply that the requested laboratory operation succeeded. Preparation and scientific lessons still require the corresponding accepted state or measurement.

Some deliberate exercises discard current calibration: Home, probe/speed/mode changes, a new baseline, E-stop, and injected faults. Use Skip Current Guide Lesson to retain valuable calibration during optional mode-change or recovery practice. **Operate > New Session** clears laboratory data; save work first. Neither navigation nor Pause/Resume performs that reset.

## Lesson coverage

| Page | Task | Engineering purpose |
| --- | --- | --- |
| 1. Welcome | Locate A/X navigation and B/Y menu switching. | Separate read-only instruction, menu input, and fixture operation. |
| 2. Comfortable position | Try right-stick movement or left-stick height adjustment. | Reach, clear space, neutral input, and recovery after focus/tracking interruption. |
| 3. Pointer command | Select Operate with a controller ray/trigger, then close the menu. | Preferred command input, validated selection, and separation from scientific acceptance. |
| 4. Load rotor | Grip the tray rotor and release upright over the spindle. | Exclusive ownership and constrained assembly; contact forces are not simulated. |
| 5. Home probe | Select Operate > Home at zero speed with a loaded rotor and clear faults. | Establish the 6.00 mm reference before calibration. |
| 6. Wrist dials | Adjust the probe, release, and restore Home. | Rotation about the dial axis, active correction plane, and setup-dependent calibration. |
| 7. Guard | Lower the orange handle fully and release to latch. | Closed interlock and released handles are distinct start prerequisites. |
| 8. Baseline | Capture the unchanged rotor and wait through coast. | Store a reference; Stop / Controlled Coast aborts partial acquisition. |
| 9. Amplitude/phase | Read both channels, units, and phase observability. | Peak versus RMS, tach reference, mass-radius unbalance, and speed-squared forcing. |
| 10. Analyzer | Use Analyze > Chart for Time and Order views. | Tach least squares differs from the displayed DFT and its leakage. |
| 11. Known trial | Fit a known plane A trial with an open guard. | Measure sensitivity with one known complex mass-radius change. |
| 12. Trial capture | Capture Trial A at matching speed and setup. | Isolate the trial's response from baseline. |
| 13. Solve | Inspect correction mass, angle, and matrix condition. | `alpha = (Vt - V0)/Ut`, `C = -V0/alpha`; solve from measured complex data. |
| 14. Apply/verify | Install total correction masses and capture fresh verification. | Test the prediction; inspect and retry a low reduction. |
| 15. Repeatability | Acquire the three-window result. | Sample scatter `s` differs from Type A SEM, `s/sqrt(n)`. |
| 16. Sweep | Inspect the speed-response trace. | Separate changing forcing from support amplification; quasi-steady windows are not transient integration. |
| 17. Two-plane reference | Select the advanced mode or skip to retain calibration. | Independent A/B trials identify direct/cross coefficients; conditioning controls sensitivity to error. |
| 18. E-stop recovery | At zero speed, latch, release, and rehome. | Calibration becomes invalid; release never starts the drive. |
| 19. Sensor/tach recovery | Reset and rehome after each fault. | Missing measurement/reference signals require fresh calibration. |
| 20. Reference tools | Explore exploded view, sound, coach, and test speed. | Geometry/audio aid inspection; 900/1,200/1,500 rpm changes invalidate calibration. |
| 21. Report | Save and confirm a JSON output path. | Connect setup, captures, solver results, events, references, and limits. |
| 22. Session | Review guide preferences, New Session, and Exit. | Keep guide navigation distinct from laboratory data lifecycle. |
| 23. Finish | Press A to finish or continue practicing. | Completion includes any skipped pages and makes no competence or performance claim. |

The two-plane page is an advanced reference rather than a second enforced complete calibration. Its state gate recognizes selection of Two Plane at zero speed. Full two-plane practice still requires fresh baseline → independent A/B trials → solve → apply totals → verify both sensors. Skip it to preserve a single-plane calibration.

## Interpreting the science

Each capture contains 1,024 samples at 1,024 Hz. The displayed waveform retains the last 256 samples; the spectrum covers 0–100 Hz. Vibration is **displacement in micrometres peak**. A sinusoid's RMS is peak divided by the square root of two. Tach phase includes support and sensor response, so it is not directly the heavy-spot angle. Near the synthetic noise floor, phase is unavailable.

The solver identifies complex influence coefficients from actual captured simulation data. Fit Known Trial restores the other plane to baseline. Fit Calculated Correction replaces trial configurations with the **total installed masses**, including any baseline masses. Single-plane balancing minimizes sensor A at one speed; sensor B can retain motion. Independent two-plane trials populate both direct and cross responses.

Verification requires a fresh accepted capture of the installed correction, unchanged configuration, healthy referencing, and zero speed. A low measured reduction still supplies a result to inspect; it does not become an invented pass. Probe, speed, mode, or correction changes invalidate the relevant current calibration/verification. New-session record IDs cannot be compared against an Apply checkpoint from a discarded session.

The sweep evaluates quasi-steady synthetic windows around an illustrative 22 Hz support mode. Unbalance forcing changes with speed squared, so its unnormalized peak width is not a direct damping estimate. Repeatability reports three independent-noise windows, sample scatter, and Type A SEM; it omits a full calibration, covariance, and expanded-uncertainty budget. Equations and primary references are in [NATIVE_RESEARCH.md](NATIVE_RESEARCH.md).

## Implementation and validation

`lab_tutorial.gd` is a separate `RefCounted` state controller. It reads snapshots and accepted action outcomes without holding or operating the laboratory model. Its public API retains `start`, `observe`, `view`, `next`, `back`, `skip_step`, `skip`, `set_startup`, and `should_autostart`. Practical gates inspect actual state, accepted captures, and confirmed saves. Input practice accepts validated menu selection or optional physical contact separately from operation acceptance, and requires menu closure.

`tutorial_panel.gd` renders a floating **0.94 × 0.66 m** guide with a 0.86 m text region. Its unchanged instruction and theory are each at most 200 characters, with space reserved for four large lines per block. It has no colliders, touch controls, ray targets, or input dispatch. Root application code owns guide placement and controller/keyboard navigation. Showing or hiding the panel cannot operate the laboratory.

## Readability dimensions and geometric checks

The revision increases world-space typography rather than adding empty card area. Instruction and theory both use a nominal 22.8 mm em; their font line height is 31.92 mm. Every visible secondary label uses at least a 17.16 mm nominal em. The guide retains the same 23 lessons and controller navigation.

| Measure | Previous guide | Enlarged guide |
| --- | --- | --- |
| Instruction nominal em | 14.50 mm | 22.80 mm, **57% larger** |
| Theory nominal em | 13.44 mm | 22.80 mm, **70% larger** |
| Instruction angular em at 1.47 m | 0.565° | 0.889° |
| Theory angular em at 1.47 m | 0.524° | 0.889° |
| Whole card, facing viewer at 1.47 m | — | 35.46° horizontal × 25.31° vertical |

Nominal em is `font_size × pixel_size`; it is not a measured glyph-ink height. Font line height includes ascent/descent spacing. Angular extents use `2 × atan(span / (2 × distance))`. These geometric specifications describe size, not headset acuity or a measured readability result. Moving the guide closer increases angular text size further; at the current approximately 1.16 m range, nominal instruction/theory em is about 1.125°.

Placement must account for the entire card, not just its center. As an explicit geometry example, a viewer-facing card at 1.15 m, 20° left azimuth, and 8° upward elevation has corner bounds of approximately **−43.27° to +3.27° horizontally** and **−7.45° to +22.26° vertically**. This is a projection check, not a Quest field-of-view guarantee. The current app uses a right-side placement search to clear opaque hardware; its tested default positions are 48–60° right at about 1.16 m. See [UX_DESIGN.md](UX_DESIGN.md) for the actual pose/sightline checks. The application still needs physical verification that the guide stays readable, avoids the monitor sightline, and requires a comfortable head turn.

`ConfigFile` stores only startup preference and completion history in `user://tutorial.cfg`. An empty path is memory-only for tests. Missing preferences use defaults; malformed/unwritable settings report an error without preventing laboratory use. Settings are written on explicit preference changes or completion, not merely on launch.

Automated checks cover every lesson's complete text, large-font wrapping, four-line reserves, nonoverlapping blocks, minimum visible em, world/angular size calculations, and projected corner bounds. Additional suites cover state gates, contact routing, the measured workflow, pause/resume, menu isolation, controller/keyboard navigation, reports, rejected reset preservation, and preference reload. A rendered guide comparison provides visual layout QA. These checks do not establish physical controller alignment, comfort, readability, or sustained headset frame pacing. Follow the pending acceptance matrix in [NATIVE_VALIDATION.md](NATIVE_VALIDATION.md), installation in [APK_SETUP.md](APK_SETUP.md), and interaction design in [DIRECT_INTERACTION_DESIGN.md](DIRECT_INTERACTION_DESIGN.md).
