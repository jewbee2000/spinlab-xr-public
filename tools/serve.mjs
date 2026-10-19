import http from 'node:http';
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const value = (key, fallback) => args.includes(key) ? args[args.indexOf(key) + 1] : fallback;
const port = Number(value('--port', '8080'));
const host = value('--host', '127.0.0.1');
const types = { '.html':'text/html; charset=utf-8', '.js':'text/javascript; charset=utf-8', '.css':'text/css; charset=utf-8', '.svg':'image/svg+xml', '.json':'application/json', '.png':'image/png', '.webmanifest':'application/manifest+json' };
const allowed = new Set(['index.html','icon.svg']);
export function resolveRequest(url) {
  let pathname;
  try { pathname = decodeURIComponent(new URL(url, 'http://localhost').pathname); } catch { return null; }
  const relative = pathname === '/' ? 'index.html' : pathname.slice(1);
  if (relative.includes('\\') || relative.split('/').some(p => p.startsWith('.')) || !(/^(src|vendor)\//.test(relative) || allowed.has(relative))) return null;
  const resolved = path.resolve(root, relative);
  if (!resolved.startsWith(root + path.sep)) return null;
  return resolved;
}
export function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405); res.end(); return; }
  const file = resolveRequest(req.url);
  if (!file || !fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404); res.end('Not found'); return; }
  res.writeHead(200, {
    'Content-Type': types[path.extname(file)] || 'application/octet-stream',
    'Content-Length': fs.statSync(file).size,
    'Cache-Control': 'no-cache',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
    'Permissions-Policy': 'xr-spatial-tracking=(self)',
    'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'"
  });
  if (req.method === 'HEAD') res.end(); else fs.createReadStream(file).pipe(res);
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const cert = value('--cert', null), key = value('--key', null);
  if (Boolean(cert) !== Boolean(key)) throw new Error('Provide both --cert and --key.');
  const server = cert ? https.createServer({ cert: fs.readFileSync(cert), key: fs.readFileSync(key) }, handler) : http.createServer(handler);
  server.on('error', e => { console.error(`SpinLab server: ${e.message}`); process.exitCode = 1; });
  server.listen(port, host, () => {
    console.log(`SpinLab XR: ${cert ? 'https' : 'http'}://${host === '127.0.0.1' ? 'localhost' : host}:${port}`);
    console.log('Quest USB: adb reverse tcp:8080 tcp:8080, then open http://localhost:8080 in Quest Browser.');
    console.log('Keep this terminal open. Press Ctrl+C to stop.');
  });
}
