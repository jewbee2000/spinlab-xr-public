import fs from 'node:fs';
import path from 'node:path';
const artifacts = path.resolve('artifacts');
const output = path.join(artifacts, 'spinlab-xr');
if (path.dirname(output) !== artifacts || path.basename(output) !== 'spinlab-xr') {
  throw new Error('Unexpected package output directory');
}
// A fresh output tree prevents obsolete documentation from surviving a rebuild.
fs.rmSync(output, { recursive: true, force: true });
fs.mkdirSync(output, { recursive: true });
for (const entry of ['index.html','icon.svg','package.json','README.md','LICENSE','THIRD_PARTY_NOTICES.md','src','vendor','tools','docs','tests']) {
  fs.cpSync(path.resolve(entry), path.join(output, entry), { recursive:true });
}
console.log(`Portable app: ${output}`);
console.log('Start with: node tools/serve.mjs');
