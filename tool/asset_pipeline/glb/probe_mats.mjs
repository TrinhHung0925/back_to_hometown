import puppeteer from 'puppeteer-core'; import path from 'path'; import { fileURLToPath } from 'url';
const here = path.dirname(fileURLToPath(import.meta.url));
const b = await puppeteer.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless:'new', args:['--use-angle=swiftshader','--enable-unsafe-swiftshader','--allow-file-access-from-files','--disable-gpu']});
const p = await b.newPage(); await p.goto('file://'+path.join(here,'page.html')); await p.waitForFunction(()=>window.glb&&window.glb.ready);
for (const m of process.argv.slice(2)) {
  const r = await p.evaluate(async (u)=>window.glb.mats(u), 'file://'+path.join(here,'models',m+'.glb'));
  console.log('==',m); for (const x of r) console.log(JSON.stringify(x));
}
await b.close();
