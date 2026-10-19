/**
 * Visible-control browser smoke test; run against `npm start` in another shell.
 *
 * npm install --no-save playwright
 * node tests/browser-smoke.mjs
 *
 * Optional: SPINLAB_URL, PLAYWRIGHT_MODULE (package name or absolute module
 * path), PLAYWRIGHT_CHANNEL (default msedge), PLAYWRIGHT_EXECUTABLE_PATH.
 * No XR hardware is emulated. Telemetry is inspected through read-only QA APIs;
 * every change to station state passes through its rendered buttons/sliders.
 */
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { isAbsolute } from 'node:path';
import { pathToFileURL } from 'node:url';

const moduleName = process.env.PLAYWRIGHT_MODULE || 'playwright';
const importName = isAbsolute(moduleName) ? pathToFileURL(moduleName).href : moduleName;
let chromium;
try {
  ({ chromium } = await import(importName));
} catch (error) {
  throw new Error('Install Playwright, or set PLAYWRIGHT_MODULE to its absolute index.mjs path.', { cause: error });
}
const launchOptions = {
  headless: true,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
};
if (process.env.PLAYWRIGHT_EXECUTABLE_PATH) launchOptions.executablePath = process.env.PLAYWRIGHT_EXECUTABLE_PATH;
else launchOptions.channel = process.env.PLAYWRIGHT_CHANNEL || 'msedge';
const browser = await chromium.launch(launchOptions);
const context = await browser.newContext({ viewport: { width: 1365, height: 900 }, acceptDownloads: true });
const page = await context.newPage();
const errors = [];
page.on('pageerror', (error) => errors.push(error.message));
page.on('console', (message) => { if (message.type() === 'error') errors.push(message.text()); });
page.on('requestfailed', (request) => errors.push(`${request.method()} ${request.url()}: ${request.failure()?.errorText}`));
const press = (name) => page.locator(`[data-action="${name}"]`).click();
const telemetry = () => page.evaluate(() => window.spinlab.getTelemetry());
const waitForTelemetry = (predicate) => page.waitForFunction(predicate, null, { timeout: 120_000 });
async function slider(id, value) {
  const input = page.locator(`#${id}`);
  await input.scrollIntoViewIfNeeded();
  // Input events are the same application path used by a pointer or keyboard.
  await input.evaluate((element, nextValue) => {
    element.value = String(nextValue);
    element.dispatchEvent(new Event('input', { bubbles: true }));
  }, value);
}
async function saveReport() {
  const downloadPromise = page.waitForEvent('download');
  await press('report');
  const download = await downloadPromise;
  assert.equal(download.suggestedFilename(), 'spinlab-session.json');
  const report = JSON.parse(await readFile(await download.path(), 'utf8'));
  const persisted = await page.evaluate(() => JSON.parse(localStorage.getItem('spinlab-last-report')));
  assert.deepEqual(persisted, report, 'download matches the browser-persisted report');
  return report;
}

try {
  await page.goto(process.env.SPINLAB_URL || 'http://localhost:8080', { waitUntil: 'networkidle' });
  await page.waitForFunction(() => !!window.spinlab);
  assert.equal(await page.locator('#fatal').isVisible(), false);
  assert.equal((await telemetry()).mounted, false);
  await press('run');
  assert.match(await page.locator('#status').innerText(), /Mount rotor/);
  assert.equal((await telemetry()).running, false);
  await slider('mass', 0.6);
  assert.equal((await telemetry()).massGrams, 0, 'mass change is blocked before loading');
  await press('mount');
  await press('home');
  await slider('probe', 7);
  await press('guard');
  await press('run');
  assert.equal((await telemetry()).running, false, 'bad probe position blocks acquisition');
  await slider('probe', 6);
  await press('run');
  assert.equal((await telemetry()).running, true);
  await slider('mass', 0.6);
  assert.equal((await telemetry()).massGrams, 0, 'running sweep rejects correction changes');
  console.log('Baseline acquisition started; waiting for simulated sweep and coast-down.');
  await waitForTelemetry(() => window.spinlab.getTelemetry().complete);
  let t = await telemetry();
  assert.equal(t.passed, false);
  assert.equal(t.rpm, 0);
  assert.equal(t.samples, 49);
  assert.ok(t.peak > 0);
  await page.waitForFunction(() => document.getElementById('result').textContent.includes('CORRECTION REQUIRED'));
  assert.match(await page.locator('#result').innerText(), /CORRECTION REQUIRED/);
  assert.equal(await page.evaluate(() => window.spinlab.getRuns().length), 1);

  // The guard must be open for installing trim mass, then closed for the run.
  await slider('mass', 0.6);
  assert.equal((await telemetry()).massGrams, 0, 'closed guard rejects correction changes');
  await press('guard');
  await slider('mass', 0.6);
  await slider('angle', 300);
  t = await telemetry();
  assert.equal(t.massGrams, 0.6);
  assert.equal(t.massAngle, 300);
  assert.equal(t.residual, 0);
  assert.equal(t.complete, false, 'correction invalidates earlier acquisition');
  assert.equal(t.passed, false, 'zero simulated residual still requires verification');
  await press('guard');
  await press('run');
  console.log('Corrected acquisition started; waiting for verification.');
  await waitForTelemetry(() => window.spinlab.getTelemetry().passed);
  await page.waitForFunction(() => document.getElementById('result').textContent.includes('VERIFIED'));
  assert.match(await page.locator('#result').innerText(), /VERIFIED/);
  assert.equal(await page.evaluate(() => window.spinlab.getRuns().length), 2);
  const verified = await saveReport();
  assert.equal(verified.latest.measuredResults.passed, true);
  assert.equal(verified.completedRuns.length, 2);
  assert.equal(verified.completedRuns[0].measuredResults.passed, false);
  assert.equal(verified.completedRuns[1].measuredResults.passed, true);
  assert.equal(verified.latest.balance.correction.massGrams, 0.6);
  assert.equal(verified.latest.balance.correction.angleDeg, 300);
  assert.equal(verified.latest.measurements.length, 49);
  assert.equal(verified.latest.units.imbalance, 'g·mm');

  await press('fault');
  t = await telemetry();
  assert.equal(t.fault, 'sensor');
  assert.equal(t.homed, false);
  assert.equal(t.passed, false);
  await press('run');
  assert.equal((await telemetry()).running, false);
  await press('recover');
  await press('run');
  assert.equal((await telemetry()).running, false, 'fault reset does not replace probe homing');
  await press('home');
  await press('run');
  await waitForTelemetry(() => window.spinlab.getTelemetry().rpm > 100);
  await press('estop');
  t = await telemetry();
  assert.equal(t.estop, true);
  assert.equal(t.targetRpm, 0);
  assert.equal(t.running, false);
  assert.equal(t.passed, false);
  await press('recover');
  assert.equal((await telemetry()).estop, false);
  assert.equal((await telemetry()).fault, 'emergency-stop', 'releasing E-stop does not reset the fault');
  await waitForTelemetry(() => window.spinlab.getTelemetry().rpm === 0);
  await press('recover');
  assert.equal((await telemetry()).fault, null);

  await press('run');
  await waitForTelemetry(() => window.spinlab.getTelemetry().rpm > 100);
  await press('guard');
  t = await telemetry();
  assert.equal(t.fault, 'guard');
  assert.equal(t.targetRpm, 0);
  assert.equal(t.complete, false);
  await waitForTelemetry(() => window.spinlab.getTelemetry().rpm === 0);
  await press('recover');
  assert.equal((await telemetry()).fault, 'guard', 'open guard prevents resetting guard fault');
  await press('guard');
  await press('recover');
  assert.equal((await telemetry()).fault, null);
  const faulted = await saveReport();
  assert.equal(faulted.latest.measuredResults.passed, false, 'aborted run cannot export a stale passing result');
  assert.equal(faulted.latest.measuredResults.complete, false);
  assert.equal(faulted.completedRuns.length, 2, 'historical completed sweeps remain in report');
  assert.ok(faulted.latest.events.some((event) => event.type === 'fault-latched' && event.kind === 'guard'));

  await page.locator('#exploded-button').click();
  assert.match(await page.locator('#exploded-button').innerText(), /Return to assembly/);
  await page.locator('#exploded-button').click();
  await page.locator('#help-button').click();
  assert.equal(await page.locator('#help').isVisible(), true);
  await page.locator('#close-help').click();
  for (const size of [{ width: 1365, height: 900 }, { width: 900, height: 900 }, { width: 390, height: 844 }]) {
    await page.setViewportSize(size);
    await page.locator('[data-action="report"]').scrollIntoViewIfNeeded();
    const bounds = await page.locator('.console').boundingBox();
    assert.ok(bounds.x >= 0 && bounds.x + bounds.width <= size.width + 1, `console fits ${size.width}px viewport`);
    assert.equal(await page.locator('[data-action="report"]').isVisible(), true);
    assert.equal(await page.locator('#fatal').isVisible(), false);
  }
  const persistedBeforeReload = await page.evaluate(() => localStorage.getItem('spinlab-last-report'));
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForFunction(() => !!window.spinlab);
  assert.equal(await page.evaluate(() => localStorage.getItem('spinlab-last-report')), persistedBeforeReload, 'saved report bytes survive reload');
  assert.equal((await telemetry()).mounted, false, 'reload starts a new station session');
  const savedReportButton = page.getByRole('button', { name: 'Saved report' });
  assert.equal(await savedReportButton.isVisible(), true, 'previous report can be retrieved after reload');
  const preservedDownload = page.waitForEvent('download');
  await savedReportButton.click();
  const restoredReport = JSON.parse(await readFile(await (await preservedDownload).path(), 'utf8'));
  assert.deepEqual(restoredReport, JSON.parse(persistedBeforeReload), 'retrieving saved report preserves the earlier measurements');
  await press('reset');
  assert.equal(await page.evaluate(() => localStorage.getItem('spinlab-last-report')), persistedBeforeReload, 'new session preserves saved report');
  for (const id of ['enter-vr']) {
    const bounds = await page.locator(`#${id}`).boundingBox();
    assert.ok(bounds.x >= 0 && bounds.x + bounds.width <= 391, `${id} remains within narrow viewport with saved report present`);
  }
  assert.deepEqual(errors, [], 'no JavaScript, console, or network errors');
  console.log('PASS: visible controls, baseline, correction, verification, JSON persistence, faults, E-stop, responsive layouts, and browser error checks. Native XR hardware remains untested.');
} finally {
  await browser.close();
}
