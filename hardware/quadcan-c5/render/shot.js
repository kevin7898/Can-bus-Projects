// shot.js <outdir> <view> [w h]: render the three.js scene headless and save a PNG
const { chromium } = require('playwright');
(async () => {
  const [,, outdir, view, w = '2400', h = '1500'] = process.argv;
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: +w, height: +h } });
  p.on('console', m => { if (m.type() === 'error') console.log('console:', m.text()); });
  p.on('pageerror', e => console.log('pageerror:', e.message));
  await p.goto(`http://127.0.0.1:8765/index.html?view=${view}`);
  await p.waitForFunction(() => window.__done === true, null, { timeout: 180000 });
  await p.screenshot({ path: `${outdir}/3d-${view}.png` });
  await b.close();
  console.log('ok', view);
})();
