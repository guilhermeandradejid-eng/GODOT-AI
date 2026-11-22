import { PROBLEMS, TICKETS, ROUND_SECONDS, TEAM_SCALE } from './config.js';

let nextId = 1;

export class TicketManager {
  constructor(game) {
    this.game = game;
    this.open = [];
    this.nextAt = TICKETS.firstDelay;
    this.elapsed = 0;
    this.script = ['paper', 'cable']; // primeiros chamados = tutorial suave
  }

  get routerDown() { return this.open.some((t) => t.type === 'router'); }

  update(dt) {
    this.elapsed += dt;
    const k = Math.min(1, this.elapsed / ROUND_SECONDS);
    if (this.elapsed >= this.nextAt) {
      if (this.open.length < TICKETS.maxOpen) this.spawn();
      const n = Math.max(1, Math.min(4, this.game.players.length));
      const iv = (TICKETS.intervalStart + (TICKETS.intervalEnd - TICKETS.intervalStart) * k) * TEAM_SCALE.interval[n - 1];
      this.nextAt = this.elapsed + iv * (0.75 + Math.random() * 0.5) + (this.open.length === 0 ? -2 : 0);
    }
    // nunca deixe a tela vazia por muito tempo
    if (this.open.length === 0 && this.nextAt - this.elapsed > 3) this.nextAt = this.elapsed + 1.5;

    const down = this.routerDown;
    for (const t of [...this.open]) {
      const drain = down && t.type !== 'router' ? TICKETS.routerDownDrain : 1;
      t.remaining -= dt * drain;
      t.station.problem && (t.station.problem.t += dt);
      if (t.type === 'virus' && !t.spread && t.remaining / t.sla < TICKETS.virusSpreadAt) {
        t.spread = true;
        const n = t.station.neighbors?.find((d) => !d.problem);
        if (n && this.open.length < TICKETS.maxOpen + 1) {
          const nt = this.spawn('virus', n);
          if (nt) this.game.ui.floatText(n.markerPos(n.pos.clone()), 'Vírus espalhou!', '#6ee36e');
        }
      }
      if (t.remaining <= 0) this.fail(t);
    }
    for (const d of this.game.desks) d.netDown = down;
  }

  pick() {
    const el = this.elapsed;
    const types = Object.entries(PROBLEMS).filter(([type]) => {
      if (type === 'fire' && el < 25) return false;
      if (type === 'router' && (el < 45 || this.routerDown)) return false;
      if (type === 'virus' && el < 12) return false;
      return true;
    });
    let total = 0;
    const w = types.map(([type, def]) => { const x = def.weight * (type === 'fire' ? 1 + el / 90 : 1); total += x; return [type, x]; });
    let r = Math.random() * total;
    for (const [type, x] of w) { r -= x; if (r <= 0) return type; }
    return w[0][0];
  }

  spawn(forceType = null, forceStation = null) {
    let type = forceType || this.script.shift() || this.pick();
    let station = forceStation;
    if (!station) {
      const cands = this.game.stations.filter((s) => s.canHave(type) && !s.problem);
      if (!cands.length) {
        // tenta outro tipo
        for (let i = 0; i < 6 && !cands.length; i++) {
          type = this.pick();
          cands.push(...this.game.stations.filter((s) => s.canHave(type) && !s.problem));
        }
        if (!cands.length) return null;
      }
      // VIP aparece de vez em quando
      const vipC = cands.filter((s) => s.vip);
      station = vipC.length && Math.random() < 0.18 ? vipC[0] : cands.filter((s) => !s.vip)[Math.floor(Math.random() * cands.filter((s) => !s.vip).length)] || cands[0];
    }
    const def = PROBLEMS[type];
    const vip = station.vip;
    const sla = def.sla * (vip ? 0.75 : 1);
    const t = {
      id: nextId++, type, def, station, vip, sla, remaining: sla, spread: false,
      who: station.kind === 'desk' ? station.name : station.name,
      reward: Math.round(def.reward * (vip ? 1.5 : 1)),
    };
    station.setProblem(type, t);
    this.open.push(t);
    this.game.onTicketOpened(t);
    return t;
  }

  close(t) {
    this.open = this.open.filter((o) => o !== t);
  }

  resolve(station, player) {
    const t = station.problem?.ticket; if (!t) return;
    this.close(t);
    station.clearProblem(true);
    this.game.onTicketResolved(t, player);
  }

  fail(t) {
    this.close(t);
    t.station.clearProblem(false);
    this.game.onTicketFailed(t);
  }
}
