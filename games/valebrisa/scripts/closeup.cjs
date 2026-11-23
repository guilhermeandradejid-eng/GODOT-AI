// Close de personagens: node scripts/closeup.cjs out.png "<js antes>" [esperaMs]
// renderiza com pixel 6x numa janela pequena para ver detalhes
const { chromium } = require('playwright');
(async () => {
  const [out = 'shots/close.png', js = '', wait = '2500'] = process.argv.slice(2);
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 960, height: 540 } });
  const logs = [];
  p.on('pageerror', (e) => logs.push('PAGEERROR: ' + e.message));
  p.on('console', (m) => { if (m.type() === 'error') logs.push(m.text()); });
  await p.goto((process.env.URL || 'http://localhost:5180/') + '?hora=tarde');
  await p.waitForFunction(() => window.__game, null, { timeout: 60000 });
  await p.waitForTimeout(3000);
  console.log(await p.evaluate(`(()=>{ const g=__game; g.pr.pixelScaleOverride=5; g.pr.resize(); g.ui.applyScale(); document.querySelector('.screen').style.display='none'; g.ui.hud.style.display='none'; g.ui.quest.style.display='none'; g.state='play'; ${js}; return 1 })()`));
  await p.waitForTimeout(Number(wait));
  await p.screenshot({ path: out });
  console.log(logs.slice(0, 10).join('\n'));
  await b.close();
})();
