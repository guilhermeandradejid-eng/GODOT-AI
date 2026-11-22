import * as THREE from 'three';
import { makeItemMesh } from './models.js';
import { pushOutCircle, groundAt } from './physics.js';
import { ITEMS } from './config.js';
import { addOutline } from './toon.js';

let nextId = 1;
export class Item {
  constructor(kind, scene, pos) {
    this.id = nextId++;
    this.kind = kind;
    this.def = ITEMS[kind];
    this.group = new THREE.Group();
    this.mesh = makeItemMesh(kind);
    addOutline(this.mesh, 0.018);
    this.group.add(this.mesh);
    this.group.position.copy(pos);
    scene.add(this.group);
    this.scene = scene;
    this.vel = new THREE.Vector3();
    this.heldBy = null;
    this.thrownBy = null; this.thrownT = 0;
    this.spin = 0;
    this.squash = 0;
    this.r = 0.2;
    this.alive = true;
    this.highlight = 0;
  }
  get pos() { return this.group.position; }

  attachTo(player) {
    this.heldBy = player;
    this.thrownBy = null;
    this.vel.set(0, 0, 0);
    player.hold.add(this.group);
    this.group.position.set(0, 0, 0);
    this.group.rotation.set(0, 0, 0);
    this.mesh.rotation.set(0, 0, 0);
  }
  release(vel = null) {
    const p = this.heldBy;
    this.scene.attach(this.group);
    this.group.rotation.set(0, p ? p.angle : 0, 0);
    this.heldBy = null;
    if (vel) { this.vel.copy(vel); this.thrownBy = p; this.thrownT = 0; this.spin = 10; }
    else this.vel.set(0, 0, 0);
  }
  destroy() { this.alive = false; this.group.removeFromParent(); }

  update(dt, game) {
    if (this.heldBy) { this.squash *= 0.8; return; }
    const p = this.group.position;
    this.thrownT += dt;
    this.vel.y -= 22 * dt;
    p.addScaledVector(this.vel, dt);
    const hit = pushOutCircle(p, this.r, game.colliders, { y: p.y });
    if (hit) {
      const dot = this.vel.x * hit.nx + this.vel.z * hit.nz;
      if (dot < 0) { this.vel.x -= 1.6 * dot * hit.nx; this.vel.z -= 1.6 * dot * hit.nz; this.vel.x *= 0.6; this.vel.z *= 0.6; }
    }
    const g = groundAt(p.x, p.z, p.y, game.colliders);
    if (p.y <= g) {
      p.y = g;
      if (this.vel.y < -3) { this.squash = 1; game.fx.puff(p.clone().setY(g + 0.05), 4); game.sfx.drop(); }
      this.vel.y = this.vel.y < -3 ? -this.vel.y * 0.3 : 0;
      this.vel.x *= Math.max(0, 1 - 9 * dt); this.vel.z *= Math.max(0, 1 - 9 * dt);
      this.spin *= 0.85;
      if (this.thrownT > 0.1) this.thrownBy = null;
    }
    this.mesh.rotation.y += this.spin * dt;
    this.squash = Math.max(0, this.squash - dt * 5);
    const s = 1 + Math.sin(this.squash * Math.PI) * 0.25;
    this.mesh.scale.set(s, 1 / s, s);
    // pulso quando alguém pode pegar
    this.highlight = Math.max(0, this.highlight - dt * 4);
    const h = 1 + this.highlight * 0.12 * (0.5 + 0.5 * Math.sin(performance.now() * 0.012));
    this.mesh.scale.multiplyScalar(h);

    // pegar no ar (arremesso → companheiro)
    if (this.thrownBy && p.y > 0.2) {
      for (const pl of game.players) {
        if (pl === this.thrownBy || pl.held) continue;
        const dx = pl.pos.x - p.x, dz = pl.pos.z - p.z;
        if (dx * dx + dz * dz < 0.75 * 0.75 && p.y < 1.8) { pl.grab(this, game); game.ui.floatText(pl.pos.clone().setY(2.2), 'Pegou!', '#ffd23f'); break; }
      }
    }
  }
}
