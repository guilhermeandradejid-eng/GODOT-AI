// Quadros de efeitos/juice (passo determinístico): node scripts/juice.cjs
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 640, height: 400 } });
  await p.goto((process.env.URL || 'http://localhost:5180/') + '?hora=tarde');
  await p.waitForFunction(() => window.__game, null, { timeout: 60000 });
  await p.waitForTimeout(2500);
  await p.evaluate(() => {
    const g = __game;
    document.querySelector('.screen').style.display = 'none'; g.ui.hud.style.display = 'none'; g.ui.quest.style.display = 'none';
    const e = g.enemies.find((x) => x.kind === 'slime');
    g.player.place(e.pos.x - 1.1, e.pos.z - 1.1); g.player.facing = Math.PI / 4; g.player.faceS.value = Math.PI / 4;
    e.state = 'idle'; e.hp = 200; e.cd = 99;
    g.camTarget.copy(g.player.pos); g.state = 'pause';
    window.__seq = (fn, n) => { g.state = 'play'; fn && fn(g); for (let i = 0; i < n; i++) { __step(1, 1 / 60); g.fx.update(1 / 60); } g.state = 'pause'; };
  });
  const shots = [];
  const snap = async () => { await p.waitForTimeout(300); shots.push(await p.screenshot()); };
  const run = async (setup, steps, n) => { await p.evaluate(`__seq(${setup}, 1)`); for (let i = 0; i < steps; i++) { await p.evaluate(`__seq(null, ${n})`); await snap(); } };
  await run("(g)=>{ g.player.state='free'; g.player.combo=0; g.player.comboTimer=0; g.input.pressed.add('attack'); }", 6, 3);
  await run("(g)=>{ g.input.pressed.add('attack'); }", 5, 3);
  await run("(g)=>{ g.player.state='free'; g.player.stats.ep=50; g.input.pressed.add('skill'); }", 6, 4);
  await run("(g)=>{ const e=g.enemies.find(x=>x.kind==='slime'&&x.alive); e.hp=1; g.player.state='free'; g.player.combo=0; g.player.comboTimer=0; g.input.pressed.add('attack'); }", 7, 3);
  await b.close();
  fs.mkdirSync('shots/jc', { recursive: true });
  shots.forEach((buf, i) => fs.writeFileSync(`shots/jc/${String(i).padStart(2, '0')}.png`, buf));
  console.log('quadros', shots.length);
})();
