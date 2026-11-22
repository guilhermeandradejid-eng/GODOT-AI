// Teste de fumaça headless: menu → entrar 2 jogadores → consertar cabo → apagar fogo → fim do expediente.
// Uso: npm run build && npx vite preview --port 4173  (em outro terminal)  →  node scripts/smoke_test.cjs
const { chromium } = require('playwright');
const URL = process.env.URL || 'http://localhost:4173/';
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  const errors = [];
  p.on('pageerror', (e) => errors.push(e.message));
  p.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await p.goto(URL);
  await p.waitForTimeout(1500);
  const ok = (c, msg) => { console.log((c ? 'ok   ' : 'FAIL ') + msg); if (!c) process.exitCode = 1; };

  // entrar pelo teclado (E e Enter) e começar com Espaço
  await p.keyboard.press('KeyE'); await p.waitForTimeout(700);
  await p.keyboard.press('Enter'); await p.waitForTimeout(700);
  ok(await p.evaluate(() => __game.joined.length) === 2, 'dois técnicos entraram pelo teclado');
  await p.keyboard.press('Space'); await p.waitForTimeout(700);
  ok(await p.evaluate(() => __game.players.length) === 2, 'partida começou com 2 jogadores');

  const r = await p.evaluate(() => {
    const g = __game, step = __step, out = {};
    step(240); // contagem regressiva
    out.state = g.state;
    const T = g.tickets; T.script = []; T.nextAt = 1e9;
    for (const t of [...T.open]) T.fail(t);
    const P = g.players[0];
    const goTo = (x, z) => {
      for (let i = 0; i < 900; i++) {
        const dx = x - P.pos.x, dz = z - P.pos.z, d = Math.hypot(dx, dz);
        if (d < 0.15) break;
        g.inputOverride.kbA = { x: dx / d, z: dz / d }; step(1);
      }
      g.inputOverride.kbA = {}; step(3);
    };
    const face = (x, z) => { P.angle = Math.atan2(x - P.pos.x, z - P.pos.z); };
    const press = (k) => { g.inputOverride.kbA = { [k]: true, ...(k === 'use' ? { usePressed: true } : {}) }; step(1); g.inputOverride.kbA = {}; step(2); };
    // cabo
    const desk = g.desks[0];
    T.spawn('cable', desk);
    goTo(-10.9, -6.1); face(-10.9, -7); press('grab');
    out.gotCable = P.held?.kind;
    goTo(-6.0, -3.2); goTo(desk.pos.x + 1.25, desk.pos.z + 0.4); face(desk.pos.x, desk.pos.z);
    for (let i = 0; i < 200 && desk.problem; i++) { g.inputOverride.kbA = { use: true }; step(1); }
    g.inputOverride.kbA = {};
    out.cableFixed = !desk.problem; out.score1 = g.score;
    // fogo com extintor
    const pr = g.stations.find((s) => s.name === 'Impressora 1');
    T.spawn('fire', pr);
    const ext = g.items.find((i) => i.kind === 'extinguisher');
    goTo(ext.pos.x + 0.6, ext.pos.z + 0.6); face(ext.pos.x, ext.pos.z); press('grab');
    out.gotExt = P.held?.kind;
    goTo(pr.pos.x, pr.pos.z + 1.6); face(pr.pos.x, pr.pos.z);
    for (let i = 0; i < 400 && pr.problem; i++) { g.inputOverride.kbA = { use: true }; step(1); }
    g.inputOverride.kbA = {};
    out.fireOut = !pr.problem; out.score2 = g.score;
    // arremesso para o colega
    const P2 = g.players[1];
    P.drop(g); step(2);
    P.grab(g.spawnItem('paper', P.pos.clone()), g);
    P2.pos.set(P.pos.x, 0, P.pos.z + 3); P.angle = 0; step(1);
    press('use');
    step(60);
    out.caught = P2.held?.kind;
    // internet + vírus espalhando
    T.spawn('router'); const vt = T.spawn('virus', g.desks[4]);
    vt.remaining = vt.sla * 0.44; step(2);
    out.virusSpread = T.open.filter((t) => t.type === 'virus').length;
    out.netDown = T.routerDown;
    // resto do expediente
    T.nextAt = T.elapsed + 1;
    for (let i = 0; i < 200 && g.state === 'playing'; i++) step(60);
    out.end = g.state; out.stats = g.stats;
    return out;
  });
  console.log(JSON.stringify(r));
  ok(r.state === 'playing', 'contagem regressiva termina');
  ok(r.gotCable === 'cable', 'pega cabo na prateleira');
  ok(r.cableFixed && r.score1 > 0, 'troca o cabo e pontua');
  ok(r.gotExt === 'extinguisher', 'pega extintor');
  ok(r.fireOut && r.score2 > r.score1, 'apaga o fogo');
  ok(r.caught === 'paper', 'colega pega item arremessado');
  ok(r.virusSpread === 2, 'vírus espalha para o vizinho');
  ok(r.netDown === true, 'internet cai');
  ok(r.end === 'ending' || r.end === 'results', 'expediente termina');
  await p.waitForFunction(() => __game.state === 'results', null, { timeout: 15000 }).catch(() => {});
  ok(await p.evaluate(() => __game.state) === 'results', 'mostra relatório');
  await p.screenshot({ path: 'shots/smoke_results.png' });
  ok(errors.length === 0, 'sem erros no console' + (errors.length ? ': ' + errors.join(' | ') : ''));
  await b.close();
})();
