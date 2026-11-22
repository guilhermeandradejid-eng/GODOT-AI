// Uso: node scripts/shot.cjs "<query>" out.png [esperaMs] [js]
const { chromium } = require('playwright');
(async () => {
  const [q = '', out = 'shots/shot.png', wait = '2500', js = ''] = process.argv.slice(2);
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: Number(process.env.VW || 1280), height: Number(process.env.VH || 720) }, deviceScaleFactor: Number(process.env.DSF || 1) });
  const logs = [];
  p.on('console', (m) => { if (['error', 'warning'].includes(m.type()) && !m.text().includes('GPU stall')) logs.push(m.type() + ': ' + m.text()); });
  p.on('pageerror', (e) => logs.push('PAGEERROR: ' + e.message));
  await p.goto((process.env.URL || 'http://localhost:5180/') + q);
  await p.waitForTimeout(Number(wait));
  if (js) { console.log('eval:', await p.evaluate(js)); await p.waitForTimeout(Number(process.env.AFTER || 2500)); }
  await p.screenshot({ path: out });
  console.log(logs.slice(0, 20).join('\n'));
  await b.close();
})();
