# Visible hands and direct fixture interaction

Version 0.3 design and implementation, checked 18 October 2026. The native Quest 2 app adds visible simulated gloves and interactions driven by physically reaching toward the fixture. The default input remains the two Touch controllers; no optical hand-tracking setting is required. The hands' positions follow tracked controller poses; finger articulation is inferred from controller inputs and interaction state. Physical acceptance of this revision is pending.

## Chosen input approach

Controller-driven hands provide pose input, deliberate squeeze actions, and haptic feedback on the already connected Quest 2. Godot documents this approach separately from optical skeleton tracking. Keeping the existing action map also avoids introducing a new device setting or hand-tracking permission before the direct controls can be tested. Optional reach assist supplies an aim ray for menu buttons; the rotor, guard, and dials still require nearby physical grips. [Godot, *OpenXR hand tracking*, introduction](https://docs.godotengine.org/en/4.7/tutorials/xr/openxr_hand_tracking.html).

The mapping is **reach with the virtual hand, push buttons with the visible index tip, and squeeze near a handle when its `GRIP` hint appears**. The controller supplies the tracked physical movement. Trigger and grip values animate finger curl; releasing the index trigger extends the modeled index. The visible contact point and mathematical contact point share the hand's fingertip marker. In XR, the Load Rotor and Open/Close Guard menu controls give gesture instructions; their actions require the rotor and handle respectively.

Short B/Y presses cycle menus; holding B/Y for 0.85 seconds toggles reach assist. A/X cycles analyzer charts. The assist ray uses trigger clicks on menu buttons only. Left-stick height adjustment is available when no mechanism is held. The Session menu provides height, bench near/far distance, and recenter controls. The scientific model and acquisition methods are unchanged from v0.2.

## Godot/OpenXR pose and input contract

| Purpose | Native binding |
| --- | --- |
| Left/right tracked controller | `XRController3D.tracker = "left_hand"` / `"right_hand"` |
| Virtual palm and nearby hold | Separate controller node with `pose = "grip"` |
| Distant pointing | Separate controller node with `pose = "aim"` |
| Finger/hand animation | `get_float("trigger")`, `get_float("grip")`, optional touch/button actions |
| Deliberate hold | Hysteresis on `grip`: acquire at 0.65, release below 0.20, with a fresh released state required after tracking recovery |
| Feedback | `trigger_haptic_pulse("haptic", 0.0, amplitude, duration_seconds, 0.0)` |

Set `tracker` before `pose`: the tracker setter resets the pose name to `default`. These nodes are children of `XROrigin3D`. The OpenXR action map continues to bind the underlying `/user/hand/left` and `/user/hand/right` paths; the controller nodes use Godot's registered names. [Godot 4.7.2 controller registration](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/openxr/openxr_interface.cpp#L525), [node setter/binding implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/3d/xr/xr_nodes.cpp), [controller input API](https://docs.godotengine.org/en/4.7/classes/class_xrcontroller3d.html).

Do not assume the grip pose's negative Z axis is the extended index finger. OpenXR defines grip orientation around the grasp, while aim has negative Z pointing along the runtime's targeting direction. The procedural glove uses a shared local transform for its mesh and fingertip. Its canonical positive Y is the dorsum; the handed transforms map the palm outward to positive X on the left and negative X on the right, with extended fingers approximately along grip negative Y. Orientation/position offsets remain available in the hand implementation for calibration. Confirm the resulting placement on physical Touch controllers; the coordinate derivation alone is not a hardware-fit result. [Khronos, standard pose identifiers](https://registry.khronos.org/OpenXR/specs/1.1-khr/html/xrspec.html#semantic-path-standard-pose-identifiers).

## Direct buttons

A direct press is a small state machine, not an unconditional sphere overlap:

1. **Withdrawn:** the fingertip is outside the button's front rearm distance. It can become armed.
2. **Approaching:** the fingertip enters the face footprint from the front. Highlight the target and show visible depression as it advances.
3. **Pressed:** the fingertip crosses the actuation depth. Dispatch the existing command handler once and give a short click/haptic response.
4. **Latched:** additional movement or holding the fingertip inside must not issue repeats. Require withdrawal beyond the larger rearm distance before another actuation.

`DirectInteraction.PushContact` uses each button's resting front-face local coordinates, so sloped panels follow the same rule. Swept segment/plane crossing preserves fast front approaches and rejects back/side entry. A per-button latch shared across hands prevents duplicated actuation while held. The visible cap depression is separate from command dispatch.

| Parameter | Version 0.3 value |
| --- | --- |
| Actuation depth behind resting face | 6 mm |
| Maximum visible button travel | 8 mm |
| Fresh front approach/rearm distance | 35 mm |
| Withdrawal needed to release the press latch | 25 mm; rearming still requires the 35 mm approach position |
| Debounce interval | 120 ms |
| Maximum valid interval between contact samples | 250 ms; longer gaps reset contact history |

These are project tuning parameters, not established human-factors standards. Acceptance requires repeatable intentional pressing on the headset with one command per approach and no repeat while held. Each successful direct press receives one short haptic pulse. UI page changes, recentering, station movement, new-session resets, and tracking loss discard contact history; a control appearing around an embedded fingertip cannot actuate until the hand withdraws and approaches again.

Button travel, hover/press color, and controller haptics provide complementary feedback. The virtual button has no physical backing surface; software collision cannot exert force on a real controller. Meta's own hand-interaction case study describes the value of visible contact feedback and the risk of unintended activation. [Meta, *Hand Tracking in Tiny Castles*, UI section](https://developers.meta.com/vr/blog/hand-tracking-in-tiny-castles/).

## Nearby grabs, handles, and dials

Only an eligible nearby target responds to a squeeze. The closest available rotor, guard, or dial collision volume within 55 mm of the modeled palm is selected, and each target has one owner. All mechanisms require zero speed with no active acquisition/analysis. Loading also requires an open guard and released E-stop. A `GRIP` hint identifies the candidate. Reach assist cannot acquire these mechanisms remotely.

The carried rotor preserves its grip-relative transform at acquisition and follows the palm while held. Release seats it only when its center is within 0.17 m of the spindle and its up-axis dot product with the station's up-axis exceeds 0.78. Invalid or cancelled placement returns it to the tray. These forgiving teaching tolerances do not model a real spindle's mechanical fit. The user-facing instruction is to release the rotor upright and centered over the spindle.

The guard is a counterbalanced vertical lift with 0.43 m travel. While held, palm-height change controls its opening fraction. Lifting a closed guard opens its interlock; a fully lowered release latches it. A partially raised guard remains open. This mechanism is a lift, not a hinged hood.

For dials, the hand's wrist rotation is projected onto the dial axis. Probe travel is 0.5 mm/revolution, correction mass is 0.5 g/revolution, and the correction angle changes 1:1 with the dial turn. Values are clamped to their permitted range. Physical ± buttons give increments of 0.05 mm, 0.025 g, and 5° respectively. There is no thumbstick dial adjustment. Existing model interlocks still apply; a rejected operation cannot be made valid by moving its visual control. Poking is disabled while the hand is squeezing/holding, and a new acquisition is rejected while any mechanism is held.

The mechanism is a constrained training interaction; it is not a force-feedback simulation of micrometer friction, grip pressure, or actual fixture loads.

## Tracking loss and re-entry

Contact and grabs require app input focus, `get_has_tracking_data()`, and `get_pose().tracking_confidence == XR_TRACKING_CONFIDENCE_HIGH`. A registered tracker or last-known transform is insufficient; `get_is_active()` alone does not establish current data. Godot also exposes `tracking_changed` and `show_when_tracked` for this lifecycle. [XRNode3D tracking API](https://docs.godotengine.org/en/4.7/classes/class_xrnode3d.html), [XRPose confidence and stale-data semantics](https://docs.godotengine.org/en/4.7/classes/class_xrpose.html).

Loss of usable tracking cancels pending contact and active ownership without committing a fixture operation; a carried unseated rotor returns to the tray and the untracked glove is hidden. Grip acquisition remains unarmed until the side grip is released. Direct buttons require a fresh front approach. Station movement/recentering also cancels holds and contacts. App-focus interruptions use the cancellation path. These conservative choices for a precision training station still require headset testing.

## Reach and comfort

Keep common controls and fixture handles within a comfortable front-facing work area. Preserve seated/standing height adjustment and recentering; retaining the aim-ray option supports users with different reach and mobility. Do not require users to touch the floor, reach behind their body, repeatedly hold their arms above shoulder height, or collide their real controller rings together to perform a lab step.

Use an explicit way to reposition the station rather than silently stretching arm reach or moving a tracked hand away from its expected location. Repositioning cancels active contacts and grabs. Button labels must remain readable while the hand is nearby, and the hand material should contrast with the panel without obscuring the beam/signal plots. Validate left/right orientation and use separately; mirroring a hand is not sufficient proof that both work.

## Optional future optical hands

Quest 2 supports optical hand tracking, but enabling it is a separate feature and validation exercise. Godot's current API uses these components:

- Enable `xr/openxr/extensions/hand_tracking` and the Meta export hand-tracking feature. Declare it optional if the controller workflow remains available. Confirm the runtime capability and the user's hand-tracking setting.
- Position each rig with an `XRNode3D` under `XROrigin3D`, tracker `/user/hand_tracker/left` or `/user/hand_tracker/right`, pose `default`.
- Use a properly rigged/skinned hand mesh with `XRHandModifier3D` to animate its skeleton. `Skeleton3D.motion_scale` controls bone-position scaling.
- Read `XRHandTracker` joint `HAND_JOINT_INDEX_FINGER_TIP` for contact, and `HAND_JOINT_THUMB_TIP`/finger distances for a deliberately designed pinch/grab gesture. Check `has_tracking_data`, joint validity/tracked flags, and `hand_tracking_source`.
- Distinguish `HAND_TRACKING_SOURCE_UNOBSTRUCTED` from `HAND_TRACKING_SOURCE_CONTROLLER`: the latter means the runtime inferred joints from controller input. Do not label it measured optical articulation.

These are future integration steps; the controller-hand revision does not claim bare-hand control. [Godot hand-tracking setup](https://docs.godotengine.org/en/4.7/tutorials/xr/openxr_hand_tracking.html), [XRHandTracker](https://docs.godotengine.org/en/4.7/classes/class_xrhandtracker.html), [XRHandModifier3D](https://docs.godotengine.org/en/4.7/classes/class_xrhandmodifier3d.html).

Optical hands require additional evaluation around occlusion, leaving the cameras' field of view, gesture ambiguity, and the lack of controller haptics. Historical Meta Quest 2 experience reports document these issues; they should motivate actual tests rather than predictions of the current runtime's accuracy. [Meta, *Hand Tracking in Tiny Castles*, challenges section](https://developers.meta.com/vr/blog/hand-tracking-in-tiny-castles/).

## Acceptance evidence

The pure contact tests cover front strokes, partial strokes, embedded spawn, back/side entry, fast swept crossing, hold/jitter, debounce, tracking loss, reset/relocation, invalid samples, and stalled sampling. Broader application tests must cover ownership, command routing, and interlocks. A physical Quest 2 run must additionally check hand placement, both index tips, direct button feel, grasp/release alignment, guard latching, wrist dials, comfort, and reacquisition after interruption. Record unintended commands and reproduction steps. Re-profile representative reaching, carrying, adjustment, and signal-analysis workloads. A physical Quest 2 smoke test confirmed v0.2's buttons and spinning rotor, but that does not establish this revision's direct interactions; physical report retrieval and sustained performance also remain pending. See [the validation record](NATIVE_VALIDATION.md).
