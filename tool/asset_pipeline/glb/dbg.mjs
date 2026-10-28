import puppeteer from 'puppeteer-core'; import path from 'path'; import fs from 'fs'; import { fileURLToPath } from 'url';
const here = path.dirname(fileURLToPath(import.meta.url));
const [,, model, out, ...tints] = process.argv;
const b = await puppeteer.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless:'new', args:['--use-angle=swiftshader','--enable-unsafe-swiftshader','--allow-file-access-from-files','--disable-gpu']});
const p = await b.newPage(); await p.goto('file://'+path.join(here,'page.html')); await p.waitForFunction(()=>window.glb&&window.glb.ready);
const t = tints.length ? {match: tints[0], color: tints[1] || '#ff00ff', dropMap: true} : undefined;
await p.evaluate((u,o)=>window.glb.load(u,o), 'file://'+path.join(here,'models',model+'.glb'), {length:4.5, turn:0, tint:t});
const r = await p.evaluate(()=>window.glb.view({yaw:60, elev:7, ppm:120, ss:1, lamps:[]}));
fs.writeFileSync(out, Buffer.from(r.png,'base64')); await b.close();
