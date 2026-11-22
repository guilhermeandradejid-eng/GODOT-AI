// Uso: node tools_shot.cjs "<query>" out.png [esperaMs]
const { chromium } = require('playwright');
(async () => {
  const [q = '', out = 'shots/shot.png', wait = '2500', js = ''] = process.argv.slice(2);
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: Number(process.env.DSF || 1) });
  const logs = [];
  p.on('console', (m) => { if (['error', 'warning'].includes(m.type())) logs.push(m.type() + ': ' + m.text()); });
  p.on('pageerror', (e) => logs.push('PAGEERROR: ' + e.message));
  await p.goto((process.env.URL || 'http://localhost:5173/') + q);
  await p.waitForTimeout(Number(wait));
  if (js) { console.log('eval:', await p.evaluate(js)); await p.waitForTimeout(1500); }
  await p.screenshot({ path: out });
  const fps = await p.evaluate(() => new Promise((r) => { let n = 0; const t0 = performance.now(); const f = () => { n++; if (performance.now() - t0 < 2000) requestAnimationFrame(f); else r(n / 2); }; requestAnimationFrame(f); }));
  console.log('fps~', fps);
  console.log(logs.slice(0, 20).join('\n'));
  await b.close();
})();
