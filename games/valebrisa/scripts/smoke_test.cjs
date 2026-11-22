// Teste de fumaça headless: título → missão completa (vó, gosmas, runa, portão, chefe) → final.
// Uso: npm run build && npx vite preview --port 4173  (em outro terminal)  →  npm test
const { chromium } = require('playwright');
const URL = process.env.URL || 'http://localhost:4173/';
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 960, height: 540 } });
  const errors = [];
  p.on('pageerror', (e) => errors.push(e.message));
  p.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await p.goto(URL);
  await p.waitForFunction(() => window.__game && window.__game.state === 'title', null, { timeout: 60000 });
  const ok = (c, msg) => { console.log((c ? 'ok   ' : 'FAIL ') + msg); if (!c) process.exitCode = 1; };

  ok(await p.isVisible('button[data-act=new]'), 'tela de título com "Novo jogo"');
  await p.click('button[data-act=new]');
  await p.waitForFunction(() => __game.state === 'play', null, { timeout: 20000 });
  ok(true, 'jogo começou');

  // helpers dentro da página
  await p.evaluate(() => {
    window.__t = {
      near(obj, dx = 1, dz = 0.6) { const g = __game; g.player.pos.x = obj.pos.x + dx; g.player.pos.z = obj.pos.z + dz; g.player.state = 'free'; },
      async talk(npc) {
        const g = __game; this.near(npc); g.player.facing = g.player.angleTo(npc.pos);
        const pr = g.talkTo(npc);
        for (let i = 0; i < 40 && g.ui.inDialog; i++) { g.ui.advance(); g.ui.advance(); await new Promise((r) => setTimeout(r, 5)); }
        await pr;
      },
    };
  });

  // 1) falar com a Vó Amora
  await p.evaluate(() => __t.talk(__game.amora));
  ok(await p.evaluate(() => __game.quest.stage) === 1, 'Vó Amora deu a missão das gosmas');

  // 2) combate real: combo de espada acerta uma gosma
  const hit = await p.evaluate(() => {
    const g = __game, e = g.enemies.find((x) => x.kind === 'slime' && x.alive);
    g.player.pos.set(e.pos.x - 0.9, e.pos.y, e.pos.z); g.player.facing = Math.PI / 2; e.state = 'idle'; e.st = 0;
    const hp0 = e.hp;
    g.input.pressed.add('attack'); __step(20);
    return [hp0, e.hp, g.player.combo];
  });
  ok(hit[1] < hit[0], `espada causou dano (${hit[0]} → ${hit[1]})`);

  // rolamento dá invulnerabilidade
  const roll = await p.evaluate(() => { const g = __game; g.player.state = 'free'; g.input.pressed.add('roll'); __step(2); return [g.player.state, g.player.invuln > 0]; });
  ok(roll[0] === 'roll' && roll[1], 'rolamento com invulnerabilidade');

  // 3) derrotar gosmas → voltar
  const st2 = await p.evaluate(() => {
    const g = __game;
    for (const e of g.enemies.filter((x) => x.kind === 'slime' && x.alive).slice(0, 7)) g.hitEnemy(e, 999, g.player.pos, 1, false);
    __step(60);
    return [g.quest.stage, g.quest.slimes, g.player.stats.level, g.pickups.length];
  });
  ok(st2[0] === 2, `6 gosmas derrotadas (contagem ${st2[1]}, nível ${st2[2]})`);
  await p.evaluate(() => __t.talk(__game.amora));
  ok(await p.evaluate(() => __game.quest.stage) === 3, 'missão da runa recebida');

  // 4) baú preso até derrotar os fungões
  const chest1 = await p.evaluate(async () => { const g = __game; __t.near(g.chest, 0.9, 0.4); g.openChest(); for (let i = 0; i < 5; i++) { g.ui.advance(); g.ui.advance(); } await new Promise((r) => setTimeout(r, 20)); return g.chest.opened; });
  ok(!chest1, 'baú preso por raízes com fungões vivos');
  const chest2 = await p.evaluate(() => { const g = __game; for (const e of g.camps.find((c) => c.hollow).list) if (e.alive) g.hitEnemy(e, 999, g.player.pos, 1, false); __step(10); g.openChest(); return [g.chest.opened, g.quest.rune, g.quest.stage]; });
  ok(chest2[0] && chest2[1] && chest2[2] === 4, 'runa obtida do baú');

  // 5) portão
  const gate = await p.evaluate(() => { const g = __game; g.useGate(); __step(30); return [g.quest.gate, g.scenery.gate.collider.off, g.quest.stage]; });
  ok(gate[0] && gate[1] && gate[2] === 5, 'portão do bosque aberto');

  // 6) chefe: entrar na clareira, esperar a introdução, derrotar
  const boss = await p.evaluate(() => {
    const g = __game, c = g.arenaCenter;
    g.player.pos.set(c.x + 3.5, c.y, c.z + 3.5); g.player.stats.hp = 9999; g.player.stats.maxHp = 9999;
    __step(200);
    const s1 = g.boss.state, locked = !g.arenaLock.off;
    for (let i = 0; i < 400 && g.boss.alive; i++) { __step(3); if (g.boss.state !== 'intro' && g.boss.state !== 'dormant') g.hitEnemy(g.boss, 40, g.player.pos, 1, false); }
    __step(30);
    return [s1, locked, g.boss.alive, g.quest.stage, g.arenaLock.off];
  });
  ok(boss[0] !== 'dormant' && boss[1], `chefe acordou e trancou a arena (estado ${boss[0]})`);
  ok(!boss[2] && boss[3] === 6 && boss[4], 'Toco Ancião derrotado, arena destrancada');

  // 7) final
  await p.evaluate(() => __t.talk(__game.amora));
  ok(await p.evaluate(() => __game.state) === 'ending', 'tela final exibida');
  ok(await p.isVisible('.screen.ending'), 'painel de vitória visível');

  // 8) salvar
  ok(await p.evaluate(() => { try { return JSON.parse(localStorage.getItem('valebrisa-save-v1')).quest.stage === 7; } catch { return false; } }), 'progresso salvo no localStorage');

  ok(errors.length === 0, 'sem erros no console' + (errors.length ? ': ' + errors.slice(0, 3).join(' | ') : ''));
  await b.close();
})();
