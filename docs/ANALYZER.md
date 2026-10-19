# Reading the analyzer

The monitor displays acquired measurements. A new session starts on **Time** with a short instruction to acquire a baseline. Starting a normal run selects Time; starting a speed sweep selects Sweep. The physical **CHART** button cycles Time → Order → Sweep. A view that has no corresponding measurement shows an acquisition instruction rather than an invented trace.

All amplitudes are simulated displacement in micrometres. They do not represent measurements from connected hardware.

| View | Horizontal axis | Vertical axis | What to notice |
| --- | --- | --- | --- |
| Time | Actual capture time, 0.750–1.000 seconds | Signed sensor displacement, µm | Five revolutions at 1,200 RPM; the trace includes offset, noise, and harmonics. Two-plane captures show sensor A in teal and B in amber. |
| Order | Frequency divided by the captured shaft frequency, 0–5× | Sensor A one-sided DFT peak amplitude, µm | A 1× component repeats once per revolution; 2× repeats twice. The 0× component is a constant offset. |
| Sweep | Shaft speed, 0–1,800 RPM | Sensor A fitted 1× peak amplitude, µm | Real acquired quasi-steady points appear during the sweep. The support response amplifies motion near its simulated 22 Hz mode. |

The footer identifies the source record and its acquisition speed. Changing the test-speed setting does not relabel an older spectrum using the new setting. While a new normal acquisition is running, the previous captured trace stays identified as the previous record; it is not presented as a live stream. The first trace appears when sample analysis finishes. A sweep displays its acquired points as they become available.

The instrument generates 1,024 samples at 1,024 samples per second for each capture and retains the last 256 for the time display. The one-sided DFT covers 0–100 Hz; the order display converts those same frequency bins to shaft multiples and displays the range through 5×. At a noninteger-bin excitation, leakage spreads a spectral peak across bins. This fixed-speed view is not an angle-resampled changing-speed order analysis. The balancing solver uses the separate tach-referenced least-squares phasor, not a peak selected from the displayed spectrum.

Sweep points are independent quasi-steady simulated windows, rather than a transient rotor integration. The forcing changes with speed squared, so the displayed displacement peak is not a force-normalized frequency response. Its maximum alone cannot establish a modal frequency or a damping ratio. See [the scientific basis](NATIVE_RESEARCH.md) for equations and primary references.

The chart uses 2.8 mm triangle ribbons and triangle grid geometry rather than implementation-dependent one-pixel line primitives. Tick marks carry numerical domains and units. Deterministic tests acquire an actual baseline and sweep through the application and check that measured samples reach the chart's CPU geometry; an OpenGL render check verifies visible time, order, and sweep traces. Stereo readability and comfort still require a headset check.
