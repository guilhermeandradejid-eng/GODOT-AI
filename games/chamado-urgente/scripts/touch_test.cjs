// Teste dos controles touch num celular emulado (horizontal).
const { chromium } = require('playwright');
const URL = process.env.URL || 'http://localhost:4173/';
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const errors = [];
  p.on('pageerror', (e) => errors.push(e.message));
  await p.goto(URL + '?q=low');
  await p.waitForTimeout(1500);
  const ok = (c, msg) => { console.log((c ? 'ok   ' : 'FAIL ') + msg); if (!c) process.exitCode = 1; };
  ok(await p.evaluate(() => document.body.classList.contains('touch')), 'detecta toque');
  await p.screenshot({ path: 'shots/touch_menu.png' });
  // a renderização por software é muito lenta; congela o loop e avança com __step
  await p.evaluate(() => { __game.freeze = true; });
  await p.tap('#start-btn');
  await p.waitForTimeout(500);
  const r = await p.evaluate(() => {
    const g = __game; __step(240);
    const P = g.players[0], out = { dev: P.device.id, state: g.state };
    const zone = document.querySelector('.stick-zone');
    const fire = (el, type, x, y) => el.dispatchEvent(new PointerEvent(type, { pointerId: 7, pointerType: 'touch', clientX: x, clientY: y, bubbles: true }));
    const x0 = P.pos.x;
    fire(zone, 'pointerdown', 150, 280); fire(zone, 'pointermove', 220, 280);
    __step(40);
    out.moved = P.pos.x - x0;
    fire(zone, 'pointerup', 220, 280); __step(5);
    // vai até a prateleira de cabos e aperta A
    P.pos.set(-10.9, 0, -6.1); P.angle = Math.PI;
    const A = document.querySelector('[data-btn=grab]');
    A.dispatchEvent(new PointerEvent('pointerdown', { pointerId: 9, pointerType: 'touch', bubbles: true })); __step(1);
    A.dispatchEvent(new PointerEvent('pointerup', { pointerId: 9, pointerType: 'touch', bubbles: true })); __step(2);
    out.held = P.held?.kind;
    out.visible = getComputedStyle(document.getElementById('touch')).display;
    __step(2, true);
    return out;
  });
  console.log(JSON.stringify(r));
  ok(r.dev === 'touch', 'jogador 1 usa o toque');
  ok(r.moved > 1, 'joystick move o técnico');
  ok(r.held === 'cable', 'botão A pega o item');
  ok(r.visible === 'block', 'controles aparecem durante a partida');
  await p.waitForTimeout(800);
  await p.screenshot({ path: 'shots/touch_game.png' });
  ok(errors.length === 0, 'sem erros' + (errors.length ? ': ' + errors.join(' | ') : ''));
  await b.close();
})();
