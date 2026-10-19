# Operator interaction redesign

Version 0.5 separates the physical station, its analyzer, optional instruction, and the application menu. This document records the input contract and locomotion mathematics. Hardware acceptance of this revision is pending; previous launches, desktop captures, or numerical tests do not establish headset comfort or reliable physical interaction.

## Workstation and menu

The default view is the laboratory. Reach with the controller-driven gloves to carry the rotor, lower/latch the guard, turn the micrometers, and press physical station controls. A dedicated monitor presents the measurements and plots. Its placement and larger text replace the dense collection of floating readouts around the fixture.

The optional floating guide sits beside the work area and explains DO THIS and WHY. It points out the current physical target. It must not cover the analyzer or the button/handle the user needs. Progress remains manual and state-gated: pressing A/Next cannot invent an accepted measurement or operate the apparatus. Turning your head towards the guide and pressing A/X leaves it anchored; it does not reposition another step sideways on every page. Starting, restarting, skipping, and changing guide preferences preserve laboratory data. Deliberately using Home, changing measurement setup, or practicing faults can invalidate calibration as documented by the lab.

**B or Y opens/closes an explicit menu.** Opening it replaces the simulated gloves with Touch-controller representations and aim pointers. Point and use the trigger to choose menu controls. Menu input has its own collision layer; it must not reach through the menu to actuate physical buttons. Pointer selection and grip acquisition require release/rearming after interruption; fingertip contact requires a fresh front approach after the menu closes. Merely opening the menu does not reset the model or start/stop a measurement.

Operate, Balance, Analyze, and Session remain menu categories. The guide is managed in Session rather than occupying a fifth tab. Session includes guide pause/resume, restart, skip lesson, startup preference, walking on/off, report save, recenter, and Exit; New Session is in Operate. Pausing/resuming keeps the current guide page and temporary practice history, while Restart begins it again. B/Y always provides the visible menu transition; holding it does not secretly enable another interaction mode.

## Chosen controller map

| Input | Menu closed / laboratory | Menu open |
| --- | --- | --- |
| B or Y | Open menu; show controller pointers. | Close menu; return to gloves. |
| Right A | Continue the guide only when its current objective is ready. | No hidden physical station action. |
| Left X | Go back one guide page. | No hidden physical station action. |
| Index trigger | Animate the index finger; release it to extend the visible fingertip for physical pressing. | Select a pointed menu control after a fresh release/press. |
| Side grip | Acquire/release an actual nearby rotor, handle, or dial. | Does not acquire hidden mechanical targets. |
| Right stick | Walk horizontally relative to head direction when navigation is permitted. | No walking. |
| Left stick vertical | Adjust station height when no mechanism is held. | No station movement. |
| Physical index-tip press | Actuate a front-facing physical button once per deliberate approach/withdrawal. | Disabled. |

Chart changes belong to the physical analyzer/station controls and Analyze menu; A/X are guide navigation. A loose squeeze with no acquired object must not suppress all fingertip presses. Actual held-object state, tracking, and the contact state machine govern whether physical contact is available. The existing front-approach, actuation stroke, shared latch, and withdrawal rules remain in effect.

Desktop review uses M for the explicit menu, 1–4 for its categories, Space for guide Next, and Backspace for guide Back. Desktop clicks and renders exercise shared command behavior, not stereo or actual Touch pose alignment.

## Commanded walking

The right stick controls slow head-relative translation. This is a deliberate project mapping: Meta describes left-stick movement/right-stick turning as the familiar controller convention, while allowing application-specific mappings. Here the left stick retains workstation height and the right stick provides movement without artificial rotation. Input gates prevent walking from conflicting with menu selection or precision manipulation. [Meta, artificial locomotion input maps](https://developers.meta.com/vr/design/locomotion-input-maps/).

`native/scripts/operator_navigation.gd` contains pure math with two static functions:

```gdscript
movement(stick: Vector2, headforward: Vector3, delta: float) -> Vector3
constrain_motion(position: Vector3, step: Vector3,
    bench_center: Vector3, bench_half_extents: Vector2,
    margin: float = 0.25) -> Vector3
```

Pass `headforward = -camera.global_basis.z`. Positive stick Y moves forward and positive X moves right. `movement()` projects the head direction onto XZ and normalizes it, removing pitch so looking up/down never creates elevation or changes nominal speed. A missing, exactly vertical, or invalid heading produces no motion. The helper does not invent a fallback yaw.

The radial deadzone is **0.18**. Above it, stick strength is remapped continuously from zero to one. The direction is normalized before applying strength, so diagonals and over-range finite input cannot exceed **0.65 m/s**. Delta is capped at **0.05 s**; a stalled frame cannot create a catch-up jump larger than 3.25 cm. There is no velocity retained after the stick is released, no artificial yaw, and no camera bob or vertical motion.

The application must permit walking only with the menu closed, walking enabled, current app/XR input focus, valid current headset/controller tracking, and no acquired mechanical handle. It must rearm navigation only after the stick returns to the deadzone following a menu transition, tracking/focus loss, recenter, or held-object interaction. A stale deflected stick must not restart walking automatically. These runtime gates belong to `main.gd`; the pure helper receives only stick, heading, and time.

The collision position is the **actual tracked head's world X/Z**, not the tracking origin. Main applies `allowed_position - actual_head_position` to `XROrigin3D`, preserving tracked head/hand relationships. Godot distinguishes the tracking origin from the physically displaced user and explains why testing collision at the origin can be wrong. It also describes why forcibly cancelling physical head movement can create a visual/vestibular mismatch. [Godot 4.7, room scale in XR](https://docs.godotengine.org/en/4.7/tutorials/xr/xr_room_scale.html).

## Fixture and room constraints

`constrain_motion()` returns an **absolute allowed head-ground position** and preserves the input Y. It ignores `step.y`. For the current station, main supplies:

```gdscript
bench_center = station.to_global(Vector3(0, 0, -1.4))
bench_half_extents = Vector2(0.85, 0.475)
margin = 0.18
```

The bench's world-aligned XZ rectangle is expanded by the clearance margin. A swept segment test detects crossing even when a large commanded step ends beyond the opposite side. At a face, the blocked component stops while the tangent slides. A simultaneous inward corner collision blocks both components; tangential edge travel and paths merely grazing a corner remain available. This allows the operator to walk around all sides without cutting through the table. The helper's default margin remains 0.25 m for other callers; the application explicitly chooses 0.18 m.

Artificial motion also stays within **X = −3.2 to +3.2 m** and **Z = −2.70 to +2.8 m**. The rear limit includes clearance before the workshop wall at world Z = −2.95 m; the floor continues beyond that wall. A side component can slide along the room boundary. Bench height changes move the station rather than its surrounding room/floor.

An actual physical step, recenter, or fixture relocation can put the tracked head inside the bench rectangle or outside the virtual room bounds. The helper does not eject or snap that head position. While already inside the bench clearance, it permits only commanded recovery toward a nearest exit face. While outside a room boundary, it blocks deeper movement and allows gradual inward recovery. With no commanded movement it returns the same position. This constrains artificial translation; it cannot restrain physical movement.

The collision model is intentionally limited to the table footprint and virtual room limits. It is not a full character body, a model of every prop/monitor, or a replacement for the headset's physical play-area boundary. Nonfinite input or invalid obstacle dimensions fail closed. The caller must supply a finite tracked position and an axis-aligned station; arbitrary rotated benches need an explicit local-space transformation.

## Comfort and acceptance

Slow bounded movement and automatic input gating are design choices, not evidence that smooth locomotion is comfortable for every user. Walking can be turned off in Session, and fixture operation remains possible from the operator position. Meta recommends controlling acceleration/elevation and considering comfort alternatives; no vignette, teleport, snap-turn, or fitted comfort guarantee is claimed by this helper. [Meta, locomotion best practices](https://developers.meta.com/vr/design/locomotion-best-practices/), [comfort and usability](https://developers.meta.com/vr/design/locomotion-comfort-usability/).

The pure `native/tests/test_navigation.gd` suite checks deadzone/analog strength, cardinal/diagonal direction, yaw/pitch, invalid input, delta limits, room boundaries, large swept crossings, face sliding, corner entry/grazing, translated bench geometry, gradual invalid-start recovery, a complete route around the bench, and deterministic adversarial paths. It does not test physical comfort or headset/controller input delivery.

Application and headset acceptance must additionally check:

- B/Y changes only the intended interaction mode; menu pointers cannot activate hidden station buttons, and closing a menu with trigger/grip held requires fresh release.
- A advances only a ready guide page and X goes back, with no old A/X chart shortcut. Guide and analyzer text remain readable without covering the physical target.
- Actual loose grip does not disable fingertip buttons; an acquired tool does. Each hand can press, withdraw, carry, latch, and rotate the intended control.
- Right-stick walking follows head yaw at a consistent speed, stops immediately on neutral/menu/hold/tracking/focus loss, and requires rearming after interruption. Left-stick height cannot raise the room floor or move a held mechanism unexpectedly.
- The head can travel around the expanded bench rectangle without tunneling, sticky corners, forced elevation, or a sudden recovery snap. Recenter remains explicit and restores a usable operator position.
- Seated and standing users can disable walking, read the monitor/guide, reach required controls, and complete a measured balancing exercise. Record the actual APK hash, headset OS/runtime, tracking interruptions, perceived comfort, and sustained foreground performance separately.

Hardware observations remain pending until performed on the installed redesign build. Keep those observations separate from the historical v0.2/v0.3/v0.4 evidence and software test counts.
