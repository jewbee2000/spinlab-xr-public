import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { handler, resolveRequest } from '../tools/serve.mjs';
test('server exposes app assets but not repository data or traversal', () => {
  assert.ok(resolveRequest('/'));
  assert.ok(resolveRequest('/src/app.js'));
  for (const url of ['/.git/config','/docs/PROJECT_PLAN.md','/package.json','/src/%2e%2e/%2e%2e/.git/config','/src/%5c..%5c.git/config','/%zz']) assert.equal(resolveRequest(url), null, url);
});
test('server provides XR permissions and correct module MIME', async () => {
  const server = http.createServer(handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const url = `http://127.0.0.1:${server.address().port}`;
    const page = await fetch(url);
    assert.equal(page.status,200);
    assert.equal(page.headers.get('permissions-policy'),'xr-spatial-tracking=(self)');
    await page.text();
    const module = await fetch(`${url}/vendor/three.module.js`);
    assert.match(module.headers.get('content-type'),/javascript/);
    await module.text();
    assert.equal((await fetch(`${url}/.git/config`)).status,404);
  } finally { await new Promise(resolve => server.close(resolve)); }
});
