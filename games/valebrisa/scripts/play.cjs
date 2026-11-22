// Roteiro de teste: node scripts/play.cjs roteiro.json
// passos: {wait}, {key, ms}, {down}, {up}, {eval}, {shot}, {click}
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const steps = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const mobile = !!process.env.MOBILE;
  const p = await b.newPage({ viewport: { width: Number(process.env.VW || (mobile ? 844 : 1280)), height: Number(process.env.VH || (mobile ? 390 : 720)) }, hasTouch: mobile, isMobile: mobile, deviceScaleFactor: mobile ? 2 : 1 });
  const logs = [];
  p.on('console', (m) => { if (['error', 'warning'].includes(m.type()) && !/GPU stall|Clock/.test(m.text())) logs.push(m.type() + ': ' + m.text()); });
  p.on('pageerror', (e) => logs.push('PAGEERROR: ' + e.message));
  await p.goto(process.env.URL || 'http://localhost:5180/');
  for (const s of steps) {
    if (s.wait) await p.waitForTimeout(s.wait);
    if (s.click) await p.click(s.click);
    if (s.tap) await p.tap(s.tap);
    if (s.tapxy) await p.touchscreen.tap(s.tapxy[0], s.tapxy[1]);
    if (s.key) { await p.keyboard.down(s.key); await p.waitForTimeout(s.ms || 80); await p.keyboard.up(s.key); }
    if (s.down) await p.keyboard.down(s.down);
    if (s.up) await p.keyboard.up(s.up);
    if (s.eval) console.log('eval:', JSON.stringify(await p.evaluate(s.eval)));
    if (s.shot) await p.screenshot({ path: s.shot });
  }
  console.log(logs.slice(0, 30).join('\n'));
  await b.close();
})();
