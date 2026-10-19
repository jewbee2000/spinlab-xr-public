# SpinLab XR native lab: research and engineering basis

Research checked 18 October 2026. This document records the scientific methods behind the native lab and its implementation boundaries. Equations below use one consistent angular reference; the app's training parameters, scenarios, meshes, and thresholds are synthetic.

## Implemented scope of version 0.2

The numerical model implements measured single/two-plane complex influence coefficients, independent trial validation, a matrix conditioning check, a fresh verification capture, tach-referenced least-squares extraction of DC/1×/2×, a 0–100 Hz one-sided DFT, a quasi-steady resonance sweep, and three-window repeatability. A capture contains 1,024 samples at 1,024 Hz; displayed waveforms retain the last 256 samples. Measurements are displacement **peak micrometres**. The support mode is 22 Hz with damping ratio 0.11, and the correction radius is 30 mm. The rendered fixture intentionally magnifies small parts for VR legibility.

Angular resampling during a changing-speed record, a full order waterfall, identified damping/modal fitting, a Type B calibration budget, expanded uncertainty, Monte Carlo correction intervals, and a full gyroelastic wheel model are research extensions, not completed capabilities of this build. The current sweep evaluates a separate quasi-steady window at each speed rather than numerically integrating a spinning rotor's transient response. Its apparent run duration is an interaction affordance, not a claim that a physical lab can collect every settled sweep window in that time.

## Why a reaction-wheel test lab is credible

Reaction wheels control spacecraft attitude but also inject vibration into the structure. NASA's Solar Dynamics Observatory study used measured disturbances, harmonic/order analysis, structural dynamics, and validation tests to predict instrument jitter. Its wheel model combined tones whose forcing scales with speed squared with broadband noise and structural amplification. This motivates an engineering training lab covering fixture design, motion, instrumentation, signal processing, test sequences, and root-cause diagnosis. SpinLab uses that methodology as inspiration; it is not a model of the SDO wheel or its measured performance. [Liu, Maghami and Blaurock, *Reaction Wheel Disturbance Modeling, Jitter Analysis, and Validation Tests for Solar Dynamics Observatory*, 2008, sections II–IV](https://ntrs.nasa.gov/api/citations/20080039248/downloads/20080039248.pdf).

## 1. Measured influence-coefficient balancing

Use complex vectors rather than treating measured vibration phase as the physical heavy-spot angle. A support transfer function and the sensor/tachometer convention rotate that phase.

For one plane, acquire baseline synchronous vibration `V0`, add a known trial unbalance `T = m_trial * r * exp(i*theta_trial)`, and acquire `Vt` at the **same settled speed**. Then:

```text
alpha = (Vt - V0) / T
C = -V0 / alpha
m_correction = abs(C) / r
theta_correction = arg(C)
```

For two correction planes and two measurement channels:

```text
V0 = [V_A, V_B]^T
A[:, 1] = (V_trial_plane_1 - V0) / T1
A[:, 2] = (V_trial_plane_2 - V0) / T2
A * C = -V0
C = [C1, C2]^T
```

Remove the first trial mass before measuring the second trial against the original baseline. Both sensors respond to either plane: the off-diagonal matrix entries are cross effects. Reject singular/poorly conditioned matrices and trial responses too small relative to noise. Verify the result with a fresh run after removing trial masses and applying correction masses. The solver should use saved measurements rather than the scenario's hidden unbalance. These equations are the linear model specialized from Yu and Péton's measured complex influence matrix. Assumptions: linear response, repeatable mounting/sensor geometry, consistent phase reference, stable speed, and unchanged support dynamics. [Yu and Péton, Texas A&M Turbomachinery Laboratory, 2021, Theory, equations 1–2](https://oaktrust.library.tamu.edu/items/e9117928-4326-48e0-8302-335013f69251).

Rigid thin discs often permit single-plane treatment; distributed mass and couple unbalance motivate two planes. This distinction supplies a meaningful progression from an introductory rotor to an advanced diagnostic exercise. [Brüel & Kjær, *Static and Dynamic Balancing of Rigid Rotors*](https://www.bksv.com/de/knowledge/blog/vibration/static-and-dynamic-balancing-of-rigid-rotors).

## 2. Tachometer-referenced synchronous analysis

For uniform angular samples spanning complete revolutions, the complex peak-amplitude order estimate is:

```text
Z_k = (2/N) * sum(x_j * exp(-i*k*theta_j))
amplitude_peak = abs(Z_k)
phase = atan2(imag(Z_k), real(Z_k))
amplitude_rms = amplitude_peak / sqrt(2)
```

The factor of two applies to a real sinusoid at a non-DC, non-Nyquist order. Peak and RMS must be explicitly labeled. A constant channel offset should be removed. If a window is used, replace `N` with the sum of window weights for coherent-gain normalization. For nonuniform shaft speed, interpolate vibration onto uniform angular increments before estimating orders; directly averaging time samples weighted only by angle can bias the result.

The 1× component follows shaft rotation. Higher orders can reveal effects a simple trim correction does not remove. Frequency/order plots should distinguish a speed-proportional excitation from a structural resonance; they do not by themselves prove a specific bearing defect. The method discussed here is conventional resampling/order analysis; NI's documentation also describes a distinct Gabor algorithm. [NI, *Performing Order Analysis in LabVIEW with Sound and Vibration Software*](https://www.ni.com/en/shop/labview/performing-order-analysis-in-labview-with-sound-and-vibration-so.html), [NI, *Order Analysis Based on Resampling*](https://www.ni.com/docs/ne-NP/bundle/diadem/page/genmaths/genmaths/calc_oa_resampling.htm).

The current fixed-speed capture fits the five-column model `x = b0 + a1*cos(theta) + b1*sin(theta) + a2*cos(2*theta) + b2*sin(2*theta)` by least squares, then takes `Z1 = a1 - i*b1`. This separates DC and 2× even when the capture contains noninteger revolutions. The rectangular-window DFT is a separate visualization; off-bin tones leak across bins, so its largest bin need not equal the least-squares synchronous amplitude. This is why the balancing solver uses the fitted tach phasor rather than a peak-picked spectrum bin.

## 3. Support dynamics and resonance

An educational lateral single-degree-of-freedom support model is:

```text
omega = 2*pi*rpm/60
omega_n = sqrt(k/m)
zeta = c / (2*sqrt(k*m))
H_xF(omega) = 1 / (k - m*omega^2 + i*c*omega)
F_1x = U * omega^2
X_1x = H_xF * F_1x
V_1x = i*omega*X_1x
```

`U` is mass times eccentric radius in kg·m; `X` is displacement in m; `V` is velocity in m/s. `1 g·mm = 1e-6 kg·m`. This separates unbalance forcing from support response. Multi-channel/two-plane scenarios may use a synthetic complex response matrix built from such modes. This remains a reduced model, not finite-element analysis or a full gyroscopic flexible-rotor solution.

A coast/speed sweep illustrates critical-speed amplification. Damping estimates from half-power bandwidth use `zeta ≈ (f2-f1)/(2*fn)` for an isolated lightly damped mode, with the FRF magnitude at `f1,f2` equal to peak magnitude divided by `sqrt(2)`. Do not apply that rule to an unnormalized unbalance response: its input force changes with speed squared. Use force-normalized FRF data or fit the full response model. Narrow modes need fine frequency resolution and sufficient settling; overlapping/noisy modes require stronger fitting methods. [Brüel & Kjær, *Structural Testing Part 2: Modal Analysis and Simulation*, pp. 24–29](https://www.bksv.com/media/doc/br0507.pdf).

## 4. Repeatability and uncertainty

For `n` independent repeat captures under the same conditions:

```text
mean = sum(x_i)/n
s = sqrt(sum((x_i-mean)^2)/(n-1))
u_A(mean) = s/sqrt(n)
```

Report `s` as observed repeatability and `u_A` as standard uncertainty of the mean. They answer different questions. Repeating correlated samples or measuring only one capture does not establish this uncertainty. For vibration phase near zero amplitude, report poor phase observability rather than a precise angle. Complex means should average real and imaginary parts, avoiding the 359°/1° arithmetic-mean error. [NIST, *Evaluating uncertainty components: Type A*](https://pml.nist.gov/cuu/Uncertainty/typea.html).

Add independent calibration/resolution contributions through sensitivity coefficients. For a simple amplitude result with compatible units, `u_c = sqrt(u_A^2 + u_cal^2 + u_res^2)`; a uniform rounding interval of width `q` contributes `q/sqrt(12)`. Shared calibration bias does not average down with more captures. General propagation includes covariance. [NIST, *Combining uncertainty components*](https://pml.nist.gov/cuu/Uncertainty/combination.html).

Expanded uncertainty is `U_expanded = k_cov*u_c`. The common `k_cov=2` approximates 95% coverage only when a normal approximation and adequate uncertainty estimate apply. Small samples, nonlinear correction angles, or nearly singular influence matrices can invalidate that simplification. Training pass limits are project choices and do not claim ISO balance-grade certification. [NIST, *Expanded uncertainty and coverage factors*](https://pml.nist.gov/cuu/Uncertainty/coverage.html).

## Native Quest implementation decision

The native app uses Godot 4.7.2 stable, GDScript, ARM64 Android export, and OpenXR. The release and matching export templates must have the same version. [Godot's official 4.7.2 release](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable).

Godot 4.6+ includes a generic Android OpenXR route. The optional OpenXR Vendors plugin adds vendor manifest/export behavior and extensions. For reliable Quest identification, use its Meta export option or inspect the packaged manifest for equivalent VR category/runtime-discovery entries. Core head and controller tracking run locally through OpenXR. Compatibility/OpenGL is the conservative Quest 2 starting point; actual refresh stability still requires headset profiling. [Godot, *Deploying to Android*, 4.7](https://docs.godotengine.org/en/4.7/tutorials/xr/deploying_to_android.html).

The official vendors release 5.1.0 supports Godot 4.6+. Its Meta export implementation includes Quest 2 support, `com.oculus.intent.category.VR`, `org.khronos.openxr.intent.category.IMMERSIVE_HMD`, head-tracking features, and device metadata. The common manifest supplies runtime-broker discovery. [OpenXR Vendors 5.1.0](https://github.com/GodotVR/godot_openxr_vendors/releases/tag/5.1.0-stable), [Meta export source](https://github.com/GodotVR/godot_openxr_vendors/blob/5.1.0-stable/plugin/src/main/cpp/export/meta_export_plugin.cpp), [common manifest](https://github.com/GodotVR/godot_openxr_vendors/blob/5.1.0-stable/plugin/src/main/AndroidManifest.xml).

Quest 2's useful baseline is stereo head tracking, two Touch controllers, spatial interaction, audio, and haptics. Eye tracking, face tracking, and Quest 3 color passthrough are not Quest 2 requirements. Optional extensions must be capability-checked; controller interaction must remain complete. A physical acceptance run must confirm app launch in immersive mode, both controllers, readable plots, recovery after headset removal, sustained frame pacing, and seated comfort. An exported APK and a desktop smoke test alone cannot establish these results.

## Scientific boundaries

- All motors, probes, faults, enclosure logic, measurements, and safety responses are simulated. The app does not drive external machinery.
- Analytical signal generation can faithfully demonstrate a method without reproducing all bearing, gyroelastic, thermal, mounting, and electronics effects of a real instrument.
- Standards-informed vocabulary is not a conformance claim. No flight qualification, calibrated accuracy, or certified safety behavior is asserted.
- The native implementation and its tests determine the currently available features; the equations above also guide future extensions. See the native test results and user guide before treating an optional method as implemented.
