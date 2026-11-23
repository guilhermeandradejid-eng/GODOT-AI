// Gera folhas de quadros da animação do herói (passo determinístico): node scripts/frames.cjs saida.png
const { chromium } = require('playwright');
(async () => {
  const out = process.argv[2] || 'shots/frames.png';
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 480, height: 300 } });
  await p.goto((process.env.URL || 'http://localhost:5180/') + '?hora=tarde');
  await p.waitForFunction(() => window.__game, null, { timeout: 60000 });
  await p.waitForTimeout(2500);
  await p.evaluate(() => {
    const g = __game; g.pr.pixelScaleOverride = 4; g.pr.resize(); g.ui.applyScale();
    document.querySelector('.screen').style.display = 'none'; g.ui.hud.style.display = 'none'; g.ui.quest.style.display = 'none';
    const c = g.arenaCenter; g.player.place(c.x + 4, c.z + 4); g.camTarget.copy(g.player.pos); g.state = 'pause';
    g.boss.state = 'gone'; g.boss.obj.visible = false;
    window.__seq = (fn, n, dt) => { g.state = 'play'; fn && fn(g); __step(n, dt); g.state = 'pause'; g.camTarget.copy(g.player.pos); g.camTarget.y += 0.6; };
  });
  const shots = [];
  const snap = async () => { await p.waitForTimeout(350); shots.push(await p.screenshot()); };
  const seqs = [
    // caminhar para a direita da tela
    { setup: (g) => { g.input.held.add('right'); g.input.held.add('down'); }, steps: 10, n: 4, dt: 1 / 60 },
    { setup: (g) => { g.input.held.clear(); g.player.state = 'free'; g.player.combo = 0; g.player.comboTimer = 0; g.input.pressed.add('attack'); }, steps: 8, n: 2, dt: 1 / 60 },
    { setup: (g) => { g.input.held.clear(); g.player.state = 'free'; g.player.rollCd = 0; g.input.pressed.add('roll'); }, steps: 8, n: 3, dt: 1 / 60 },
  ];
  for (const s of seqs) {
    await p.evaluate(`__seq(${s.setup.toString()}, 1, 1/60)`);
    for (let i = 0; i < s.steps; i++) { await p.evaluate(`__seq(null, ${s.n}, ${s.dt})`); await snap(); }
  }
  await b.close();
  const fs = require('fs');
  fs.mkdirSync('shots/fr', { recursive: true });
  shots.forEach((buf, i) => fs.writeFileSync(`shots/fr/${String(i).padStart(2, '0')}.png`, buf));
  console.log('quadros', shots.length);
})();
