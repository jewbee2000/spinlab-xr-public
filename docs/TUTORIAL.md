# Automatic rotor-balancing work instructions

The floating guide teaches a complete **single-plane balancing procedure at the physical station**. Fifteen short instructions pair the operation in front of the user with relevant science. It starts with seating the rotor, rather than a menu tour. Completing the correct work advances the guide automatically; repeated A-button navigation is unnecessary.

The guide is read-only. It never mounts a rotor, moves a guard, starts a drive, applies a correction, saves a report, or resets laboratory data. All measurements are synthetic. Guide completion can include explicitly skipped instructions and does not certify operator competence or machinery safety.

## Procedure

The guide uses the captions printed on the station console. Carry the rotor and move the orange guard handle with the grip controls; press console caps with an index fingertip. Independent menu commands remain available, but menu navigation is not a tutorial objective. Hands, guard latching, and command acceptance still use the application's normal interlocks.

| Instruction | Operator work | Science and acceptance |
| --- | --- | --- |
| 1. Seat the rotor | Carry the tray rotor upright over the spindle and release. | Mass-radius unbalance produces rotating force `F = Uω²`. An already seated rotor can be confirmed without removing it. |
| 2. HOME | Press **HOME** with a loaded rotor at zero speed; confirm 6.00 mm. | A fresh reference fixes probe geometry before calibration. An earlier Home does not count. |
| 3. Latch the guard | Lower the orange handle fully and release. | CLOSED and released fixture handles are distinct starting prerequisites. An already closed guard can be confirmed. |
| 4. BASELINE | Press **BASELINE**, wait through acquisition, analysis, and coast to zero. | Store measured complex `V0` and baseline masses. Amplitude is micrometres peak; sinusoidal RMS is peak/√2. **STOP** aborts partial acquisition. |
| 5. Open for trial | At zero speed, lift the orange handle. | Keep speed, radius, support response, and sensor geometry consistent with baseline. |
| 6. FIT TRIAL | Select plane A and press **FIT TRIAL** with guard open. | Add the known 0.250 g vector relative to baseline; restore the other plane to baseline so the perturbation is independent. |
| 7. Latch for trial | Lower and release the handle with the trial installed. | A guard state is a prerequisite rather than measurement evidence. |
| 8. MEASURE TRIAL A | Press **MEASURE TRIAL A** and wait through analysis and coast. | `Vt − V0` isolates the trial response. Tach least squares separates DC, 1×, and 2×; displayed DFT bin height can differ because of leakage. |
| 9. SOLVE | Press **SOLVE** and inspect correction and matrix condition. | Identify `α = (Vt − V0)/Ut`; solve `C = −V0/α` from captured complex data. Poor conditioning amplifies errors. |
| 10. Open for correction | Lift the guard at zero speed. | Preserve the calibrated setup while installing the calculated result. |
| 11. APPLY CORRECTION | Press **APPLY CORRECTION** with guard open. | Install total masses relative to baseline; replace the temporary trial rather than adding the correction on top of it. |
| 12. Latch for verification | Close and release the handle with the correction installed. | Single-plane balancing targets sensor A at one speed; sensor B may retain vibration. |
| 13. VERIFY | Press **VERIFY** and inspect new measured reduction after coast. | Require a fresh accepted capture of the calculated installed masses. A low reduction remains a result to diagnose, rather than an invented pass. |
| 14. REPEAT | Press **REPEAT** without changing the corrected setup. | Three windows report mean, sample scatter `s`, and Type A SEM `s/√n`; this is not total measurement uncertainty. |
| 15. SAVE REPORT | Press **SAVE REPORT** and confirm the saved path. | Require a successful save outcome and actual output file. Preserve configuration, captures, solver evidence, events, references, and limits. |

Each instruction and theory block is at most 200 characters. There are no mandatory menu, comfort, input-practice, fault-injection, resonance-sweep, or advanced two-plane detours. Advanced tools remain available for independent exploration; see [NATIVE_RESEARCH.md](NATIVE_RESEARCH.md) for their scientific scope and limits.

## Automatic progression and review

A correct outcome shows a success message for **1.5 seconds** before the next instruction appears. The timer pauses while the menu is open, input focus is lost, head pose is invalid, or the guide is paused or being reviewed. A large frame delay cannot skip the message: an individual timer tick contributes at most 0.1 seconds and advances at most one instruction.

Legitimate fast actions are preserved. For example, HOME pressed while the rotor-seating success message is visible counts toward the following Home instruction. Accepted outcomes are buffered in their original order after the preceding completion checkpoint; each following instruction still has its own readable dwell. Old Home events, existing measurements, old solutions, and old files cannot silently carry the entire procedure forward.

**X** reviews earlier instructions without moving the unfinished work checkpoint. **A** moves forward through review, or advances the current instruction early only when its actual objective is satisfied. The normal workflow needs neither. **B/Y** opens the separate Balance/Analyze/Session menu. The floating guide hides while that menu is open and returns when it closes. Opening a menu alone does not stop a running acquisition: keep the guard closed until zero speed.

Session controls retain **Pause/Resume**, **Restart Floating Guide**, **Skip Current Guide Lesson**, and **Guide at Startup ON/OFF**. Pause retains the current checkpoint. Restart begins at rotor preparation while preserving fixture data; an already mounted rotor is confirmed, then a new Home is required. Explicit Skip advances a chosen instruction without claiming its work was performed. Skipping the final save closes the guide without creating completion history.

Successful final reporting ends the guide, records completion history, and turns startup OFF. Explicitly selecting startup ON later is honored even after completion. Pause or Skip does not change that preference. Current instruction, review position, and transient evidence are session-only; startup preference and completion history use `user://tutorial.cfg`. Missing settings use defaults, and settings are written only on a user preference change or completed procedure.

**New Session** resets the laboratory only after the actual command succeeds, then clears obsolete guide evidence and returns to rotor preparation, including when the operator is reviewing. A rejected reset preserves work. Probe, speed, mode, Home, a new baseline, E-stop, or faults can invalidate calibration; continuing the guide never overrides those instrument rules. No acquisition restarts automatically after recovery.

## Measurement evidence

Freshness uses accepted outcomes and record IDs relative to each instruction's entry checkpoint, not whether an old compatible value happens to be displayed. Baseline, Trial A, Verify, and Repeat require a new accepted capture, completed analysis, and spindle speed below **0.1 rpm**. Starting or aborting an acquisition is insufficient. New-session record numbering can restart without being compared to discarded high IDs from a previous session.

Fit Trial, Solve, Apply, and Save require accepted real command outcomes plus the corresponding resulting state. Raw contact telemetry emitted before validation, rejected commands, textual `"true"` values, and failed output writes do not supply accepted evidence. Trial installation compares complex mass-radius vectors with baseline and rejects a simultaneous other-plane change. Verification and Repeat require the calculated correction to remain installed and the capture configuration to remain current. A measured verification with low reduction is still an honest result to inspect; the guide does not fabricate a pass.

Each measurement uses 1,024 synthetic samples at 1,024 Hz. The displayed waveform retains 256 samples and the DFT covers 0–100 Hz. Sensor phase includes support dynamics and is not directly the heavy-spot angle. Near zero amplitude, phase becomes unobservable. The influence-coefficient solver reads captured phasors; it does not solve directly from the signal generator's hidden unbalance. The repeated windows omit calibration bias, covariance, and a full expanded-uncertainty budget.

## Implementation and readability

`lab_tutorial.gd` is an independent `RefCounted` observer. Its API is `start(snapshot)`, `observe(snapshot, event={})`, `tick(delta, snapshot)`, pure `view(snapshot)`, `next`, `back`, `skip_step`, `skip`, `set_startup`, and `should_autostart`. The application calls `tick` while instructions are visible and input is usable. Views include `automatic`, `ready`, `success_remaining_s`, `review`/`reviewing`, current index/total, text, hint, and startup/history fields. Neither rendering nor observation executes instrument actions.

`tutorial_panel.gd` renders a **0.94 × 0.66 m** read-only card with a **0.86 m** text region. Task and theory share bright, 22.8 mm nominal world em text, with four full 31.92 mm line heights reserved for each block. Visible secondary labels use at least 17.16 mm nominal em. It has no colliders, touch targets, ray targets, or command dispatch. The footer explains automatic progression and optional review, rather than asking for A after every action.

| Geometric measure | Earlier small guide | Current text |
| --- | --- | --- |
| Task nominal em | 14.50 mm | 22.80 mm, 57% larger |
| Theory nominal em | 13.44 mm | 22.80 mm, 70% larger |
| Task angular em at 1.47 m | 0.565° | 0.889° |
| Theory angular em at 1.47 m | 0.524° | 0.889° |
| Entire facing card at 1.47 m | — | 35.46° horizontal × 25.31° vertical |

Nominal em is `font_size × pixel_size`, not measured glyph ink. Angular size uses `2 × atan(span/(2×distance))`. These are geometry checks, not measured headset readability. Root application code owns guide pose, station sightline clearance, and optional controller/keyboard dispatch. The guide's pose is independent of the station menu and remains stable between instructions. See [UX_DESIGN.md](UX_DESIGN.md) for current placement checks.

![Automatic load and verification instructions in desktop layout QA](images/automatic-guide.png)

## Validation and hardware status

Automated tutorial checks cover content, pure rendering, accepted outcomes, stale/aborted/processing/coasting captures, installed correction, rejected Save/Apply, review/reset recovery, ordered actions during dwell, mounted restart, isolated preference persistence, and a complete actual numerical balancing sequence. Panel checks cover full copy on all fifteen instructions, large-text wrapping, nonoverlapping four-line blocks, no input colliders, angular dimensions, and projected bounds. Application integration exercises real command routing, capture, progression, persistence, and file output.

Rendered layout QA and headless numerical/application tests do not establish physical readability, controller alignment, stereo comfort, acquisition frame pacing, or sustained headset performance. Earlier hardware launch/button/spin checks do not validate this redesigned automatic procedure. Physical acceptance remains pending in [NATIVE_VALIDATION.md](NATIVE_VALIDATION.md). Installation and recovery are in [APK_SETUP.md](APK_SETUP.md).
