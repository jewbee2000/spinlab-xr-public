# SpinLab XR — feasibility and engineering research

Research checked: 18 October 2026. Sources below are first-party platform documentation, standards, a textbook publisher, instrument manufacturers, and NASA. Source facts are distinguished from project design assumptions. Browser/OS behavior still requires verification on a physical Quest 2.

## Findings and decisions

| Question | Evidence | Project decision and limit |
| --- | --- | --- |
| Can a web app use head/controller tracking for VR? | W3C WebXR defines immersive sessions, tracked poses, target rays, and grip spaces. [S1] | Use Three.js/WebXR; feature-detect support and retain desktop interaction. A standard does not prove a particular installed browser build works. |
| Can local development reach Quest Browser? | Meta documents developer mode, USB/ADB, remote debugging, and port reversal to headset localhost. [S3] | Serve the self-contained build on the computer and forward its port. Rendering executes on the headset; the computer is a file server. |
| Is plain LAN HTTP adequate for immersive WebXR? | WebXR is a secure-context API; the Secure Contexts standard treats loopback and qualifying localhost names as potentially trustworthy. [S1, S2] | Use headset localhost through USB port reversal for development, or valid HTTPS hosting. Do not assume `http://192.168...` enables XR. |
| Is controller input feasible? | W3C defines select/squeeze and tracked spaces; its Gamepads module defines trigger, squeeze, thumbstick, and axis layout. [S1, S4] | Use pointing/trigger as the reliable baseline. Detect optional grip, axes, and haptics and validate their mapping physically. |
| Is Quest 2 rendering performance plausible? | Meta describes WebXR profiling and frame budgets, and warns that draw-call submission can dominate CPU cost. [S5] | Target 72 Hz with small procedural geometry, simple lighting, shared assets, and measured optimization. This is a target, not an achieved benchmark. |
| Is balancing a credible engineering lesson? | Dewesoft's manufacturer manual explains amplitude/phase vectors and initial, trial, and correction runs. [S7] | Begin with one correction plane and an approximately linear response; add a measured trial exercise at fixed test speed after basic interaction is proven. |
| Does this relate to aerospace engineering? | NASA describes reaction wheels, static/dynamic imbalance disturbances, and precision-pointing jitter concerns. [S8, S9] | Explain component imbalance as one disturbance source. Do not infer spacecraft pointing accuracy or qualification from this bench demo. |

## Physical model

### Unbalance and force

For a small mass `m` at radius `r`, the required radial force magnitude is `m r ω²`. The equal reaction appears as a rotating load on the rotor/support. This magnitude follows from Newton's second law and circular motion. [OpenStax, S6](https://openstax.org/books/university-physics-volume-1/pages/6-3-centripetal-force)

Use:

```text
omega = 2*pi*rpm/60                    [rad/s]
U     = sum(m_i*r_i*exp(j*theta_i))      [kg*m]
F_1x  = abs(U)*omega^2                  [N, peak]
```

The complex-vector sum and its use for the fictional rotor are this project's mathematical formulation. A useful internal unit conversion is `1 g·mm = 1e-6 kg·m`. For an illustrative unbalance of `1 g·mm`, the ideal peak rotating force is about `0.0987 N` at `3,000 rpm`, and `0.3948 N` at `6,000 rpm`. These are arithmetic examples, not a component specification. Their fourfold ratio is a meaningful automated test.

Force is not the same quantity as vibration velocity or acceleration. A display labeled `mm/s RMS` needs an explicit transfer model and peak-to-RMS convention; it must not simply relabel force. A scalar force view is valid for teaching speed-squared scaling, while a vibration instrument view needs the assumptions below.

### Synthetic vibration and phase

For a deliberately simplified harmonic response at one speed, define a linear complex transfer function `H(omega)` from rotating imbalance force to sensor response:

```text
V_1x(omega) = H(omega) * U * omega^2
```

`H` includes chosen magnitude/phase and units. The initial implementation uses a damped single-degree-of-freedom support with fictional effective mass `0.8 kg`, natural frequency `22 Hz`, and damping ratio `0.12`. Its displayed peak velocity magnitude is:

```text
v_peak = abs(U)/M * omega^3 /
         sqrt((omega_n^2 - omega^2)^2 + (2*zeta*omega_n*omega)^2)
```

This is the steady harmonic response of a linear support evaluated at the instantaneous speed, converted from m/s to mm/s for display. It illustrates a resonance crossing during the 12-second run to `1,800 rpm`; it does not solve transient vibration during the ramp. Its constants are synthetic and uncalibrated.

The initial acquisition records analytical peak-velocity magnitudes with small seeded multiplicative noise every `0.25 s`. It does not acquire a high-rate accelerometer waveform or compute a measured spectrum. The reported RMS summary is the root mean square of the sampled harmonic RMS magnitudes over the run, including its ramp; it is not a calibrated steady-speed acceptance measurement. Exact mathematical cancellation yields zero response because this model has no independent sensor noise floor or other disturbance sources.

The initial display uses **compensated imbalance position** in rotor coordinates, with increasing angle counterclockwise as seen from above the rotor. It directly reports the remaining mass-radius vector angle after ideal transfer-function compensation; this is not the raw vibration sensor phase. A real sensor's phase includes support dynamics and reference conventions. The initial teaching correction is `0.600 g` at `300°`, which cancels `18 g·mm` at `120°` when fitted at a `30 mm` radius. All of these values are invented for the exercise.

The rotor mesh animation is deliberately slowed to `0.022` times the simulated angular speed so motion remains visible. The displayed bench is an illustrative enlarged assembly, and probe travel is exaggerated for readability. Its mesh dimensions are not a dimensional inspection model of the numerical rotor or the `30 mm` correction radius. Instrument values and exported units come from the simulation rather than being inferred from apparent mesh motion or dimensions.

### Trial-mass influence coefficient

Dewesoft describes measuring the baseline vector, adding a known trial mass at a known radius/angle, and observing the resulting vector change before applying a correction. [Dewesoft, S7](https://manual.dewesoft.com/x/setupmodule/modules/machinery/balancingapplication/theory)

The following expert workflow is planned; the first runnable demonstrator uses direct guided correction and does not implement an influence-coefficient solver. For the planned single-plane, fixed-speed, linear formulation:

```text
U_trial = m_trial * r_trial * exp(j*theta_trial)
alpha   = (V_trial - V_baseline) / U_trial
U_corr  = -V_baseline / alpha
m_corr  = abs(U_corr) / r_corr
theta_corr = arg(U_corr)
```

This expression is a project derivation of the vector procedure, rather than a quotation of an instrument manufacturer's algorithm. It assumes unchanged speed, sensor setup, transfer response, phase convention, and approximately linear support behavior. If the trial mass is removed before correction, `U_corr` is the added correction relative to the original rotor. If the trial mass remains, subtract `U_trial` when computing the additional mass vector. The exercise must explicitly state which procedure it uses.

Reject division by a near-zero response change, invalid/zero trial mass or radius, unsettled RPM, inconsistent test speed, missing tach phase, or saturated measurements. Acquire sufficient repeatable response to separate the trial effect from noise. Do not encourage indiscriminate trial-mass sizing from fictional values.

### What single-plane balance leaves out

A correction in one plane can address the modeled static unbalance vector. It does not generally eliminate a couple created by masses in separated axial planes. Schenck's own balancing documentation distinguishes static, couple, and quasi-static unbalance and describes why separated planes can require dynamic correction. [S10](https://www.schenck-rotec.com/fileadmin/Downloads/1._Products/DE/1.4_Handhelds/1.4.4_Smart_Balancer3/BE-49766-ENG-SmartBalancer_V3.pdf)

The prototype intentionally omits flexible-rotor modes, gyroscopic coupling, bearing defects/friction, motor harmonics, thermal/vacuum changes, fixture calibration, uncertainty budgets, physical contact forces, and spacecraft attitude-control dynamics. All training pass limits are invented. A green result means the simulation's exercise criterion was met, not compliance with a balance standard, flight requirement, or safe physical operating limit.

## Application relevance

NASA's small-spacecraft GNC reference describes reaction wheels as torque/momentum actuators and notes unwanted forces and torques from imbalance. Its NESC article links wheel mass imbalance and bearing noise to pointing disturbances in demanding observatory applications. Those sources establish a real engineering motivation for minimizing disturbance; they do not establish that this simulation reproduces a particular mission or supplier's process. [NASA GNC, S8](https://www.nasa.gov/smallsat-institute/sst-soa/guidance-navigation-and-control/), [NASA NESC, S9](https://www.nasa.gov/centers-and-facilities/nesc/microthrusters-as-a-potential-solution-for-accomplishing-pointing-stability-for-large-space-telescopes/)

The educational value extends to motor/fan/impeller test fixtures: preparing a DUT, satisfying interlocks, operating at a controlled speed, interpreting a phase-aware measurement, changing a controlled variable, and preserving evidence. That broader training value is the project's inference, not a documented outcome study of this app. A future user study could test task completion, error rate, and explanation quality before/after training.

## Quest-specific feasibility and remaining checks

The app should request immersive VR only after a user gesture, handle rejection with a readable message, and check `isSecureContext`, `navigator.xr`, and immersive-session support. Do not require hand tracking, passthrough, room scanning, persistent spatial anchors, or experimental extensions for the basic exercise. The necessary experience is a stable virtual bench using head and controller poses.

Quest 2's available installed software and current account/developer setup cannot be inferred from the development computer. Physical acceptance must verify controller axes/buttons, grip semantics, haptic support, reference-space height, session suspension, text legibility, five-minute performance, and comfort. Optional features should degrade to buttons/text feedback. A desktop WebXR emulator may help debug interaction logic but cannot establish tracking quality or headset performance.

At 72 Hz there is approximately `1000/72 = 13.89 ms` per display interval. Meta's guidance calls for profiling both CPU and GPU rather than judging a scene only by polygon count. Use that target to budget scene complexity and instrument updates, then record actual results on Quest 2. Text panels need not upload a new canvas texture at headset frame rate. A high JavaScript frame-rate counter alone cannot prove that the display met its target. [Meta performance workflow, S5](https://developers.meta.com/vr/documentation/web/webxr-perf-workflow/)

USB port reversal is a documented local testing route, but it requires developer mode, Android Platform Tools, device authorization, and an active serving computer. A valid-HTTPS static host can provide an untethered launch path. Hosting configuration determines build accessibility independently of source-repository access controls.

## Source register

All links were checked on 18 October 2026. Dates below are the dates shown by the sources where available; a living manual may have no stable page publication date.

| ID | Primary source | Date/status seen | Supported use |
| --- | --- | --- | --- |
| S1 | [W3C WebXR Device API](https://www.w3.org/TR/webxr/) | Candidate Recommendation Draft, 9 June 2026 | Secure-context API, immersive sessions, poses, tracked input spaces and events |
| S2 | [W3C Secure Contexts](https://www.w3.org/TR/secure-contexts/) | Candidate Recommendation Draft, 10 November 2023 | HTTPS and potentially trustworthy loopback/localhost origins; these are specification rules, not a guarantee of every browser's implementation |
| S3 | [Meta: Debug Browser content](https://developers.meta.com/vr/documentation/web/browser-remote-debugging/) | Updated 22 July 2026 | Developer mode/USB prerequisites, ADB port reverse, Quest Browser localhost and Chrome remote inspection |
| S4 | [W3C WebXR Gamepads Module — Level 1](https://www.w3.org/TR/webxr-gamepads-module-1/) | Working Draft, 7 July 2025 | `xr-standard` trigger/squeeze/thumbstick mapping and optional placeholders |
| S5 | [Meta: WebXR performance optimization workflow](https://developers.meta.com/vr/documentation/web/webxr-perf-workflow/) | Updated 21 July 2026 | CPU/GPU timing, performance HUD, draw-call and simulation costs |
| S6 | [OpenStax: University Physics Volume 1, 6.3 Centripetal Force](https://openstax.org/books/university-physics-volume-1/pages/6-3-centripetal-force) | Live textbook section | `F = m r omega²`; source for the force derivation, not rotor balancing tolerances |
| S7 | [Dewesoft X manual: Theory of Balancing](https://manual.dewesoft.com/x/setupmodule/modules/machinery/balancingapplication/theory) | Living manufacturer manual | Initial/trial/correction runs and amplitude/phase vector method |
| S8 | [NASA Small Spacecraft Technology State of the Art: Guidance, Navigation, and Control](https://www.nasa.gov/smallsat-institute/sst-soa/guidance-navigation-and-control/) | Living NASA reference | Reaction-wheel function and imbalance disturbance context |
| S9 | [NASA NESC: Microthrusters as a Potential Solution for Accomplishing Pointing Stability for Large Space Telescopes](https://www.nasa.gov/centers-and-facilities/nesc/microthrusters-as-a-potential-solution-for-accomplishing-pointing-stability-for-large-space-telescopes/) | NASA article, 2021 | Wheel imbalance/bearing-noise motivation for precision-pointing applications |
| S10 | [Schenck RoTec: SmartBalancer user documentation](https://www.schenck-rotec.com/fileadmin/Downloads/1._Products/DE/1.4_Handhelds/1.4.4_Smart_Balancer3/BE-49766-ENG-SmartBalancer_V3.pdf) | Manufacturer PDF, document BE-49766 | Static/couple/quasi-static imbalance distinctions and the need for appropriate correction planes |

These sources support the analytical methods and engineering context. The simulation parameters are training examples rather than equipment operating procedures or flight qualification criteria.
