// raster.js <svg> <out.png> <px_per_mm>: render an SVG (mm units) on white at an exact scale
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const [,, inp, out, ppmm] = process.argv;
  let svg = fs.readFileSync(inp, 'utf8');
  const m = svg.match(/width="([\d.]+)mm" height="([\d.]+)mm"/);
  const W = Math.round(parseFloat(m[1]) * ppmm), H = Math.round(parseFloat(m[2]) * ppmm);
  svg = svg.replace(m[0], `width="${W}" height="${H}"`);
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: W, height: H } });
  await p.setContent(`<html><body style="margin:0;background:#fff">${svg}</body></html>`);
  await p.screenshot({ path: out, clip: { x: 0, y: 0, width: W, height: H } });
  await b.close();
  console.log(out, W, H);
})();
