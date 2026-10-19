import test from 'node:test';
import assert from 'node:assert/strict';
import { SpinLabSimulation, SIMULATION_CONSTANTS as C, normalizeAngleDeg } from '../src/simulation.js';

function ready(seed = 42) {
  const simulation = new SpinLabSimulation({ seed });
  assert.equal(simulation.mountRotor().ok, true);
  assert.equal(simulation.homeProbe().ok, true);
  assert.equal(simulation.toggleGuard().ok, true);
  return simulation;
}

function completeSweep(simulation) {
  assert.equal(simulation.startSweep().ok, true);
  simulation.tick(C.sweepDurationSeconds + C.targetRpm / C.decelerationRpmPerSecond + 0.1);
  assert.equal(simulation.getTelemetry().complete, true);
}

test('start requires rotor, guard, homing, valid probe, and zero-speed interlocks', () => {
  const s = new SpinLabSimulation();
  assert.equal(s.startSweep().ok, false);
  assert.deepEqual(s.getTelemetry().interlocks, ['Mount rotor', 'Close guard', 'Home probe']);
  s.mountRotor();
  assert.equal(s.startSweep().ok, false);
  s.toggleGuard();
  assert.equal(s.startSweep().ok, false);
  s.homeProbe();
  s.setProbePosition(7);
  assert.equal(s.startSweep().ok, false);
  s.setProbePosition(6.5);
  assert.equal(s.startSweep().ok, true);
  assert.equal(s.startSweep().ok, false);
});

test('guard opens remove drive and latch a fault until stopped and guard restored', () => {
  const s = ready();
  s.startSweep();
  s.tick(2);
  assert.ok(s.rpm > 0);
  assert.equal(s.toggleGuard().ok, false);
  assert.equal(s.targetRpm, 0);
  assert.equal(s.running, false);
  assert.equal(s.fault, 'guard');
  assert.equal(s.resetFault().ok, false);
  s.tick(2);
  assert.equal(s.rpm, 0);
  assert.equal(s.resetFault().ok, false);
  s.toggleGuard();
  assert.equal(s.resetFault().ok, true);
  assert.equal(s.getTelemetry().complete, false);
  assert.equal(s.getTelemetry().passed, false);
  assert.equal(s.startSweep().ok, true);
});

test('emergency stop cannot be reset until released, and release does not restart', () => {
  const s = ready();
  s.startSweep();
  s.tick(5);
  s.emergencyStop();
  assert.equal(s.estop, true);
  assert.equal(s.targetRpm, 0);
  assert.equal(s.resetFault().ok, false);
  s.tick(3);
  assert.equal(s.resetFault().ok, false);
  assert.equal(s.startSweep().ok, false);
  assert.equal(s.releaseEstop().ok, true);
  assert.equal(s.running, false);
  assert.equal(s.startSweep().ok, false);
  assert.equal(s.resetFault().ok, true);
  assert.equal(s.startSweep().ok, true);
});

test('sensor fault aborts acquisition and requires rehoming after reset', () => {
  const s = ready();
  s.startSweep();
  s.tick(1);
  s.injectFault();
  assert.equal(s.fault, 'sensor');
  assert.equal(s.homed, false);
  assert.equal(s.targetRpm, 0);
  assert.equal(s.homeProbe().ok, false);
  s.tick(2);
  assert.equal(s.resetFault().ok, true);
  assert.equal(s.startSweep().ok, false);
  s.homeProbe();
  assert.equal(s.startSweep().ok, true);
});

test('correction requires a mounted stationary rotor and an open guard', () => {
  const s = new SpinLabSimulation();
  assert.equal(s.setCorrection(0.6, 300).ok, false);
  s.mountRotor();
  assert.equal(s.setCorrection(0.6, -60).ok, true);
  assert.equal(s.massAngle, 300);
  s.homeProbe();
  s.toggleGuard();
  assert.equal(s.setCorrection(0.5, 300).ok, false);
  s.startSweep();
  s.tick(1);
  s.stop();
  s.toggleGuard();
  assert.equal(s.setCorrection(0.5, 300).ok, false);
  s.tick(1);
  s.resetFault();
  assert.equal(s.setCorrection(0.5, 300).ok, false, 'guard fault must be reset with guard closed');
  s.toggleGuard();
  s.resetFault();
  s.toggleGuard();
  assert.equal(s.setCorrection(0.5, 300).ok, true);
});

test('unbalanced sweep crosses resonance, samples deterministically, stops automatically, and fails balance', () => {
  const s = ready();
  s.startSweep();
  s.tick(5);
  assert.ok(Math.abs(s.rpm - 1800) < 1e-7);
  assert.ok(s.getTelemetry().peak > s.getTelemetry().vibration, 'resonance produces a peak during the speed ramp');
  s.tick(7);
  assert.equal(s.running, false);
  assert.equal(s.targetRpm, 0);
  assert.equal(s.getTelemetry().complete, false, 'wait for coast-down before marking the sweep complete');
  s.tick(2.01);
  const t = s.getTelemetry();
  assert.equal(t.rpm, 0);
  assert.equal(t.complete, true);
  assert.equal(t.passed, false);
  assert.ok(Math.abs(t.residual - 18) < 1e-10);
  assert.ok(Math.abs(t.phase - 120) < 1e-10);
  assert.equal(t.samples, 49);
  assert.equal(s.measurements.at(-1).time, 12);
  assert.ok(t.rms > 0 && t.peak > 0);
});

test('opposing correction cancels imbalance; in-phase correction doubles it', () => {
  const s = ready();
  s.toggleGuard();
  s.setCorrection(0.6, 120);
  assert.ok(Math.abs(s.getTelemetry().residual - 36) < 1e-10);
  s.setCorrection(0.6, 300);
  assert.equal(s.getTelemetry().residual, 0);
  s.toggleGuard();
  completeSweep(s);
  assert.equal(s.getTelemetry().passed, true);
  assert.equal(s.getTelemetry().peak, 0);
  assert.equal(s.getTelemetry().phase, 0, 'phase is defined as zero for a cancelled vector');
});

test('a result cannot pass before a complete sweep, or remain passed after correction or probe changes', () => {
  const s = ready();
  s.toggleGuard();
  s.setCorrection(0.6, 300);
  assert.equal(s.getTelemetry().passed, false);
  s.toggleGuard();
  completeSweep(s);
  assert.equal(s.getTelemetry().passed, true);
  s.setProbePosition(6.2);
  assert.equal(s.getTelemetry().complete, false);
  assert.equal(s.exportReport().measuredResults.passed, false);
  completeSweep(s);
  s.toggleGuard();
  s.setCorrection(0.5, 300);
  assert.equal(s.getTelemetry().passed, false);
  assert.equal(s.getTelemetry().complete, false);
  s.toggleGuard();
  completeSweep(s);
  assert.equal(s.getTelemetry().passed, false, '3 g·mm exceeds the fictional training limit');
});

test('manual stop coasts to zero without creating a completed test', () => {
  const s = ready();
  s.startSweep();
  s.tick(2);
  const speed = s.rpm;
  s.stop();
  assert.equal(s.targetRpm, 0);
  assert.ok(speed > 0);
  assert.equal(s.startSweep().ok, false);
  s.tick(0.1);
  assert.ok(s.rpm < speed && s.rpm > 0);
  s.tick(10);
  assert.equal(s.rpm, 0);
  assert.equal(s.getTelemetry().complete, false);
  assert.equal(s.getTelemetry().passed, false);
});

test('same seed and actions yield the same detached report, independent of clock or tick partition', () => {
  const a = ready(123);
  const b = ready(123);
  a.startSweep();
  b.startSweep();
  a.tick(15);
  for (let i = 0; i < 1500; i++) b.tick(0.01);
  assert.deepEqual(a.exportReport(), b.exportReport());
  const report = a.exportReport();
  assert.equal(report.schema, 'spinlab-xr/balance-report');
  assert.equal(report.schemaVersion, '1.0.0');
  assert.equal(report.trainingOnly, true);
  assert.ok(report.phaseConvention.includes('180 degrees opposite'));
  assert.doesNotThrow(() => JSON.stringify(report));
  report.measurements[0].rpm = 99;
  report.events[0].type = 'changed';
  assert.equal(a.measurements[0].rpm, 0);
  assert.equal(a.events[0].type, 'reset');
});

test('different seeds vary sensor samples without changing physical truth', () => {
  const a = ready(1);
  const b = ready(2);
  completeSweep(a);
  completeSweep(b);
  assert.equal(a.getTelemetry().residual, b.getTelemetry().residual);
  assert.notDeepEqual(a.measurements, b.measurements);
});

test('invalid numeric inputs are rejected without poisoning state', () => {
  const s = new SpinLabSimulation();
  assert.equal(s.setProbePosition(NaN).ok, false);
  assert.equal(s.setProbePosition(13).ok, false);
  assert.equal(s.setCorrection(-1, 0).ok, false);
  assert.equal(s.setCorrection(3, 0).ok, false);
  assert.equal(s.setCorrection(1, Infinity).ok, false);
  assert.equal(s.injectFault('').ok, false);
  assert.throws(() => s.tick(-1), RangeError);
  assert.throws(() => s.tick(Infinity), RangeError);
  assert.throws(() => normalizeAngleDeg(NaN), RangeError);
  assert.equal(normalizeAngleDeg(720), 0);
  assert.equal(normalizeAngleDeg(-90), 270);
  assert.equal(s.sensorPosition, 6);
  assert.equal(s.massGrams, 0);
  assert.equal(s.tick(0).rpm, 0);
});

test('reset clears run data, faults, emergency stop, correction, and simulated time', () => {
  const s = ready();
  s.startSweep();
  s.tick(1);
  s.emergencyStop();
  s.reset();
  assert.equal(s.time, 0);
  assert.equal(s.mounted, false);
  assert.equal(s.homed, false);
  assert.equal(s.estop, false);
  assert.equal(s.fault, null);
  assert.equal(s.rpm, 0);
  assert.equal(s.measurements.length, 0);
  assert.equal(s.events.length, 1);
  assert.equal(s.getTelemetry().passed, false);
});
