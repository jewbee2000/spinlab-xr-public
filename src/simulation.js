/**
 * SpinLab XR: fictional, single-plane rotor-balance training model.
 *
 * Units: speed rpm; angles degrees; correction g at a 30 mm radius; imbalance
 * g·mm; probe position mm; vibration peak velocity mm/s. The displayed phase
 * is the angular position of the imbalance vector in the rotor coordinate
 * system, after ideal sensor/transfer-function compensation. It is therefore
 * NOT the raw accelerometer phase. Add correction 180° opposite this phase.
 *
 * This is a mass/spring/damper visualization, not a machine design, acceptance
 * standard, or a validated predictor of the behavior of physical hardware.
 * All clocks and sensor noise are simulated, so replay needs no wall clock.
 */

export const SIMULATION_CONSTANTS = Object.freeze({
  initialImbalanceGmm: 18,
  initialImbalanceAngleDeg: 120,
  correctionRadiusMm: 30,
  maxCorrectionGrams: 2,
  nominalProbePositionMm: 6,
  probeToleranceMm: 0.5,
  minProbePositionMm: 0,
  maxProbePositionMm: 12,
  sweepDurationSeconds: 12,
  targetRpm: 1800,
  accelerationRpmPerSecond: 360,
  decelerationRpmPerSecond: 900,
  sampleIntervalSeconds: 0.25,
  effectiveMassKg: 0.8,
  naturalFrequencyHz: 22,
  dampingRatio: 0.12,
  passResidualGmm: 2,
});

const C = SIMULATION_CONSTANTS;
const EPSILON = 1e-9;
const rad = (degrees) => degrees * Math.PI / 180;
const rounded = (value, digits = 6) => Number(value.toFixed(digits));
const result = (ok, message) => ({ ok, message });

export function normalizeAngleDeg(angle) {
  if (!Number.isFinite(angle)) throw new RangeError('Angle must be finite.');
  return ((angle % 360) + 360) % 360;
}

function polar(magnitude, degrees) {
  return { x: magnitude * Math.cos(rad(degrees)), y: magnitude * Math.sin(rad(degrees)) };
}

/** Harmonic velocity response of a damped, single-degree-of-freedom support. */
function velocityAmplitude(imbalanceGmm, rpm) {
  const omega = rpm * 2 * Math.PI / 60;
  const naturalOmega = C.naturalFrequencyHz * 2 * Math.PI;
  const denominator = Math.hypot(
    naturalOmega ** 2 - omega ** 2,
    2 * C.dampingRatio * naturalOmega * omega,
  );
  // 1 g·mm = 1e-6 kg·m; multiply m/s by 1000 for mm/s.
  return imbalanceGmm * 1e-6 / C.effectiveMassKg * omega ** 3 / denominator * 1000;
}

export class SpinLabSimulation {
  constructor({ seed = 42 } = {}) {
    if (!Number.isFinite(seed)) throw new RangeError('Seed must be finite.');
    this.seed = Math.trunc(seed) >>> 0;
    this.reset();
  }

  reset() {
    this.mounted = false;
    this.guardClosed = false;
    this.homed = false;
    this.estop = false;
    this.fault = null;
    this.rpm = 0;
    this.targetRpm = 0;
    this.running = false;
    this.time = 0;
    this.sensorPosition = C.nominalProbePositionMm;
    this.massAngle = 0;
    this.massGrams = 0;
    this.measurements = [];
    this.events = [];
    this._elapsed = 0;
    this._sinceSample = 0;
    this._revision = 0;
    this._measurementRevision = -1;
    this._complete = false;
    this._pendingComplete = false;
    this._runCount = 0;
    this._rng = this.seed;
    this._record('reset', { seed: this.seed });
    return result(true, 'Station reset. Load a rotor to begin.');
  }

  _record(type, details = {}) {
    this.events.push({ sequence: this.events.length + 1, time: rounded(this.time), type, ...details });
  }

  _invalidate() {
    this._revision += 1;
    this._complete = false;
    this._pendingComplete = false;
  }

  _stationary() {
    return !this.running && this.rpm <= EPSILON;
  }

  _actionBlocked() {
    if (this.estop) return 'Release the emergency stop and reset the fault first.';
    if (this.fault) return 'Reset the latched fault first.';
    if (!this._stationary()) return 'Wait until the rotor has stopped.';
    return null;
  }

  mountRotor() {
    const blocked = this._actionBlocked();
    if (blocked) return result(false, blocked);
    if (this.guardClosed) return result(false, 'Open the guard before loading the rotor.');
    if (this.mounted) return result(true, 'Rotor is already mounted.');
    this.mounted = true;
    this.homed = false;
    this._invalidate();
    this._record('rotor-mounted');
    return result(true, 'Rotor mounted. Home the probe, then close the guard.');
  }

  toggleGuard() {
    this.guardClosed = !this.guardClosed;
    this._record('guard-changed', { closed: this.guardClosed });
    if (!this.guardClosed && (this.running || this.rpm > EPSILON)) {
      this._latchFault('guard', 'Guard opened during rotation. Drive removed.');
      return result(false, 'Guard interlock tripped. Wait for zero speed, close the guard, then reset.');
    }
    return result(true, this.guardClosed ? 'Guard closed.' : 'Guard open.');
  }

  homeProbe() {
    const blocked = this._actionBlocked();
    if (blocked) return result(false, blocked);
    if (!this.mounted) return result(false, 'Mount the rotor before homing the probe.');
    if (!this.homed || this.sensorPosition !== C.nominalProbePositionMm) this._invalidate();
    this.homed = true;
    this.sensorPosition = C.nominalProbePositionMm;
    this._record('probe-homed', { positionMm: this.sensorPosition });
    return result(true, 'Probe homed to 6.0 mm.');
  }

  setProbePosition(mm) {
    if (!Number.isFinite(mm) || mm < C.minProbePositionMm || mm > C.maxProbePositionMm) {
      return result(false, 'Probe position must be between 0 and 12 mm.');
    }
    const blocked = this._actionBlocked();
    if (blocked) return result(false, blocked);
    if (this.sensorPosition !== mm) this._invalidate();
    this.sensorPosition = mm;
    this._record('probe-positioned', { positionMm: mm });
    return result(true, `Probe positioned at ${mm.toFixed(1)} mm.`);
  }

  setCorrection(grams, angleDeg) {
    if (!Number.isFinite(grams) || grams < 0 || grams > C.maxCorrectionGrams || !Number.isFinite(angleDeg)) {
      return result(false, 'Correction must be 0–2 g with a finite angle.');
    }
    const blocked = this._actionBlocked();
    if (blocked) return result(false, blocked);
    if (!this.mounted) return result(false, 'Mount a rotor before adding correction mass.');
    if (this.guardClosed) return result(false, 'Open the guard before changing correction mass.');
    const angle = normalizeAngleDeg(angleDeg);
    if (this.massGrams !== grams || this.massAngle !== angle) this._invalidate();
    this.massGrams = grams;
    this.massAngle = angle;
    this._record('correction-changed', { grams, angleDeg: angle, radiusMm: C.correctionRadiusMm });
    return result(true, `Correction set: ${grams.toFixed(3)} g at ${angle.toFixed(0)}°.`);
  }

  get interlocks() {
    const reasons = [];
    if (!this.mounted) reasons.push('Mount rotor');
    if (!this.guardClosed) reasons.push('Close guard');
    if (!this.homed) reasons.push('Home probe');
    if (Math.abs(this.sensorPosition - C.nominalProbePositionMm) > C.probeToleranceMm + EPSILON) {
      reasons.push('Set probe within 5.5–6.5 mm');
    }
    if (this.estop) reasons.push('Release emergency stop');
    if (this.fault) reasons.push(`Reset ${this.fault} fault`);
    if (!this.running && this.rpm > EPSILON) reasons.push('Wait for zero speed');
    return reasons;
  }

  startSweep() {
    if (this.running) return result(false, 'A sweep is already running.');
    const interlocks = this.interlocks;
    if (interlocks.length) return result(false, interlocks.join('. ') + '.');
    this._runCount += 1;
    this._complete = false;
    this._pendingComplete = false;
    this._measurementRevision = this._revision;
    this._elapsed = 0;
    this._sinceSample = 0;
    this.measurements = [];
    this._rng = this.seed;
    this.running = true;
    this.targetRpm = C.targetRpm;
    this._record('sweep-started', { run: this._runCount, configurationRevision: this._revision });
    this._sample();
    return result(true, 'Sweep started. Keep the guard closed until zero speed.');
  }

  stop() {
    if (!this.running && !this._pendingComplete && this.rpm <= EPSILON) {
      return result(true, 'Rotor is stopped.');
    }
    this.running = false;
    this.targetRpm = 0;
    this._complete = false;
    this._pendingComplete = false;
    this._record('sweep-stopped');
    return result(true, 'Drive removed. Rotor is coasting to zero speed.');
  }

  _latchFault(kind, message) {
    this.fault = kind;
    this.running = false;
    this.targetRpm = 0;
    this._invalidate();
    if (kind === 'sensor') this.homed = false;
    this._record('fault-latched', { kind, message });
  }

  emergencyStop() {
    this.estop = true;
    this._latchFault('emergency-stop', 'Emergency stop actuated. Drive removed.');
    return result(true, 'Emergency stop latched. Release it after the rotor stops, then reset the fault.');
  }

  releaseEstop() {
    if (!this.estop) return result(true, 'Emergency stop is already released.');
    this.estop = false;
    this._record('emergency-stop-released');
    return result(true, 'Emergency stop released. Reset the fault before restarting.');
  }

  resetFault() {
    if (!this._stationary()) return result(false, 'Wait for zero speed before resetting a fault.');
    if (this.estop) return result(false, 'Release the emergency stop before resetting the fault.');
    if (this.fault === 'guard' && !this.guardClosed) return result(false, 'Close the guard before resetting its fault.');
    if (!this.fault) return result(true, 'No fault is latched.');
    const previousFault = this.fault;
    this.fault = null;
    this._record('fault-reset', { previousFault });
    return result(true, previousFault === 'sensor' ? 'Sensor fault reset. Home the probe again.' : 'Fault reset.');
  }

  injectFault(kind = 'sensor') {
    if (typeof kind !== 'string' || !kind.trim()) return result(false, 'Provide a fault name.');
    this._latchFault(kind.trim(), 'Instructor-injected training fault.');
    return result(true, `${kind.trim()} training fault injected. Drive removed.`);
  }

  _balance() {
    const initial = polar(C.initialImbalanceGmm, C.initialImbalanceAngleDeg);
    const correction = polar(this.massGrams * C.correctionRadiusMm, this.massAngle);
    const x = initial.x + correction.x;
    const y = initial.y + correction.y;
    const rawMagnitude = Math.hypot(x, y);
    const magnitude = rawMagnitude < EPSILON ? 0 : rawMagnitude;
    return {
      initial,
      correction,
      residual: { x, y },
      magnitude,
      angle: magnitude === 0 ? 0 : normalizeAngleDeg(Math.atan2(y, x) * 180 / Math.PI),
    };
  }

  _random() {
    this._rng = (Math.imul(this._rng, 1664525) + 1013904223) >>> 0;
    return this._rng / 4294967296;
  }

  _sample() {
    const balance = this._balance();
    const trueVibration = velocityAmplitude(balance.magnitude, this.rpm);
    // Seeded multiplicative noise never invents vibration at exact cancellation.
    const measuredVibration = trueVibration * (1 + (this._random() - 0.5) * 0.006);
    const phaseNoise = (this._random() - 0.5) * 0.3;
    this.measurements.push({
      time: rounded(this._elapsed),
      rpm: rounded(this.rpm),
      vibration: rounded(measuredVibration),
      phase: rounded(balance.magnitude === 0 ? 0 : normalizeAngleDeg(balance.angle + phaseNoise)),
      residual: rounded(balance.magnitude),
    });
  }

  /** Advance deterministic simulation time. dt is seconds; no timer is used. */
  tick(dt) {
    if (!Number.isFinite(dt) || dt < 0) throw new RangeError('dt must be a finite, nonnegative number of seconds.');
    let remaining = dt;
    while (remaining > EPSILON) {
      if (!this.running && this.rpm <= EPSILON) {
        this.time += remaining;
        remaining = 0;
        break;
      }
      let step = Math.min(remaining, 1 / 120);
      if (this.running) {
        step = Math.min(step, C.sweepDurationSeconds - this._elapsed, C.sampleIntervalSeconds - this._sinceSample);
      } else {
        step = Math.min(step, this.rpm / C.decelerationRpmPerSecond);
      }
      if (this.targetRpm > this.rpm) {
        this.rpm = Math.min(this.targetRpm, this.rpm + C.accelerationRpmPerSecond * step);
      } else {
        this.rpm = Math.max(this.targetRpm, this.rpm - C.decelerationRpmPerSecond * step);
      }
      this.time += step;
      remaining -= step;
      if (this.running) {
        this._elapsed += step;
        this._sinceSample += step;
        if (this._sinceSample >= C.sampleIntervalSeconds - EPSILON) {
          this._sinceSample = 0;
          this._sample();
        }
        if (this._elapsed >= C.sweepDurationSeconds - EPSILON) {
          this._elapsed = C.sweepDurationSeconds;
          this.running = false;
          this.targetRpm = 0;
          this._pendingComplete = true;
          this._record('sweep-acquisition-complete', { samples: this.measurements.length });
        }
      }
      if (!this.running && this.rpm <= EPSILON) {
        this.rpm = 0;
        if (this._pendingComplete) {
          this._pendingComplete = false;
          this._complete = this._measurementRevision === this._revision && !this.fault && !this.estop;
          this._record('sweep-complete', { valid: this._complete, passed: this._complete && this._balance().magnitude <= C.passResidualGmm });
        }
      }
    }
    return this.getTelemetry();
  }

  get phase() {
    if (this.fault || this.estop) return 'fault';
    if (this.running) return 'sweep';
    if (this.rpm > EPSILON) return 'coast';
    if (this._complete) return this._balance().magnitude <= C.passResidualGmm ? 'passed' : 'review';
    return 'setup';
  }

  getTelemetry() {
    const balance = this._balance();
    const complete = this._complete && this._measurementRevision === this._revision;
    const passed = complete && balance.magnitude <= C.passResidualGmm;
    const sumSquared = this.measurements.reduce((sum, sample) => sum + sample.vibration ** 2, 0);
    const rms = this.measurements.length ? Math.sqrt(sumSquared / (2 * this.measurements.length)) : 0;
    const peak = this.measurements.reduce((max, sample) => Math.max(max, sample.vibration), 0);
    let status;
    if (this.estop) status = 'Emergency stop latched';
    else if (this.fault) status = `${this.fault} fault latched`;
    else if (this.running) status = 'Sweep in progress';
    else if (this.rpm > EPSILON) status = this._pendingComplete ? 'Coasting after sweep' : 'Coasting to stop';
    else if (complete) status = passed ? 'PASS — residual within 2 g·mm' : 'Correction required — review phase and residual';
    else status = this.interlocks.length ? this.interlocks.join(' · ') : 'Ready for sweep';
    return {
      rpm: this.rpm,
      targetRpm: this.targetRpm,
      vibration: velocityAmplitude(balance.magnitude, this.rpm),
      phase: balance.angle,
      residual: balance.magnitude,
      rms,
      peak,
      complete,
      passed,
      status,
      samples: this.measurements.length,
      elapsed: this._elapsed,
      progress: Math.min(1, this._elapsed / C.sweepDurationSeconds),
      interlocks: [...this.interlocks],
      mounted: this.mounted,
      guardClosed: this.guardClosed,
      homed: this.homed,
      estop: this.estop,
      fault: this.fault,
      running: this.running,
      sensorPosition: this.sensorPosition,
      massGrams: this.massGrams,
      massAngle: this.massAngle,
      state: this.phase,
      time: this.time,
      initialImbalance: C.initialImbalanceGmm,
      initialAngle: C.initialImbalanceAngleDeg,
      correctionRadius: C.correctionRadiusMm,
      passLimit: C.passResidualGmm,
    };
  }

  /** Return a detached, JSON-serializable report. Time values are simulated. */
  exportReport() {
    const t = this.getTelemetry();
    const balance = this._balance();
    const vector = (v) => ({ x: rounded(v.x), y: rounded(v.y) });
    return {
      schema: 'spinlab-xr/balance-report',
      schemaVersion: '1.0.0',
      serial: `SLX-${this.seed.toString(16).toUpperCase().padStart(8, '0')}`,
      run: this._runCount,
      simulationTimeSeconds: rounded(this.time),
      trainingOnly: true,
      model: 'Fictional single-plane rotor; linear mass/spring/damper support',
      phaseConvention: 'Compensated angular imbalance position in rotor coordinates; add correction 180 degrees opposite.',
      settings: {
        targetRpm: C.targetRpm,
        sweepDurationSeconds: C.sweepDurationSeconds,
        probePositionMm: this.sensorPosition,
        probeHomed: this.homed,
        correctionRadiusMm: C.correctionRadiusMm,
        effectiveMassKg: C.effectiveMassKg,
        naturalFrequencyHz: C.naturalFrequencyHz,
        dampingRatio: C.dampingRatio,
        sampleIntervalSeconds: C.sampleIntervalSeconds,
        passResidualGmm: C.passResidualGmm,
        configurationRevision: this._revision,
        measuredConfigurationRevision: this._measurementRevision,
      },
      units: { imbalance: 'g·mm', correction: 'g', position: 'mm', speed: 'rpm', vibration: 'mm/s peak', phase: 'deg', time: 's' },
      balance: {
        initial: { magnitudeGmm: C.initialImbalanceGmm, angleDeg: C.initialImbalanceAngleDeg, vectorGmm: vector(balance.initial) },
        correction: { massGrams: this.massGrams, radiusMm: C.correctionRadiusMm, angleDeg: this.massAngle, vectorGmm: vector(balance.correction) },
        residual: { magnitudeGmm: rounded(balance.magnitude), angleDeg: rounded(balance.angle), vectorGmm: vector(balance.residual) },
      },
      measuredResults: {
        complete: t.complete,
        passed: t.passed,
        status: t.status,
        samples: t.samples,
        elapsedSeconds: rounded(t.elapsed),
        peakVibrationMmS: rounded(t.peak),
        // Time average of sampled harmonic RMS velocity, including the ramp.
        rmsVibrationMmS: rounded(t.rms),
        maximumMeasuredRpm: this.measurements.reduce((max, sample) => Math.max(max, sample.rpm), 0),
      },
      state: {
        mounted: this.mounted, guardClosed: this.guardClosed, homed: this.homed,
        emergencyStop: this.estop, fault: this.fault, running: this.running,
        rpm: rounded(this.rpm), interlocks: [...t.interlocks],
      },
      measurements: this.measurements.map((sample) => ({ ...sample })),
      events: this.events.map((event) => ({ ...event })),
    };
  }
}
