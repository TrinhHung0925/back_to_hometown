// Chạy trang page.html trong Chrome không đầu, dựng ảnh thô (siêu mẫu) cho từng xe.
//   node render.mjs jobs.json        (jobs.json do build_glb_vehicles.py ghi)
// jobs.json: { out, ss, elev, ppm, jobs: [{name, glb, length, turn, tint, top, lamps, yaws}] }
import puppeteer from 'puppeteer-core';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const here = path.dirname(fileURLToPath(import.meta.url));
const spec = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const only = new Set(process.argv.slice(3));
const chrome = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
fs.mkdirSync(spec.out, { recursive: true });

const browser = await puppeteer.launch({
  executablePath: chrome, headless: 'new',
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--allow-file-access-from-files', '--disable-gpu', '--hide-scrollbars'],
});
const page = await browser.newPage();
page.on('console', m => { const t = m.text(); if (t.startsWith('ERR')) console.log(t); });
page.on('pageerror', e => console.log('PAGEERROR', e.message));
await page.goto('file://' + path.join(here, 'page.html'));
await page.waitForFunction(() => window.glb && window.glb.ready, { timeout: 60000 });

for (const job of spec.jobs) {
  if (only.size && !only.has(job.name)) continue;
  const t0 = Date.now();
  const dims = await page.evaluate((url, o) => window.glb.load(url, o), 'file://' + job.glb, job);
  const meta = { dims, views: {} };
  if (job.top) {
    const r = await page.evaluate(o => window.glb.topdown(o), { ...job.top, ss: spec.ss });
    fs.writeFileSync(`${spec.out}/${job.name}_top.png`, Buffer.from(r.png, 'base64'));
  }
  const L = dims.L, W = dims.W, H = dims.H;
  const l = job.lampSpec || {};
  const lamps = [];
  for (const s of [-1, 1]) {
    lamps.push({ kind: 'tail', x: s * (l.tailX ?? 0.38) * W, y: (l.tailY ?? 0.52) * H, z: L / 2, nx: s * 0.45, nz: 1 });
    lamps.push({ kind: 'head', x: s * (l.headX ?? 0.36) * W, y: (l.headY ?? 0.40) * H, z: -L / 2, nx: s * 0.45, nz: -1 });
  }
  for (const yaw of job.yaws) {
    const r = await page.evaluate(o => window.glb.view(o), { yaw, elev: spec.elev, ppm: spec.ppm, ss: spec.ss, lamps });
    fs.writeFileSync(`${spec.out}/${job.name}_v${yaw}.png`, Buffer.from(r.png, 'base64'));
    meta.views[yaw] = { W: r.W, H: r.H, ground: r.ground, lamps: r.lamps.map((p, i) => ({ kind: lamps[i].kind, x: lamps[i].x, p: p.p, vis: p.vis })) };
  }
  fs.writeFileSync(`${spec.out}/${job.name}.json`, JSON.stringify(meta));
  console.log(`${job.name}: ${((Date.now() - t0) / 1000).toFixed(1)}s  L=${dims.L.toFixed(2)} W=${dims.W.toFixed(2)} H=${dims.H.toFixed(2)}`);
}
await browser.close();
